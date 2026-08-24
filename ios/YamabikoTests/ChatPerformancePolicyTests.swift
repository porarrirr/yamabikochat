import SwiftUI
import XCTest
@testable import YamabikoChat

final class ChatPerformancePolicyTests: XCTestCase {
    func testScrollFollowsContentOnlyWhenIdleAtBottom() {
        XCTAssertTrue(ChatScrollPolicy.shouldFollowContentGrowth(isNearBottom: true, isUserInteracting: false))
        XCTAssertFalse(ChatScrollPolicy.shouldFollowContentGrowth(isNearBottom: false, isUserInteracting: false))
        XCTAssertFalse(ChatScrollPolicy.shouldFollowContentGrowth(isNearBottom: true, isUserInteracting: true))
    }

    func testStreamingScrollFollowsMeasuredLayoutGrowth() {
        XCTAssertTrue(ChatScrollPolicy.shouldFollowStreamingLayoutChange(
            wasNearBottom: true,
            isUserInteracting: false,
            isStreaming: true,
            isFinalizingStreamLayout: false,
            previousBottomMaxY: 700,
            currentBottomMaxY: 730
        ))
        XCTAssertFalse(ChatScrollPolicy.shouldFollowStreamingLayoutChange(
            wasNearBottom: true,
            isUserInteracting: false,
            isStreaming: true,
            isFinalizingStreamLayout: false,
            previousBottomMaxY: 730,
            currentBottomMaxY: 700
        ))
        XCTAssertFalse(ChatScrollPolicy.shouldFollowStreamingLayoutChange(
            wasNearBottom: true,
            isUserInteracting: true,
            isStreaming: true,
            isFinalizingStreamLayout: false,
            previousBottomMaxY: 700,
            currentBottomMaxY: 730
        ))
        XCTAssertFalse(ChatScrollPolicy.shouldFollowStreamingLayoutChange(
            wasNearBottom: true,
            isUserInteracting: false,
            isStreaming: false,
            isFinalizingStreamLayout: false,
            previousBottomMaxY: 700,
            currentBottomMaxY: 730
        ))
    }

    func testCompletedStreamFollowsFinalLayoutGrowthAndShrink() {
        XCTAssertTrue(ChatScrollPolicy.shouldFollowStreamingLayoutChange(
            wasNearBottom: true,
            isUserInteracting: false,
            isStreaming: false,
            isFinalizingStreamLayout: true,
            previousBottomMaxY: 730,
            currentBottomMaxY: 700
        ))
        XCTAssertTrue(ChatScrollPolicy.shouldFollowStreamingLayoutChange(
            wasNearBottom: true,
            isUserInteracting: false,
            isStreaming: false,
            isFinalizingStreamLayout: true,
            previousBottomMaxY: 700,
            currentBottomMaxY: 730
        ))
        XCTAssertFalse(ChatScrollPolicy.shouldFollowStreamingLayoutChange(
            wasNearBottom: false,
            isUserInteracting: false,
            isStreaming: false,
            isFinalizingStreamLayout: true,
            previousBottomMaxY: 730,
            currentBottomMaxY: 700
        ))
        XCTAssertFalse(ChatScrollPolicy.shouldFollowStreamingLayoutChange(
            wasNearBottom: true,
            isUserInteracting: true,
            isStreaming: false,
            isFinalizingStreamLayout: true,
            previousBottomMaxY: 730,
            currentBottomMaxY: 700
        ))
    }

    func testMarkdownInputSignatureDistinguishesFinalStreamingTransition() {
        let streaming = MathMarkdownInputSignature(
            markdownText: "same",
            mathRenderingEnabled: true,
            isStreaming: true,
            colorScheme: .light
        )
        let final = MathMarkdownInputSignature(
            markdownText: "same",
            mathRenderingEnabled: true,
            isStreaming: false,
            colorScheme: .light
        )

        XCTAssertNotEqual(streaming, final)
        XCTAssertEqual(streaming, streaming)
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
}
