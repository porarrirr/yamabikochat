import XCTest
import GRDB
@testable import YamabikoChat

final class ReviewRegressionTests: XCTestCase {
    func testPiRequiresExactlyOneValidCompletion() throws {
        var state = PiStreamCompletionState()
        XCTAssertThrowsError(try state.finish())
        XCTAssertThrowsError(try state.complete(hasResponse: false))
        XCTAssertThrowsError(try state.finish())
        try state.complete(hasResponse: true)
        try state.finish()
        XCTAssertThrowsError(try state.complete(hasResponse: true))
    }

    func testHTMLPolicyPrecedesAllUntrustedMarkup() {
        for html in ["<!-- fake <head> --> <html><head></head></html>", "<html title='>'><head></head>", "<img src='https://example.test/pixel' srcset='https://example.test/x 2x'>", "<style>body { background: url(https://example.test/css) }</style>"] {
            let result = HtmlPreviewWebView.Coordinator.sandbox(html)
            XCTAssertTrue(result.hasPrefix("<!doctype html><html><head><meta http-equiv=\"Content-Security-Policy\""))
            XCTAssertTrue(result.hasSuffix(html + "</body></html>"))
        }
    }

    func testFusionRejectsNonImageAttachmentsExplicitly() throws {
        XCTAssertThrowsError(try FusionService.validateAttachments(["/tmp/document.pdf"]))
        XCTAssertThrowsError(try FusionService.validateAttachments(["/tmp/document.txt"]))
        XCTAssertNoThrow(try FusionService.validateAttachments(["/tmp/photo.png"]))
    }

    func testVisionUsesPiInputContractWithoutPricingOrCredentials() async throws {
        let db = try DatabaseQueue()
        try AppDatabase.migrator.migrate(db)
        let gateway = ProviderGateway(settingsRepository: SettingsRepository(dbQueue: db), credentialStore: PiAuthTestCredentialStore(), piModelResolver: { configs in
            XCTAssertEqual(configs.first?.provider, "openai")
            XCTAssertEqual(configs.first?.model, "gpt-4.1")
            return [PiModelResolution(supported: true, input: ["text", "image"])]
        })
        let supported = try await gateway.modelSupportsVision(provider: "OPENAI", model: "gpt-4.1")
        XCTAssertTrue(supported)
    }

