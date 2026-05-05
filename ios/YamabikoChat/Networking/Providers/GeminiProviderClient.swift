import Foundation
import UniformTypeIdentifiers

struct GeminiProviderClient: ProviderClient {
    let provider: LLMProvider = .gemini
    private let geminiApiBase = "https://generativelanguage.googleapis.com/v1beta"
    private static let geminiCliProcessSessionID = geminiCliUUID()
    private static let geminiCliModelFallbacks = [
        "gemini-2.5-flash-image": "gemini-2.5-flash"
    ]
    static let noUsableStreamDataReason = "Gemini stream produced no usable data"
    private static let geminiCliStreamMaxAttempts = 3
    private static let geminiCliRetryInitialDelayMs = 5_000
    private static let geminiCliRetryMaxDelayMs = 30_000
    private static let geminiCliQuotaDomains: Set<String> = [
        "cloudcode-pa.googleapis.com",
        "staging-cloudcode-pa.googleapis.com",
        "autopush-cloudcode-pa.googleapis.com"
    ]

    func generate(
        request: ProviderRequest,
        settings: AppSettings,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse {
        let resolvedProvider = LLMProvider(rawOrDefault: request.metadata["provider"] ?? settings.apiProvider)
        switch resolvedProvider {
        case .gemini:
            return try await generateWithAPIKey(request: request, credentialStore: credentialStore, httpClient: httpClient)
        case .geminiAuth:
            return try await generateWithBearerToken(request: request, credentialStore: credentialStore, httpClient: httpClient)
        default:
            throw ProviderClientError.invalidBaseURL("Provider not supported by Gemini client")
        }
    }

    func stream(
        request: ProviderRequest,
        settings: AppSettings,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let resolvedProvider = LLMProvider(rawOrDefault: request.metadata["provider"] ?? settings.apiProvider)
                    let credential = try await resolveCredential(provider: resolvedProvider, store: credentialStore)
                    let projectID = try requireGeminiCliProjectID(provider: resolvedProvider, store: credentialStore)
                    let endpoint = try streamEndpoint(
                        model: request.model,
                        provider: resolvedProvider,
                        token: credential.token,
                        credentialStore: credentialStore
                    )
                    let body = try buildGeminiBody(
                        request: request,
                        provider: resolvedProvider,
                        projectID: projectID,
                        credentialStore: credentialStore
                    )

                    var headers = ["Content-Type": "application/json"]
                    if credential.isBearer {
                        headers["Authorization"] = "Bearer \(credential.token)"
                    }
                    if resolvedProvider == .geminiAuth {
                        let compatibility = GeminiCliCompatibility.resolved(using: credentialStore)
                        applyGeminiCliHeaders(
                            to: &headers,
                            compatibility: compatibility,
                            model: request.model,
                            activityRequestID: GeminiCliCompatibility.makeActivityRequestID(),
                            streaming: true
                        )
                    }

                    let httpRequest = HTTPRequest(url: endpoint, headers: headers, body: body.data)
                    DiagnosticsLogger.log(
                        "Gemini stream start",
                        category: .network,
                        metadata: [
                            "provider": resolvedProvider.rawValue,
                            "model": request.model,
                            "url": endpoint.absoluteString
                        ]
                    )
                    let maxAttempts = resolvedProvider == .geminiAuth ? Self.geminiCliStreamMaxAttempts : 1
                    var attempt = 1

                    while !Task.isCancelled {
                        let (lineStream, response) = try await httpClient.stream(httpRequest)
                        guard !(200 ... 299).contains(response.statusCode) else {
                            try await consumeStreamEvents(
                                lineStream: lineStream,
                                response: response,
                                provider: resolvedProvider,
                                model: request.model,
                                continuation: continuation
                            )
                            return
                        }

                        let parsedError = await parseGeminiStreamErrorBody(lineStream: lineStream)
                        if let delayMs = retryDelayForGeminiStreamFailure(
                            statusCode: response.statusCode,
                            response: response,
                            provider: resolvedProvider,
                            attempt: attempt,
                            maxAttempts: maxAttempts,
                            parsedError: parsedError
                        ) {
                            DiagnosticsLogger.log(
                                "Gemini stream retry scheduled",
                                category: .network,
                                metadata: [
                                    "provider": resolvedProvider.rawValue,
                                    "model": request.model,
                                    "status": String(response.statusCode),
                                    "attempt": String(attempt),
                                    "max_attempts": String(maxAttempts),
                                    "retry_delay_ms": String(delayMs)
                                ]
                            )
                            try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                            attempt += 1
                            continue
                        }

                        throw ProviderClientError.httpStatus(
                            response.statusCode,
                            buildGeminiStreamFailureMessage(
                                statusCode: response.statusCode,
                                provider: resolvedProvider,
                                parsedError: parsedError
                            )
                        )
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct ResolvedCredential {
        var token: String
        var isBearer: Bool
    }

    private struct ParsedGeminiParts {
        var text: String
        var reasoning: String
    }

    private struct ParsedGeminiChunk {
        var text: String
        var reasoning: String
        var usage: ProviderUsage?
    }

    private struct ParsedGeminiError {
        var rawBody: String?
        var message: String?
        var details: [[String: Any]]
    }

    private struct GeminiQuotaDecision {
        var terminal: Bool
        var retryDelayMs: Int?
    }

    private func consumeStreamEvents(
        lineStream: AsyncThrowingStream<String, Error>,
        response: HTTPURLResponse,
        provider: LLMProvider,
        model: String,
        continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    ) async throws {
        var fullText = ""
        var fullReasoning = ""
        var latestUsage: ProviderUsage?
        var hasUsableData = false
        var eventLines: [String] = []
        var streamFinished = false
        var parseErrorCount = 0
        var totalLineCount = 0
        var flushCount = 0
        var singleLineFlushCount = 0
        var boundaryFlushCount = 0
        var blankLineFlushCount = 0
        var eofFlushCount = 0
        var flushTrace: [String] = []
        var invalidPayloadSnippets: [String] = []
        let maxSnippets = 6
        let snippetLimit = 256

        func recordInvalidPayload(_ payload: String) {
            parseErrorCount += 1
            guard invalidPayloadSnippets.count < maxSnippets else { return }
            let compact = payload
                .replacingOccurrences(of: "\n", with: "\\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            invalidPayloadSnippets.append(String(compact.prefix(snippetLimit)))
        }

        func failNoUsableData(_ phase: String) throws {
            DiagnosticsLogger.log(
                "Gemini stream produced no usable data",
                category: .network,
                metadata: [
                    "provider": provider.rawValue,
                    "model": model,
                    "phase": phase,
                    "status": String(response.statusCode),
                    "line_count": String(totalLineCount),
                    "flush_count": String(flushCount),
                    "flush_singleline_count": String(singleLineFlushCount),
                    "flush_boundary_count": String(boundaryFlushCount),
                    "flush_blankline_count": String(blankLineFlushCount),
                    "flush_eof_count": String(eofFlushCount),
                    "flush_trace": flushTrace.joined(separator: " | "),
                    "parse_error_count": String(parseErrorCount),
                    "invalid_payloads": invalidPayloadSnippets.joined(separator: " || ")
                ]
            )
            throw ProviderClientError.parseFailure(Self.noUsableStreamDataReason)
        }

        func parseChunk(_ chunk: String) -> ParsedGeminiChunk? {
            if provider == .geminiAuth {
                return parseGeminiCliStreamChunk(chunk)
            }
            return parseGeminiStreamChunk(chunk)
        }

        func bufferedChunk() -> String {
            eventLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func canFlushBufferedEvent() -> Bool {
            let chunk = bufferedChunk()
            guard !chunk.isEmpty else { return false }
            if chunk == "[DONE]" { return true }
            return parseChunk(chunk) != nil
        }

        func flushEventLines(trigger: String) throws {
            guard !eventLines.isEmpty, !streamFinished else { return }
            let chunk = bufferedChunk()
            eventLines.removeAll(keepingCapacity: true)
            guard !chunk.isEmpty else { return }
            flushCount += 1
            let shape = chunk == "[DONE]" ? "done" : (chunk.contains("\n") ? "multiline" : "singleline")
            if flushTrace.count < 10 {
                flushTrace.append("\(trigger):\(shape)")
            }
            switch trigger {
            case "singleline":
                singleLineFlushCount += 1
            case "next_data":
                boundaryFlushCount += 1
            case "blank_line":
                blankLineFlushCount += 1
            case "eof":
                eofFlushCount += 1
            default:
                break
            }

            if chunk == "[DONE]" {
                if !hasUsableData && fullText.isEmpty && fullReasoning.isEmpty {
                    try failNoUsableData("done")
                }
                let final = ProviderResponse(
                    text: fullText,
                    reasoningSummary: fullReasoning.trimmedNonEmpty,
                    raw: nil,
                    usage: latestUsage
                )
                continuation.yield(.completed(final))
                continuation.finish()
                streamFinished = true
                return
            }

            let parsed = parseChunk(chunk)
            guard let parsed else {
                recordInvalidPayload(chunk)
                return
            }
            if let usage = parsed.usage?.normalizedNonEmpty() {
                latestUsage = usage
            }

            if !parsed.reasoning.isEmpty {
                fullReasoning += parsed.reasoning
                hasUsableData = true
                continuation.yield(.reasoningDelta(parsed.reasoning))
            }
            if !parsed.text.isEmpty {
                fullText += parsed.text
                hasUsableData = true
                continuation.yield(.textDelta(parsed.text))
            }
        }

        for try await line in lineStream {
            if streamFinished { return }
            totalLineCount += 1
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix(":") {
                continue
            }
            if trimmed.isEmpty {
                try flushEventLines(trigger: "blank_line")
                continue
            }
            guard trimmed.hasPrefix("data:") else {
                continue
            }

            if canFlushBufferedEvent() {
                try flushEventLines(trigger: "next_data")
            }

            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            eventLines.append(payload)

            if eventLines.count == 1, canFlushBufferedEvent() {
                try flushEventLines(trigger: "singleline")
            }
        }

        if streamFinished { return }
        try flushEventLines(trigger: "eof")
        if streamFinished { return }
        if !hasUsableData && fullText.isEmpty && fullReasoning.isEmpty {
            try failNoUsableData("eof")
        }

        let final = ProviderResponse(
            text: fullText,
            reasoningSummary: fullReasoning.trimmedNonEmpty,
            raw: nil,
            usage: latestUsage
        )
        continuation.yield(.completed(final))
        continuation.finish()
    }

    private func retryDelayForGeminiStreamFailure(
        statusCode: Int,
        response: HTTPURLResponse,
        provider: LLMProvider,
        attempt: Int,
        maxAttempts: Int,
        parsedError: ParsedGeminiError
    ) -> Int? {
        guard provider == .geminiAuth else { return nil }
        guard attempt < maxAttempts else { return nil }
        guard statusCode == 429 || (500 ... 599).contains(statusCode) else { return nil }

        var quotaDelayMs: Int?
        if statusCode == 429 {
            let decision = classifyGeminiQuotaDecision(
                details: parsedError.details,
                message: parsedError.message
            )
            if decision?.terminal == true {
                return nil
            }
            quotaDelayMs = decision?.retryDelayMs
        }

        let delayMs = resolveGeminiRetryDelayMs(
            response: response,
            details: parsedError.details,
            message: parsedError.message,
            quotaDelayMs: quotaDelayMs,
            attempt: attempt
        )
        return delayMs > 0 ? delayMs : nil
    }

    private func buildGeminiStreamFailureMessage(
        statusCode: Int,
        provider: LLMProvider,
        parsedError: ParsedGeminiError
    ) -> String {
        if statusCode == 429, provider == .geminiAuth {
            let decision = classifyGeminiQuotaDecision(
                details: parsedError.details,
                message: parsedError.message
            )
            if decision?.terminal == true {
                return "Quota exhausted for this account. Please wait for your quota to reset or upgrade your plan."
            }
            if decision != nil {
                return "Rate limit exceeded. Please retry shortly."
            }
        }
        if let message = parsedError.message?.trimmedNonEmpty {
            return message
        }
        if let body = parsedError.rawBody?.trimmedNonEmpty {
            return body
        }
        return "Gemini stream failed: \(statusCode)"
    }

    private func resolveGeminiRetryDelayMs(
        response: HTTPURLResponse,
        details: [[String: Any]],
        message: String?,
        quotaDelayMs: Int?,
        attempt: Int
    ) -> Int {
        if let retryAfterMs = parseRetryAfterMsHeader(response.value(forHTTPHeaderField: "retry-after-ms")) {
            return clampGeminiRetryDelayMs(retryAfterMs)
        }
        if let retryAfter = parseRetryAfterHeader(response.value(forHTTPHeaderField: "retry-after")) {
            return clampGeminiRetryDelayMs(retryAfter)
        }
        if let quotaDelayMs {
            return clampGeminiRetryDelayMs(quotaDelayMs)
        }
        if let detailDelay = extractRetryDelayFromGeminiDetails(details: details, message: message) {
            return clampGeminiRetryDelayMs(detailDelay)
        }
        return exponentialGeminiRetryDelayMs(forAttempt: attempt)
    }

    private func parseRetryAfterMsHeader(_ value: String?) -> Int? {
        guard let value = value?.trimmedNonEmpty else { return nil }
        guard let parsed = Double(value), parsed > 0 else { return nil }
        return Int(parsed.rounded())
    }

    private func parseRetryAfterHeader(_ value: String?) -> Int? {
        guard let value = value?.trimmedNonEmpty else { return nil }
        if let seconds = Double(value), seconds >= 0 {
            return Int((seconds * 1_000).rounded())
        }
        let parsedDate = DateFormatter.rfc1123.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let parsedDate else { return nil }
        let milliseconds = Int((parsedDate.timeIntervalSinceNow * 1_000).rounded())
        return max(0, milliseconds)
    }

    private func clampGeminiRetryDelayMs(_ delayMs: Int) -> Int {
        min(max(0, delayMs), Self.geminiCliRetryMaxDelayMs)
    }

    private func exponentialGeminiRetryDelayMs(forAttempt attempt: Int) -> Int {
        let exponent = max(0, attempt - 1)
        let factor = Int(pow(2.0, Double(exponent)))
        return min(Self.geminiCliRetryInitialDelayMs * factor, Self.geminiCliRetryMaxDelayMs)
    }

    private func parseGeminiStreamErrorBody(lineStream: AsyncThrowingStream<String, Error>) async -> ParsedGeminiError {
        let maxCollectedCharacters = 64 * 1024
        var regularLines: [String] = []
        var dataLines: [String] = []
        var consumedCharacters = 0

        do {
            for try await line in lineStream {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("data:") {
                    let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if !payload.isEmpty {
                        dataLines.append(payload)
                        consumedCharacters += payload.count
                    }
                } else if !trimmed.isEmpty {
                    regularLines.append(trimmed)
                    consumedCharacters += trimmed.count
                }
                if consumedCharacters >= maxCollectedCharacters {
                    break
                }
            }
        } catch {
            // Best effort: parse what we already collected.
        }

        let candidates = [
            dataLines.joined(separator: "\n").trimmedNonEmpty,
            regularLines.joined(separator: "\n").trimmedNonEmpty
        ]
            .compactMap { $0 }

        for candidate in candidates {
            if let parsed = parseGeminiErrorBody(candidate) {
                return parsed
            }
        }

        return ParsedGeminiError(
            rawBody: candidates.first,
            message: nil,
            details: []
        )
    }

    private func parseGeminiErrorBody(_ rawBody: String) -> ParsedGeminiError? {
        guard let root = parseJSONObject(rawBody) else { return nil }
        let errorObject = (root["error"] as? [String: Any]) ?? root
        let details = (errorObject["details"] as? [Any] ?? [])
            .compactMap { $0 as? [String: Any] }
        return ParsedGeminiError(
            rawBody: rawBody,
            message: (errorObject["message"] as? String)?.trimmedNonEmpty,
            details: details
        )
    }

    private func classifyGeminiQuotaDecision(
        details: [[String: Any]],
        message: String?
    ) -> GeminiQuotaDecision? {
        let retryDelayMs = extractRetryDelayFromGeminiDetails(details: details, message: message)

        let errorInfo = details.first {
            ($0["@type"] as? String) == "type.googleapis.com/google.rpc.ErrorInfo"
        }
        if let domain = errorInfo?["domain"] as? String,
           !domain.isEmpty,
           !Self.geminiCliQuotaDomains.contains(domain) {
            return nil
        }

        if let reason = errorInfo?["reason"] as? String {
            if reason == "QUOTA_EXHAUSTED" {
                return GeminiQuotaDecision(terminal: true, retryDelayMs: retryDelayMs)
            }
            if reason == "RATE_LIMIT_EXCEEDED" {
                return GeminiQuotaDecision(terminal: false, retryDelayMs: retryDelayMs ?? 10_000)
            }
        }

        if let quotaFailure = details.first(where: { ($0["@type"] as? String) == "type.googleapis.com/google.rpc.QuotaFailure" }),
           let violations = quotaFailure["violations"] as? [Any], !violations.isEmpty {
            let violationText = violations
                .compactMap { $0 as? [String: Any] }
                .flatMap { [($0["quotaId"] as? String) ?? "", ($0["description"] as? String) ?? ""] }
                .joined(separator: " ")
                .lowercased()

            if violationText.contains("perday") || violationText.contains("daily") || violationText.contains("per day") {
                return GeminiQuotaDecision(terminal: true, retryDelayMs: retryDelayMs)
            }
            if violationText.contains("perminute") || violationText.contains("per minute") {
                return GeminiQuotaDecision(terminal: false, retryDelayMs: retryDelayMs ?? 60_000)
            }
            return GeminiQuotaDecision(terminal: false, retryDelayMs: retryDelayMs)
        }

        if let metadata = errorInfo?["metadata"] as? [String: Any],
           let quotaLimit = (metadata["quota_limit"] as? String)?.lowercased(),
           quotaLimit.contains("perminute") || quotaLimit.contains("per minute") {
            return GeminiQuotaDecision(terminal: false, retryDelayMs: retryDelayMs ?? 60_000)
        }

        return GeminiQuotaDecision(terminal: false, retryDelayMs: retryDelayMs)
    }

    private func extractRetryDelayFromGeminiDetails(
        details: [[String: Any]],
        message: String?
    ) -> Int? {
        if let retryInfo = details.first(where: { ($0["@type"] as? String) == "type.googleapis.com/google.rpc.RetryInfo" }),
           let retryDelay = retryInfo["retryDelay"],
           let parsed = parseRetryDelayValue(retryDelay) {
            return parsed
        }
        return parseRetryDelayFromMessage(message)
    }

    private func parseRetryDelayValue(_ value: Any) -> Int? {
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.hasSuffix("ms") {
                let numberPart = String(trimmed.dropLast(2))
                guard let milliseconds = Double(numberPart), milliseconds > 0 else { return nil }
                return Int(milliseconds.rounded())
            }
            if trimmed.hasSuffix("s") {
                let numberPart = String(trimmed.dropLast())
                guard let seconds = Double(numberPart), seconds > 0 else { return nil }
                return Int((seconds * 1_000).rounded())
            }
            return nil
        }

        if let value = value as? [String: Any] {
            let seconds = doubleValue(value["seconds"]) ?? 0
            let nanos = doubleValue(value["nanos"]) ?? 0
            guard seconds.isFinite, nanos.isFinite else { return nil }
            let totalMs = Int((seconds * 1_000 + nanos / 1_000_000).rounded())
            return totalMs > 0 ? totalMs : nil
        }

        return nil
    }

    private func parseRetryDelayFromMessage(_ message: String?) -> Int? {
        guard let message = message?.trimmedNonEmpty else { return nil }
        if let delay = firstRegexCapture(
            in: message,
            pattern: #"Please retry in ([0-9.]+(?:ms|s))"#
        ), let parsed = parseRetryDelayValue(delay) {
            return parsed
        }
        if let delay = firstRegexCapture(
            in: message,
            pattern: #"after\s+([0-9.]+(?:ms|s))"#
        ), let parsed = parseRetryDelayValue(delay) {
            return parsed
        }
        return nil
    }

    private func firstRegexCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        guard match.numberOfRanges > 1 else { return nil }
        let captureRange = match.range(at: 1)
        guard let capture = Range(captureRange, in: text) else { return nil }
        return String(text[capture])
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? String {
            return Double(value)
        }
        return nil
    }

    private func resolveCredential(provider: LLMProvider, store: SecureCredentialStore) async throws -> ResolvedCredential {
        switch provider {
        case .gemini:
            guard let key = try store.credential(for: .gemini)?.trimmedNonEmpty else {
                throw ProviderClientError.missingCredential(LLMProvider.gemini.rawValue)
            }
            return ResolvedCredential(token: key, isBearer: false)
        case .geminiAuth:
            let token = try (store.geminiAccessToken() ?? store.credential(for: .geminiAuth))?.trimmedNonEmpty
            guard let token else {
                throw ProviderClientError.missingCredential(LLMProvider.geminiAuth.rawValue)
            }
            return ResolvedCredential(token: token, isBearer: true)
        default:
            throw ProviderClientError.invalidBaseURL("Unsupported provider for Gemini")
        }
    }

    private func generateWithAPIKey(
        request: ProviderRequest,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse {
        guard let apiKey = try credentialStore.credential(for: .gemini)?.trimmedNonEmpty else {
            throw ProviderClientError.missingCredential(LLMProvider.gemini.rawValue)
        }

        guard let url = nonStreamingEndpoint(
            model: request.model,
            provider: .gemini,
            token: apiKey,
            credentialStore: credentialStore
        ) else {
            throw ProviderClientError.invalidBaseURL("Gemini endpoint")
        }

        let payload = try buildGeminiBody(
            request: request,
            provider: .gemini,
            projectID: nil,
            credentialStore: credentialStore
        )
        let httpRequest = HTTPRequest(
            url: url,
            headers: ["Content-Type": "application/json"],
            body: payload.data
        )

        let (data, response) = try await httpClient.send(httpRequest)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return try parseResponse(data: data)
    }

    private func generateWithBearerToken(
        request: ProviderRequest,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse {
        let accessToken = try (credentialStore.geminiAccessToken() ?? credentialStore.credential(for: .geminiAuth))?.trimmedNonEmpty
        guard let accessToken else {
            throw ProviderClientError.missingCredential(LLMProvider.geminiAuth.rawValue)
        }

        let projectID = try requireGeminiCliProjectID(provider: .geminiAuth, store: credentialStore)
        guard let endpoint = nonStreamingEndpoint(
            model: request.model,
            provider: .geminiAuth,
            token: accessToken,
            credentialStore: credentialStore
        ) else {
            throw ProviderClientError.invalidBaseURL("Gemini endpoint")
        }

        let payload = try buildGeminiBody(
            request: request,
            provider: .geminiAuth,
            projectID: projectID,
            credentialStore: credentialStore
        )
        let compatibility = GeminiCliCompatibility.resolved(using: credentialStore)
        var headers = [
            "Authorization": "Bearer \(accessToken)",
            "Content-Type": "application/json"
        ]
        applyGeminiCliHeaders(
            to: &headers,
            compatibility: compatibility,
            model: request.model,
            activityRequestID: GeminiCliCompatibility.makeActivityRequestID(),
            streaming: false
        )
        let httpRequest = HTTPRequest(
            url: endpoint,
            headers: headers,
            body: payload.data
        )

        let (data, response) = try await httpClient.send(httpRequest)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return try parseGeminiCliResponse(data: data)
    }

    private func nonStreamingEndpoint(
        model: String,
        provider: LLMProvider,
        token: String,
        credentialStore: SecureCredentialStore
    ) -> URL? {
        switch provider {
        case .gemini:
            var components = URLComponents(string: "\(geminiApiBase)/models/\(model):generateContent")
            components?.queryItems = [URLQueryItem(name: "key", value: token)]
            return components?.url
        case .geminiAuth:
            let compatibility = GeminiCliCompatibility.resolved(using: credentialStore)
            return URL(
                string: "\(compatibility.remote.codeAssistEndpoint)/\(compatibility.remote.codeAssistVersion):\(compatibility.remote.requestFormat.generateAction)"
            )
        default:
            return nil
        }
    }

    private func streamEndpoint(
        model: String,
        provider: LLMProvider,
        token: String,
        credentialStore: SecureCredentialStore
    ) throws -> URL {
        switch provider {
        case .gemini:
            var components = URLComponents(string: "\(geminiApiBase)/models/\(model):streamGenerateContent")
            components?.queryItems = [
                URLQueryItem(name: "alt", value: "sse"),
                URLQueryItem(name: "key", value: token)
            ]
            guard let url = components?.url else { throw ProviderClientError.invalidBaseURL("Gemini streaming endpoint") }
            return url
        case .geminiAuth:
            let compatibility = GeminiCliCompatibility.resolved(using: credentialStore)
            var components = URLComponents(
                string: "\(compatibility.remote.codeAssistEndpoint)/\(compatibility.remote.codeAssistVersion):\(compatibility.remote.requestFormat.streamAction)"
            )
            if compatibility.remote.requestFormat.streamUsesAltSse {
                components?.queryItems = [URLQueryItem(name: "alt", value: "sse")]
            }
            guard let url = components?.url else { throw ProviderClientError.invalidBaseURL("Gemini streaming endpoint") }
            return url
        default:
            throw ProviderClientError.invalidBaseURL("Unsupported provider for Gemini stream")
        }
    }

    private struct GeminiBodyBuildResult {
        var data: Data
        var requestIdentifier: String?
    }

    private func buildGeminiBody(
        request: ProviderRequest,
        provider: LLMProvider,
        projectID: String?,
        credentialStore: SecureCredentialStore
    ) throws -> GeminiBodyBuildResult {
        let contents = request.messages.map { message -> [String: Any] in
            [
                "role": message.role == "assistant" ? "model" : "user",
                "parts": buildGeminiParts(for: message)
            ]
        }

        var generationConfig: [String: Any] = [:]
        if let mime = request.metadata["geminiResponseMimeType"]?.trimmedNonEmpty {
            generationConfig["responseMimeType"] = mime
        }
        if let schemaText = request.metadata["geminiResponseJSONSchema"]?.trimmedNonEmpty,
           let data = schemaText.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data) {
            generationConfig["responseJsonSchema"] = jsonObject
        }

        if let thinking = request.thinking {
            var thinkingConfig: [String: Any] = [:]
            if let budget = thinking.budget {
                thinkingConfig["thinkingBudget"] = budget
            }
            if let includeThoughts = thinking.includeThoughts {
                thinkingConfig["includeThoughts"] = includeThoughts
            }
            if let level = request.metadata["geminiThinkingLevel"]?.trimmedNonEmpty {
                thinkingConfig["thinkingLevel"] = level
            }
            if !thinkingConfig.isEmpty {
                generationConfig["thinkingConfig"] = thinkingConfig
            }
        }

        let tools = geminiToolObjects(from: request.tools)

        switch provider {
        case .geminiAuth:
            let compatibility = GeminiCliCompatibility.resolved(using: credentialStore)
            let sessionID = resolveGeminiCliSessionID(from: request.metadata)
            let userPromptID = resolveGeminiCliRequestIdentifier(from: request.metadata)
            var inner: [String: Any] = [
                "contents": contents,
                "session_id": sessionID
            ]
            if let systemPrompt = request.systemPrompt, !systemPrompt.isEmpty {
                inner[compatibility.remote.requestFormat.systemInstructionFieldName] = [
                    "role": "system",
                    "parts": [["text": systemPrompt]]
                ]
            }
            if !tools.isEmpty {
                inner["tools"] = tools
            }
            if !generationConfig.isEmpty {
                inner["generationConfig"] = generationConfig
            }

            var root: [String: Any] = [
                compatibility.remote.requestFormat.modelFieldName: normalizedGeminiCliModel(request.model),
                compatibility.remote.requestFormat.userPromptIDFieldName: userPromptID,
                compatibility.remote.requestFormat.requestFieldName: inner
            ]
            if let projectID = projectID?.trimmedNonEmpty {
                root[compatibility.remote.requestFormat.projectFieldName] = projectID
            }
            return GeminiBodyBuildResult(
                data: try JSONSerialization.data(withJSONObject: root),
                requestIdentifier: userPromptID
            )
        default:
            var root: [String: Any] = [
                "contents": contents
            ]
            if let systemPrompt = request.systemPrompt, !systemPrompt.isEmpty {
                root["system_instruction"] = ["parts": [["text": systemPrompt]]]
            }
            if !tools.isEmpty {
                root["tools"] = tools
            }
            if !generationConfig.isEmpty {
                root["generationConfig"] = generationConfig
            }
            return GeminiBodyBuildResult(
                data: try JSONSerialization.data(withJSONObject: root),
                requestIdentifier: nil
            )
        }
    }

    private func resolveAttachmentFileURL(_ rawAttachment: String) -> URL? {
        if let parsed = URL(string: rawAttachment), parsed.isFileURL {
            return parsed
        }

        let directPath = URL(fileURLWithPath: rawAttachment)
        if FileManager.default.fileExists(atPath: directPath.path) {
            return directPath
        }

        if let decoded = rawAttachment.removingPercentEncoding {
            let decodedPath = URL(fileURLWithPath: decoded)
            if FileManager.default.fileExists(atPath: decodedPath.path) {
                return decodedPath
            }
        }

        return nil
    }

    private func resolveAttachmentMimeType(fileURL: URL) -> String {
        if let values = try? fileURL.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = values.contentType,
           let mime = contentType.preferredMIMEType,
           !mime.isEmpty {
            return mime
        }

        let ext = fileURL.pathExtension
        if let type = UTType(filenameExtension: ext),
           let mime = type.preferredMIMEType,
           !mime.isEmpty {
            return mime
        }

        return "application/octet-stream"
    }

    private func inlineDataPart(from rawAttachment: String) -> [String: Any]? {
        guard let fileURL = resolveAttachmentFileURL(rawAttachment) else {
            DiagnosticsLogger.log(
                "Gemini attachment skipped: unreadable file URL",
                category: .network,
                metadata: ["attachment": rawAttachment]
            )
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let mime = resolveAttachmentMimeType(fileURL: fileURL)
            return [
                "inlineData": [
                    "mimeType": mime,
                    "data": data.base64EncodedString()
                ]
            ]
        } catch {
            DiagnosticsLogger.log(
                "Gemini attachment skipped: file read failed",
                category: .network,
                metadata: [
                    "attachment": rawAttachment,
                    "path": fileURL.path
                ],
                error: error
            )
            return nil
        }
    }

    private func buildGeminiParts(for message: ProviderRequestMessage) -> [[String: Any]] {
        var parts: [[String: Any]] = [["text": message.content]]

        for attachment in message.attachments {
            if let inline = inlineDataPart(from: attachment) {
                parts.append(inline)
            }
        }

        return parts
    }

    private func parseGeminiParts(_ parts: [[String: Any]], payloadText: String? = nil) -> ParsedGeminiParts {
        var text = ""
        var reasoning = ""

        for part in parts {
            guard let value = part["text"] as? String, !value.isEmpty else { continue }
            if (part["thought"] as? Bool) == true {
                reasoning += value
            } else {
                text += value
            }
        }

        if let payloadText, !payloadText.isEmpty {
            text += payloadText
        }

        return ParsedGeminiParts(text: text, reasoning: reasoning)
    }

    private func parseGeminiPartsFromPayload(_ payload: [String: Any]) -> ParsedGeminiParts? {
        var parts: [[String: Any]] = []
        if
            let candidates = payload["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let candidateParts = content["parts"] as? [[String: Any]]
        {
            parts = candidateParts
        }

        let payloadText = payload["text"] as? String
        let parsed = parseGeminiParts(parts, payloadText: payloadText)
        guard !parsed.text.isEmpty || !parsed.reasoning.isEmpty else {
            return nil
        }
        return parsed
    }

    private func parseGeminiStreamChunk(_ chunk: String) -> ParsedGeminiChunk? {
        guard let root = parseJSONObject(chunk) else { return nil }
        let parsedParts = parseGeminiPartsFromPayload(root)
        let usage = parseGeminiUsage(payload: root)
        if parsedParts == nil, usage == nil {
            return nil
        }
        return ParsedGeminiChunk(
            text: parsedParts?.text ?? "",
            reasoning: parsedParts?.reasoning ?? "",
            usage: usage
        )
    }

    private func parseGeminiCliStreamChunk(_ chunk: String) -> ParsedGeminiChunk? {
        guard let root = parseJSONObject(chunk) else { return nil }
        let payload = extractGeminiCliPayload(from: root)
        let parsedParts = parseGeminiPartsFromPayload(payload)
        let usage = parseGeminiUsage(payload: payload)
        if parsedParts == nil, usage == nil {
            return nil
        }
        return ParsedGeminiChunk(
            text: parsedParts?.text ?? "",
            reasoning: parsedParts?.reasoning ?? "",
            usage: usage
        )
    }

    private func parseGeminiCliResponse(data: Data) throws -> ProviderResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderClientError.parseFailure("Gemini Auth response root is invalid")
        }
        let payload = (root["response"] as? [String: Any]) ?? root
        return try parseGeminiResponsePayload(payload: payload, rawData: data)
    }

    private func parseGeminiResponsePayload(payload: [String: Any], rawData: Data) throws -> ProviderResponse {
        guard let parsed = parseGeminiPartsFromPayload(payload) else {
            throw ProviderClientError.parseFailure("Gemini response missing candidates")
        }

        let text = parsed.text
        let reasoning = parsed.reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && reasoning.isEmpty {
            throw ProviderClientError.parseFailure("Gemini response text is empty")
        }

        return ProviderResponse(
            text: text,
            reasoningSummary: reasoning.isEmpty ? nil : reasoning,
            raw: String(data: rawData, encoding: .utf8),
            usage: parseGeminiUsage(payload: payload)
        )
    }

    private func geminiToolObjects(from tools: [ProviderTool]) -> [[String: Any]] {
        var mapped: [[String: Any]] = []
        for tool in tools {
            switch tool.type {
            case "google_search":
                mapped.append(["google_search": [:]])
            case "code_execution":
                mapped.append(["code_execution": [:]])
            case "url_context":
                mapped.append(["url_context": [:]])
            case "google_maps":
                mapped.append(["google_maps": [:]])
            case "computer_use":
                mapped.append(["computer_use": [:]])
            case "function_declarations":
                if let json = tool.payload["json"]?.trimmedNonEmpty,
                   let data = json.data(using: .utf8),
                   let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   !list.isEmpty {
                    mapped.append(["function_declarations": list])
                }
            default:
                break
            }
        }
        return mapped
    }

    private func applyGeminiCliHeaders(
        to headers: inout [String: String],
        compatibility: GeminiCliResolvedCompatibility,
        model: String,
        activityRequestID: String,
        streaming: Bool
    ) {
        headers["User-Agent"] = compatibility.buildUserAgent(model: normalizedGeminiCliModel(model))
        headers["x-activity-request-id"] = activityRequestID
        if streaming {
            headers["Accept"] = "text/event-stream"
        }
        let strippedHeaderKeys = headers.keys.filter {
            $0.caseInsensitiveCompare("x-api-key") == .orderedSame ||
                $0.caseInsensitiveCompare("x-goog-api-key") == .orderedSame ||
                $0.caseInsensitiveCompare("x-goog-api-client") == .orderedSame ||
                $0.caseInsensitiveCompare("client-metadata") == .orderedSame
        }
        for key in strippedHeaderKeys {
            headers.removeValue(forKey: key)
        }
    }

    private func requireGeminiCliProjectID(
        provider: LLMProvider,
        store: SecureCredentialStore
    ) throws -> String? {
        guard provider == .geminiAuth else {
            return try store.readSecret(key: "gemini_project_id")
        }
        guard let projectID = try store.readSecret(key: "gemini_project_id")?.trimmedNonEmpty else {
            throw ProviderClientError.parseFailure("Project ID is required")
        }
        return projectID
    }

    private func resolveGeminiCliSessionID(from metadata: [String: String]) -> String {
        let aliases = [
            "geminiSessionId",
            "session_id",
            "sessionId"
        ]
        for key in aliases {
            if let value = metadata[key]?.trimmedNonEmpty {
                return value
            }
        }
        return Self.geminiCliProcessSessionID
    }

    private func resolveGeminiCliRequestIdentifier(from metadata: [String: String]) -> String {
        let aliases = [
            "geminiUserPromptId",
            "geminiPromptId",
            "geminiRequestId",
            "user_prompt_id",
            "userPromptId",
            "prompt_id",
            "promptId",
            "request_id",
            "requestId"
        ]
        for key in aliases {
            if let value = metadata[key]?.trimmedNonEmpty {
                return value
            }
        }
        return Self.geminiCliUUID()
    }

    private func normalizedGeminiCliModel(_ model: String) -> String {
        Self.geminiCliModelFallbacks[model] ?? model
    }

    private static func geminiCliUUID() -> String {
        UUID().uuidString.lowercased()
    }

    private func parseResponse(data: Data) throws -> ProviderResponse {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ProviderClientError.parseFailure("Gemini response root is invalid")
        }

        return try parseGeminiResponsePayload(payload: root, rawData: data)
    }

    private func parseGeminiUsage(payload: [String: Any]) -> ProviderUsage? {
        guard
            let usage = (payload["usageMetadata"] as? [String: Any]) ??
                (payload["usage_metadata"] as? [String: Any])
        else {
            return nil
        }
        let promptTokenCount = intValue(in: usage, keys: ["promptTokenCount", "prompt_token_count"]) ?? 0
        let candidatesTokenCount = intValue(in: usage, keys: ["candidatesTokenCount", "candidates_token_count"]) ?? 0
        let cachedContentTokenCount = intValue(in: usage, keys: ["cachedContentTokenCount", "cached_content_token_count"])
        let thoughtsTokenCount = intValue(
            in: usage,
            keys: ["thoughtsTokenCount", "thoughts_token_count", "reasoningTokenCount", "reasoning_token_count"]
        )
        let cacheCreationTokenCount = intValue(
            in: usage,
            keys: ["cacheCreationInputTokenCount", "cache_creation_input_token_count"]
        )
        let toolUsePromptTokenCount = intValue(in: usage, keys: ["toolUsePromptTokenCount", "tool_use_prompt_token_count"]) ?? 0
        let totalFallback = promptTokenCount + candidatesTokenCount + toolUsePromptTokenCount + max(0, thoughtsTokenCount ?? 0)
        let totalTokenCount = intValue(in: usage, keys: ["totalTokenCount", "total_token_count"]) ?? totalFallback
        return ProviderUsage(
            inputTokens: promptTokenCount,
            outputTokens: candidatesTokenCount,
            totalTokens: totalTokenCount,
            reasoningTokens: thoughtsTokenCount,
            cachedInputTokens: cachedContentTokenCount,
            cacheCreationInputTokens: cacheCreationTokenCount
        )
        .normalizedNonEmpty()
    }

    private func intValue(in object: [String: Any]?, keys: [String]) -> Int? {
        guard let object else { return nil }
        for key in keys {
            if let value = intValue(object[key]) {
                return value
            }
        }
        return nil
    }

    private func parseJSONObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let object = root as? [String: Any] {
            return object
        }
        if let array = root as? [[String: Any]] {
            return array.first
        }
        return nil
    }

    private func extractGeminiCliPayload(from root: [String: Any]) -> [String: Any] {
        if let response = root["response"] as? [String: Any] {
            return response
        }
        if let nested = root["result"] as? [String: Any],
           let response = nested["response"] as? [String: Any] {
            return response
        }
        return root
    }

    private func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int {
            return value
        }
        if let value = raw as? NSNumber {
            return value.intValue
        }
        if let value = raw as? String {
            return Int(value)
        }
        return nil
    }
}

private extension DateFormatter {
    static let rfc1123: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }()
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
