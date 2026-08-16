import Foundation

struct UserFacingError: Equatable {
    var title: String
    var summary: String
    var detail: String

    var hasDetail: Bool {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != summary && trimmed != title
    }
}

enum UserFacingErrorFormatter {
    private static let wrapperPrefixes = [
        "Response parse failed:",
        "Pi provider failed:",
        "Pi agent failed:"
    ]
    private static let chatErrorPrefixes = [
        "错误：",
        "错误:",
        "エラー:",
        "erreur :",
        "erreur:",
        "error:"
    ]
    private static let quotaSummaries: Set<String> = [
        "プランまたは課金設定を確認してください。",
        "Check your plan or billing settings.",
        "Revisa tu plan o la configuración de facturación.",
        "Vérifiez votre forfait ou les paramètres de facturation.",
        "请检查套餐或账单设置。"
    ]
    private static let authSummaries: Set<String> = [
        "ログインまたはAPIキーを確認してください。",
        "Check your sign-in or API key.",
        "Revisa el inicio de sesión o la clave API.",
        "Vérifiez la connexion ou la clé API.",
        "请检查登录或 API 密钥。"
    ]
    private static let serverSummaries: Set<String> = [
        "しばらくしてから再試行してください。",
        "Please try again in a moment.",
        "Inténtalo de nuevo en un momento.",
        "Veuillez réessayer dans un instant.",
        "请稍后再试。"
    ]
    private static let fallbackSummaries: Set<String> = [
        "応答を取得できませんでした",
        "Couldn't get a response",
        "No se pudo obtener una respuesta",
        "Impossible d’obtenir une réponse",
        "无法获取回复"
    ]
    private static let humanReadableLimit = 220

    static func format(_ error: Error) -> UserFacingError {
        format(error.localizedDescription)
    }

    static func format(_ raw: String?) -> UserFacingError {
        let original = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if original.isEmpty {
            return fallback(detail: "")
        }

        let stripped = stripWrappers(stripChatErrorPrefix(original))
        let fields = extractFields(from: original, stripped: stripped)
        if let mapped = mapKnown(fields) {
            return UserFacingError(title: mapped.title, summary: mapped.summary, detail: original)
        }

        if let mapped = mapKnownSummary(stripped) {
            return UserFacingError(
                title: mapped.title,
                summary: mapped.summary,
                detail: extraDetail(original: original, summary: mapped.summary)
            )
        }

        if let message = fields.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           isAlreadyHumanReadable(message) {
            return UserFacingError(
                title: L10n.text("エラー"),
                summary: message,
                detail: extraDetail(original: original, summary: message)
            )
        }

        if isAlreadyHumanReadable(stripped) {
            return UserFacingError(
                title: L10n.text("エラー"),
                summary: stripped,
                detail: extraDetail(original: original, summary: stripped)
            )
        }

        return fallback(detail: original)
    }

    static func placeholder(for error: Error) -> String {
        placeholder(for: error.localizedDescription)
    }

    static func placeholder(for raw: String?) -> String {
        let formatted = format(raw)
        if looksLikeChatError(formatted.summary) {
            return formatted.summary
        }
        return L10n.format("エラー: %@", formatted.summary)
    }

    static func looksLikeChatError(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if hasChatErrorPrefix(trimmed) { return true }
        if hasWrapperPrefix(trimmed) { return true }
        if trimmed.hasPrefix("{"), extractErrorPayload(from: trimmed) != nil {
            return true
        }
        if startsWithHTTPStatus(trimmed) {
            return true
        }
        return false
    }

    private static func fallback(detail: String) -> UserFacingError {
        UserFacingError(
            title: L10n.text("エラー"),
            summary: L10n.text("応答を取得できませんでした"),
            detail: detail
        )
    }

    private static func mapKnown(_ fields: ExtractedFields) -> (title: String, summary: String)? {
        let code = fields.code?.uppercased() ?? ""
        let status = fields.status?.uppercased() ?? ""
        let message = fields.message?.lowercased() ?? ""
        let http = fields.httpStatus ?? Int(code)

        if http == 429
            || code == "429"
            || status == "RESOURCE_EXHAUSTED"
            || message.contains("quota")
            || message.contains("resource has been exhausted")
            || message.contains("resource_exhausted") {
            return (
                L10n.text("利用上限に達しました"),
                L10n.text("プランまたは課金設定を確認してください。")
            )
        }

        if http == 401
            || http == 403
            || code == "401"
            || code == "403"
            || status == "UNAUTHENTICATED"
            || status == "PERMISSION_DENIED"
            || status == "UNAUTHORIZED"
            || message.contains("unauthenticated")
            || message.contains("unauthorized")
            || message.contains("api key")
            || message.contains("permission denied") {
            return (
                L10n.text("認証に失敗しました"),
                L10n.text("ログインまたはAPIキーを確認してください。")
            )
        }

        if http == 500
            || http == 502
            || http == 503
            || http == 529
            || status == "INTERNAL"
            || status == "UNAVAILABLE"
            || status == "DEADLINE_EXCEEDED"
            || message.contains("internal server") {
            return (
                L10n.text("サーバーエラー"),
                L10n.text("しばらくしてから再試行してください。")
            )
        }

        return nil
    }

    private static func mapKnownSummary(_ stripped: String) -> (title: String, summary: String)? {
        let text = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text == L10n.text("プランまたは課金設定を確認してください。") || quotaSummaries.contains(text) {
            return (
                L10n.text("利用上限に達しました"),
                L10n.text("プランまたは課金設定を確認してください。")
            )
        }
        if text == L10n.text("ログインまたはAPIキーを確認してください。") || authSummaries.contains(text) {
            return (
                L10n.text("認証に失敗しました"),
                L10n.text("ログインまたはAPIキーを確認してください。")
            )
        }
        if text == L10n.text("しばらくしてから再試行してください。") || serverSummaries.contains(text) {
            return (
                L10n.text("サーバーエラー"),
                L10n.text("しばらくしてから再試行してください。")
            )
        }
        if text == L10n.text("応答を取得できませんでした") || fallbackSummaries.contains(text) {
            return (
                L10n.text("エラー"),
                L10n.text("応答を取得できませんでした")
            )
        }
        return nil
    }

