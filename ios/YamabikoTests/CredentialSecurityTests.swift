import Security
import GRDB
import XCTest
@testable import YamabikoChat

final class CredentialSecurityTests: XCTestCase {
    func testOnlyHTTPSAndExactLoopbackHTTPAreAllowed() throws {
        for address in ["http://api.example/v1", "http://192.168.0.2/v1", "http://127.0.0.1.attacker.example/v1", "https://user:password@api.example/v1"] {
            XCTAssertFalse(SecureProviderEndpoint.isAllowed(try XCTUnwrap(URL(string: address))), address)
        }
        for address in ["https://api.example/v1", "http://127.0.0.1:1234/v1", "http://localhost:1234/v1", "http://[::1]:1234/v1"] {
            XCTAssertTrue(SecureProviderEndpoint.isAllowed(try XCTUnwrap(URL(string: address))), address)
        }
    }

    func testExistingKeychainItemIsUpgradedToDeviceOnlyProtection() throws {
        let service = "com.yamabiko.test.\(UUID())"
        let store = KeychainStore(service: service)
        defer { try? store.deleteSecret(key: "synthetic") }
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "synthetic", kSecValueData: Data("test-secret".utf8), kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecMissingEntitlement {
            throw XCTSkip("Keychain migration requires an ad hoc signed simulator test host; CODE_SIGNING_ALLOWED=NO has no Keychain entitlement.")
        }
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertEqual(try store.readSecret(key: "synthetic"), "test-secret")
        var result: AnyObject?
        let attributes: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "synthetic", kSecReturnAttributes: true]
        XCTAssertEqual(SecItemCopyMatching(attributes as CFDictionary, &result), errSecSuccess)
        XCTAssertEqual((result as? [String: Any])?[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    func testLegacySnapshotErrorBodiesAreRemovedBeforeExport() throws {
        let json = #"{"format":"yamabiko.pi-agent-execution","version":3,"state":{"errorMessage":"unknown-unlabelled-secret"},"failure":{"message":"unknown-unlabelled-secret"},"credentials":{"refresh_token":"synthetic-refresh"}}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let clean = String(decoding: try JSONEncoder().encode(PiDiagnosticSanitizer.sanitize(value)), as: UTF8.self)
        XCTAssertFalse(clean.contains("unknown-unlabelled-secret"))
        XCTAssertFalse(clean.contains("synthetic-refresh"))
        XCTAssertTrue(clean.contains("REDACTED"))
        XCTAssertTrue(clean.contains("yamabiko.pi-agent-execution"))
        XCTAssertEqual(PiDiagnosticSanitizer.sanitize(value), PiDiagnosticSanitizer.sanitize(PiDiagnosticSanitizer.sanitize(value)))
    }

    func testQuotedCredentialJSONIsRedacted() {
        let input = #"request failed {"api_key":"secret-one", "refresh_token": "secret-two", "authorization_token":"secret-three"}"#
        let output = DiagnosticsLogSanitizer.sanitize(input)
        for value in ["secret-one", "secret-two", "secret-three"] { XCTAssertFalse(output.contains(value)) }
        let prefixed = PiDiagnosticSanitizer.sanitize(.string("yamabiko.pi-agent-execution " + input))
        XCTAssertFalse(prefixed.stringValue?.contains("secret-one") ?? true)
    }

    func testDatabaseUpgradeRemovesLegacyErrorsFromStoredSnapshots() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v33_retire_fusion")
        let repository = ConversationRepository(dbQueue: queue)
        let conversation = try repository.createConversation(title: "security", model: "test", provider: "TEST", systemPrompt: "")
        let message = try repository.insertMessage(ChatMessage(conversationId: conversation, role: "model", text: "keep this answer"))
        let legacy = #"{"format":"yamabiko.pi-agent-execution","version":3,"failure":{"message":"synthetic-unlabelled-secret"},"state":{"errorMessage":"synthetic-unlabelled-secret"}}"#
        try queue.write { db in
            try db.execute(sql: "INSERT INTO chat_message_tool_activity (messageId, piExecutionJSON) VALUES (?, ?)", arguments: [message, legacy])
        }
        try AppDatabase.migrator.migrate(queue)
        let saved = try XCTUnwrap(repository.fetchFullMessage(id: message))
        let encoded = String(decoding: try JSONEncoder().encode(saved.toolActivity?.piExecution), as: UTF8.self)
        XCTAssertFalse(encoded.contains("synthetic-unlabelled-secret"))
        XCTAssertTrue(encoded.contains("yamabiko.pi-agent-execution"))
        XCTAssertEqual(saved.message.text, "keep this answer")
    }
}
