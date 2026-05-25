import XCTest
@testable import YamabikoChat

final class SSEPayloadAssemblerTests: XCTestCase {
    func testMultilineSingleEventJoinedOnBlankLine() {
        var assembler = SSEPayloadAssembler()
        XCTAssertTrue(assembler.consume(line: #"data: {"a":1}"#).isEmpty)
        XCTAssertTrue(assembler.consume(line: #"data: "continued""#).isEmpty)
        let payloads = assembler.consume(line: "")
        XCTAssertEqual(payloads.count, 1)
        XCTAssertTrue(payloads[0].contains(#"{"a":1}"#))
        XCTAssertTrue(payloads[0].contains("continued"))
    }

    func testBackToBackDataLinesFlushWithoutBlankLine() {
        var assembler = SSEPayloadAssembler()
        XCTAssertTrue(assembler.consume(line: #"data: {"choices":[{"delta":{"content":"a"}}]}"#).isEmpty)
        let payloads = assembler.consume(line: #"data: {"choices":[{"delta":{"content":"b"}}]}"#)
        XCTAssertEqual(payloads.count, 1)
        XCTAssertTrue(payloads[0].contains(#"content":"a"#))
        XCTAssertTrue(assembler.consume(line: "").isEmpty)
        let remaining = assembler.flushRemaining()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(remaining[0].contains(#"content":"b"#))
    }

    func testRawJSONLineWithoutDataPrefix() {
        var assembler = SSEPayloadAssembler()
        let payloads = assembler.consume(line: #"{"choices":[{"delta":{"content":"x"}}]}"#)
        XCTAssertEqual(payloads.count, 1)
        XCTAssertTrue(payloads[0].contains("x"))
    }

    func testDonePayloadOnBlankLine() async throws {
        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield("data: [DONE]")
            continuation.yield("")
            continuation.finish()
        }
        var payloads: [String] = []
        for try await payload in SSEPayloadAssembly.payloads(from: stream) {
            payloads.append(payload)
        }
        XCTAssertEqual(payloads, ["[DONE]"])
    }
}
