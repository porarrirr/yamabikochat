import Security
import Network
import GRDB
import XCTest
@testable import YamabikoChat

final class CredentialSecurityTests: XCTestCase {
    func testCredentialTransportDoesNotReplayPostAtRedirectTarget() async throws {
        let target = try CredentialRedirectFixture(location: nil)
        let targetPort = try await target.start()
        defer { target.stop() }
        let source = try CredentialRedirectFixture(location: "http://127.0.0.1:\(targetPort)/capture")
        let sourcePort = try await source.start()
        defer { source.stop() }
        let request = HTTPRequest(url: URL(string: "http://127.0.0.1:\(sourcePort)/auth")!,
            headers: ["Authorization": "Bearer synthetic", "Content-Type": "application/json"],
            body: Data(#"{"refresh_token":"synthetic-private-token"}"#.utf8))
        let (_, response) = try await URLSessionHTTPClient().send(request)
        XCTAssertEqual(response.statusCode, 307)
        XCTAssertEqual(source.requestCount, 1)
        XCTAssertEqual(target.requestCount, 0)
    }

    func testAllDormantCredentialsAreHardenedWithoutReadingTheirValues() throws {
        let service = "com.yamabiko.test.\(UUID())"
        let store = KeychainStore(service: service)
        defer { for key in ["inactive", "new"] { try? store.deleteSecret(key: key) } }
        let old: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: "inactive", kSecValueData: Data("synthetic-inactive".utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemAdd(old as CFDictionary, nil)
        if status == errSecMissingEntitlement { throw XCTSkip("Requires a signed Keychain test host") }
        XCTAssertEqual(status, errSecSuccess)
        try store.hardenExistingSecrets()
        try store.saveSecret("synthetic-new", key: "new")
        for key in ["inactive", "new"] {
            var result: AnyObject?
            let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                kSecAttrAccount: key, kSecReturnAttributes: true]
            XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
            let fields = try XCTUnwrap(result as? [String: Any])
            XCTAssertEqual(fields[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
            XCTAssertNotEqual(fields[kSecAttrSynchronizable as String] as? Bool, true)
        }
        XCTAssertEqual(try store.readSecret(key: "new"), "synthetic-new")
    }

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
        XCTAssertEqual((result as? [String: Any])?[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }

    func testOAuthBrowserURLsArePinnedBeforeOpeningSystemBrowser() throws {
        for address in ["http://auth.x.ai/device", "https://auth.x.ai.attacker.example/device", "https://user@auth.x.ai/device", "https://auth.x.ai:444/device", "https://attacker.example/", "https://auth.x.ai/device?refresh_token=synthetic"] {
            XCTAssertFalse(PiOAuthProvider.supergrok.allowsAuthorizationURL(try XCTUnwrap(URL(string: address))))
        }
        XCTAssertTrue(PiOAuthProvider.supergrok.allowsAuthorizationURL(URL(string: "https://accounts.x.ai/device?user_code=ABCD")!))
        XCTAssertFalse(PiOAuthProvider.chatgpt.allowsAuthorizationURL(URL(string: "https://auth.x.ai/")!))
        XCTAssertTrue(PiOAuthProvider.chatgpt.allowsAuthorizationURL(URL(string: "https://auth.openai.com/authorize?id_token_hint=synthetic")!))
    }

    func testProtectedFilesAndExistingTreeAreExcludedFromBackupAfterAtomicReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("legacy/file.txt")
        try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original".utf8).write(to: old)
        try ProtectedFileStorage.protectExistingTree(root)
        try ProtectedFileStorage.write(Data("replacement".utf8), to: old)
        for url in [root, old.deletingLastPathComponent(), old] {
            XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        }
        XCTAssertEqual(try String(contentsOf: old), "replacement")
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

private final class CredentialRedirectFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "credential-redirect-fixture")
    private let lock = NSLock()
    private let location: String?
    private var count = 0
    var requestCount: Int { lock.withLock { count } }

    init(location: String?) throws {
        self.location = location
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready: continuation.resume(returning: listener.port!.rawValue)
                case let .failed(error): continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connection.start(queue: self.queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, _, _ in
                    guard data?.isEmpty == false else { connection.cancel(); return }
                    self.lock.withLock { self.count += 1 }
                    let status = self.location == nil ? "200 OK" : "307 Temporary Redirect"
                    let redirect = self.location.map { "Location: \($0)\r\n" } ?? ""
                    let response = Data("HTTP/1.1 \(status)\r\n\(redirect)Content-Length: 0\r\nConnection: close\r\n\r\n".utf8)
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }
}
