import XCTest
import SwiftUI
import UIKit
@testable import YamabikoChat

@MainActor
final class ConversationDrawerTests: XCTestCase {
    func testDirectionGateAcceptsOnlyIntentionalHorizontalMovement() {
        XCTAssertTrue(canBegin(x: 20, y: 3))
        XCTAssertFalse(canBegin(x: 3, y: 20))
        XCTAssertFalse(canBegin(x: 20, y: 18))
        XCTAssertFalse(canBegin(x: 4, y: 0))
        XCTAssertFalse(canBegin(x: -20, y: 0))
        XCTAssertTrue(canBegin(x: -20, y: 3, isOpen: true))
        XCTAssertFalse(canBegin(x: 20, y: 0, isOpen: true))
        XCTAssertFalse(ConversationDrawerGesturePolicy.canBegin(
            translation: CGPoint(x: 20, y: 0), velocity: CGPoint(x: 20, y: 200), isOpen: false
        ))
    }

    func testDistanceAndFlickThresholdsInBothDirections() {
        XCTAssertFalse(shouldOpen(offset: 100, translation: 100, velocity: 0))
        XCTAssertTrue(shouldOpen(offset: 170, translation: 170, velocity: 0))
        XCTAssertTrue(shouldOpen(offset: 30, translation: 30, velocity: 700))
        XCTAssertFalse(shouldOpen(offset: 10, translation: 10, velocity: 900))
        XCTAssertTrue(shouldOpen(offset: 290, translation: -30, velocity: 0))
        XCTAssertFalse(shouldOpen(offset: 290, translation: -30, velocity: -700))
        XCTAssertFalse(shouldOpen(offset: 120, translation: -200, velocity: 0))
    }

    func testSidebarLeavesConversationVisibleOnNarrowAndWidePhones() {
        for width: CGFloat in [320, 390, 440, 600] {
            let sidebarWidth = ConversationDrawerGesturePolicy.sidebarWidth(containerWidth: width)
            XCTAssertEqual(sidebarWidth, width * 0.7, accuracy: 0.1)
            XCTAssertEqual(width - sidebarWidth, width * 0.3, accuracy: 0.1)
        }
    }

    func testComposerSelectionControlsAndNestedHorizontalScrollKeepTheirGestures() {
        let dismissalView = UIButton()
        let composer = UITextView()
        composer.isEditable = true
        XCTAssertTrue(isInteractive(composer, dismissalView: dismissalView))

        let message = UITextView()
        message.isEditable = false
        message.text = "Selectable message"
        message.selectedRange = NSRange(location: 0, length: 4)
        XCTAssertTrue(isInteractive(message, dismissalView: dismissalView))
        message.selectedRange = NSRange(location: 0, length: 0)
        XCTAssertFalse(isInteractive(message, dismissalView: dismissalView))

        XCTAssertTrue(isInteractive(UISlider(), dismissalView: dismissalView))
        XCTAssertTrue(isInteractive(UICollectionViewListCell(), dismissalView: dismissalView))
        XCTAssertFalse(isInteractive(dismissalView, dismissalView: dismissalView))

        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 500))
        let descendant = UIView()
        scrollView.addSubview(descendant)
        scrollView.contentSize = CGSize(width: 600, height: 500)
        XCTAssertTrue(isInteractive(descendant, dismissalView: dismissalView))
        scrollView.contentSize = CGSize(width: 300, height: 1000)
        XCTAssertFalse(isInteractive(descendant, dismissalView: dismissalView))
    }

    func testOpeningDoesNotUnmountConversationAndEscapeClosesDrawer() {
        let controller = ConversationDrawerController(sidebar: Text("List"), detail: Text("Chat"))
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.configure(isOpen: false, hasConversation: true, reduceMotion: true)
        controller.view.layoutIfNeeded()
        let detail = controller.detailHost
        var committedOpen: Bool?
        controller.onOpenChanged = { committedOpen = $0 }

        controller.configure(isOpen: true, hasConversation: true, reduceMotion: true)
        XCTAssertTrue(controller.detailHost === detail)
        XCTAssertNotNil(detail.parent)
        XCTAssertTrue(detail.view.accessibilityElementsHidden)
        XCTAssertFalse(controller.sidebarHost.view.accessibilityElementsHidden)
        XCTAssertTrue(controller.accessibilityPerformEscape())
        XCTAssertEqual(committedOpen, false)
        XCTAssertFalse(detail.view.accessibilityElementsHidden)
        XCTAssertFalse(controller.accessibilityPerformEscape())
    }

    func testDrawerCanCloseFromListRowsWithoutTakingOverEmbeddedControls() {
        let dismissalView = UIButton()
        for cell in [UITableViewCell(), UICollectionViewListCell()] as [UIView] {
            let content = UIView()
            cell.addSubview(content)
            XCTAssertTrue(isInteractive(content, dismissalView: dismissalView))
            XCTAssertFalse(ConversationDrawerGesturePolicy.isInteractiveContent(
                content, dismissalView: dismissalView, allowsListRowPan: true
            ))
            let control = UISlider()
            content.addSubview(control)
            XCTAssertTrue(ConversationDrawerGesturePolicy.isInteractiveContent(
                control, dismissalView: dismissalView, allowsListRowPan: true
            ))
        }
    }

    private func canBegin(x: CGFloat, y: CGFloat, isOpen: Bool = false) -> Bool {
        ConversationDrawerGesturePolicy.canBegin(
            translation: CGPoint(x: x, y: y), velocity: CGPoint(x: x * 10, y: y * 10), isOpen: isOpen
        )
    }

    private func shouldOpen(offset: CGFloat, translation: CGFloat, velocity: CGFloat) -> Bool {
        ConversationDrawerGesturePolicy.shouldOpen(offset: offset, width: 320, translation: translation, velocity: velocity)
    }

    private func isInteractive(_ view: UIView, dismissalView: UIView) -> Bool {
        ConversationDrawerGesturePolicy.isInteractiveContent(view, dismissalView: dismissalView)
    }
}
