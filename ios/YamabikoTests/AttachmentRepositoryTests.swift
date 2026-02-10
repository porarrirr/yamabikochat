import XCTest
@testable import YamabikoChat

final class AttachmentRepositoryTests: XCTestCase {
    func testRejectsDangerousExtension() throws {
        let repo = AttachmentRepository()
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("payload.exe")
        try "test".data(using: .utf8)?.write(to: file)

        let result = repo.validate(url: file)
        XCTAssertEqual(result, .dangerousFile)

        try? FileManager.default.removeItem(at: file)
    }

    func testRejectsOversizeFile() throws {
        let repo = AttachmentRepository()
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("large.txt")
        let payload = Data(count: AppConstants.maxAttachmentSizeBytes + 1)
        try payload.write(to: file)

        let result = repo.validate(url: file)
        switch result {
        case .tooLarge:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected tooLarge, got \(result)")
        }

        try? FileManager.default.removeItem(at: file)
    }
}