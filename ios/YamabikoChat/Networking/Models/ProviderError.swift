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