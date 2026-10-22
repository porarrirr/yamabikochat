import XCTest
import GRDB
@testable import YamabikoChat

private final class SubagentCredentialStore: SecureCredentialStore {
    var values: [String: String] = [:]
    func saveSecret(_ value: String?, key: String) throws { values[key] = value }
    func readSecret(key: String) throws -> String? { values[key] }
    func deleteSecret(key: String) throws { values.removeValue(forKey: key) }
}

final class SubagentTests: XCTestCase {
    @MainActor
    func testChildOutputUsesMainResponseStreamingPresentation() throws {
        var child = run(status: .running)
        child.output = "# 確認結果\n\n**重要**な結果\n\n- 項目\n\n```swift\nlet result ="
        let store = ChatTimelineRowStore(subagent: child)
        let parent = ChatTimelineRowStore(item: store.item)

        for suffix in ["", " true\n```\n\n次の段落", "\n\n[資料](https://example.org)"] {
            child.output += suffix
            store.apply(subagent: child)
            let snapshot = try XCTUnwrap(store.streamingSnapshot)
            parent.apply(snapshot: snapshot)
            XCTAssertFalse(snapshot.isFinal)
            XCTAssertEqual(snapshot.text, child.output)
            XCTAssertEqual(store.streamingMarkdownBlocks, parent.streamingMarkdownBlocks)
            XCTAssertEqual(store.streamingMarkdownBlocks, NativeMarkdownParser.parse(child.output, rendersMath: false))
        }

        for status in [SubagentRun.Status.completed, .failed, .cancelled] {
            child.status = status
            store.apply(subagent: child)
            let snapshot = try XCTUnwrap(store.streamingSnapshot)
            parent.apply(snapshot: snapshot)
            XCTAssertTrue(snapshot.isFinal)
            XCTAssertEqual(snapshot.text, child.output)
            XCTAssertEqual(store.streamingMarkdownBlocks, parent.streamingMarkdownBlocks)
            XCTAssertFalse(try XCTUnwrap(store.streamingMarkdownBlocks).isEmpty)
        }
    }

    @MainActor
    func testChildCompletionExtractsArtifactsLikeMainResponse() throws {
        var child = run(status: .running)
        child.output = "# 結果\n\n```html\n<p>成果物</p>"
        let store = ChatTimelineRowStore(subagent: child)
        child.output += "\n```"
        child.status = .completed
        store.apply(subagent: child)

        let artifacts = ChatArtifactPresentation.items(from: child.output, isStreaming: false)
        XCTAssertEqual(artifacts.count, 1)
        let markdown = ExtractedFenceRemover.remove(
            from: child.output, ranges: artifacts.map { ($0.startIndex, $0.endIndex) }
        )
        XCTAssertEqual(store.streamingMarkdownBlocks, NativeMarkdownParser.parse(markdown, rendersMath: false))
        XCTAssertTrue(try XCTUnwrap(store.streamingSnapshot).isFinal)
    }

    private func run(status: SubagentRun.Status = .running, updatedAt: Int64 = 10) -> SubagentRun {
        SubagentRun(id: "child-1", agent: "調査", task: "公式資料を調べる", provider: "openai", model: "model",
            effort: "high", status: status, activity: "fetch_url を実行中", startedAtMs: 1,
            updatedAtMs: updatedAt, finishedAtMs: status == .running ? nil : updatedAt,
            output: "途中の結果", outputTruncated: false,
            events: [.init(id: "event-1", kind: "tool_start", title: "fetch_url", detail: "https://example.org", createdAtMs: 2)],
            eventsTruncated: false, usage: nil, error: nil)
    }

