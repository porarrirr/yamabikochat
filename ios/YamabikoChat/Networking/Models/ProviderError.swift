import Foundation

enum ProviderClientError: LocalizedError, Sendable {
    case missingCredential(String)
    case invalidBaseURL(String)
    case invalidResponse
    case httpStatus(Int, String)
    case providerFailure(statusCode: Int?, code: String?, message: String)
    case parseFailure(String)
    case unsupportedModel(provider: String, model: String)

    var errorDescription: String? {
        switch self {
        case let .missingCredential(provider):
            if provider.uppercased() == "GEMINI_OAUTH_CLIENT" {
                return "API credential is missing for the selected provider."
            }
            return "Missing credential for \(provider)."
        case let .invalidBaseURL(value):
            return "Invalid base URL: \(value)."
        case .invalidResponse:
            return "Invalid API response."
        case let .httpStatus(status, body):
            return "HTTP \(status): \(body)"
        case let .providerFailure(statusCode, code, message):
            let status = statusCode.map { "HTTP \($0)" } ?? "Provider error"
            let suffix = code?.trimmedNonEmpty.map { " [\($0)]" } ?? ""
            return "\(status)\(suffix): \(message)"
        case let .parseFailure(reason):
            return "Response parse failed: \(reason)"
        case let .unsupportedModel(provider, model):
            return "Unsupported model for \(provider): \(model)."
        }
    }
}
