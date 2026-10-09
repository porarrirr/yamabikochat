import SwiftUI
import XCTest
@testable import YamabikoChat

final class ChatPerformancePolicyTests: XCTestCase {
    @MainActor
    func testLongResponseStreamingParsePerformance() {
        let prefix = String(repeating: "## 見出し\n\n本文には **強調** と `code` を含みます。\n\n", count: 100)
        let frames = (1...30).map { prefix + String(repeating: "追記する本文。", count: $0) }
        measure {
            let parser = NativeMarkdownIncrementalParser()
            for frame in frames {
                XCTAssertFalse(parser.streamingBlocks(for: frame).isEmpty)
            }
        }
    }

    @MainActor
    func testStreamingParserOnlyReparsesUnconfirmedSuffixAndReusesIdenticalText() {
        let parser = NativeMarkdownIncrementalParser()
        let prefix = String(repeating: "## 見出し\n\n日本語の **段落**。\n\n", count: 100)
        var fullParseBytes = 0
        for frame in 1...30 {
            let source = prefix + String(repeating: "追記。", count: frame)
            fullParseBytes += source.utf8.count
            XCTAssertEqual(parser.streamingBlocks(for: source), NativeMarkdownParser.parse(source, rendersMath: false))
        }
        XCTAssertLessThan(parser.parsedUTF8ByteCount, fullParseBytes / 10)
        let parsedBytes = parser.parsedUTF8ByteCount
        _ = parser.streamingBlocks(for: prefix + String(repeating: "追記。", count: 30))
        XCTAssertEqual(parser.parsedUTF8ByteCount, parsedBytes, "Thinking/tool-only updates must not parse the unchanged answer")
    }

    @MainActor
    func testIncrementalParserMatchesFullParseAcrossAmbiguousBoundariesAndReplacements() {
        let fixtures = [
            "導入👨‍👩‍👧‍👦\n\n- item\n#text\n\nAfter\n\nEnd",
            "# Intro\n\n> quote\n#text\n\nAfter\n\nEnd",
            "Intro\n\n    indented code\n\n    more code\n\nAfter\n\nEnd",
            "Intro\n\n  ### Heading\n\n  paragraph\n\nAfter\n\nEnd",
            "Intro\n\n```swift\nlet a = 1\n\nlet b = 2\n```\n\nAfter\n\nEnd",
            "Intro\n\n~~~swift\nlet a = 1\n\n~~~\n\nAfter\n\nEnd",
            "Intro\n\nTitle\n---\n\n| A | B |\n| - | - |\n| a | b |\n\nAfter",
            "Intro\n\n- first\n\n  continuation\n- next\n\nAfter\n\nEnd",
            "Intro\n\n<link>\nHTML\n\nAfter\n\nEnd",
            "Intro\n\n[linked][ref]\n\nMiddle\n\n[ref]: https://example.com\n\nEnd",
            "[ref]: https://example.com\n\nIntro\n\nMiddle\n\n[linked][ref]\n\nEnd",
            "Intro\r\n\r\n日本語 e\u{301}\r\n\r\nTail\r\n\r\nEnd"
        ]
        for source in fixtures {
            let parser = NativeMarkdownIncrementalParser()
            var partial = ""
            for character in source {
                partial.append(character)
                XCTAssertEqual(
                    parser.streamingBlocks(for: partial),
                    NativeMarkdownParser.parse(partial, rendersMath: false),
                    "Mismatch after: \(partial)"
                )
            }
            for replacement in ["Short", "", "e\u{301}\n\nMiddle\n\nTail", "é\n\nMiddle\n\nTail", "# Replaced\n\n別の本文\n\nTail", source] {
                XCTAssertEqual(parser.streamingBlocks(for: replacement), NativeMarkdownParser.parse(replacement, rendersMath: false))
            }
            parser.reset()
            XCTAssertEqual(parser.streamingBlocks(for: source), NativeMarkdownParser.parse(source, rendersMath: false))
        }
    }

    @MainActor
    func testStreamingReplacementCanMergeBackIntoPreviouslyConfirmedList() {
        let parser = NativeMarkdownIncrementalParser()
        _ = parser.streamingBlocks(for: "- first\n\nMiddle\n\nTail")
        let replacement = "- first\n\n- second"
        XCTAssertEqual(parser.streamingBlocks(for: replacement), NativeMarkdownParser.parse(replacement, rendersMath: false))
    }

