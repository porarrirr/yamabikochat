import Darwin
import os.signpost
import UIKit
import XCTest
@testable import YamabikoChat

/// Real hosting cells, layout, text selection and display commits, without network variance.
/// Opt in through the xctestrun environment: YAMABIKO_RENDER_BENCHMARK=1.
final class ChatRenderingPerformanceTests: XCTestCase {
    @MainActor
    func testRenderingWorkloads() async throws {
        guard ProcessInfo.processInfo.environment["YAMABIKO_RENDER_BENCHMARK"] == "1" else {
            throw XCTSkip("Explicit rendering benchmark only")
        }
        let log = OSLog(subsystem: "com.porarri.yamabikochat.performance", category: .pointsOfInterest)
        let prose = (1...24).map {
            "## 手順\($0)\n\n日本語の **説明** と [出典](https://example.com/\($0))。計算結果を確認してから次に進みます。\n\n"
        }.joined() + "```swift\nlet values = [12, 18, 30]\nprint(values.reduce(0, +))\n```\n\n最終回答は **60** です。"
        let list = (1...100).map {
            "\($0). 日本語の **手順\($0)** と `code`。[資料](https://example.com/\($0))を確認します。\n"
        }.joined() + "\n最終回答は **60** です。"
        for sample in 0..<3 {
            for workload in ["prose", "list", "thinking", "scroll", "idle"] {
                let store = ChatTimelineStore()
                let source = workload == "list" ? list : prose
                var messages = (1...100).map { index in
                    message(id: Int64(index), text: "## 履歴\(index)\n\n" + String(repeating: "日本語の **回答** と [資料](https://example.com)。\n\n", count: index % 4 + 1))
                }
                messages.append(message(id: 101, text: workload == "thinking" || workload == "scroll" || workload == "idle" ? source : ""))
                store.update(messages: messages)
                let controller = ChatTimelineViewController()
                controller.loadViewIfNeeded()
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.configure(store: store, scrollToLatestRequest: 1, regeneratableMessageID: nil,
                    mathRenderingEnabled: true, fusionDebugModeEnabled: false, dualSplitLayout: "VERTICAL", dualSplitRatio: 0.5,
                    fusionTraceForMessage: { _ in nil }, onRoute: { _ in }, onPreviousVariant: { _ in },
                    onNextVariant: { _ in }, onBranch: { _ in }, onRegenerate: {}, onAskChatWithSelection: { _ in },
                    onEditUserMessage: { _ in }, onSelectUserMessageText: { _ in })
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(750))
                let collection = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
                let characters = Array(source)
                let frames = (1...120).map { String(characters.prefix((characters.count * $0 + 119) / 120)) }
                if workload == "scroll" { controller.scrollViewWillBeginDragging(collection) }
                let signpostID = OSSignpostID(log: log)
                os_signpost(.begin, log: log, name: "RenderingWorkload", signpostID: signpostID, "%{public}@", workload as NSString)
                let cpuStart = cpuSeconds()
                let start = ContinuousClock.now
                for frame in 0..<120 {
                    if workload == "prose" || workload == "list" || workload == "thinking" {
                        store.applyStreamingSnapshot(ChatStreamingSnapshot(targetId: 101,
                            text: workload == "thinking" ? source : frames[frame],
                            thinking: workload == "thinking" ? String(repeating: "検討中。", count: frame + 1) : "",
                            isFinal: false))
                    } else if workload == "scroll" {
                        let fraction = CGFloat(frame % 60) / 59
                        let progress = frame < 60 ? 1 - fraction : fraction
                        collection.setContentOffset(CGPoint(x: 0, y: max(0, collection.contentSize.height - collection.bounds.height) * progress), animated: false)
                        controller.scrollViewDidScroll(collection)
                    }
                    controller.view.layoutIfNeeded()
                    // Absolute pacing: every input is applied, without dropping slow frames.
                    try await Task.sleep(until: start + .nanoseconds(Int64(frame + 1) * 33_333_333), clock: .continuous)
                }
                if workload == "scroll" { controller.scrollViewDidEndDragging(collection, willDecelerate: false) }
                if workload == "prose" || workload == "list" || workload == "thinking" {
                    store.applyStreamingSnapshot(ChatStreamingSnapshot(targetId: 101, text: source, thinking: "", isFinal: true))
                }
                // Include the final Markdown parse and pending display/layout commits.
                try await Task.sleep(for: .milliseconds(250))
                controller.view.layoutIfNeeded()
                let cpu = cpuSeconds() - cpuStart
                let elapsed = start.duration(to: .now).components
                os_signpost(.end, log: log, name: "RenderingWorkload", signpostID: signpostID)
                let cells = collection.visibleCells.compactMap { $0 as? ChatTimelineCollectionCell }
                let measurements = cells.reduce(0) { $0 + $1.contentHeightMeasurementCount }
                let result: [String: Any] = ["workload": workload, "sample": sample, "cpu_seconds": cpu,
                    "wall_seconds": Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
                    "visible_cell_measurements": measurements, "content_height": collection.contentSize.height,
                    "response_height": collection.layoutAttributesForItem(at: IndexPath(item: 100, section: 0))?.frame.height ?? 0]
                let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                print("RENDER_BENCHMARK " + String(decoding: data, as: UTF8.self))
                XCTAssertFalse(collection.visibleCells.isEmpty)
                let attributes = collection.indexPathsForVisibleItems.sorted().compactMap { collection.layoutAttributesForItem(at: $0) }
                for (a, b) in zip(attributes, attributes.dropFirst()) { XCTAssertLessThanOrEqual(a.frame.maxY, b.frame.minY) }
                if workload == "prose" || workload == "list" || workload == "thinking" {
                    let row = try XCTUnwrap(store.row(id: "m-101"))
                    if case let .message(message) = row.item {
                        XCTAssertEqual(row.streamingSnapshot?.text ?? message.displayText, source)
                    } else {
                        XCTFail("Expected the response row")
                    }
                }
                window.isHidden = true
                window.rootViewController = nil
            }
        }
    }

    private func message(id: Int64, text: String) -> FullChatMessage {
        FullChatMessage(id: id, message: ChatMessage(id: id, conversationId: 1, role: "model", text: text, createdAtMs: id), thinkingStream: nil, variants: [])
    }

    private func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }
}
