import SwiftUI
import UIKit
import WebKit

enum ConversationDrawerGesturePolicy {
    static func sidebarWidth(containerWidth: CGFloat) -> CGFloat {
        containerWidth * 0.7
    }

    static func canBegin(translation: CGPoint, velocity: CGPoint, isOpen: Bool) -> Bool {
        // Reject vertical/diagonal intent before claiming touches from the timeline.
        guard abs(translation.x) >= 6,
              abs(translation.x) > abs(translation.y) * 1.5,
              abs(velocity.x) > abs(velocity.y) * 1.5 else { return false }
        return isOpen ? translation.x < 0 : translation.x > 0
    }

    static func shouldOpen(offset: CGFloat, width: CGFloat, translation: CGFloat, velocity: CGFloat) -> Bool {
        guard width > 0 else { return false }
        // A deliberate short flick works; tiny movements still snap back.
        if abs(translation) >= 24, abs(velocity) >= 600 {
            return velocity > 0
        }
        return offset >= width * 0.5
    }

    @MainActor
    static func isInteractiveContent(
        _ touchedView: UIView, dismissalView: UIView, allowsListRowPan: Bool = false
    ) -> Bool {
        var ancestor: UIView? = touchedView
        while let view = ancestor {
            if view === dismissalView { return false }
            if view is UIControl || view is WKWebView { return true }
            if let textView = view as? UITextView,
               textView.isEditable || textView.selectedRange.length > 0 {
                return true
            }
            if let scrollView = view as? UIScrollView,
               scrollView.alwaysBounceHorizontal ||
                scrollView.contentSize.width + scrollView.adjustedContentInset.left +
                    scrollView.adjustedContentInset.right > scrollView.bounds.width + 1 {
                return true
            }
            // The compact drawer owns row swipes while open; other lists keep their actions.
            if view is UITableViewCell || view is UICollectionViewListCell {
                return !allowsListRowPan
            }
            ancestor = view.superview
        }
        return false
    }
}

/// Keeps both screens mounted while moving the conversation, including during generation.
struct ConversationDrawer<Sidebar: View, Detail: View>: UIViewControllerRepresentable {
    @Binding var isOpen: Bool
    let hasConversation: Bool
    let reduceMotion: Bool
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail

    func makeUIViewController(context: Context) -> ConversationDrawerController<Sidebar, Detail> {
        ConversationDrawerController(sidebar: sidebar(), detail: detail())
    }

    func updateUIViewController(_ controller: ConversationDrawerController<Sidebar, Detail>, context: Context) {
        controller.sidebarHost.rootView = sidebar()
        controller.detailHost.rootView = detail()
        controller.onOpenChanged = { isOpen = $0 }
        controller.configure(isOpen: isOpen, hasConversation: hasConversation, reduceMotion: reduceMotion)
    }
}

final class ConversationDrawerController<Sidebar: View, Detail: View>: UIViewController, UIGestureRecognizerDelegate {
    let sidebarHost: UIHostingController<Sidebar>
    let detailHost: UIHostingController<Detail>
    var onOpenChanged: ((Bool) -> Void)?

    private let detailCard = UIView()
    private let detailCardBorder = UIView()
    private let dismissalButton = UIButton(type: .custom)
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private var isOpen = false
    private var hasConversation = false
    private var reduceMotion = false
    private var isConfigured = false
    private var isDragging = false
    private var dragStartOffset: CGFloat = 0
    private var touchStartLocation = CGPoint.zero
    private var offset: CGFloat = 0
    private var previousSize = CGSize.zero
    private var settlingAnimator: UIViewPropertyAnimator?

