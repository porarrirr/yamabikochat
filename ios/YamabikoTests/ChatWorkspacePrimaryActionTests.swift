import XCTest
@testable import YamabikoChat

final class ChatWorkspacePrimaryActionTests: XCTestCase {
    func testEmptyRegularConversationEnablesSecretMode() {
        XCTAssertEqual(
            ChatWorkspacePrimaryAction.resolve(
                hasConversationContent: false,
                isSecretConversation: false
            ),
            .enableSecretMode
        )
    }

    func testEmptySecretConversationDisablesSecretMode() {
        XCTAssertEqual(
            ChatWorkspacePrimaryAction.resolve(
                hasConversationContent: false,
                isSecretConversation: true
            ),
            .disableSecretMode
        )
    }

    func testRegularConversationWithContentCreatesConversation() {
        XCTAssertEqual(
            ChatWorkspacePrimaryAction.resolve(
                hasConversationContent: true,
                isSecretConversation: false
            ),
            .createConversation
        )
    }

    func testSecretConversationWithContentCreatesConversation() {
        XCTAssertEqual(
            ChatWorkspacePrimaryAction.resolve(
                hasConversationContent: true,
                isSecretConversation: true
            ),
            .createConversation
        )
    }
}
