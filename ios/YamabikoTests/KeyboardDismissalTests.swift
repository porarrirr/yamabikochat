import XCTest
import UIKit
@testable import YamabikoChat

@MainActor
final class KeyboardDismissalTests: XCTestCase {
    func testComposerKeepsKeyboardOnOutsideTapAndScroll() {
        let composer = ChatComposerTextView.ComposerTextView()
        let scroll = UIScrollView()
        XCTAssertFalse(KeyboardDismissalView.shouldDismiss(responder: composer, touchedView: scroll, scrolling: false))
        XCTAssertFalse(KeyboardDismissalView.shouldDismiss(responder: composer, touchedView: scroll, scrolling: true))
    }

    func testOtherEditorDismissesOnOutsideTapAndScroll() {
        let editor = UITextField()
        let scroll = UIScrollView()
        let content = UIView()
        scroll.addSubview(content)
        XCTAssertTrue(KeyboardDismissalView.shouldDismiss(responder: editor, touchedView: content, scrolling: false))
        XCTAssertTrue(KeyboardDismissalView.shouldDismiss(responder: editor, touchedView: content, scrolling: true))
        XCTAssertFalse(KeyboardDismissalView.shouldDismiss(responder: editor, touchedView: UIView(), scrolling: true))
    }

    func testEditingAndSwitchingFieldsAreNotInterrupted() {
        let editor = UITextView()
        let selection = UIView()
        editor.addSubview(selection)
        XCTAssertFalse(KeyboardDismissalView.shouldDismiss(responder: editor, touchedView: selection, scrolling: false))
        XCTAssertFalse(KeyboardDismissalView.shouldDismiss(responder: editor, touchedView: selection, scrolling: true))
        XCTAssertFalse(KeyboardDismissalView.shouldDismiss(responder: editor, touchedView: UITextField(), scrolling: false))
    }
}
