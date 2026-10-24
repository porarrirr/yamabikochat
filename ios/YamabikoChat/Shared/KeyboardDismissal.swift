import SwiftUI
import UIKit

/// Editors that intentionally keep focus while the surrounding UI is used.
protocol KeepsKeyboardVisible: AnyObject {}

struct KeyboardDismissalHost: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissalView {
        KeyboardDismissalView()
    }

    func updateUIView(_ uiView: KeyboardDismissalView, context: Context) {}
}

final class KeyboardDismissalView: UIView, UIGestureRecognizerDelegate {
    private weak var observedWindow: UIWindow?
    private lazy var outsideTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
    private lazy var outsideScroll = UIPanGestureRecognizer(target: self, action: #selector(dismissKeyboard))

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard observedWindow !== window else { return }
        for gesture in [outsideTap, outsideScroll] {
            observedWindow?.removeGestureRecognizer(gesture)
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            gesture.delegate = self
            window?.addGestureRecognizer(gesture)
        }
        observedWindow = window
    }

    static func shouldDismiss(responder: UIView, touchedView: UIView, scrolling: Bool) -> Bool {
        guard !(responder is KeepsKeyboardVisible),
              !touchedView.isDescendant(of: responder) else { return false }
        var view: UIView? = touchedView
        var touchesScrollView = false
        while let current = view {
            // Switching editors and manipulating text selection must retain normal UIKit behavior.
            if !scrolling, current is UITextInput { return false }
            if current is UIScrollView { touchesScrollView = true }
            view = current.superview
        }
        return !scrolling || touchesScrollView
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let responder = window?.keyboardFirstResponder, let touchedView = touch.view else { return false }
        return Self.shouldDismiss(
            responder: responder,
            touchedView: touchedView,
            scrolling: gestureRecognizer === outsideScroll
        )
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func dismissKeyboard(_ gesture: UIGestureRecognizer) {
        guard gesture.state == .ended || (gesture === outsideScroll && gesture.state == .began),
              let responder = window?.keyboardFirstResponder,
              !(responder is KeepsKeyboardVisible) else { return }
        responder.resignFirstResponder()
    }
}

private extension UIView {
    var keyboardFirstResponder: UIView? {
        if isFirstResponder { return self }
        for child in subviews {
            if let responder = child.keyboardFirstResponder { return responder }
        }
        return nil
    }
}