    init(sidebar: Sidebar, detail: Detail) {
        sidebarHost = UIHostingController(rootView: sidebar)
        detailHost = UIHostingController(rootView: detail)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .amoledSystemBackground
        view.clipsToBounds = true
        addChild(sidebarHost)
        view.addSubview(sidebarHost.view)
        sidebarHost.didMove(toParent: self)

        view.addSubview(detailCard)
        detailCard.backgroundColor = .amoledSystemBackground
        detailCard.layer.cornerCurve = .continuous
        detailCard.clipsToBounds = true
        addChild(detailHost)
        detailCard.addSubview(detailHost.view)
        detailHost.didMove(toParent: self)

        dismissalButton.backgroundColor = .amoledDrawerCardVeil
        dismissalButton.accessibilityLabel = L10n.text("閉じる")
        dismissalButton.accessibilityIdentifier = "conversation-drawer-dismiss"
        dismissalButton.addTarget(self, action: #selector(closeDrawer), for: .touchUpInside)
        detailCard.addSubview(dismissalButton)

        // Outline the lifted card so its edge stays visible even when the
        // conversation behind the drawer is empty.
        detailCardBorder.isUserInteractionEnabled = false
        detailCardBorder.alpha = 0
        detailCardBorder.layer.cornerCurve = .continuous
        detailCard.addSubview(detailCardBorder)
        updateDetailCardBorderColor()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (controller: ConversationDrawerController<Sidebar, Detail>, _: UITraitCollection) in
            controller.updateDetailCardBorderColor()
        }

        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
    }

    private var sidebarWidth: CGFloat {
        ConversationDrawerGesturePolicy.sidebarWidth(containerWidth: view.bounds.width)
    }

    func configure(isOpen: Bool, hasConversation: Bool, reduceMotion: Bool) {
        loadViewIfNeeded()
        let changed = self.isOpen != isOpen || self.hasConversation != hasConversation
        // The first conversation must lay out normally before its card can animate.
        let animate = isConfigured && changed && self.hasConversation && hasConversation && !reduceMotion
        self.isOpen = isOpen
        self.hasConversation = hasConversation
        self.reduceMotion = reduceMotion
        pan.isEnabled = hasConversation
        if changed || !isConfigured {
            isDragging = false
            if isOpen { view.endEditing(true) }
            view.setNeedsLayout()
            view.layoutIfNeeded()
            settle(animated: animate)
        }
        isConfigured = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if previousSize != view.bounds.size {
            // Rotation/resizing cancels an unfinished drag and uses the committed state.
            stopSettling()
            isDragging = false
            pan.isEnabled = false
            pan.isEnabled = hasConversation
            previousSize = view.bounds.size
            offset = isOpen ? sidebarWidth : 0
            updatePresentation()
        }
        layoutScreens()
        updateInteraction()
    }

    private func layoutScreens() {
        let sidebarFrame = CGRect(
            x: 0, y: 0,
            width: hasConversation ? sidebarWidth : view.bounds.width,
            height: view.bounds.height
        )
        if sidebarHost.view.frame != sidebarFrame {
            sidebarHost.view.frame = sidebarFrame
        }
        // Keep hosted content geometry fixed. Dragging must not relayout the
        // SwiftUI tree (and remeasure long messages) on every touch update.
        if detailCard.bounds.size != view.bounds.size {
            detailCard.bounds = CGRect(origin: .zero, size: view.bounds.size)
            detailCard.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            detailHost.view.frame = detailCard.bounds
            dismissalButton.frame = detailCard.bounds
            detailCardBorder.frame = detailCard.bounds
        }
        let borderWidth = 1 / max(traitCollection.displayScale, 1)
        if detailCardBorder.layer.borderWidth != borderWidth {
            detailCardBorder.layer.borderWidth = borderWidth
        }
        updateDetailCardBorderColor()
    }

    private func updatePresentation() {
        detailCard.transform = CGAffineTransform(translationX: offset, y: 0)
        let progress = sidebarWidth > 0 ? offset / sidebarWidth : 0
        detailCard.layer.cornerRadius = 24 * progress
        detailCardBorder.layer.cornerRadius = detailCard.layer.cornerRadius
        detailCardBorder.alpha = progress
        dismissalButton.alpha = progress
    }