    private static func extraDetail(original: String, summary: String) -> String {
        if original == summary { return "" }
        let strippedPrefix = stripChatErrorPrefix(original)
        if strippedPrefix == summary { return "" }
        let fullyStripped = stripWrappers(strippedPrefix)
        if fullyStripped == summary { return "" }
        if mapKnownSummary(strippedPrefix) != nil || mapKnownSummary(fullyStripped) != nil {
            return ""
        }
        return original
    }

    private static func extractFields(from original: String, stripped: String) -> ExtractedFields {
        var fields = ExtractedFields(httpStatus: httpStatus(in: original) ?? httpStatus(in: stripped))
        var candidates: [String] = []
        for value in [original, stripped, unescapeJSON(stripped), unescapeJSON(unescapeJSON(stripped))] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !candidates.contains(trimmed) {
                candidates.append(trimmed)
            }
        }

        for candidate in candidates {
            if let payload = extractErrorPayload(from: candidate) {
                fields.message = fields.message ?? payload.message
                fields.code = fields.code ?? payload.code
                fields.status = fields.status ?? payload.status
            }
            if fields.message != nil || fields.code != nil || fields.status != nil {
                break
            }
        }

        if let message = fields.message, message.contains("{") {
            let nested = extractErrorPayload(from: unescapeJSON(message))
            fields.message = nested?.message ?? fields.message
            fields.code = fields.code ?? nested?.code
            fields.status = fields.status ?? nested?.status
        }

        return fields
    }

    private static func extractErrorPayload(from text: String) -> ExtractedFields? {
        let jsonSlice = firstJSONObject(in: text) ?? text
        var message = firstCapture("\"message\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"", in: jsonSlice)
        var code = firstCapture("\"code\"\\s*:\\s*\"?([0-9A-Za-z_.]+)\"?", in: jsonSlice)
        var status = firstCapture("\"status\"\\s*:\\s*\"([^\"]+)\"", in: jsonSlice)

        if let data = jsonSlice.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let errorObject = object["error"] as? [String: Any] ?? object
            message = message ?? stringValue(errorObject["message"])
            code = code ?? stringValue(errorObject["code"])
            status = status ?? stringValue(errorObject["status"])
        }

        message = message.map(unescapeJSONStringValue)
        guard message != nil || code != nil || status != nil else { return nil }
        return ExtractedFields(message: message, code: code, status: status, httpStatus: nil)
    }

    private static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func stripChatErrorPrefix(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prefix = matchingChatErrorPrefix(trimmed) else { return trimmed }
        return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripWrappers(_ text: String) -> String {
        var current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed {
            changed = false
            for prefix in wrapperPrefixes where current.lowercased().hasPrefix(prefix.lowercased()) {
                current = String(current.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
            }
            if let http = httpStatus(in: current) {
                let pattern = "^HTTP\\s+\(http)\\s*:\\s*"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(current.startIndex..., in: current)
                    let stripped = regex.stringByReplacingMatches(in: current, range: range, withTemplate: "")
                    if stripped != current {
                        current = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
                        changed = true
                    }
                }
            }
        }
        return current
    }

    private static func hasChatErrorPrefix(_ text: String) -> Bool {
        matchingChatErrorPrefix(text) != nil
    }

    private static func matchingChatErrorPrefix(_ text: String) -> String? {
        chatErrorPrefixes.first { prefix in
            text.lowercased().hasPrefix(prefix.lowercased())
        }
    }

    private static func startsWithHTTPStatus(_ text: String) -> Bool {
        firstCapture("^HTTP\\s+(\\d{3})\\b", in: text) != nil
    }

    private static func hasWrapperPrefix(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return wrapperPrefixes.contains { lowered.hasPrefix($0.lowercased()) }
    }

    private static func isAlreadyHumanReadable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= humanReadableLimit else { return false }
        if hasWrapperPrefix(trimmed) { return false }
        if trimmed.contains("{"), trimmed.contains("}") { return false }
        return true
    }

    private static func httpStatus(in text: String) -> Int? {
        firstCapture("HTTP\\s+(\\d{3})", in: text).flatMap(Int.init)
    }

    private static func unescapeJSON(_ text: String) -> String {
        var current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.hasPrefix("\""), current.hasSuffix("\""), current.count >= 2 {
            current = String(current.dropFirst().dropLast())
        }
        return unescapeJSONStringValue(current)
    }

    private static func unescapeJSONStringValue(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var iterator = text.makeIterator()
        while let character = iterator.next() {
            if character != "\\" {
                result.append(character)
                continue
            }
            guard let next = iterator.next() else {
                result.append(character)
                break
            }
            switch next {
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            case "/": result.append("/")
            case "u":
                var hex = ""
                for _ in 0..<4 {
                    if let digit = iterator.next() {
                        hex.append(digit)
                    }
                }
                if hex.count == 4, let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) {
                    result.append(Character(scalar))
                } else {
                    result.append("\\u")
                    result.append(hex)
                }
            default:
                result.append(next)
            }
        }
        return result
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[groupRange])
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        case let int as Int:
            return String(int)
        default:
            return nil
        }
    }

    private struct ExtractedFields {
        var message: String?
        var code: String?
        var status: String?
        var httpStatus: Int?
    }
}
