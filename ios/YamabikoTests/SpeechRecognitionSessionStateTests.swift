import XCTest
@testable import YamabikoChat

final class SpeechRecognitionSessionStateTests: XCTestCase {
    func testEndInvalidatesCallbacksFromStoppedSession() {
        var state = SpeechRecognitionSessionState()
        let stoppedSessionID = state.begin()

        state.end()

        XCTAssertFalse(state.isActive(stoppedSessionID))
    }

    func testBeginningNewSessionInvalidatesCallbacksFromPreviousSession() {
        var state = SpeechRecognitionSessionState()
        let previousSessionID = state.begin()

        let currentSessionID = state.begin()

        XCTAssertFalse(state.isActive(previousSessionID))
        XCTAssertTrue(state.isActive(currentSessionID))
    }
}
