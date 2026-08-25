import XCTest
@testable import YamabikoChat

final class ChatPresentationArchitectureTests: XCTestCase {
    func testChatModeNormalizesLegacyFlagsToExactlyOneMode() {
        for mode in ChatMode.allCases {
            let settings = mode.applying(to: AppSettings())
            XCTAssertEqual(ChatMode(settings: settings), mode)
            XCTAssertEqual(
                [settings.isDualModeEnabled, settings.isFusionModeEnabled, settings.isAutoConversationEnabled]
                    .filter { $0 }
                    .count,
                mode == .standard ? 0 : 1
            )
        }
    }

    func testTailFollowPolicyRestoresAnchorWithoutOverscrolling() {
        XCTAssertTrue(TailFollowPolicy.isNearTail(distance: 96))
        XCTAssertFalse(TailFollowPolicy.isNearTail(distance: 96.1))
        XCTAssertEqual(
            TailFollowPolicy.restoredOffset(
                anchorMinY: 1_200,
                offsetWithinViewport: 140,
                lowerBound: -20,
                upperBound: 2_000
            ),
            1_060
        )
        XCTAssertEqual(
            TailFollowPolicy.restoredOffset(
                anchorMinY: 3_000,
                offsetWithinViewport: 0,
                lowerBound: -20,
                upperBound: 2_000
            ),
            2_000
        )
    }

