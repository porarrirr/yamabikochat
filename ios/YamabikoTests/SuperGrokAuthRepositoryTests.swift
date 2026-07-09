import XCTest
@testable import YamabikoChat

final class SuperGrokAuthRepositoryTests: XCTestCase {
    func testAuthorizeURLConstants() {
        XCTAssertEqual(SuperGrokAuthConstants.clientID, "b1a00492-073a-47ea-816f-4c329264a828")
        XCTAssertEqual(SuperGrokAuthConstants.redirectURI, "http://127.0.0.1:56121/callback")
        XCTAssertTrue(SuperGrokAuthConstants.scope.contains("grok-cli:access"))
    }

    func testAccessTokenIsExpiringHonorsSkew() {
        let expired = makeJWT(exp: Int(Date().timeIntervalSince1970) - 60)
        XCTAssertTrue(SuperGrokJWTParser.accessTokenIsExpiring(expired, skewMs: 0))

        let fresh = makeJWT(exp: Int(Date().timeIntervalSince1970) + 3_600)
        XCTAssertFalse(SuperGrokJWTParser.accessTokenIsExpiring(fresh, skewMs: 0))
        XCTAssertTrue(SuperGrokJWTParser.accessTokenIsExpiring(fresh, skewMs: 3_600_000))
    }

    func testAccessTokenIsExpiringAcceptsNonIntExpClaims() {
        let exp = Int(Date().timeIntervalSince1970) - 30
        let asDouble = makeJWT(expJSON: String(Double(exp)))
        let asString = makeJWT(expJSON: "\"\(exp)\"")
        XCTAssertTrue(SuperGrokJWTParser.accessTokenIsExpiring(asDouble, skewMs: 0))
        XCTAssertTrue(SuperGrokJWTParser.accessTokenIsExpiring(asString, skewMs: 0))
    }

    func testRefreshErrorClassification() {
        XCTAssertEqual(
            SuperGrokAuthRefreshError.classified(from: #"{"error":"invalid_grant"}"#),
            .expired
        )
        XCTAssertEqual(
            SuperGrokAuthRefreshError.classified(from: #"{"error":"refresh_token_reused"}"#),
            .reused
        )
    }

    func testSuperGrokModelCatalogNormalization() {
        XCTAssertEqual(SuperGrokModelCatalog.normalizedModelID("supergrok/grok-4.3"), "grok-4.3")
        XCTAssertEqual(SuperGrokModelCatalog.model(for: "grok-build-0.1")?.id, "grok-build-0.1")
        XCTAssertEqual(SuperGrokModelCatalog.model(for: "grok-4.5")?.id, "grok-4.5")
        XCTAssertEqual(SuperGrokModelCatalog.model(for: "grok-4.5")?.supportsReasoning, true)
        XCTAssertEqual(SuperGrokModelCatalog.defaultModel, "grok-4.5")
    }

    private func makeJWT(exp: Int) -> String {
        makeJWT(expJSON: String(exp))
    }

    private func makeJWT(expJSON: String) -> String {
        let header = Data("{\"alg\":\"none\",\"typ\":\"JWT\"}".utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        let payloadObject = "{\"exp\":\(expJSON)}"
        let payload = Data(payloadObject.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return "\(header).\(payload).sig"
    }
}