import XCTest
@testable import YamabikoChat

final class AutoConversationTurnPolicyTests: XCTestCase {
    func testResumeUsesLastModelTurnAndStableIDOrder() {
        let messages = [
            message(id: 4, speaker: .user, turn: 9, content: "continue"),
            message(id: 3, speaker: .b, turn: 2, content: "B"),
            message(id: 2, speaker: .a, turn: 2, content: "A"),
            message(id: 1, speaker: .user, turn: 0, content: "start")
        ]
        let step = AutoConversationTurnPolicy.determineAutoConversationNextStep(messages: messages)
        XCTAssertEqual(step.turn, 3)
        XCTAssertEqual(step.speaker.modelCode, .a)
        let historyA = AutoConversationTurnPolicy.buildAutoConversationHistory(messages: messages, speaker: .a)
        let historyB = AutoConversationTurnPolicy.buildAutoConversationHistory(messages: messages, speaker: .b)
        XCTAssertEqual(historyA.map(\.content), ["start", "A", "B", "continue"])
        XCTAssertEqual(historyA.map(\.role), ["user", "assistant", "user", "user"])
        XCTAssertEqual(historyB.map(\.role), ["user", "user", "assistant", "user"])
    }

    func testInitialTurnAndBlankHistory() {
        let step = AutoConversationTurnPolicy.determineAutoConversationNextStep(messages: [])
        XCTAssertEqual(step.turn, 1)
        XCTAssertEqual(step.speaker.modelCode, .a)
        XCTAssertTrue(AutoConversationTurnPolicy.buildAutoConversationHistory(
            messages: [message(id: 1, speaker: .user, turn: 0, content: " \n ")], speaker: .a
        ).isEmpty)
    }

    func testSafetyBoundariesOnlyApplyToUnlimitedConversations() {
        XCTAssertFalse(AutoConversationTurnPolicy.reachedSafetyLimit(maxTurns: 0, nextTurn: 100, createdAtMs: 0, nowMs: 1_799_999))
        XCTAssertTrue(AutoConversationTurnPolicy.reachedSafetyLimit(maxTurns: 0, nextTurn: 101, createdAtMs: 0, nowMs: 1))
        XCTAssertTrue(AutoConversationTurnPolicy.reachedSafetyLimit(maxTurns: 0, nextTurn: 1, createdAtMs: 0, nowMs: 1_800_000))
        XCTAssertFalse(AutoConversationTurnPolicy.reachedSafetyLimit(maxTurns: 200, nextTurn: 101, createdAtMs: 0, nowMs: 1_800_000))
    }

    func testEndSignalNormalizationAndNaturalLanguage() {
        for (text, signal) in [(" [end] ", " \n"), ("DONE", "done"), ("会話を終了します", "custom"), ("This concludes our discussion", "custom")] {
            XCTAssertTrue(AutoConversationTurnPolicy.containsAutoConversationEndSignal(text: text, configuredEndSignal: signal), text)
        }
        XCTAssertFalse(AutoConversationTurnPolicy.containsAutoConversationEndSignal(text: "継続します", configuredEndSignal: "[END]"))
        XCTAssertFalse(AutoConversationTurnPolicy.containsAutoConversationEndSignal(text: " \n ", configuredEndSignal: ""))
    }

    func testJapaneseEndSignalsPreserveExistingPhrasings() {
        for text in ["会話を終了します", "議論を終了いたします", "対話をここで終わりにします", "討論を終わりにしましょう", "会話を終わります"] {
            XCTAssertTrue(AutoConversationTurnPolicy.containsAutoConversationEndSignal(text: text, configuredEndSignal: "[END]"), text)
        }
        for text in ["会話を終了しません", "会話を終了する方法を考えます", "議論を続けます"] {
            XCTAssertFalse(AutoConversationTurnPolicy.containsAutoConversationEndSignal(text: text, configuredEndSignal: "[END]"), text)
        }
    }

    private func message(id: Int64, speaker: AutoConversationSpeakerModel, turn: Int, content: String) -> AutoConversationMessage {
        AutoConversationMessage(id: id, autoConversationId: 1, speakerModel: speaker, content: content, turnNumber: turn)
    }
}
