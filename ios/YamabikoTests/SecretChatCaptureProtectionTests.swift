import SwiftUI
import XCTest
@testable import YamabikoChat

@MainActor
final class SecretChatCaptureProtectionTests: XCTestCase {
    func testSecretContentStartsInsideSecureCanvasBeforePresentation() throws {
        let controller = SecretChatCaptureController(content: Text("secret"), isProtected: true)
        controller.loadViewIfNeeded()
        let canvas = try XCTUnwrap(controller.secureCanvas)
        XCTAssertTrue(controller.host.view.superview === canvas)
        let field = try XCTUnwrap(canvas.superview as? UITextField)
        XCTAssertTrue(field.isSecureTextEntry)
        XCTAssertFalse(field.canBecomeFirstResponder)
        XCTAssertTrue(canvas.isUserInteractionEnabled)
        XCTAssertTrue(controller.host.parent === controller)
    }

    func testChangingModesPreservesHostAndRestoresNormalCapture() throws {
        let controller = SecretChatCaptureController(content: Text("chat"), isProtected: false)
        controller.loadViewIfNeeded()
        let canvas = try XCTUnwrap(controller.secureCanvas)
        let hostedView = controller.host.view
        XCTAssertTrue(hostedView?.superview === controller.view)

        controller.setProtected(true)
        XCTAssertTrue(hostedView?.superview === canvas)
        XCTAssertFalse(try XCTUnwrap(canvas.superview).isHidden)

        controller.setProtected(false)
        XCTAssertTrue(controller.host.view === hostedView)
        XCTAssertTrue(hostedView?.superview === controller.view)
        XCTAssertTrue(try XCTUnwrap(canvas.superview).isHidden)
    }

    func testSecureContentFillsContainer() throws {
        let controller = SecretChatCaptureController(content: Color.red, isProtected: true)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        controller.view.layoutIfNeeded()
        let canvas = try XCTUnwrap(controller.secureCanvas)
        XCTAssertEqual(canvas.bounds.width, 390, accuracy: 1)
        XCTAssertEqual(canvas.bounds.height, 700, accuracy: 1)
        XCTAssertEqual(controller.host.view.frame, canvas.bounds)
    }

    func testMissingSecureCanvasNeverFallsBackToUnprotectedContent() {
        let controller = SecretChatCaptureController(
            content: Text("secret"), isProtected: true, findCanvas: { _ in nil }
        )
        controller.loadViewIfNeeded()
        XCTAssertNil(controller.host.view.superview)

        controller.setProtected(false)
        XCTAssertTrue(controller.host.view.superview === controller.view)
        controller.setProtected(true)
        XCTAssertNil(controller.host.view.superview)
    }
}