    func testNativeMarkdownParserBuildsStableNativeBlocks() {
        let markdown = """
        # Heading

        A paragraph with **bold** and [link](https://example.com).

        ```swift
        let value = 1
        ```

        | Name | Value |
        | --- | --- |
        | A | 1 |
        """

        let first = NativeMarkdownParser.parse(markdown)
        let second = NativeMarkdownParser.parse(markdown)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.contains { if case .heading = $0 { return true }; return false })
        XCTAssertTrue(first.contains { if case .code = $0 { return true }; return false })
        XCTAssertTrue(first.contains { if case .table = $0 { return true }; return false })
    }

    func testNativeMarkdownParserHonorsDisabledMathRendering() {
        let markdown = "Energy is $E = mc^2$."

        let enabled = NativeMarkdownParser.parse(markdown, rendersMath: true)
        let disabled = NativeMarkdownParser.parse(markdown, rendersMath: false)

        XCTAssertTrue(enabled.contains { if case .math = $0 { return true }; return false })
        XCTAssertFalse(disabled.contains { if case .math = $0 { return true }; return false })
        XCTAssertTrue(disabled.contains { if case .paragraph = $0 { return true }; return false })
    }

    func testNativeMarkdownParserDoesNotTreatAdjacentPricesAsMath() {
        let blocks = NativeMarkdownParser.parse("The prices are $10 and $20.")

        XCTAssertFalse(blocks.contains { if case .math = $0 { return true }; return false })
        XCTAssertTrue(blocks.contains { if case .paragraph = $0 { return true }; return false })
    }

    func testNativeMarkdownParserPreservesRawHTMLAsVisibleSource() {
        let blocks = NativeMarkdownParser.parse("Before\n\n<section>Raw HTML</section>\n\nAfter")

        XCTAssertTrue(blocks.contains { block in
            guard case let .code(_, language, code) = block else { return false }
            return language == "html" && code.contains("<section>Raw HTML</section>")
        })
    }

    func testNativeMarkdownParserPreservesInlineHTMLAsVisibleSource() {
        let blocks = NativeMarkdownParser.parse("Press <kbd>Command-K</kbd> to search.")

        guard case let .paragraph(_, text) = blocks.first else {
            return XCTFail("Expected a native paragraph")
        }
        XCTAssertEqual(String(text.characters), "Press <kbd>Command-K</kbd> to search.")
    }

    func testNativeMarkdownParserPreservesTableCellFormatting() {
        let blocks = NativeMarkdownParser.parse("""
        | Name | Link |
        | --- | --- |
        | **Bold** | [Open](https://example.com) |
        """)

        guard case let .table(_, rows) = blocks.first else {
            return XCTFail("Expected a native table")
        }
        XCTAssertEqual(String(rows[1][0].characters), "Bold")
        XCTAssertEqual(String(rows[1][1].characters), "Open")
        XCTAssertNotEqual(rows[1][0], AttributedString("Bold"))
        XCTAssertNotEqual(rows[1][1], AttributedString("Open"))
    }

    func testDualResponsePresentationPreservesFailureThinkingAndArtifacts() {
        let activity = ToolActivityPayload(attachmentPaths: ["/tmp/generated-chart.png"])
        let message = DualChatMessage(
            conversationId: 1,
            role: DualChatMessage.Role.dualModel.rawValue,
            userText: "",
            modelAText: "partial",
            modelBText: "complete",
            modelAName: "model-a",
            modelBName: "model-b",
            providerA: "provider-a",
            providerB: "provider-b",
            modelAThinking: "reasoning",
            modelAToolActivityJSON: DualChatMessage.encodeToolActivity(activity),
            modelAStatus: DualChatMessage.SideStatus.failed.rawValue,
            modelAError: "provider failed"
        )

        let presentation = DualResponsePresentation(message: message, side: .a)

        XCTAssertEqual(presentation.status, .failed)
        XCTAssertEqual(presentation.error, "provider failed")
        XCTAssertEqual(presentation.thinking, "reasoning")
        XCTAssertEqual(presentation.attachmentPaths, ["/tmp/generated-chart.png"])
    }

    func testArtifactPresentationRejectsErrorAndStreamingContent() {
        let html = """
        ```html
        <html><body>preview</body></html>
        ```
        """

        XCTAssertEqual(ChatArtifactPresentation.items(from: html, isStreaming: false).count, 1)
        XCTAssertTrue(ChatArtifactPresentation.items(from: html, isStreaming: true).isEmpty)
        XCTAssertTrue(
            ChatArtifactPresentation.items(from: "Error: provider failed\n\(html)", isStreaming: false).isEmpty
        )
    }

    @MainActor
    func testTwoHundredMessageTimelineKeepsStableIdentityDuringStreamUpdate() {
        let store = ChatTimelineStore()
        let messages = (0..<200).map { index in
            FullChatMessage(
                id: Int64(index + 1),
                message: ChatMessage(
                    id: Int64(index + 1),
                    conversationId: 1,
                    role: index.isMultiple(of: 2) ? "user" : "model",
                    text: "Message \(index)",
                    createdAtMs: Int64(index)
                ),
                thinkingStream: nil,
                variants: []
            )
        }
        store.update(messages: messages)
        let ids = store.orderedIDs
        let generation = store.mutationGeneration

        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 200,
            text: String(repeating: "stream ", count: 5_000),
            thinking: String(repeating: "thought ", count: 5_000),
            toolActivity: ToolActivityPayload(steps: []),
            isFinal: false
        ))

        XCTAssertEqual(store.orderedIDs, ids)
        XCTAssertEqual(store.row(id: "m-200")?.streamingSnapshot?.targetId, 200)
        XCTAssertEqual(
            store.mutationGeneration,
            generation,
            "A stream frame must not invalidate the complete collection"
        )
    }

    @MainActor
    func testSessionControllerPublishesCompletionImmediatelyAndClearsLiveState() {
        let controller = ChatSessionController()
        var delivered: [ChatStreamingSnapshot] = []
        controller.onSnapshot = { delivered.append($0) }

        controller.handle(ChatStreamingSnapshot(
            targetId: 42,
            text: "partial",
            thinking: "",
            toolActivity: nil,
            isFinal: false
        ))
        XCTAssertEqual(controller.snapshot(for: 42)?.text, "partial")

        controller.handle(ChatStreamingSnapshot(
            targetId: 42,
            text: "complete",
            thinking: "",
            toolActivity: nil,
            isFinal: true
        ))
        XCTAssertNil(controller.snapshot(for: 42))
        XCTAssertEqual(delivered.last?.isFinal, true)
    }

    @MainActor
    func testSessionControllerCancelsScheduledFlushBeforeImmediatePublish() async throws {
        var currentTime = Date(timeIntervalSinceReferenceDate: 1_000)
        let controller = ChatSessionController(frameInterval: 0.05, now: { currentTime })
        var delivered: [String] = []
        controller.onSnapshot = { delivered.append($0.text) }

        controller.handle(ChatStreamingSnapshot(
            targetId: 42,
            text: "first",
            thinking: "",
            toolActivity: nil,
            isFinal: false
        ))
        controller.handle(ChatStreamingSnapshot(
            targetId: 42,
            text: "scheduled",
            thinking: "",
            toolActivity: nil,
            isFinal: false
        ))
        currentTime.addTimeInterval(0.1)
        controller.handle(ChatStreamingSnapshot(
            targetId: 42,
            text: "immediate",
            thinking: "",
            toolActivity: nil,
            isFinal: false
        ))

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(delivered, ["first", "immediate"])
    }

    @MainActor
    func testTimelineKeepsFinalSnapshotUntilDatabaseContentArrives() {
        let store = ChatTimelineStore()
        let staleMessage = FullChatMessage(
            id: 42,
            message: ChatMessage(
                id: 42,
                conversationId: 1,
                role: "model",
                text: "partial",
                createdAtMs: 1
            ),
            thinkingStream: nil,
            variants: []
        )
        store.update(messages: [staleMessage])
        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 42,
            text: "complete",
            thinking: "",
            toolActivity: nil,
            isFinal: true
        ))

        XCTAssertEqual(store.row(id: "m-42")?.streamingSnapshot?.text, "complete")

        var persistedMessage = staleMessage
        persistedMessage.message.text = "complete"
        store.update(messages: [persistedMessage])

        XCTAssertNil(store.row(id: "m-42")?.streamingSnapshot)
    }

    @MainActor
    func testTimelineAppliesStreamFrameThatArrivesBeforeObservedMessage() {
        let store = ChatTimelineStore()
        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 42,
            text: "first chunk",
            thinking: "",
            toolActivity: nil,
            isFinal: false
        ))

        store.update(messages: [FullChatMessage(
            id: 42,
            message: ChatMessage(
                id: 42,
                conversationId: 1,
                role: "model",
                text: "",
                createdAtMs: 1
            ),
            thinkingStream: nil,
            variants: []
        )])

        XCTAssertEqual(store.row(id: "m-42")?.streamingSnapshot?.text, "first chunk")
    }

    @MainActor
    func testTimelineSkipsLayoutHooksForAnIdenticalStreamFrame() {
        let store = ChatTimelineStore()
        store.update(messages: [FullChatMessage(
            id: 42,
            message: ChatMessage(
                id: 42,
                conversationId: 1,
                role: "model",
                text: "partial",
                createdAtMs: 1
            ),
            thinkingStream: nil,
            variants: []
        )])
        var willChangeCount = 0
        var didChangeCount = 0
        store.onRowContentWillChange = { willChangeCount += 1 }
        store.onRowContentDidChange = { didChangeCount += 1 }
        let snapshot = ChatStreamingSnapshot(
            targetId: 42,
            text: "streaming",
            thinking: "",
            toolActivity: nil,
            isFinal: false
        )

        store.applyStreamingSnapshot(snapshot)
        store.applyStreamingSnapshot(snapshot)

        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)
    }
}