    func testSettingsDefaultToParentAndPreserveUnknownExtraFieldsAndUnavailableSelection() throws {
        var settings = AppSettings()
        XCTAssertTrue(settings.subagents.enabled)
        XCTAssertNil(settings.subagents.defaultModelID)
        settings.extraJSON = #"{"anotherSetting":{"enabled":true}}"#
        let profile = SubagentModelProfile(id: "saved", name: "調査用", provider: "MODELS_DEV:example", model: "retired-model", effort: "xhigh")
        settings.subagents = SubagentSettings(enabled: true, defaultModelID: "saved", models: [profile])
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.subagents.models, [profile])
        XCTAssertEqual(decoded.subagents.defaultModelID, "saved")
        XCTAssertTrue(decoded.extraJSON.contains("anotherSetting"))
        var disabled = decoded.subagents
        disabled.enabled = false
        settings.subagents = disabled
        XCTAssertEqual(settings.subagents.models, [profile])
        XCTAssertEqual(settings.subagents.defaultModelID, "saved")
    }

    func testPCCProfileDefaultsAndExplicitSelectionsPreserveSavedEffort() throws {
        var profile = SubagentModelProfile(provider: "APPLE_INTELLIGENCE", model: AppleIntelligenceModelCatalog.pccModel)
        XCTAssertEqual(profile.effort, "medium")
        XCTAssertEqual(SubagentModelProfile(provider: "OPENAI", model: "gpt-5.5").effort, "off")
        XCTAssertEqual(SubagentModelProfile(provider: "APPLE_INTELLIGENCE", model: AppleIntelligenceModelCatalog.displayModel).effort, "off")
        profile.effort = "off"
        var settings = AppSettings()
        settings.subagents = SubagentSettings(defaultModelID: profile.id, models: [profile])
        let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(saved.subagents.models.first?.effort, "off")
        XCTAssertEqual(saved.subagents.defaultModelID, profile.id)
        profile.initializePCCEffortIfNeeded()
        XCTAssertEqual(profile.effort, "medium")
        for effort in ["low", "medium", "high"] {
            profile.effort = effort
            profile.initializePCCEffortIfNeeded()
            XCTAssertEqual(profile.effort, effort)
        }
    }

    func testPCCEffortSelectionsPersistAndReachChildConfiguration() async throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue)
        let gateway = ProviderGateway(settingsRepository: SettingsRepository(dbQueue: queue), credentialStore: SubagentCredentialStore())
        for (effort, label) in [("low", "Light"), ("medium", "Moderate"), ("high", "Deep")] {
            var profile = SubagentModelProfile(provider: "APPLE_INTELLIGENCE", model: AppleIntelligenceModelCatalog.pccModel)
            // The child picker binds directly to this persisted value.
            profile.effort = effort
            var settings = AppSettings()
            settings.pccReasoningLevel = "light"
            settings.subagents = SubagentSettings(models: [profile])
            let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
            let childProfile = try XCTUnwrap(saved.subagents.models.first)
            let child = try await gateway.subagentConfiguration(childProfile, settings: saved)
            XCTAssertEqual(child.thinkingLevel, effort)
            XCTAssertEqual(AppleIntelligenceModelCatalog.effortDisplayName(childProfile.effort, provider: childProfile.provider, model: childProfile.model), label)
            XCTAssertEqual(AppleIntelligenceModelCatalog.effortDisplayName(effort, provider: child.provider, model: child.model), label)
        }
        XCTAssertEqual(AppleIntelligenceModelCatalog.effortDisplayName("off", provider: "APPLE_INTELLIGENCE", model: AppleIntelligenceModelCatalog.pccModel), "off")
        XCTAssertEqual(AppleIntelligenceModelCatalog.effortDisplayName("high", provider: "openai", model: "gpt-5.5"), "high")
    }

    func testProgressIsIdempotentPersistsDetailsAndDoesNotPolluteParentTranscript() throws {
        var payload = ToolActivityPayload()
        payload.applySubagent(run())
        payload.applySubagent(run(status: .completed, updatedAt: 20))
        payload.applySubagent(run(updatedAt: 30))
        XCTAssertEqual(payload.steps.count, 1)
        XCTAssertEqual(payload.subagents.first?.status, .completed)
        XCTAssertTrue(payload.providerTranscript.isEmpty)
        let decoded = try JSONDecoder().decode(ToolActivityPayload.self, from: JSONEncoder().encode(payload))
        XCTAssertEqual(decoded.subagents.first?.task, "公式資料を調べる")
        XCTAssertEqual(decoded.subagents.first?.events.first?.detail, "https://example.org")
        XCTAssertEqual(decoded.subagents.first?.output, "途中の結果")
        let legacy = try JSONDecoder().decode(ToolActivityPayload.self, from: Data(#"{"steps":[]}"#.utf8))
        XCTAssertTrue(legacy.subagents.isEmpty)
    }

    func testFleetSummaryStaysPinnedToOneChildWhileParallelSnapshotsInterleave() {
        var first = run(updatedAt: 10)
        first.id = "child-1"
        first.agent = "researcher 1"
        var second = run(updatedAt: 20)
        second.id = "child-2"
        second.agent = "researcher 2"
        var third = run(updatedAt: 30)
        third.id = "child-3"
        third.agent = "researcher 3"
        var fleet = [first, second, third]

        XCTAssertEqual(SubagentFleetView.summaryRun(in: fleet)?.agent, "researcher 1")

        // Newer snapshots from the other children must not steal the summary line.
        fleet[1].updatedAtMs = 40
        fleet[2].updatedAtMs = 50
        XCTAssertEqual(SubagentFleetView.summaryRun(in: fleet)?.agent, "researcher 1")

        // It advances only when the pinned child stops running.
        fleet[0].status = .completed
        XCTAssertEqual(SubagentFleetView.summaryRun(in: fleet)?.agent, "researcher 2")
        XCTAssertNil(SubagentFleetView.summaryRun(in: [fleet[0]]))
    }

    func testChildNativeResultsRemainInDetailsAndSurviveSubsequentSnapshots() {
        var payload = ToolActivityPayload()
        payload.applySubagent(run())
        let artifact = ToolArtifact(path: "/output/result.csv", name: "result.csv", mime: "text/csv", size: 8)
        payload.apply(ToolActivityEvent(phase: .finished,
            call: ToolCall(id: "native-tool", name: PythonExecuteTool.name, argumentsJSON: "{}"),
            result: ToolResult(callId: "native-tool", name: PythonExecuteTool.name, content: "done", artifacts: [artifact]),
            createdAtMs: 15, ownerSubagentID: "child-1"))
        payload.applySubagent(run(status: .completed, updatedAt: 20))
        XCTAssertEqual(payload.subagents.first?.artifacts, [artifact])
        XCTAssertEqual(payload.attachmentPaths, [artifact.path])
        XCTAssertTrue(payload.parentAttachmentPaths.isEmpty)
        XCTAssertEqual(payload.steps.count, 1)
        XCTAssertTrue(payload.providerTranscript.isEmpty)
    }

    func testColdLaunchMarksUnfinishedChildrenInterruptedAndRetainsTheirOutput() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue)
        let conversations = ConversationRepository(dbQueue: queue)
        let conversation = try conversations.createConversation(title: "Subagents", model: "model", provider: "OPENAI")
        let message = try conversations.insertMessage(ChatMessage(conversationId: conversation, role: "assistant", text: "Working"))
        var payload = ToolActivityPayload()
        payload.applySubagent(run())
        try conversations.saveToolActivity(messageId: message, variantId: nil, payload: payload)
        try AppDatabase.recoverStreamCheckpoints(in: queue)
        let activity = try queue.read { db in try XCTUnwrap(ChatMessageToolActivity.fetchOne(db)) }
        XCTAssertEqual(activity.payload.subagents.first?.status, .cancelled)
        XCTAssertEqual(activity.payload.subagents.first?.output, "途中の結果")
    }

    func testPCCChildConfigurationAndBridgeAuthorization() async throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue)
        let gateway = ProviderGateway(settingsRepository: SettingsRepository(dbQueue: queue), credentialStore: SubagentCredentialStore())
        let profile = SubagentModelProfile(id: "pcc", name: "PCC", provider: "APPLE_INTELLIGENCE",
            model: AppleIntelligenceModelCatalog.pccModel, effort: "high")
        let child = try await gateway.subagentConfiguration(profile, settings: AppSettings())
        XCTAssertEqual(child.provider, "apple-pcc")
        XCTAssertEqual(child.model, AppleIntelligenceModelCatalog.pccModel)
        XCTAssertEqual(child.thinkingLevel, "high")
        XCTAssertNil(child.apiKey)
        XCTAssertNil(child.subagents)
        var parent = PiAgentConfiguration(provider: "openai", model: "gpt-5.5",
            subagents: PiSubagentOptions(enabled: true, models: [.init(id: "pcc", name: "PCC", configuration: child)]))
        XCTAssertTrue(PiAgentRuntime.hasNativePCC(parent))
        XCTAssertTrue(PiAgentRuntime.authorizesPCC(parent, subagentID: "child"))
        XCTAssertFalse(PiAgentRuntime.authorizesPCC(parent, subagentID: nil))
        parent.subagents?.enabled = false
        XCTAssertFalse(PiAgentRuntime.hasNativePCC(parent))
        XCTAssertFalse(PiAgentRuntime.authorizesPCC(parent, subagentID: "child"))
        var onDevice = profile
        onDevice.model = AppleIntelligenceModelCatalog.displayModel
        do {
            _ = try await gateway.subagentConfiguration(onDevice, settings: AppSettings())
            XCTFail("On-device Apple Intelligence must remain unsupported")
        } catch { XCTAssertTrue(error.localizedDescription.contains("subagent_native_apple_bridge_unsupported")) }
    }

    func testGatewayAttachesExplicitProfileAndDoesNotEnableSubagentsForInternalRequests() async throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue)
        let repository = SettingsRepository(dbQueue: queue)
        var settings = try repository.load()
        settings.subagents = SubagentSettings(enabled: true, defaultModelID: "research", models: [
            SubagentModelProfile(id: "research", name: "調査用", provider: "OPENAI", model: "gpt-5.5", effort: "high")
        ])
        try repository.save(settings)
        let credentials = SubagentCredentialStore()
        try credentials.setCredential("parent-secret", for: .sarashina)
        try credentials.setCredential("child-secret", for: .openAI)
        let spy = PiStreamSpy { _, _ in [.completed(ProviderResponse(text: "done"))] }
        let gateway = ProviderGateway(settingsRepository: repository, credentialStore: credentials, piStream: spy.stream)
        _ = try await gateway.generate(request: ProviderRequest(model: "sarashina3-mini", messages: [.init(role: "user", content: "hello")], metadata: ["subagentsEnabled": "true"]), providerID: "SARASHINA")
        let parent = try XCTUnwrap(spy.calls.first?.configuration)
        XCTAssertEqual(parent.apiKey, "parent-secret")
        let child = try XCTUnwrap(parent.subagents?.models.first?.configuration)
        XCTAssertEqual(child.provider, "openai")
        XCTAssertEqual(child.model, "gpt-5.5")
        XCTAssertEqual(child.thinkingLevel, "high")
        XCTAssertEqual(child.apiKey, "child-secret")
        XCTAssertNil(child.subagents)
        _ = try await gateway.generate(request: ProviderRequest(model: "sarashina3-mini", messages: [.init(role: "user", content: "title")]), providerID: "SARASHINA")
        XCTAssertNil(spy.calls.last?.configuration.subagents)
    }
}
