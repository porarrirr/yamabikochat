import Foundation

enum SecureProviderEndpoint {
    static func isAllowed(_ url: URL) -> Bool {
        guard url.host != nil, url.user == nil, url.password == nil else { return false }
        if url.scheme?.lowercased() == "https" { return true }
        return url.scheme?.lowercased() == "http" && ["127.0.0.1", "localhost", "[::1]", "::1"].contains(url.host?.lowercased() ?? "")
    }
}
