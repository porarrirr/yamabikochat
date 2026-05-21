import XCTest
@testable import YamabikoChat

final class StreamDeltaAccumulatorTests: XCTestCase {
    func testIncrementalDeltaReturnsSuffixForCumulativeIncoming() {
        let buffer = "こん"
        let incoming = "こんにちは"
        XCTAssertEqual(
            StreamDeltaAccumulator.incrementalDelta(buffer: buffer, incoming: incoming),
            "にちは"
        )
    }

    func testIncrementalDeltaReturnsEmptyWhenIncomingEqualsBuffer() {
        let text = "こんにちは！"
        XCTAssertEqual(
            StreamDeltaAccumulator.incrementalDelta(buffer: text, incoming: text),
            ""
        )
    }

    func testIncrementalDeltaReturnsIncomingWhenNotPrefixExtension() {
        XCTAssertEqual(
            StreamDeltaAccumulator.incrementalDelta(buffer: "A", incoming: "B"),
            "B"
        )
    }
}
