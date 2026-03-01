import XCTest
@testable import YamabikoChat

final class AttachmentRepositoryTests: XCTestCase {
    func testPersistAttachmentCopiesFileIntoAppSupport() throws {
        let repo = AttachmentRepository()
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("sample.txt")
        let text = "hello attachment"
        try text.data(using: .utf8)?.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let persisted = try repo.persistAttachment(url: file)
        defer { try? FileManager.default.removeItem(at: persisted) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: persisted.path))
        XCTAssertTrue(persisted.lastPathComponent.hasSuffix("_sample.txt"))
        let persistedText = try String(contentsOf: persisted, encoding: .utf8)
        XCTAssertEqual(persistedText, text)
    }

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
