import SwiftUI
import UIKit

/// A viewport-sized reader for long plain text, without full-document SwiftUI layout.
struct ScrollablePlainTextView: UIViewRepresentable {
    let text: String
    var textStyle: UIFont.TextStyle = .body
    var inset: CGFloat = 20
    var lineSpacing: CGFloat = 2
    var accessibilityIdentifier = "plain-text-reader"

    func makeUIView(context: Context) -> UITextView {
        Self.makeTextView(textStyle: textStyle, inset: inset, lineSpacing: lineSpacing,
                          accessibilityIdentifier: accessibilityIdentifier)
    }

    static func makeTextView(textStyle: UIFont.TextStyle = .body, inset: CGFloat = 20,
                             lineSpacing: CGFloat = 2,
                             accessibilityIdentifier: String = "plain-text-reader") -> UITextView {
        // TextKit 1 supports noncontiguous layout. Only the visible portion needs
        // layout, even when runtime logs contain megabytes or very long lines.
        let view = UITextView(usingTextLayoutManager: false)
        view.layoutManager.allowsNonContiguousLayout = true
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: textStyle)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        let paragraph = NSMutableParagraphStyle()
        paragraph.hyphenationFactor = 0
        paragraph.lineBreakStrategy = []
        paragraph.lineSpacing = lineSpacing
        view.typingAttributes = [
            .paragraphStyle: paragraph,
            .font: UIFont.preferredFont(forTextStyle: textStyle),
            .foregroundColor: UIColor.label
        ]
        view.accessibilityIdentifier = accessibilityIdentifier
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        guard view.text != text else { return }
        view.text = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else { return nil }
        return CGSize(width: max(0, width), height: max(0, height))
    }
}
