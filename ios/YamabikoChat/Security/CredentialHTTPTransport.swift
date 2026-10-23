import Foundation

/// Credential-bearing requests must never replay a body or header at a redirect target.
enum CredentialHTTPTransport {
    static let shared = makeSession()

    static func makeSession() -> URLSession {
        URLSession(configuration: .ephemeral, delegate: RejectRedirects(), delegateQueue: nil)
    }

    private final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }
}