    func testUnresolvedVisionIsAnErrorRatherThanUnsupported() async throws {
        let db = try DatabaseQueue()
        try AppDatabase.migrator.migrate(db)
        let gateway = ProviderGateway(settingsRepository: SettingsRepository(dbQueue: db), credentialStore: PiAuthTestCredentialStore(), piModelResolver: { _ in
            [PiModelResolution(supported: false, reason: "missing_contract")]
        })
        do {
            _ = try await gateway.modelSupportsVision(provider: "OPENAI", model: "unknown")
            XCTFail("Unknown capability must not be returned as false")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("missing_contract"))
        }
    }

    func testShareInboxIsDurableDistinctAndIdempotent() throws {
        let db = try DatabaseQueue()
        try AppDatabase.migrator.migrate(db)
        let repository = ConversationRepository(dbQueue: db)
        let first = try XCTUnwrap(repository.importShare(payloadID: "first", text: "one", model: "model", provider: "provider", systemPrompt: nil))
        let second = try XCTUnwrap(repository.importShare(payloadID: "second", text: "two", model: "model", provider: "provider", systemPrompt: nil))
        XCTAssertNotEqual(first, second)
        let restarted = ConversationRepository(dbQueue: db)
        XCTAssertEqual(try restarted.shareImportText(conversationID: first), "one")
        XCTAssertEqual(try restarted.shareImportText(conversationID: second), "two")
        XCTAssertEqual(try restarted.importShare(payloadID: "first", text: "changed", model: "model", provider: "provider", systemPrompt: nil), first)
        XCTAssertEqual(try restarted.shareImportText(conversationID: first), "one")
        _ = try restarted.insertMessage(ChatMessage(conversationId: first, role: "user", text: "one"))
        XCTAssertNil(try restarted.shareImportText(conversationID: first))
        try restarted.deleteConversation(id: first)
        XCTAssertNil(try restarted.importShare(payloadID: "first", text: "one", model: "model", provider: "provider", systemPrompt: nil))
    }

    func testShareInboxTransactionDoesNotLeaveAnEmptyConversationOnFailure() throws {
        let db = try DatabaseQueue()
        try AppDatabase.migrator.migrate(db)
        try db.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_share BEFORE INSERT ON share_imports BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        let repository = ConversationRepository(dbQueue: db)
        XCTAssertThrowsError(try repository.importShare(payloadID: "first", text: "one", model: "model", provider: "provider", systemPrompt: nil))
        XCTAssertEqual(try repository.allConversationIDs(), [])
    }

    func testStandardExportRemovesNestedDiagnosticsFromEveryMessageKind() throws {
        let db = try DatabaseQueue()
        try AppDatabase.migrator.migrate(db)
        let repository = ConversationRepository(dbQueue: db)
        let id = try repository.createConversation(title: "test", model: "m", provider: "p")
        var snapshot = try repository.fetchDebugExport(conversationId: id)
        let marker = "PRIVATE_DIAGNOSTIC_MARKER"
        snapshot.messages = [ConversationMessageDebugExport(
            message: ChatMessage(conversationId: id, role: "model", text: "answer"),
            thinkingStream: marker, attachments: [], toolActivity: nil,
            variants: [ConversationVariantDebugExport(variant: ChatMessageVariant(baseMessageId: 1, variantIndex: 1, text: "variant", thinkingStream: marker), attachments: [], toolActivity: nil)]
        )]
        snapshot.dualMessages = [DualMessageDebugExport(message: DualChatMessage(conversationId: id, userText: "q", modelAText: "a", modelBText: "b", modelAName: "a", modelBName: "b", providerA: "p", providerB: "p", modelAThinking: marker, modelBThinking: marker, modelAToolActivityJSON: marker, modelBToolActivityJSON: marker), attachments: [], modelAToolActivity: nil, modelBToolActivity: nil)]
        snapshot.autoConversations = [AutoConversationDebugExport(conversation: AutoConversation(title: "auto", modelA: "a", modelB: "b", providerA: "p", providerB: "p", systemPromptA: "", systemPromptB: "", maxTurns: 2), messages: [AutoConversationMessageDebugExport(message: AutoConversationMessage(autoConversationId: 1, speakerModel: .a, content: "answer", reasoning: marker, turnNumber: 1, piExecutionJSON: marker), piExecution: .string(marker))])]
        let standard = ConversationExportService.preparedExport(snapshot, mode: .standard)
        let encoded = String(decoding: try JSONEncoder().encode(StandardConversationExport(snapshot)), as: UTF8.self)
        XCTAssertNil(standard.messages[0].variants[0].variant.thinkingStream)
        XCTAssertFalse(encoded.contains(marker))
        for field in ["thinkingStream", "modelAThinking", "modelBThinking", "piExecutionJSON", "modelAToolActivityJSON", "modelBToolActivityJSON", "reasoning"] {
            XCTAssertFalse(encoded.contains("\"\(field)\""), field)
        }
        let diagnostic = ConversationExportService.preparedExport(snapshot, mode: .fullDiagnostics)
        XCTAssertEqual(diagnostic.dualMessages[0].message.modelAThinking, marker)
        XCTAssertEqual(diagnostic.autoConversations[0].messages[0].message.reasoning, marker)
    }

    func testPiRequestPreservesExplicitSkillAndNativeHistory() throws {
        let skill = SkillRequestContext(catalog: [], explicitlyRequestedNames: ["review"], explicitInstructions: ["instructions"], resourceLists: ["resources"], skillFilePaths: ["/skills/review/SKILL.md"], explicitMessageIndices: [0], conversationID: "1", enabledSkillSetHash: "hash")
        let native: JSONValue = .object(["provider": .string("openai"), "model": .string("source"), "api": .string("openai-responses")])
        let request = ProviderRequest(model: "target", messages: [ProviderRequestMessage(role: "user", content: "@review"), ProviderRequestMessage(role: "assistant", content: "answer", piMessage: native)], skillContext: skill)
        let encoded = try JSONEncoder().encode(PiAgentRuntime.makeRequest(request))
        let decoded = try JSONDecoder().decode(PiRequest.self, from: encoded)
        XCTAssertEqual(decoded.skillContext, skill)
        XCTAssertEqual(decoded.messages[1].piMessage, native)
    }

    func testQueuedPythonCancellationDoesNotAcquireTheInterpreter() async throws {
        let queue = PythonJobQueue()
        let first = UUID()
        try await queue.acquire(first)
        let queued = Task {
            try await queue.acquire(UUID())
            XCTFail("Cancelled queued job acquired the interpreter")
        }
        await Task.yield()
        queued.cancel()
        do { try await queued.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("\(error)") }
        await queue.release(first)
        let next = UUID()
        try await queue.acquire(next)
        await queue.release(next)
    }

    func testPoisonedInterpreterRejectsWaitingAndFutureJobs() async throws {
        let queue = PythonJobQueue()
        try await queue.acquire(UUID())
        let queued = Task { try await queue.acquire(UUID()) }
        await Task.yield()
        await queue.poison()
        do { try await queued.value; XCTFail("Expected poison") } catch { XCTAssertEqual(error as? PythonToolError, .poisoned) }
        do { try await queue.acquire(UUID()); XCTFail("Expected poison") } catch { XCTAssertEqual(error as? PythonToolError, .poisoned) }
    }

    func testDelayedCodexLoginCannotRestoreLoggedOutCredentials() async throws {
        let started = expectation(description: "login started")
        let delayed = ReviewResolutionLatch()
        let store = PiAuthTestCredentialStore()
        let repository = CodexAuthRepository(credentialStore: store, loginHandler: { _, _, _ in
            started.fulfill()
            return await delayed.wait()
        })
        let login = Task { await repository.loginWithBrowser() }
        await fulfillment(of: [started], timeout: 2)
        _ = await repository.logout()
        await delayed.finish()
        _ = await login.value
        XCTAssertFalse(repository.currentState().isLoggedIn)
        XCTAssertFalse(repository.hasAuthToken())
    }

    func testDelayedSuperGrokResolutionCannotRestoreLoggedOutCredentials() async throws {
        let started = expectation(description: "resolution started")
        let delayed = ReviewResolutionLatch()
        let store = PiAuthTestCredentialStore()
        try store.saveSecret("old", key: "pi_oauth_supergrok_v1")
        let repository = SuperGrokAuthRepository(credentialStore: store, resolveHandler: { _, _, _ in
            started.fulfill()
            return await delayed.wait()
        })
        let resolve = Task { await repository.getBearerToken() }
        await fulfillment(of: [started], timeout: 2)
        _ = await repository.logout()
        await delayed.finish()
        let result = await resolve.value
        XCTAssertNil(result)
        XCTAssertFalse(repository.currentState().isLoggedIn)
        XCTAssertFalse(repository.hasAuthToken())
    }
}

private actor ReviewResolutionLatch {
    private var continuation: CheckedContinuation<PiOAuthResolution, Never>?
    private var finished = false
    func wait() async -> PiOAuthResolution {
        if finished { return oauthResolution() }
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() {
        finished = true
        continuation?.resume(returning: oauthResolution())
        continuation = nil
    }
}