    @MainActor
    func testSelectableTextCachesSizeByWidthAndInvalidatesForContentAndFontChanges() {
        let view = SelectableChatTextView()
        view.isScrollEnabled = false
        view.attributedText = NSAttributedString(string: String(repeating: "本文 text ", count: 40), attributes: [.font: UIFont.systemFont(ofSize: 17)])
        let original = view.measuredSize(for: 320)
        let narrower = view.measuredSize(for: 200)
        XCTAssertGreaterThan(narrower.height, original.height)
        let count = view.textMeasurementCount
        for _ in 0..<20 {
            XCTAssertEqual(view.measuredSize(for: 320), original)
            XCTAssertEqual(view.measuredSize(for: 200), narrower)
        }
        XCTAssertEqual(view.textMeasurementCount, count)
        view.attributedText = NSAttributedString(string: "Short", attributes: [.font: UIFont.systemFont(ofSize: 17)])
        XCTAssertLessThan(view.measuredSize(for: 320).height, original.height)
        let small = view.measuredSize(for: 320)
        view.attributedText = NSAttributedString(string: "Short", attributes: [.font: UIFont.systemFont(ofSize: 40)])
        XCTAssertGreaterThan(view.measuredSize(for: 320).height, small.height)
        XCTAssertEqual(view.textMeasurementCount, count + 2)
        view.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        view.updateTraitsIfNeeded()
        XCTAssertEqual(view.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
        _ = view.measuredSize(for: 320)
        XCTAssertEqual(view.textMeasurementCount, count + 3, "Dynamic Type must invalidate cached metrics even when source text is unchanged")
    }

    @MainActor
    func testTimelineLayoutOnlyRebuildsChangedSuffixAndFindsVisibleRowsWithoutScanningHistory() throws {
        let layout = ChatTimelineLayout()
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 700), collectionViewLayout: layout)
        let source = LayoutDataSource(count: 1_000)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collection.dataSource = source
        collection.reloadData()
        collection.layoutIfNeeded()
        let previousCount = layout.preparedItemCount
        let previousHeight = layout.collectionViewContentSize.height
        let previousFirstFrame = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame
        let context = ChatTimelineLayoutInvalidationContext()
        context.preferredHeights[IndexPath(item: 999, section: 0)] = 200
        layout.invalidateLayout(with: context)
        layout.invalidateLayout()
        layout.prepare()
        XCTAssertEqual(layout.preparedItemCount - previousCount, 1)
        XCTAssertEqual(layout.collectionViewContentSize.height - previousHeight, 80, accuracy: 0.5)
        XCTAssertEqual(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame, previousFirstFrame)
        let visibleRect = CGRect(x: 0, y: previousHeight - 700, width: 390, height: 700)
        let visible = try XCTUnwrap(layout.layoutAttributesForElements(in: visibleRect))
        let expected = (0..<1_000).compactMap { layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }.filter { $0.frame.intersects(visibleRect) }
        XCTAssertEqual(visible.map(\.indexPath), expected.map(\.indexPath))
        XCTAssertLessThan(layout.lastElementLookupCount, 25)
        let preparedCount = layout.preparedItemCount
        for _ in 0..<20 { layout.prepare() }
        XCTAssertEqual(layout.preparedItemCount, preparedCount)

        let ids = (0..<1_000).map(String.init)
        layout.remapMeasuredHeights(from: ids, to: [ids[999]] + Array(ids.dropLast()))
        layout.prepare()
        XCTAssertEqual(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.size.height, 200)
        collection.bounds.size.width = 600
        layout.prepare()
        XCTAssertEqual(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.size.width, 564)
        layout.resetMeasuredHeights()
        layout.prepare()
        XCTAssertEqual(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.size.height, 120)
        layout.remapMeasuredHeights(from: ids, to: [])
        source.count = 0
        collection.reloadData()
        collection.layoutIfNeeded()
        XCTAssertNil(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        XCTAssertEqual(layout.collectionViewContentSize.height, 44)
        layout.remapMeasuredHeights(from: [], to: Array(ids.prefix(3)))
        source.count = 3
        collection.reloadData()
        collection.layoutIfNeeded()
        XCTAssertEqual(layout.collectionViewContentSize.height, 44 + 3 * 120 + 2 * 22)
        withExtendedLifetime(source) {}
    }

