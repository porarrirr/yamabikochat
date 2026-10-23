import GRDB
import XCTest
@testable import YamabikoChat

final class SecretConversationVaultTests: XCTestCase {
    func testSecretSingleAndDualRequestsNeverCarryChildCredentialsForChatGPTSuperGrokOrAPI() async throws {
        for provider in ["OPENAI", "CODEX_AUTH", "SUPERGROK"] {
            let queue = try DatabaseQueue()
            try AppDatabase.migrator.migrate(queue)
            let settingsRepo = SettingsRepository(dbQueue: queue)
            let credentials = PiAuthTestCredentialStore()
            try credentials.setCredential("synthetic-api-key", for: .openAI)
            try credentials.setCredential("synthetic-child-key", for: .gemini)
            let codex = CodexAuthRepository(credentialStore: credentials,
                loginHandler: { host, _, _ in chatGPTResolution(hostID: host) },
                resolveHandler: { _, _, _ in chatGPTResolution() })
            let grok = SuperGrokAuthRepository(credentialStore: credentials,
                loginHandler: { _, _, _ in oauthResolution(accountID: nil) },
                resolveHandler: { _, _, _ in oauthResolution(accountID: nil) })
            _ = await codex.loginWithBrowser()
            _ = await grok.loginWithBrowser()
            var settings = AppSettings()
            settings.apiProvider = provider
            settings.defaultModel = provider == "SUPERGROK" ? "grok-4.5" : "gpt-6-sol"
            settings.dualProviderA = provider
            settings.dualProviderB = provider
            settings.dualModelA = settings.defaultModel
            settings.dualModelB = settings.defaultModel
            settings.subagents = SubagentSettings(enabled: true, defaultModelID: "child", models: [
                SubagentModelProfile(id: "child", provider: "GEMINI", model: "gemini-2.5-flash")
            ])
            try settingsRepo.save(settings)
            let spy = PiStreamSpy()
            let repository = ChatRepositoryTestSupport.makeRepository(dbQueue: queue, settings: settingsRepo,
                conversations: ConversationRepository(dbQueue: queue), credentials: credentials, piStream: spy.stream,
                codexAuthRepository: codex, superGrokAuthRepository: grok)
            let id = try repository.createSecretConversation()
            defer { SecretConversationVault.shared.destroy(conversationID: id) }
            _ = try await repository.sendMessage(conversationId: id, text: "synthetic private message", attachments: [])
            _ = try await repository.sendDualMessage(conversationId: id, text: "synthetic dual private message")
            XCTAssertEqual(spy.calls.count, 3, provider)
            for call in spy.calls {
                XCTAssertEqual(call.request.executionPolicy, .restricted, provider)
                XCTAssertEqual(call.request.metadata["supportsClientTools"], "false")
                XCTAssertEqual(call.request.metadata["subagentsEnabled"], "false")
                XCTAssertTrue(call.request.tools.isEmpty)
                XCTAssertNil(call.configuration.subagents)
                let encoded = String(decoding: try JSONEncoder().encode(call.configuration), as: UTF8.self)
                XCTAssertFalse(encoded.contains("synthetic-child-key"))
            }
        }
    }

    func testDestroyingProcessKeyMakesCiphertextUnreadable() throws {
        let vault = SecretConversationVault.shared
        let conversationID = Int64.random(in: 1_000_000...Int64.max)
        defer { vault.destroy(conversationID: conversationID) }

        vault.activate(conversationID: conversationID)
        let ciphertext = try vault.seal("sensitive text", conversationID: conversationID)

        XCTAssertTrue(ciphertext.hasPrefix(SecretConversationVault.prefix))
        XCTAssertFalse(ciphertext.contains("sensitive text"))
        XCTAssertEqual(try vault.open(ciphertext, conversationID: conversationID), "sensitive text")

        vault.destroy(conversationID: conversationID)
        XCTAssertThrowsError(try vault.open(ciphertext, conversationID: conversationID))
    }

