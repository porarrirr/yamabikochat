import XCTest
import UIKit
import SwiftUI
@testable import YamabikoChat

@MainActor
final class ScrollablePlainTextViewTests: XCTestCase {
    func testLargeLogUsesScrollableViewportWithoutMeasuringEntireDocument() {
        let view = ScrollablePlainTextView.makeTextView(textStyle: .caption1, inset: 16, lineSpacing: 0)
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
        let text = String(repeating: "runtime 日本語 https://example.com/" + String(repeating: "x", count: 1000) + "\n", count: 2000)
        view.text = text
        view.layoutIfNeeded()

        XCTAssertEqual(view.text, text)
        XCTAssertEqual(view.bounds.height, 600)
        XCTAssertTrue(view.isScrollEnabled)
        XCTAssertTrue(view.isSelectable)
        XCTAssertFalse(view.isEditable)
        XCTAssertNil(view.textLayoutManager)
        XCTAssertTrue(view.layoutManager.allowsNonContiguousLayout)
        let paragraph = view.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(paragraph?.hyphenationFactor ?? 0, 0)
    }

    func testChatSelectionRetainsLongUnbrokenMessageAndDisablesHyphenation() {
        let view = ScrollablePlainTextView.makeTextView()
        let text = String(repeating: "longword", count: 10000) + " 日本語 👨‍👩‍👧‍👦 e\u{301}"
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 300)
        view.text = text
        view.layoutIfNeeded()

        XCTAssertEqual(view.text, text)
        XCTAssertEqual(view.font, .preferredFont(forTextStyle: .body))
        XCTAssertEqual(view.textContainerInset.left, 20)
        let paragraph = view.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertNotNil(paragraph)
        XCTAssertEqual(paragraph?.hyphenationFactor, 0)
        XCTAssertEqual(paragraph?.lineBreakStrategy, [])
        XCTAssertEqual(paragraph?.lineSpacing, 2)
    }

    func testSwiftUIReaderFillsViewportForMultiMegabyteDocument() throws {
        let text = String(repeating: "日本語 longword https://example.com/\n", count: 100000)
        let host = UIHostingController(rootView: ScrollablePlainTextView(text: text))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        func findReader(_ view: UIView) -> UITextView? {
            if let reader = view as? UITextView { return reader }
            return view.subviews.lazy.compactMap { findReader($0) }.first
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let reader = try XCTUnwrap(findReader(host.view))
        XCTAssertTrue(reader.text == text)
        XCTAssertGreaterThan(reader.bounds.width, 0)
        XCTAssertGreaterThan(reader.bounds.height, 0)
        XCTAssertLessThanOrEqual(reader.bounds.height, 600)
    }
}