    @MainActor
    private final class LayoutDataSource: NSObject, UICollectionViewDataSource {
        var count: Int
        init(count: Int) { self.count = count }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { count }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        }
    }

    func testStreamingMarkdownKeepsRenderedBlocksVisibleWhileNextParseIsPending() {
        XCTAssertFalse(NativeMarkdownPresentationPolicy.showsInitialRawText(
            hasParsedRequest: true,
            hasRenderedBlocks: true,
            sourceIsEmpty: false
        ))
        XCTAssertTrue(NativeMarkdownPresentationPolicy.showsInitialRawText(
            hasParsedRequest: false,
            hasRenderedBlocks: false,
            sourceIsEmpty: false
        ))
        XCTAssertFalse(NativeMarkdownPresentationPolicy.showsInitialRawText(
            hasParsedRequest: false,
            hasRenderedBlocks: false,
            sourceIsEmpty: true
        ))
    }

    func testToolActivityPreviewClipsBeforeSwiftUITextLayout() {
        let oversized = String(repeating: "あ", count: ToolActivityPreviewPolicy.maximumDisplayedCharacters + 50)
        let clipped = ToolActivityPreviewPolicy.displayText(oversized)

        XCTAssertEqual(
            clipped.dropLast(2).count,
            ToolActivityPreviewPolicy.maximumDisplayedCharacters
        )
        XCTAssertTrue(clipped.hasSuffix("\n…"))
        XCTAssertEqual(ToolActivityPreviewPolicy.displayText("short"), "short")
    }

    func testReleaseToolFailurePresentationDoesNotHighlightRecoveredFailure() {
        let steps = [
            toolStep(id: "success-1", status: .completed),
            toolStep(id: "failure", status: .failed),
            toolStep(id: "success-2", status: .completed)
        ]

        XCTAssertFalse(ToolActivityFailurePresentationPolicy.shouldHighlightAggregateFailure(
            in: steps,
            includesRecoveredFailures: false
        ))
        XCTAssertTrue(ToolActivityFailurePresentationPolicy.shouldHighlightAggregateFailure(
            in: steps,
            includesRecoveredFailures: true
        ))
    }

    #if DEBUG
    func testDebugToolFailurePresentationHighlightsRecoveredFailureByDefault() {
        let steps = [
            toolStep(id: "failure", status: .failed),
            toolStep(id: "success", status: .completed)
        ]

        XCTAssertTrue(ToolActivityFailurePresentationPolicy.shouldHighlightAggregateFailure(in: steps))
    }
    #endif

    func testReleaseToolFailurePresentationHighlightsTerminalFailure() {
        let steps = [
            toolStep(id: "success", status: .completed),
            toolStep(id: "failure", status: .failed)
        ]

        XCTAssertTrue(ToolActivityFailurePresentationPolicy.shouldHighlightAggregateFailure(
            in: steps,
            includesRecoveredFailures: false
        ))
    }

    func testReleaseToolFailurePresentationWaitsForRunningStep() {
        let steps = [
            toolStep(id: "failure", status: .failed),
            toolStep(id: "running", status: .running)
        ]

        XCTAssertFalse(ToolActivityFailurePresentationPolicy.shouldHighlightAggregateFailure(
            in: steps,
            includesRecoveredFailures: false
        ))
    }

    func testMarkdownDocumentCacheBuildsIdenticalDocumentOnce() {
        let unique = UUID().uuidString
        let signature = MathMarkdownDocumentSignature(
            mathRenderingEnabled: false,
            colorScheme: .dark,
            mathJaxScriptTag: unique,
            copyButtonLabel: "Copy",
            copiedButtonLabel: "Copied"
        )
        var buildCount = 0

        let first = MathMarkdownDocumentCache.document(for: signature) {
            buildCount += 1
            return "document"
        }
        let second = MathMarkdownDocumentCache.document(for: signature) {
            buildCount += 1
            return "other"
        }

        XCTAssertEqual(first, "document")
        XCTAssertEqual(second, "document")
        XCTAssertEqual(buildCount, 1)
    }

    func testHundredMessageTimelineFixtureBuildsInStableOrder() {
        let markdown = """
        # Performance fixture
        A paragraph with **Markdown**, `code`, and math $x^2 + y^2$.
        """
        let longThinking = String(repeating: "reasoning line\n", count: 1_250)
        let messages = (0..<100).map { index in
            FullChatMessage(
                id: Int64(index + 1),
                message: ChatMessage(
                    id: Int64(index + 1),
                    conversationId: 1,
                    role: index.isMultiple(of: 2) ? "user" : "model",
                    text: String(repeating: markdown, count: index.isMultiple(of: 5) ? 12 : 1),
                    createdAtMs: Int64(index)
                ),
                thinkingStream: index.isMultiple(of: 10) ? longThinking : nil,
                variants: []
            )
        }.reversed()

        measure {
            let snapshot = ChatTimelineSnapshot(messages: Array(messages), dualMessages: [])
            XCTAssertEqual(snapshot.items.count, 100)
            XCTAssertEqual(snapshot.items.first?.createdAtMs, 0)
            XCTAssertEqual(snapshot.items.last?.createdAtMs, 99)
        }
    }

    private func toolStep(id: String, status: ToolActivityStep.Status) -> ToolActivityStep {
        ToolActivityStep(
            id: id,
            round: 1,
            toolName: "test_tool",
            title: id,
            detail: "",
            status: status,
            resultCount: nil,
            sources: [],
            errorMessage: status == .failed ? "failed" : nil,
            createdAtMs: 1
        )
    }
}
