import XCTest
import UIKit
@testable import YamabikoChat

final class ChatPresentationArchitectureTests: XCTestCase {
    func testComposerFocusClearsAtGenerationStartAndDoesNotRestoreAtCompletion() {
        var isFocused = true

        isFocused = ChatComposerFocusPolicy.focusState(current: isFocused, isSending: true)
        XCTAssertFalse(isFocused)

        isFocused = ChatComposerFocusPolicy.focusState(current: isFocused, isSending: false)
        XCTAssertFalse(isFocused)
    }

    func testComposerSynchronizationPreservesCaretForLocalEdits() {
        XCTAssertEqual(
            ChatComposerSynchronizationPolicy.action(
                isInitialConfiguration: false,
                hasMarkedText: false,
                isFirstResponder: true,
                isExternalChange: false,
                nativeTextMatchesBinding: true
            ),
            .none
        )
    }

    func testComposerSynchronizationDoesNotOverwriteMarkedText() {
        XCTAssertEqual(
            ChatComposerSynchronizationPolicy.action(
                isInitialConfiguration: false,
                hasMarkedText: true,
                isFirstResponder: true,
                isExternalChange: true,
                nativeTextMatchesBinding: false
            ),
            .none
        )
    }

    func testComposerSynchronizationMovesCaretForExternalFocusedChange() {
        XCTAssertEqual(
            ChatComposerSynchronizationPolicy.action(
                isInitialConfiguration: false,
                hasMarkedText: false,
                isFirstResponder: true,
                isExternalChange: true,
                nativeTextMatchesBinding: false
            ),
            .replaceText(moveCaretToEnd: true)
        )
    }

    @MainActor
    func testComposerNativeTextViewFillsItsMeasuredContainer() {
        let container = ChatComposerTextView.ComposerContainerView()
        container.frame = CGRect(x: 0, y: 0, width: 320, height: 40)

        container.setNeedsLayout()
        container.layoutIfNeeded()

        XCTAssertGreaterThan(container.textView.bounds.height, 0)
        XCTAssertEqual(container.textView.frame.minY, 0, accuracy: 0.5)
        XCTAssertEqual(container.textView.frame.height, 40, accuracy: 0.5)
    }

    func testSelectedChatTextStartsWithOneTrailingHalfWidthSpace() {
        XCTAssertEqual(ChatComposerSelectionPolicy.initialInput(for: "選択部分"), "選択部分 ")
    }

    func testSelectedChatTextPreservesExistingDraft() {
        XCTAssertEqual(
            ChatComposerSelectionPolicy.initialInput(for: "選択部分", preserving: "この点を説明して"),
            "選択部分 この点を説明して"
        )
    }

    func testSelectedChatTextDoesNotExposeInternalSeparatorToAccessibility() {
        XCTAssertEqual(
            ChatComposerSelectionPolicy.accessibilityValue(selectedText: "選択部分", suffix: " "),
            "選択部分"
        )
        XCTAssertEqual(
            ChatComposerSelectionPolicy.accessibilityValue(selectedText: "選択部分", suffix: " 質問"),
            "選択部分 質問"
        )
    }

    func testSelectedChatTextMeasuresEditorFromActualTokenWidth() {
        XCTAssertEqual(
            ChatComposerSelectionPolicy.editorWidth(totalWidth: 300, selectedTextWidth: nil),
            300,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ChatComposerSelectionPolicy.editorWidth(totalWidth: 300, selectedTextWidth: 40),
            234,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ChatComposerSelectionPolicy.editorWidth(totalWidth: 300, selectedTextWidth: 500),
            124,
            accuracy: 0.001
        )
    }

    @MainActor
    func testLongSelectedChatTextKeepsQuestionEditorUsable() {
        let container = ChatComposerTextView.ComposerContainerView()
        container.frame = CGRect(x: 0, y: 0, width: 300, height: 80)
        container.setSelectedText(String(repeating: "長い選択文", count: 30))

        container.setNeedsLayout()
        container.layoutIfNeeded()

        XCTAssertGreaterThanOrEqual(
            container.textView.frame.width,
            ChatComposerSelectionPolicy.minimumEditorWidth - 0.5
        )
        XCTAssertLessThanOrEqual(
            container.textView.frame.maxX,
            container.bounds.maxX + 0.5
        )
    }

    func testSelectedChatTextDeletesSpaceBeforeDeletingWholeToken() {
        let selectedText = "選択部分"
        let initialInput = ChatComposerSelectionPolicy.initialInput(for: selectedText)
        let suffix = ChatComposerSelectionPolicy.editableSuffix(
            in: initialInput,
            selectedText: selectedText
        )
        XCTAssertEqual(suffix, " ")

        let suffixAfterFirstDeletion = String(suffix.dropLast())
        XCTAssertEqual(
            ChatComposerSelectionPolicy.combinedInput(
                selectedText: selectedText,
                suffix: suffixAfterFirstDeletion
            ),
            selectedText
        )
        XCTAssertEqual(
            ChatComposerSelectionPolicy.combinedInput(selectedText: nil, suffix: ""),
            ""
        )
    }

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

