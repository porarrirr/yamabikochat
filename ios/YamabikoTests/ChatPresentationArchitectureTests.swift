import XCTest
import UIKit
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
        XCTAssertFalse(TailFollowPolicy.shouldAdjustOffset(current: 100, target: 100.5))
        XCTAssertTrue(TailFollowPolicy.shouldAdjustOffset(current: 100, target: 100.51))
    }

    func testStreamingMarkdownPreservesConfirmedHeadingAndListBlockIDs() async {
        let parser = NativeMarkdownIncrementalParser()
        let firstSource = "# Heading\n\n- first\n- second"
        let first = await parser.streamingBlocks(for: firstSource)
        let second = await parser.streamingBlocks(
            for: firstSource + "\n\nTail with **emphasis**"
        )

        XCTAssertEqual(Array(second.prefix(first.count)).map(\.id), first.map(\.id))
        XCTAssertEqual(first.first?.id, "block-0")
        XCTAssertEqual(first.dropFirst().first?.id, "block-\("# Heading\n\n".utf8.count)")
    }

    func testStreamingMarkdownKeepsTailIDWhenBlankLineConfirmsIt() async throws {
        let parser = NativeMarkdownIncrementalParser()
        let prefix = "Intro\n\n"
        let tail = "## Live heading"
        let beforeConfirmation = await parser.streamingBlocks(for: prefix + tail)
        let tailID = try XCTUnwrap(beforeConfirmation.last?.id)
        let afterConfirmation = await parser.streamingBlocks(for: prefix + tail + "\n\nNext")

        XCTAssertEqual(tailID, afterConfirmation.dropLast().last?.id)
        XCTAssertEqual(tailID, "block-\(prefix.utf8.count)")
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
        var changes: [(String, ChatTimelineRowChangeKind)] = []
        store.onRowContentWillChange = { _, _ in willChangeCount += 1 }
        store.onRowContentDidChange = { id, kind in
            didChangeCount += 1
            changes.append((id, kind))
        }
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
        XCTAssertEqual(changes.first?.0, "m-42")
        XCTAssertEqual(changes.first?.1, .streamUpdate)
    }

    @MainActor
    func testRapidStreamingUpdatesKeepCollectionCellFramesSeparated() async throws {
        let store = ChatTimelineStore()
        store.update(messages: (1...8).map { timelineMessage(id: Int64($0), text: "Message \($0)") })
        let controller = configuredTimelineController(store: store)
        await settleTimeline(controller)

        for frame in 1...8 {
            store.applyStreamingSnapshot(ChatStreamingSnapshot(
                targetId: Int64(frame),
                text: String(repeating: "stream \(frame) ", count: 80 + frame),
                thinking: "",
                toolActivity: nil,
                isFinal: false
            ))
        }
        await settleTimeline(controller)

        let collectionView = try XCTUnwrap(findCollectionView(in: controller.view))
        let frames = (0..<store.orderedIDs.count).compactMap {
            collectionView.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame
        }
        XCTAssertEqual(frames.count, store.orderedIDs.count)
        for (previous, next) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThanOrEqual(previous.maxY, next.minY)
        }
    }

    @MainActor
    func testLatestMoveAndStreamCompletionKeepOffsetAndVisibleAnchor() async throws {
        let store = ChatTimelineStore()
        store.update(messages: (1...20).map {
            timelineMessage(id: Int64($0), text: String(repeating: "Message \($0) line\n", count: 5))
        })
        let controller = configuredTimelineController(store: store, scrollRequest: 1)
        await settleTimeline(controller)
        let collectionView = try XCTUnwrap(findCollectionView(in: controller.view))
        let initialOffset = collectionView.contentOffset.y
        let initialAnchor = try XCTUnwrap(visibleAnchor(in: collectionView))

        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 20,
            text: String(repeating: "# Live heading\n\n- item\n", count: 40),
            thinking: "",
            toolActivity: nil,
            isFinal: false
        ))
        await settleTimeline(controller)
        XCTAssertEqual(collectionView.contentOffset.y, initialOffset, accuracy: 0.5)
        assertVisibleAnchor(initialAnchor, in: collectionView)

        let streamOffset = collectionView.contentOffset.y
        let streamAnchor = try XCTUnwrap(visibleAnchor(in: collectionView))
        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 20,
            text: String(repeating: "# Final heading\n\n- item\n", count: 60),
            thinking: "",
            toolActivity: nil,
            isFinal: true
        ))
        await settleTimeline(controller)
        XCTAssertEqual(collectionView.contentOffset.y, streamOffset, accuracy: 0.5)
        assertVisibleAnchor(streamAnchor, in: collectionView)
    }

    @MainActor
    private func configuredTimelineController(
        store: ChatTimelineStore,
        scrollRequest: Int = 0
    ) -> ChatTimelineViewController {
        let controller = ChatTimelineViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        controller.configure(
            store: store,
            scrollToLatestRequest: scrollRequest,
            regeneratableMessageID: nil,
            mathRenderingEnabled: true,
            fusionDebugModeEnabled: false,
            dualSplitLayout: "VERTICAL",
            dualSplitRatio: 0.5,
            fusionTraceForMessage: { _ in nil },
            onRoute: { _ in },
            onPreviousVariant: { _ in },
            onNextVariant: { _ in },
            onBranch: { _ in },
            onRegenerate: {}
        )
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        return controller
    }

    private func timelineMessage(id: Int64, text: String) -> FullChatMessage {
        FullChatMessage(
            id: id,
            message: ChatMessage(
                id: id,
                conversationId: 1,
                role: "model",
                text: text,
                createdAtMs: id
            ),
            thinkingStream: nil,
            variants: []
        )
    }

    @MainActor
    private func settleTimeline(_ controller: ChatTimelineViewController) async {
        var previousContentSize = CGSize.zero
        var previousOffset = CGFloat.infinity
        var stablePasses = 0
        for _ in 0..<50 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            controller.view.layoutIfNeeded()
            guard let collectionView = findCollectionView(in: controller.view) else { continue }
            if collectionView.contentSize == previousContentSize,
               abs(collectionView.contentOffset.y - previousOffset) <= 0.01 {
                stablePasses += 1
                if stablePasses >= 3 { return }
            } else {
                stablePasses = 0
                previousContentSize = collectionView.contentSize
                previousOffset = collectionView.contentOffset.y
            }
        }
    }

    private func findCollectionView(in view: UIView) -> UICollectionView? {
        if let collectionView = view as? UICollectionView { return collectionView }
        return view.subviews.lazy.compactMap(findCollectionView).first
    }

    private func visibleAnchor(in collectionView: UICollectionView) -> (indexPath: IndexPath, offset: CGFloat)? {
        guard let indexPath = collectionView.indexPathsForVisibleItems.sorted().first,
              let attributes = collectionView.layoutAttributesForItem(at: indexPath)
        else { return nil }
        return (indexPath, attributes.frame.minY - collectionView.contentOffset.y)
    }

    private func assertVisibleAnchor(
        _ anchor: (indexPath: IndexPath, offset: CGFloat),
        in collectionView: UICollectionView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let current = visibleAnchor(in: collectionView)
        XCTAssertEqual(current?.indexPath, anchor.indexPath, file: file, line: line)
        XCTAssertEqual(current?.offset ?? .infinity, anchor.offset, accuracy: 0.5, file: file, line: line)
    }
}
