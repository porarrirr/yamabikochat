import GRDB
import XCTest
@testable import YamabikoChat

final class SecretConversationVaultTests: XCTestCase {
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
            pricingRepository: FusionNoopPricingRepository()
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
