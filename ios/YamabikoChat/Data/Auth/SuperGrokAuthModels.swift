import Foundation

struct SuperGrokDeviceCodeChallenge: Equatable, Sendable {
    var verificationURI: String
    var userCode: String
    var browserURL: String
}

struct SuperGrokAuthState: Equatable, Sendable {
    var isLoggedIn: Bool = false
    var email: String? = nil
    var lastRefreshISO8601: String? = nil
    var pendingDeviceCode: SuperGrokDeviceCodeChallenge? = nil
}