    @MainActor
    func testPreferredCellHeightPreservesOriginalTopEdge() {
        let cell = ChatTimelineCollectionCell(frame: CGRect(x: 18, y: 240, width: 354, height: 120))
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.text = String(repeating: "tool summary and streamed answer ", count: 30)
        cell.contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
            label.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
            label.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor)
        ])
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        attributes.frame = CGRect(x: 18, y: 240, width: 354, height: 120)

        let fitted = cell.preferredLayoutAttributesFitting(attributes)

        XCTAssertGreaterThan(fitted.frame.height, attributes.frame.height)
        XCTAssertEqual(fitted.frame.minY, attributes.frame.minY, accuracy: 0.01)
    }

    @MainActor
    func testTimelineUsesOnlyItsManualStreamingSelfSizingPath() throws {
        let store = ChatTimelineStore()
        store.update(messages: [timelineMessage(id: 1, text: "Initial")])
        let controller = configuredTimelineController(store: store)
        let collectionView = try XCTUnwrap(findCollectionView(in: controller.view))

        XCTAssertEqual(collectionView.selfSizingInvalidation, .disabled)
    }

    @MainActor
    func testStreamingMarkdownPreservesConfirmedHeadingAndListBlockIDs() {
        let parser = NativeMarkdownIncrementalParser()
        let firstSource = "# Heading\n\n- first\n- second"
        let first = parser.streamingBlocks(for: firstSource)
        let second = parser.streamingBlocks(
            for: firstSource + "\n\nTail with **emphasis**"
        )

        XCTAssertEqual(Array(second.prefix(first.count)).map(\.id), first.map(\.id))
        XCTAssertEqual(first.first?.id, "block-0")
        XCTAssertEqual(first.dropFirst().first?.id, "block-\("# Heading\n\n".utf8.count)")
    }

    @MainActor
    func testStreamingMarkdownKeepsTailIDWhenBlankLineConfirmsIt() throws {
        let parser = NativeMarkdownIncrementalParser()
        let prefix = "Intro\n\n"
        let tail = "## Live heading"
        let beforeConfirmation = parser.streamingBlocks(for: prefix + tail)
        let tailID = try XCTUnwrap(beforeConfirmation.last?.id)
        let afterConfirmation = parser.streamingBlocks(for: prefix + tail + "\n\nNext")

        XCTAssertEqual(tailID, afterConfirmation.dropLast().last?.id)
        XCTAssertEqual(tailID, "block-\(prefix.utf8.count)")
    }

    @MainActor
    func testStreamingMarkdownDoesNotCommitBlankLineInsideOpenCodeFence() {
        let source = """
        Intro

        ```swift
        let first = 1

        let second = 2
        """

        let split = NativeMarkdownIncrementalParser.streamingSplit(source)

        XCTAssertEqual(split.prefix, "Intro\n\n")
        XCTAssertEqual(split.prefix + split.tail, source)
        XCTAssertTrue(split.tail.hasPrefix("```swift"))
    }

    @MainActor
    func testStreamingMarkdownMatchesFullParseAfterCodeFenceWithInternalBlankLine() {
        let parser = NativeMarkdownIncrementalParser()
        let openFence = """
        Intro

        ```swift
        let first = 1

        let second = 2
        """
        _ = parser.streamingBlocks(for: openFence)

        let source = openFence + "\n```\n\nAfter"
        let streamed = parser.streamingBlocks(for: source)
        let fullyParsed = NativeMarkdownParser.parse(source, rendersMath: false)

        XCTAssertEqual(streamed, fullyParsed)
    }

    @MainActor
    func testStreamingMarkdownMatchesFullParseForEveryComplexMarkdownUpdate() {
        let parser = NativeMarkdownIncrementalParser()
        let source = """
        # 日本語の見出し

        最初の本文です。

        > 引用の一段目です。
        >
        > 空行後も同じ引用です。

        - 最初の項目

          同じ項目の二段落目です。
        - 次の項目

        ```swift
        let first = 1

        let second = 2
        ```

        ## 次の見出し

        最後の本文です。
        """
        var partial = ""

        for character in source {
            partial.append(character)
            let streamed = parser.streamingBlocks(for: partial)
            let fullyParsed = NativeMarkdownParser.parse(partial, rendersMath: false)
            XCTAssertEqual(streamed, fullyParsed, "Mismatch after: \(partial)")
        }
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

    func testNativeMarkdownParserDisplaysNamedLinkWithoutRawURL() throws {
        let blocks = NativeMarkdownParser.parse("[Google 日本](https://www.google.co.jp/search?q=test)")

        guard case let .paragraph(_, text) = blocks.first else {
            return XCTFail("Expected a native paragraph")
        }
        XCTAssertEqual(String(text.characters), "Google 日本↗")
        XCTAssertFalse(String(text.characters).contains("https://"))
        XCTAssertEqual(text.runs.compactMap(\.link).first, URL(string: "https://www.google.co.jp/search?q=test"))
    }

    func testNativeMarkdownParserCompactsBareURLIntoLinkedHost() throws {
        let blocks = NativeMarkdownParser.parse(
            "朝日新聞「ニュースの要点」: https://www.asahi.com/pickup-news-summary/20260826/"
        )

        guard case let .paragraph(_, text) = blocks.first else {
            return XCTFail("Expected a native paragraph")
        }
        XCTAssertEqual(String(text.characters), "朝日新聞「ニュースの要点」: asahi.com↗")
        XCTAssertFalse(String(text.characters).contains("https://"))
        XCTAssertEqual(
            text.runs.compactMap(\.link).first,
            URL(string: "https://www.asahi.com/pickup-news-summary/20260826/")
        )
    }

    func testNativeMarkdownParserKeepsPunctuationAfterBareURL() throws {
        let blocks = NativeMarkdownParser.parse("See https://example.com/article。 Next")

        guard case let .paragraph(_, text) = blocks.first else {
            return XCTFail("Expected a native paragraph")
        }
        XCTAssertEqual(String(text.characters), "See example.com↗。 Next")
        XCTAssertEqual(text.runs.compactMap(\.link).first, URL(string: "https://example.com/article"))
    }

    func testChatTextSelectionPolicyReturnsOnlySelectedText() {
        let text = "Before selected text after"
        let range = (text as NSString).range(of: "selected text")

        XCTAssertEqual(ChatTextSelectionPolicy.selectedText(in: text, range: range), "selected text")
    }

    func testChatTextSelectionPolicyRejectsCaretAndWhitespaceSelection() {
        XCTAssertNil(ChatTextSelectionPolicy.selectedText(in: "text", range: NSRange(location: 2, length: 0)))
        XCTAssertNil(ChatTextSelectionPolicy.selectedText(in: "   ", range: NSRange(location: 0, length: 3)))
    }

    func testNativeMarkdownRenderIdentityChangesWhenBlockKindChangesAtSameOffset() {
        let paragraph = NativeMarkdownBlock.paragraph(id: "block-0", text: AttributedString("Title"))
        let heading = NativeMarkdownBlock.heading(id: "block-0", level: 1, text: AttributedString("Title"))

        XCTAssertEqual(paragraph.id, heading.id)
        XCTAssertNotEqual(paragraph.renderID, heading.renderID)
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
        XCTAssertEqual(String(rows[1][1].characters), "Open↗")
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
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: indexPath),
                  let attributes = collectionView.layoutAttributesForItem(at: indexPath)
            else { continue }
            let fittedHeight = cell.contentView.systemLayoutSizeFitting(
                CGSize(
                    width: attributes.size.width,
                    height: UIView.layoutFittingCompressedSize.height
                ),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            XCTAssertEqual(
                attributes.size.height,
                ceil(fittedHeight),
                accuracy: 0.5,
                "The layout must contain the asynchronously rendered Markdown content"
            )
        }
    }

    @MainActor
    func testStreamingMarkdownKeepsShortResponseViewportStable() async throws {
        let store = ChatTimelineStore()
        store.update(messages: [timelineMessage(id: 1, text: "")])
        let controller = configuredTimelineController(store: store)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        await settleTimeline(controller)
        let collectionView = try XCTUnwrap(findCollectionView(in: controller.view))
        var offsets: [CGFloat] = []
        let source = """
        # 📰 今日のニュースまとめ（フィクション）
        2026年8月25日（月）

        ### 🌍 国際ニュース
        月面基地「アルテミス・ゲート」が正式運用開始
        アメリカ航空宇宙局（NASA）と国際パートナーは今日、月面基地「アルテミス・ゲート」の運用を正式に開始したと発表した。

        ### 🔬 科学技術
        量子コンピュータが新薬開発に革命 — 開発期間を10分の1に

        Google Quantum AI
        """
        for boundary in stride(from: 12, through: source.count, by: 12) {
            store.applyStreamingSnapshot(ChatStreamingSnapshot(
                targetId: 1,
                text: String(source.prefix(boundary)),
                thinking: "",
                toolActivity: nil,
                isFinal: false
            ))
            try? await Task.sleep(nanoseconds: 20_000_000)
            controller.view.layoutIfNeeded()
            _ = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            offsets.append(collectionView.contentOffset.y)
        }
        await settleTimeline(controller)
        let drift = try XCTUnwrap(offsets.max()) - (try XCTUnwrap(offsets.min()))
        XCTAssertLessThanOrEqual(drift, 0.5, "Unexpected streaming offsets: \(offsets)")
        let indexPath = IndexPath(item: 0, section: 0)
        let cell = try XCTUnwrap(collectionView.cellForItem(at: indexPath))
        let attributes = try XCTUnwrap(collectionView.layoutAttributesForItem(at: indexPath))
        let fittedHeight = cell.contentView.systemLayoutSizeFitting(
            CGSize(
                width: attributes.size.width,
                height: UIView.layoutFittingCompressedSize.height
            ),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        XCTAssertEqual(
            attributes.size.height,
            ceil(fittedHeight),
            accuracy: 0.5,
            "The cell must track the asynchronously rendered Markdown height"
        )
    }

    @MainActor
    func testStreamingMarkdownNeverPresentsContentTallerThanItsCell() async throws {
        let store = ChatTimelineStore()
        store.update(messages: [timelineMessage(id: 1, text: "")])
        let controller = configuredTimelineController(store: store)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        await settleTimeline(controller)
        let collectionView = try XCTUnwrap(findCollectionView(in: controller.view))
        let indexPath = IndexPath(item: 0, section: 0)
        let paragraphs = [
            "# ストリーミング表示\n\n",
            "最初の段落は、セル幅で複数行に折り返されるだけの長さを持つ文章です。表示中に上へ潜り込んではいけません。\n\n",
            "二番目の段落も、生成途中で少しずつ伸びていきます。上の段落を一行隠してから元へ戻す動きは不正です。\n\n",
            "三番目の段落で高さ更新をもう一度発生させます。"
        ]
        var source = ""

        for paragraph in paragraphs {
            for character in paragraph {
                source.append(character)
                store.applyStreamingSnapshot(ChatStreamingSnapshot(
                    targetId: 1,
                    text: source,
                    thinking: "",
                    toolActivity: nil,
                    isFinal: false
                ))
                for _ in 0..<3 {
                    await Task.yield()
                    controller.view.layoutIfNeeded()
                    guard let cell = collectionView.cellForItem(at: indexPath),
                          let attributes = collectionView.layoutAttributesForItem(at: indexPath)
                    else { continue }
                    let fittedHeight = ceil(cell.contentView.systemLayoutSizeFitting(
                        CGSize(
                            width: attributes.size.width,
                            height: UIView.layoutFittingCompressedSize.height
                        ),
                        withHorizontalFittingPriority: .required,
                        verticalFittingPriority: .fittingSizeLevel
                    ).height)
                    XCTAssertGreaterThanOrEqual(
                        attributes.size.height + 0.5,
                        fittedHeight,
                        "Rendered content escaped its cell for source: \(source)"
                    )
                }
            }
        }
    }

    @MainActor
    func testStreamingParagraphBoundariesNeverMoveViewportEvenTransiently() async throws {
        let store = ChatTimelineStore()
        store.update(messages: (1...20).map {
            timelineMessage(id: Int64($0), text: String(repeating: "Message \($0) line\n", count: 5))
        })
        let controller = configuredTimelineController(store: store, scrollRequest: 1)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        await settleTimeline(controller)
        let collectionView = try XCTUnwrap(findCollectionView(in: controller.view))

        var source = """
        # 生成中の見出し

        最初の段落です。十分な長さを持たせて複数行に折り返し、実際の生成表示と同じ高さ変化を起こします。
        """
        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 20,
            text: source,
            thinking: "",
            toolActivity: nil,
            isFinal: false
        ))
        await settleTimeline(controller)

        controller.scrollViewWillBeginDragging(collectionView)
        collectionView.setContentOffset(
            CGPoint(x: 0, y: max(
                -collectionView.adjustedContentInset.top,
                collectionView.contentOffset.y - 150
            )),
            animated: false
        )
        controller.scrollViewDidScroll(collectionView)
        controller.scrollViewDidEndDragging(collectionView, willDecelerate: false)
        await settleTimeline(controller)

        let baseline = collectionView.contentOffset.y
        var observedOffsets: [CGFloat] = []
        let observation = collectionView.observe(\.contentOffset, options: [.new]) { _, change in
            if let offset = change.newValue?.y {
                observedOffsets.append(offset)
            }
        }
        defer { observation.invalidate() }

        for character in "\n\n次の段落です。この段落が追加される瞬間にも表示位置を動かしてはいけません。" {
            source.append(character)
            store.applyStreamingSnapshot(ChatStreamingSnapshot(
                targetId: 20,
                text: source,
                thinking: "",
                toolActivity: nil,
                isFinal: false
            ))
            for _ in 0..<3 {
                await Task.yield()
                controller.view.layoutIfNeeded()
            }
        }

        XCTAssertTrue(
            observedOffsets.allSatisfy { abs($0 - baseline) <= 0.5 },
            "Transient viewport movement: baseline=\(baseline), offsets=\(observedOffsets)"
        )
    }

    @MainActor
    func testStreamingSelfSizingNeverMovesWholeTimelineBetweenMeasurementPasses() async throws {
        let store = ChatTimelineStore()
        store.update(messages: (1...24).map {
            timelineMessage(id: Int64($0), text: String(repeating: "Message \($0) line\n", count: 4))
        })
        let controller = configuredTimelineController(store: store, scrollRequest: 1)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        await settleTimeline(controller)
        let collectionView = try XCTUnwrap(findCollectionView(in: controller.view))

        controller.scrollViewWillBeginDragging(collectionView)
        collectionView.setContentOffset(
            CGPoint(x: 0, y: max(
                -collectionView.adjustedContentInset.top,
                collectionView.contentOffset.y - 150
            )),
            animated: false
        )
        controller.scrollViewDidScroll(collectionView)
        controller.scrollViewDidEndDragging(collectionView, willDecelerate: false)
        await settleTimeline(controller)
        let anchor = try XCTUnwrap(visibleAnchor(in: collectionView))
        var observedAnchorOffsets: [CGFloat] = []
        var source = "# 生成中\n\n最初の段落です。"

        for paragraph in 1...8 {
            source += "\n\n段落\(paragraph)です。セルの高さを確実に増やすため、十分に長い文章を追加して複数行へ折り返します。"
            store.applyStreamingSnapshot(ChatStreamingSnapshot(
                targetId: 24,
                text: source,
                thinking: "",
                toolActivity: nil,
                isFinal: false
            ))
            for _ in 0..<8 {
                await Task.yield()
                controller.view.layoutIfNeeded()
                if let attributes = collectionView.layoutAttributesForItem(at: anchor.indexPath) {
                    observedAnchorOffsets.append(attributes.frame.minY - collectionView.contentOffset.y)
                }
            }
        }

        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 24,
            text: source,
            thinking: "",
            toolActivity: nil,
            isFinal: true
        ))
        for _ in 0..<12 {
            await Task.yield()
            controller.view.layoutIfNeeded()
            if let attributes = collectionView.layoutAttributesForItem(at: anchor.indexPath) {
                observedAnchorOffsets.append(attributes.frame.minY - collectionView.contentOffset.y)
            }
        }
        store.update(messages: (1...24).map {
            timelineMessage(
                id: Int64($0),
                text: $0 == 24 ? source : String(repeating: "Message \($0) line\n", count: 4)
            )
        })
        for _ in 0..<12 {
            await Task.yield()
            controller.view.layoutIfNeeded()
            if let attributes = collectionView.layoutAttributesForItem(at: anchor.indexPath) {
                observedAnchorOffsets.append(attributes.frame.minY - collectionView.contentOffset.y)
            }
        }

        XCTAssertTrue(
            observedAnchorOffsets.allSatisfy { abs($0 - anchor.offset) <= 0.5 },
            "Whole-timeline movement: baseline=\(anchor.offset), observed=\(observedAnchorOffsets)"
        )
    }

    @MainActor
    func testStreamingMeasurementNeverRewindsActiveUserScroll() async throws {
        let store = ChatTimelineStore()
        store.update(messages: (1...24).map {
            timelineMessage(id: Int64($0), text: String(repeating: "Message \($0) line\n", count: 4))
        })
        let controller = configuredTimelineController(store: store, scrollRequest: 1)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        await settleTimeline(controller)
        let collectionView = try XCTUnwrap(findCollectionView(in: controller.view))
        let minimumOffset = -collectionView.adjustedContentInset.top
        let initialContentHeight = collectionView.contentSize.height
        var source = "# 生成中\n\n最初の段落です。"
        var expectedOffset = collectionView.contentOffset.y

        controller.scrollViewWillBeginDragging(collectionView)
        for paragraph in 1...6 {
            source += "\n\n段落\(paragraph)です。高さを増やしながら指で上へスクロールします。"
            store.applyStreamingSnapshot(ChatStreamingSnapshot(
                targetId: 24,
                text: source,
                thinking: "",
                toolActivity: nil,
                isFinal: false
            ))

            // The finger moves after the stream update captured its pre-measurement state.
            // A delayed height measurement must not restore that older offset.
            expectedOffset = max(minimumOffset, expectedOffset - 18)
            collectionView.setContentOffset(CGPoint(x: 0, y: expectedOffset), animated: false)
            controller.scrollViewDidScroll(collectionView)
            for _ in 0..<6 {
                await Task.yield()
                controller.view.layoutIfNeeded()
            }
            XCTAssertEqual(collectionView.contentOffset.y, expectedOffset, accuracy: 0.5)
        }

        controller.scrollViewDidEndDragging(collectionView, willDecelerate: true)
        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 24,
            text: source + "\n\n慣性スクロール中の更新です。",
            thinking: "",
            toolActivity: nil,
            isFinal: false
        ))
        expectedOffset = max(minimumOffset, expectedOffset - 24)
        collectionView.setContentOffset(CGPoint(x: 0, y: expectedOffset), animated: false)
        controller.scrollViewDidScroll(collectionView)
        for _ in 0..<8 {
            await Task.yield()
            controller.view.layoutIfNeeded()
        }
        XCTAssertEqual(
            collectionView.contentOffset.y,
            expectedOffset,
            accuracy: 0.5,
            "Streaming must not fight deceleration"
        )
        XCTAssertGreaterThan(
            abs(collectionView.contentSize.height - initialContentHeight),
            0.5,
            "Streaming height measurement must still be applied while the user scrolls"
        )
        controller.scrollViewDidEndDecelerating(collectionView)
    }

    @MainActor
    func testReturningToTailDuringGenerationContinuesFollowingNewContent() async throws {
        let store = ChatTimelineStore()
        store.update(messages: (1...24).map {
            timelineMessage(id: Int64($0), text: String(repeating: "Message \($0) line\n", count: 4))
        })
        let controller = configuredTimelineController(store: store, scrollRequest: 1)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        await settleTimeline(controller)
        let collectionView = try XCTUnwrap(findCollectionView(in: controller.view))

        var source = String(repeating: "生成中の回答です。\n\n", count: 20)
        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 24,
            text: source,
            thinking: "",
            toolActivity: nil,
            isFinal: false
        ))
        await settleTimeline(controller)

        controller.scrollViewWillBeginDragging(collectionView)
        collectionView.setContentOffset(
            CGPoint(x: 0, y: maximumContentOffset(in: collectionView)),
            animated: false
        )
        controller.scrollViewDidScroll(collectionView)
        controller.scrollViewDidEndDragging(collectionView, willDecelerate: false)
        let previousTailOffset = collectionView.contentOffset.y

        source += String(repeating: "さらに生成された文章です。\n\n", count: 30)
        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 24,
            text: source,
            thinking: "",
            toolActivity: nil,
            isFinal: false
        ))
        await settleTimeline(controller)

        XCTAssertGreaterThan(collectionView.contentOffset.y, previousTailOffset)
        XCTAssertEqual(
            collectionView.contentOffset.y,
            maximumContentOffset(in: collectionView),
            accuracy: 0.5,
            "A reader who returns to the tail must follow newly streamed text"
        )
    }

    @MainActor
    func testReleasedDetachedScrollRemainsStableAcrossNextStreamFrame() async throws {
        let store = ChatTimelineStore()
        store.update(messages: (1...24).map {
            timelineMessage(id: Int64($0), text: String(repeating: "Message \($0) line\n", count: 4))
        })
        let controller = configuredTimelineController(store: store, scrollRequest: 1)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        await settleTimeline(controller)
        let collectionView = try XCTUnwrap(findCollectionView(in: controller.view))

        controller.scrollViewWillBeginDragging(collectionView)
        let detachedOffset = max(
            -collectionView.adjustedContentInset.top,
            collectionView.contentOffset.y - 500
        )
        collectionView.setContentOffset(CGPoint(x: 0, y: detachedOffset), animated: false)
        controller.scrollViewDidScroll(collectionView)
        controller.scrollViewDidEndDragging(collectionView, willDecelerate: false)
        await settleTimeline(controller)
        let settledOffset = collectionView.contentOffset.y
        let anchor = try XCTUnwrap(visibleAnchor(in: collectionView))

        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 24,
            text: String(repeating: "生成中の長い回答です。\n", count: 80),
            thinking: "",
            toolActivity: nil,
            isFinal: false
        ))
        await settleTimeline(controller)

        XCTAssertEqual(collectionView.contentOffset.y, settledOffset, accuracy: 0.5)
        assertVisibleAnchor(anchor, in: collectionView)
    }

    @MainActor
    func testPendingLatestMoveDoesNotOverrideAUserScroll() async throws {
        let store = ChatTimelineStore()
        store.update(messages: (1...20).map {
            timelineMessage(id: Int64($0), text: String(repeating: "Message \($0) line\n", count: 4))
        })
        let controller = configuredTimelineController(store: store, scrollRequest: 1)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        await settleTimeline(controller)
        let collectionView = try XCTUnwrap(findCollectionView(in: controller.view))

        store.update(messages: (1...21).map {
            timelineMessage(id: Int64($0), text: String(repeating: "Message \($0) line\n", count: 4))
        })
        configure(controller, store: store, scrollRequest: 2)

        controller.scrollViewWillBeginDragging(collectionView)
        let userOffset = max(
            -collectionView.adjustedContentInset.top,
            collectionView.contentOffset.y - 500
        )
        collectionView.setContentOffset(CGPoint(x: 0, y: userOffset), animated: false)
        controller.scrollViewDidScroll(collectionView)
        controller.scrollViewDidEndDragging(collectionView, willDecelerate: false)
        await settleTimeline(controller)

        XCTAssertEqual(
            collectionView.contentOffset.y,
            userOffset,
            accuracy: 0.5,
            "A delayed diffable-data-source completion must not jump back to the tail"
        )
    }

    @MainActor
    func testToolSummaryAndAnswerNeverMoveTogetherDuringStreamingUpdates() async throws {
        let store = ChatTimelineStore()
        store.update(messages: (1...24).map {
            timelineMessage(id: Int64($0), text: String(repeating: "Message \($0) line\n", count: 4))
        })
        let controller = configuredTimelineController(store: store, scrollRequest: 1)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        var source = "# 回答\n\n" + String(
            repeating: "ツールを使った回答を生成中です。表示位置を確認する段落です。\n\n",
            count: 10
        )
        var steps = [toolActivityStep(id: "tool-0", status: .completed)]
        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 24,
            text: source,
            thinking: "",
            toolActivity: ToolActivityPayload(steps: steps),
            isFinal: false
        ))
        await settleTimeline(controller)
        let collectionView = try XCTUnwrap(findCollectionView(in: controller.view))
        let targetIndexPath = IndexPath(item: 23, section: 0)

        controller.scrollViewWillBeginDragging(collectionView)
        collectionView.setContentOffset(
            CGPoint(x: 0, y: max(
                -collectionView.adjustedContentInset.top,
                collectionView.contentOffset.y - 120
            )),
            animated: false
        )
        controller.scrollViewDidScroll(collectionView)
        controller.scrollViewDidEndDragging(collectionView, willDecelerate: false)
        await settleTimeline(controller)
        let cell = try XCTUnwrap(collectionView.cellForItem(at: targetIndexPath))
        let baselineFrame = cell.convert(cell.bounds, to: controller.view)
        let baselineTop = baselineFrame.minY
        let stableTopRegion = CGRect(
            x: baselineFrame.minX,
            y: baselineFrame.minY,
            width: baselineFrame.width,
            height: min(baselineFrame.height, 100)
        )
        let baselinePixels = try XCTUnwrap(renderedPixels(of: controller.view))
        let baselineFirstInkRow = try XCTUnwrap(
            baselinePixels.darkPixelCountsByRow(in: stableTopRegion).firstIndex { $0 >= 8 }
        )
        var observedTops: [CGFloat] = []
        var observedFirstInkRows: [Int] = []

        for update in 1...6 {
            for status in [ToolActivityStep.Status.running, .completed] {
                if status == .running {
                    steps.append(toolActivityStep(id: "tool-\(update)", status: .running))
                } else {
                    steps[steps.index(before: steps.endIndex)].status = .completed
                    source += "\n\n更新\(update)です。回答の高さを増やしながら、ツール表示と回答全体の位置が動かないことを確認します。"
                }
                store.applyStreamingSnapshot(ChatStreamingSnapshot(
                    targetId: 24,
                    text: source,
                    thinking: "",
                    toolActivity: ToolActivityPayload(steps: steps),
                    isFinal: false
                ))
                for _ in 0..<10 {
                    try? await Task.sleep(nanoseconds: 4_000_000)
                    controller.view.layoutIfNeeded()
                    observedTops.append(cell.convert(cell.bounds, to: controller.view).minY)
                    let pixels = try XCTUnwrap(renderedPixels(of: controller.view))
                    if let firstInkRow = pixels.darkPixelCountsByRow(in: stableTopRegion).firstIndex(where: { $0 >= 8 }) {
                        observedFirstInkRows.append(firstInkRow)
                    }
                    if let presentationFrame = cell.layer.presentation()?.frame {
                        observedTops.append(presentationFrame.minY - collectionView.contentOffset.y)
                    }
                }
            }
        }

        XCTAssertTrue(
            observedTops.allSatisfy { abs($0 - baselineTop) <= 0.5 },
            "Tool summary + answer moved together: baseline=\(baselineTop), observed=\(observedTops)"
        )
        XCTAssertTrue(
            observedFirstInkRows.allSatisfy { $0 == baselineFirstInkRow },
            "Hosted tool summary + answer moved inside the cell: baseline=\(baselineFirstInkRow), observed=\(observedFirstInkRows)"
        )
    }

    @MainActor
    func testStreamingMarkdownKeepsRenderedPriorParagraphStableWhileAppendingParagraph() async throws {
        let store = ChatTimelineStore()
        store.update(messages: [timelineMessage(id: 1, text: "")])
        let controller = configuredTimelineController(store: store)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        var source = "# 見出し\n\n最初の段落は位置を変えてはいけません。"
        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 1,
            text: source,
            thinking: "",
            toolActivity: nil,
            isFinal: false
        ))
        await settleTimeline(controller)
        let collectionView = try XCTUnwrap(findCollectionView(in: controller.view))
        let cell = try XCTUnwrap(collectionView.cellForItem(at: IndexPath(item: 0, section: 0)))
        let cellFrame = cell.convert(cell.bounds, to: controller.view)
        XCTAssertLessThan(cellFrame.height, 100, "Short content must shrink below the 120pt estimate")
        let stableRegion = CGRect(
            x: cellFrame.minX,
            y: cellFrame.minY,
            width: cellFrame.width,
            height: max(cellFrame.height - 1, 1)
        )
        let baselineFrame = try XCTUnwrap(renderedPixels(of: controller.view))
        let baselineInkRows = baselineFrame.darkPixelCountsByRow(in: stableRegion)
        XCTAssertGreaterThan(baselineInkRows.max() ?? 0, 0)
        var changedVerticalProfiles = 0
        var firstChangedProfile: [Int]?

        for character in "\n\n次の段落を生成しています。" {
            source.append(character)
            store.applyStreamingSnapshot(ChatStreamingSnapshot(
                targetId: 1,
                text: source,
                thinking: "",
                toolActivity: nil,
                isFinal: false
            ))
            for _ in 0..<3 {
                await Task.yield()
                controller.view.layoutIfNeeded()
                let renderedFrame = try XCTUnwrap(renderedPixels(of: controller.view))
                let inkRows = renderedFrame.darkPixelCountsByRow(in: stableRegion)
                if inkRows != baselineInkRows {
                    changedVerticalProfiles += 1
                    if firstChangedProfile == nil {
                        firstChangedProfile = inkRows
                    }
                }
            }
        }

        XCTAssertEqual(
            changedVerticalProfiles,
            0,
            "Existing heading/paragraph moved vertically in \(changedVerticalProfiles) intermediate frames; baseline=\(baselineInkRows), firstChanged=\(firstChangedProfile ?? [])"
        )
        XCTAssertGreaterThan(
            cell.bounds.height,
            cellFrame.height,
            "The test must exercise a real self-sizing cell height increase"
        )
    }

    @MainActor
    func testLatestMoveFollowsStreamGrowthAndCompletion() async throws {
        let store = ChatTimelineStore()
        store.update(messages: (1...20).map {
            timelineMessage(id: Int64($0), text: String(repeating: "Message \($0) line\n", count: 5))
        })
        let controller = configuredTimelineController(store: store, scrollRequest: 1)
        await settleTimeline(controller)
        let collectionView = try XCTUnwrap(findCollectionView(in: controller.view))
        let initialOffset = collectionView.contentOffset.y

        let firstStream = String(repeating: "# Live heading\n\n- item\n\n", count: 40)
        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 20,
            text: firstStream,
            thinking: "",
            toolActivity: nil,
            isFinal: false
        ))
        await settleTimeline(controller)
        XCTAssertGreaterThan(collectionView.contentOffset.y, initialOffset)
        XCTAssertEqual(collectionView.contentOffset.y, maximumContentOffset(in: collectionView), accuracy: 0.5)

        let streamOffset = collectionView.contentOffset.y
        let secondStream = firstStream + String(repeating: "追加の生成段落です。\n\n", count: 40)
        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 20,
            text: secondStream,
            thinking: "",
            toolActivity: nil,
            isFinal: false
        ))
        await settleTimeline(controller)
        XCTAssertGreaterThan(collectionView.contentOffset.y, streamOffset)
        XCTAssertEqual(collectionView.contentOffset.y, maximumContentOffset(in: collectionView), accuracy: 0.5)

        store.applyStreamingSnapshot(ChatStreamingSnapshot(
            targetId: 20,
            text: secondStream,
            thinking: "",
            toolActivity: nil,
            isFinal: true
        ))
        await settleTimeline(controller)
        XCTAssertEqual(collectionView.contentOffset.y, maximumContentOffset(in: collectionView), accuracy: 0.5)
    }

    @MainActor
    private func configuredTimelineController(
        store: ChatTimelineStore,
        scrollRequest: Int = 0
    ) -> ChatTimelineViewController {
        let controller = ChatTimelineViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        configure(controller, store: store, scrollRequest: scrollRequest)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        return controller
    }

    @MainActor
    private func configure(
        _ controller: ChatTimelineViewController,
        store: ChatTimelineStore,
        scrollRequest: Int
    ) {
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
            onRegenerate: {},
            onAskChatWithSelection: { _ in }
        )
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

    private func toolActivityStep(id: String, status: ToolActivityStep.Status) -> ToolActivityStep {
        ToolActivityStep(
            id: id,
            round: 1,
            toolName: "test_tool",
            title: "Tool",
            detail: id,
            status: status,
            resultCount: 1,
            sources: [],
            errorMessage: nil,
            createdAtMs: 1
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

    private struct RenderedPixels {
        let data: Data
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let bytesPerPixel: Int

        func darkPixelCountsByRow(in rect: CGRect) -> [Int] {
            let integral = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
            guard !integral.isEmpty else { return [] }
            let minX = Int(integral.minX)
            let maxX = Int(integral.maxX)
            let minY = Int(integral.minY)
            let maxY = Int(integral.maxY)
            var output: [Int] = []
            output.reserveCapacity(maxY - minY)
            for y in minY..<maxY {
                var darkPixels = 0
                for x in minX..<maxX {
                    let offset = y * bytesPerRow + x * bytesPerPixel
                    guard offset + 2 < data.count else { continue }
                    if data[offset] < 160, data[offset + 1] < 160, data[offset + 2] < 160 {
                        darkPixels += 1
                    }
                }
                output.append(darkPixels)
            }
            return output
        }
    }

    @MainActor
    private func renderedPixels(of view: UIView) -> RenderedPixels? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            UIColor.systemBackground.setFill()
            context.fill(view.bounds)
            view.layer.render(in: context.cgContext)
        }
        guard let cgImage = image.cgImage,
              let providerData = cgImage.dataProvider?.data
        else { return nil }
        return RenderedPixels(
            data: providerData as Data,
            width: cgImage.width,
            height: cgImage.height,
            bytesPerRow: cgImage.bytesPerRow,
            bytesPerPixel: cgImage.bitsPerPixel / 8
        )
    }

    private func visibleAnchor(in collectionView: UICollectionView) -> (indexPath: IndexPath, offset: CGFloat)? {
        guard let indexPath = collectionView.indexPathsForVisibleItems.sorted().first,
              let attributes = collectionView.layoutAttributesForItem(at: indexPath)
        else { return nil }
        return (indexPath, attributes.frame.minY - collectionView.contentOffset.y)
    }

    private func maximumContentOffset(in collectionView: UICollectionView) -> CGFloat {
        max(
            -collectionView.adjustedContentInset.top,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
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
