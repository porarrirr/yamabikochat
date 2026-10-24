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

    func testDrawerCardLiftsOffTrueBlackInDarkModeAndDimsInLightMode() {
        var darkWhite: CGFloat = 0
        var darkAlpha: CGFloat = 0
        XCTAssertTrue(
            UIColor.amoledDrawerCardVeil
                .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
                .getWhite(&darkWhite, alpha: &darkAlpha)
        )
        // A black scrim over an AMOLED canvas is invisible, so dark mode must
        // lighten the conversation card to show the drawer boundary.
        XCTAssertGreaterThan(darkWhite, 0.5)
        XCTAssertGreaterThan(darkAlpha, 0.05)

        var lightWhite: CGFloat = 0
        var lightAlpha: CGFloat = 0
        XCTAssertTrue(
            UIColor.amoledDrawerCardVeil
                .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
                .getWhite(&lightWhite, alpha: &lightAlpha)
        )
        XCTAssertLessThan(lightWhite, 0.5)
        XCTAssertEqual(lightAlpha, 0.14, accuracy: 0.01)
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

    func testDragKeepsContentSizeAndSafeAreaStableAndCancellationRestoresChat() async throws {
        let (controller, window) = try makeVisibleDrawer()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))
        let detail = controller.detailHost.view!
        let card = try XCTUnwrap(detail.superview)
        let initialBounds = detail.bounds
        let initialSafeArea = detail.safeAreaInsets
        let pan = DrawerTestPanGestureRecognizer()

        sendPan(pan, to: controller, state: .began, translation: 0)
        for distance in stride(from: CGFloat(10), through: 240, by: 10) {
            sendPan(pan, to: controller, state: .changed, translation: distance)
            controller.view.layoutIfNeeded()
            detail.layoutIfNeeded()
            XCTAssertEqual(card.frame.minX, distance, accuracy: 0.1)
            XCTAssertEqual(detail.bounds, initialBounds)
            XCTAssertEqual(detail.safeAreaInsets, initialSafeArea)
        }

        sendPan(pan, to: controller, state: .cancelled, translation: 240)
        XCTAssertEqual(card.frame.minX, 0, accuracy: 0.1)
        XCTAssertTrue(detail.isUserInteractionEnabled)
        XCTAssertFalse(detail.accessibilityElementsHidden)
    }

    func testClosingKeepsBackdropVisibleUntilAnimationFinishes() async throws {
        let (controller, window) = try makeVisibleDrawer()
        defer { window.isHidden = true }
        controller.configure(isOpen: true, hasConversation: true, reduceMotion: true)
        try await Task.sleep(for: .milliseconds(100))
        let card = try XCTUnwrap(controller.detailHost.view.superview)
        let backdrop = try XCTUnwrap(card.subviews.compactMap { $0 as? UIButton }.first)

        controller.configure(isOpen: false, hasConversation: true, reduceMotion: false)
        XCTAssertFalse(backdrop.isHidden, "The scrim must fade with the card instead of disappearing at release")
        XCTAssertFalse(controller.detailHost.view.isUserInteractionEnabled)

        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(backdrop.isHidden)
        XCTAssertTrue(controller.detailHost.view.isUserInteractionEnabled)
        XCTAssertEqual(card.frame.minX, 0, accuracy: 0.1)
    }

    func testGrabbingAnimationKeepsPositionCornersAndBackdropTogether() async throws {
        let (controller, window) = try makeVisibleDrawer()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))
        let card = try XCTUnwrap(controller.detailHost.view.superview)
        let backdrop = try XCTUnwrap(card.subviews.compactMap { $0 as? UIButton }.first)
        let width = ConversationDrawerGesturePolicy.sidebarWidth(containerWidth: controller.view.bounds.width)

        controller.configure(isOpen: true, hasConversation: true, reduceMotion: false)
        try await Task.sleep(for: .milliseconds(60))
        let visibleOffset = try XCTUnwrap(card.layer.presentation()).frame.minX
        XCTAssertGreaterThan(visibleOffset, 0)
        XCTAssertLessThan(visibleOffset, width)

        let pan = DrawerTestPanGestureRecognizer()
        sendPan(pan, to: controller, state: .began, translation: 0)
        XCTAssertEqual(card.frame.minX, visibleOffset, accuracy: 1)
        sendPan(pan, to: controller, state: .changed, translation: -20)
        let draggedOffset = max(0, visibleOffset - 20)
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(card.layer.presentation()?.frame.minX ?? card.frame.minX, draggedOffset, accuracy: 1)
        XCTAssertEqual(
            CGFloat(backdrop.layer.presentation()?.opacity ?? backdrop.layer.opacity),
            draggedOffset / width, accuracy: 0.02
        )
        XCTAssertEqual(card.layer.presentation()?.cornerRadius ?? card.layer.cornerRadius,
                       24 * draggedOffset / width, accuracy: 0.5)

        sendPan(pan, to: controller, state: .cancelled, translation: -20)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(card.frame.minX, width, accuracy: 0.1)
    }

    func testResizeDuringDragUsesCommittedStateAndNewWidth() throws {
        let (controller, window) = try makeVisibleDrawer()
        defer { window.isHidden = true }
        controller.configure(isOpen: true, hasConversation: true, reduceMotion: true)
        let card = try XCTUnwrap(controller.detailHost.view.superview)
        let pan = DrawerTestPanGestureRecognizer()
        sendPan(pan, to: controller, state: .began, translation: 0)
        sendPan(pan, to: controller, state: .changed, translation: -80)

        controller.view.frame.size = CGSize(width: 600, height: 390)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        XCTAssertEqual(card.frame.minX, 420, accuracy: 0.1)
        XCTAssertEqual(controller.detailHost.view.bounds.size, CGSize(width: 600, height: 390))
    }

    private func makeVisibleDrawer() throws -> (ConversationDrawerController<Text, Text>, UIWindow) {
        let controller = ConversationDrawerController(sidebar: Text("List"), detail: Text("Chat"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.configure(isOpen: false, hasConversation: true, reduceMotion: true)
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        return (controller, window)
    }

    private func sendPan(
        _ pan: DrawerTestPanGestureRecognizer,
        to controller: ConversationDrawerController<Text, Text>,
        state: UIGestureRecognizer.State,
        translation: CGFloat
    ) {
        pan.simulatedState = state
        pan.simulatedTranslation = CGPoint(x: translation, y: 0)
        controller.perform(NSSelectorFromString("handlePan:"), with: pan)
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

@MainActor
private final class DrawerTestPanGestureRecognizer: UIPanGestureRecognizer {
    var simulatedState: UIGestureRecognizer.State = .possible
    var simulatedTranslation = CGPoint.zero

    override var state: UIGestureRecognizer.State {
        get { simulatedState }
        set { simulatedState = newValue }
    }
    override func translation(in view: UIView?) -> CGPoint { simulatedTranslation }
    override func velocity(in view: UIView?) -> CGPoint { .zero }
}