    private func updateDetailCardBorderColor() {
        detailCardBorder.layer.borderColor = UIColor.amoledDrawerCardBorder
            .resolvedColor(with: traitCollection).cgColor
    }

    private func updateInteraction() {
        dismissalButton.isHidden = !hasConversation ||
            (!isOpen && !isDragging && settlingAnimator == nil && offset <= 0)
        detailCard.isHidden = !hasConversation
        sidebarHost.view.accessibilityElementsHidden = hasConversation && !isOpen
        detailHost.view.accessibilityElementsHidden = isOpen
        detailHost.view.isUserInteractionEnabled = !isOpen && !isDragging && settlingAnimator == nil
    }

    private func settle(animated: Bool) {
        stopSettling()
        let updates = {
            self.offset = self.isOpen ? self.sidebarWidth : 0
            self.updatePresentation()
        }
        if animated {
            let animator = UIViewPropertyAnimator(duration: 0.25, curve: .easeOut, animations: updates)
            settlingAnimator = animator
            updateInteraction()
            animator.addCompletion { [weak self, weak animator] _ in
                guard let self, let animator, self.settlingAnimator === animator else { return }
                self.settlingAnimator = nil
                self.updateInteraction()
            }
            animator.startAnimation()
        } else {
            UIView.performWithoutAnimation(updates)
            updateInteraction()
        }
    }

    private func stopSettling() {
        guard let animator = settlingAnimator else { return }
        // Capture the visible position before stopping all animated properties,
        // including the scrim and corners, so a new drag cannot jump ahead.
        offset = detailCard.layer.presentation()?.affineTransform().tx ?? detailCard.transform.tx
        settlingAnimator = nil
        animator.stopAnimation(true)
        UIView.performWithoutAnimation { updatePresentation() }
    }

    @objc private func closeDrawer() {
        commit(isOpen: false)
    }

    override func accessibilityPerformEscape() -> Bool {
        guard isOpen, hasConversation else { return false }
        closeDrawer()
        return true
    }

    private func commit(isOpen: Bool) {
        self.isOpen = isOpen
        isDragging = false
        if isOpen { view.endEditing(true) }
        settle(animated: !reduceMotion)
        onOpenChanged?(isOpen)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard hasConversation, let touchedView = touch.view else { return false }
        touchStartLocation = touch.location(in: view)
        return !ConversationDrawerGesturePolicy.isInteractiveContent(
            touchedView, dismissalView: dismissalButton,
            allowsListRowPan: isOpen && touchedView.isDescendant(of: sidebarHost.view)
        )
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // UIPan subtracts its recognition slop from translation. Use the original
        // touch position so the intent threshold also works on newer iOS versions.
        let location = pan.location(in: view)
        return ConversationDrawerGesturePolicy.canBegin(
            translation: CGPoint(x: location.x - touchStartLocation.x, y: location.y - touchStartLocation.y),
            velocity: pan.velocity(in: view),
            isOpen: isOpen
        )
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // A vertical scroll view can recognize first; the direction gate still owns the decision.
        guard let scrollView = otherGestureRecognizer.view as? UIScrollView,
              otherGestureRecognizer === scrollView.panGestureRecognizer else { return false }
        return scrollView.contentSize.width <= scrollView.bounds.width + 1 && !scrollView.alwaysBounceHorizontal
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view).x
        switch recognizer.state {
        case .began:
            stopSettling()
            dragStartOffset = offset
            isDragging = true
            view.endEditing(true)
            updateInteraction()
            fallthrough
        case .changed:
            offset = min(sidebarWidth, max(0, dragStartOffset + translation))
            updatePresentation()
        case .ended:
            commit(isOpen: ConversationDrawerGesturePolicy.shouldOpen(
                offset: offset, width: sidebarWidth,
                translation: translation, velocity: recognizer.velocity(in: view).x
            ))
        case .cancelled, .failed:
            guard isDragging else { return }
            isDragging = false
            settle(animated: !reduceMotion)
        default:
            break
        }
    }
}
