import AVFoundation
import XCTest
@testable import YamabikoChat

final class CameraAccessStateTests: XCTestCase {
    func testNotDeterminedRequiresExplicitAuthorization() {
        XCTAssertEqual(CameraAccessState(authorizationStatus: .notDetermined), .needsAuthorization)
    }

    func testAuthorizedAllowsCameraPresentation() {
        XCTAssertEqual(CameraAccessState(authorizationStatus: .authorized), .authorized)
    }

    func testDeniedAndRestrictedBlockCameraPresentation() {
        XCTAssertEqual(CameraAccessState(authorizationStatus: .denied), .denied)
        XCTAssertEqual(CameraAccessState(authorizationStatus: .restricted), .denied)
    }
}
