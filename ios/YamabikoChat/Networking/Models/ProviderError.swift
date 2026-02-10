import Foundation

enum ProviderClientError: LocalizedError, Sendable {
    case missingCredential(String)
    case invalidBaseURL(String)
    case invalidResponse
    case httpStatus(Int, String)
    case parseFailure(String)

    var errorDescription: String? {
        switch self {
        case let .missingCredential(provider):
            if provider.uppercased() == "GEMINI_OAUTH_CLIENT" {
                return "Gemini OAuth client ID/secret is missing. Configure GEMINI_OAUTH_CLIENT_ID and GEMINI_OAUTH_CLIENT_SECRET in Info.plist."
            }
            return "Missing credential for \(provider)."
        case let .invalidBaseURL(value):
            return "Invalid base URL: \(value)."
        case .invalidResponse:
            return "Invalid API response."
        case let .httpStatus(status, body):
            return "HTTP \(status): \(body)"
        case let .parseFailure(reason):
            return "Response parse failed: \(reason)"
        }
    }
}