    func testSecretRepositoryRowsNeverContainPlaintextAndToolActivityIsNotStored() throws {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)
        let repository = ConversationRepository(dbQueue: dbQueue)
        let marker = "secret-marker-\(UUID().uuidString)"
        let conversationID = try repository.createConversation(
            title: marker,
            model: "test-model",
            provider: "TEST",
            systemPrompt: marker,
            isSecret: true
        )
        defer { SecretConversationVault.shared.destroy(conversationID: conversationID) }

        let messageID = try repository.insertMessage(
            ChatMessage(
                conversationId: conversationID,
                role: "user",
                text: marker,
                createdAtMs: 1
            )
        )
        try repository.saveToolActivity(
            messageId: messageID,
            variantId: nil,
            payload: ToolActivityPayload(steps: [], providerTranscript: [], attachmentPaths: [])
        )

        let stored: (String, String, Int) = try dbQueue.read { db in
            let prompt = try String.fetchOne(
                db,
                sql: "SELECT systemPrompt FROM conversations WHERE id = ?",
                arguments: [conversationID]
            ) ?? ""
            let text = try String.fetchOne(
                db,
                sql: "SELECT text FROM chat_messages WHERE id = ?",
                arguments: [messageID]
            ) ?? ""
            let activityCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM chat_message_tool_activity WHERE messageId = ?",
                arguments: [messageID]
            ) ?? 0
            return (prompt, text, activityCount)
        }

        XCTAssertTrue(stored.0.hasPrefix(SecretConversationVault.prefix))
        XCTAssertTrue(stored.1.hasPrefix(SecretConversationVault.prefix))
        XCTAssertFalse(stored.0.contains(marker))
        XCTAssertFalse(stored.1.contains(marker))
        XCTAssertEqual(stored.2, 0)
        XCTAssertEqual(try repository.fetchFullMessage(id: messageID)?.message.text, marker)
    }

    func testPlaintextBeginningWithStoragePrefixIsStillEncrypted() throws {
        let vault = SecretConversationVault.shared
        let conversationID = Int64.random(in: 1_000_000...Int64.max)
        let plaintext = SecretConversationVault.prefix + "user supplied text"
        defer { vault.destroy(conversationID: conversationID) }

        vault.activate(conversationID: conversationID)
        let ciphertext = try vault.seal(plaintext, conversationID: conversationID)

        XCTAssertNotEqual(ciphertext, plaintext)
        XCTAssertEqual(try vault.open(ciphertext, conversationID: conversationID), plaintext)
    }

    func testNormalConversationCanStoreTextBeginningWithStoragePrefix() throws {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)
        let repository = ConversationRepository(dbQueue: dbQueue)
        let plaintext = SecretConversationVault.prefix + "ordinary message"
        let conversationID = try repository.createConversation(
            title: "Normal",
            model: "test-model",
            provider: "TEST"
        )
        let messageID = try repository.insertMessage(
            ChatMessage(conversationId: conversationID, role: "user", text: plaintext, createdAtMs: 1)
        )

        XCTAssertEqual(try repository.fetchFullMessage(id: messageID)?.message.text, plaintext)
    }

    func testSecretConversationRejectsAttachmentsBeforePersistingMessage() async throws {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)
        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = SecretVaultTestCredentialStore()
        let repository = ChatRepositoryTestSupport.makeRepository(
            dbQueue: dbQueue,
            settings: settings,
            conversations: conversations,
            credentials: credentials,
            pricingRepository: ChatTestNoopPricingRepository()
        )
        let conversationID = try repository.createSecretConversation()
        defer { SecretConversationVault.shared.destroy(conversationID: conversationID) }

        do {
            _ = try await repository.sendMessage(
                conversationId: conversationID,
                text: "must not persist",
                attachments: ["/tmp/plaintext.txt"]
            )
            XCTFail("Secret conversations must reject attachments")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("添付ファイル"))
        }

        XCTAssertTrue(try conversations.fetchMessages(conversationId: conversationID).isEmpty)
    }
}

private struct SecretVaultTestCredentialStore: SecureCredentialStore {
    func saveSecret(_ value: String?, key: String) throws {}
    func readSecret(key: String) throws -> String? { nil }
    func deleteSecret(key: String) throws {}
}
