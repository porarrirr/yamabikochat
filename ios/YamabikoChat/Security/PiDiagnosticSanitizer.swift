import Foundation

enum PiDiagnosticSanitizer {
    private static let credentialFields: Set<String> = [
        "apikey", "accesstoken", "refreshtoken", "idtoken", "authorization",
        "authorizationtoken", "mcpauthorizationtoken", "clientsecret", "password",
        "credential", "xapikey", "xgoogapikey"
    ]

    static func sanitize(_ value: JSONValue) -> JSONValue {
        clean(value, legacyErrors: false, parent: "")
    }

    static func sanitizeEncoded(_ text: String) -> String {
        guard text.contains("yamabiko.pi-agent-execution") else { return text }
        guard let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first,
              ["{", "[", "\""].contains(first) else { return DiagnosticsLogSanitizer.sanitize(text) }
        guard let decoded = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
              let sanitized = try? JSONEncoder().encode(sanitize(decoded)) else { return "[REDACTED]" }
        return String(decoding: sanitized, as: UTF8.self)
    }

    private static func clean(_ value: JSONValue, legacyErrors: Bool, parent: String) -> JSONValue {
        switch value {
        case let .object(fields):
            let isSnapshot = fields["format"]?.stringValue == "yamabiko.pi-agent-execution"
            let version: Double
            if case let .number(number)? = fields["version"] { version = number } else { version = 0 }
            let legacy = legacyErrors || (isSnapshot && version < 4)
            var result: [String: JSONValue] = [:]
            for (key, nested) in fields {
                let normalized = key.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
                if credentialFields.contains(normalized) {
                    result[key] = .string("[REDACTED]")
                } else if legacy && (normalized == "errormessage" || normalized == "error" || normalized == "message" && ["failure", "error"].contains(parent)) {
                    result[key] = .string("[REDACTED]")
                } else {
                    result[key] = clean(nested, legacyErrors: legacy, parent: normalized)
                }
            }
            if isSnapshot {
                // A version upgrade must also retain the v29 storage contract:
                // never relabel a pre-v3 snapshot while keeping redundant bodies.
                if version < 3 {
                    for key in ["request", "providerRequests", "providerTranscript", "events"] { result.removeValue(forKey: key) }
                    if case var .object(state)? = result["state"] {
                        state.removeValue(forKey: "messages")
                        state.removeValue(forKey: "streamingMessage")
                        result["state"] = .object(state)
                    }
                    result["legacyCompacted"] = .number(1)
                    result["redactions"] = .array([.string("Credentials, message bodies, image bytes, and provider payload bodies")])
                }
                result["version"] = .number(4)
            }
            return .object(result)
        case let .array(values): return .array(values.map { clean($0, legacyErrors: legacyErrors, parent: parent) })
        case let .string(text):
            // Persisted checkpoints sometimes contain an encoded snapshot string.
            if text.contains("yamabiko.pi-agent-execution") { return .string(sanitizeEncoded(text)) }
            return .string(DiagnosticsLogSanitizer.sanitize(text))
        default: return value
        }
    }
}
