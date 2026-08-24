import SwiftUI
import XCTest
@testable import YamabikoChat

final class ChatPerformancePolicyTests: XCTestCase {
    func testTimelineFollowUsesLayoutHeightOnlyWhileActivelyFollowing() {
        XCTAssertTrue(ChatScrollPolicy.shouldFollowTimelineLayoutChange(
            isAutoFollowing: true,
            isUserInteracting: false,
            previousHeight: 700,
            currentHeight: 730
        ))
        XCTAssertTrue(ChatScrollPolicy.shouldFollowTimelineLayoutChange(
            isAutoFollowing: true,
            isUserInteracting: false,
            previousHeight: 730,
            currentHeight: 700
        ))
        XCTAssertFalse(ChatScrollPolicy.shouldFollowTimelineLayoutChange(
            isAutoFollowing: false,
            isUserInteracting: false,
            previousHeight: 700,
            currentHeight: 730
        ))
        XCTAssertFalse(ChatScrollPolicy.shouldFollowTimelineLayoutChange(
            isAutoFollowing: true,
            isUserInteracting: true,
            previousHeight: 700,
            currentHeight: 730
        ))
        XCTAssertFalse(ChatScrollPolicy.shouldFollowTimelineLayoutChange(
            isAutoFollowing: true,
            isUserInteracting: false,
            previousHeight: 0,
            currentHeight: 730
        ))
        XCTAssertFalse(ChatScrollPolicy.shouldFollowTimelineLayoutChange(
            isAutoFollowing: true,
            isUserInteracting: false,
            previousHeight: 700,
            currentHeight: 700.5
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
