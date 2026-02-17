import XCTest
@testable import YamabikoChat

final class ChatViewModelSystemPromptLabelTests: XCTestCase {
    func testSystemPromptContextLabel_usesPresetNameWhenActivePresetExists() {
        let label = ChatViewModel.systemPromptContextLabel(
            activePresetName: "  Persona A  ",
            conversationSystemPrompt: "ignored prompt"
        )

        XCTAssertEqual(label, L10n.format("Prompt: %@", "Persona A"))
    }

    func testSystemPromptContextLabel_usesCustomWhenPromptExistsWithoutPreset() {
        let label = ChatViewModel.systemPromptContextLabel(
            activePresetName: nil,
            conversationSystemPrompt: "  custom prompt  "
        )

        XCTAssertEqual(label, L10n.text("Prompt: Custom"))
    }

    func testSystemPromptContextLabel_treatsBlankPresetAsCustomWhenPromptExists() {
        let label = ChatViewModel.systemPromptContextLabel(
            activePresetName: "   ",
            conversationSystemPrompt: "custom prompt"
        )

        XCTAssertEqual(label, L10n.text("Prompt: Custom"))
    }

    func testSystemPromptContextLabel_usesNoneWhenPromptIsEmptyAndNoPreset() {
        let label = ChatViewModel.systemPromptContextLabel(
            activePresetName: nil,
            conversationSystemPrompt: "   "
        )

        XCTAssertEqual(label, L10n.text("Prompt: なし"))
    }
}
