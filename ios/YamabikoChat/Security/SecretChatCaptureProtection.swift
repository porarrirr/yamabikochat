import SwiftUI
import UIKit

extension View {
    func secretChatCaptureProtected(_ enabled: Bool) -> some View {
        SecretChatCaptureHost(content: self, isProtected: enabled)
    }
}

private struct SecretChatCaptureHost<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let isProtected: Bool

    func makeUIViewController(context: Context) -> SecretChatCaptureController<Content> {
        SecretChatCaptureController(content: content, isProtected: isProtected)
    }

    func updateUIViewController(_ controller: SecretChatCaptureController<Content>, context: Context) {
        // Move into the secure hierarchy before supplying any newly secret content.
        controller.setProtected(isProtected)
        controller.host.rootView = content
    }
}

/// Uses the secure text canvas's compositor protection, rather than reacting after capture.
/// UIKit's canvas hierarchy is undocumented. If it changes, secret content stays hidden.
/// Keep the text field and its canvas intact; never reparent CALayers.
final class SecretChatCaptureController<Content: View>: UIViewController {
    let host: UIHostingController<Content>
    private let secureField = NonEditingSecureTextField()
    private let placeholder = UILabel()
    private let findCanvas: (UITextField) -> UIView?
    private(set) var secureCanvas: UIView?
    private var isProtected: Bool
    private var contentConstraints: [NSLayoutConstraint] = []

    init(
        content: Content,
        isProtected: Bool,
        findCanvas: @escaping (UITextField) -> UIView? = { field in
            field.subviews.first { String(describing: type(of: $0)) == "_UITextLayoutCanvasView" }
        }
    ) {
        host = UIHostingController(rootView: content)
        self.isProtected = isProtected
        self.findCanvas = findCanvas
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        placeholder.text = L10n.text("シークレットチャットを保護中")
        placeholder.textAlignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        secureField.isSecureTextEntry = true
        secureField.isAccessibilityElement = false
        secureField.backgroundColor = .clear
        secureField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(secureField)
        NSLayoutConstraint.activate([
            secureField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            secureField.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            secureField.topAnchor.constraint(equalTo: view.topAnchor),
            secureField.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        secureField.layoutIfNeeded()
        secureCanvas = findCanvas(secureField)
        secureCanvas?.isUserInteractionEnabled = true

        addChild(host)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        placeContent()
        host.didMove(toParent: self)
        if secureCanvas == nil {
            DiagnosticsLogger.log("Secure capture canvas unavailable; secret chat display blocked", category: .app)
        }
    }

    func setProtected(_ enabled: Bool) {
        guard enabled != isProtected else { return }
        isProtected = enabled
        if isViewLoaded { placeContent() }
    }

    private func placeContent() {
        NSLayoutConstraint.deactivate(contentConstraints)
        host.view.removeFromSuperview()
        secureField.isHidden = !isProtected
        placeholder.isHidden = !isProtected || secureCanvas != nil
        // No fallback to an ordinary view for secret content.
        guard let target = isProtected ? secureCanvas : view else { return }
        target.addSubview(host.view)
        contentConstraints = [
            host.view.leadingAnchor.constraint(equalTo: target.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: target.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: target.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: target.bottomAnchor)
        ]
        NSLayoutConstraint.activate(contentConstraints)
    }
}

private final class NonEditingSecureTextField: UITextField {
    override var canBecomeFirstResponder: Bool { false }
    override func textRect(forBounds bounds: CGRect) -> CGRect { bounds }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { bounds }
}
