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

    func testPersistGeneratedFileSanitizesNameAndWritesBytes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("generated-files-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AttachmentRepository(generatedFilesRootOverride: root)
        let payload = Data("generated".utf8)
        let persisted = try repository.persistGeneratedFile(
            data: payload,
            filename: "plot:unsafe.png",
            collection: "Chat 42"
        )
        let duplicate = try repository.persistGeneratedFile(
            data: payload,
            filename: "plot:unsafe.png",
            collection: "Chat 42"
        )

        XCTAssertEqual(try Data(contentsOf: persisted), payload)
        XCTAssertEqual(persisted.lastPathComponent, "plot_unsafe.png")
        XCTAssertEqual(persisted.deletingLastPathComponent().lastPathComponent, "Chat 42")
        XCTAssertEqual(duplicate.lastPathComponent, "plot_unsafe (2).png")
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
        defer { try? FileManager.default.removeItem(at: file) }

        let result = repo.validate(url: file)
        XCTAssertEqual(result, .tooLarge(sizeBytes: payload.count))
    }

    func testRequiresVisionOnlyForImageTypes() throws {
        let repo = AttachmentRepository()

        XCTAssertTrue(repo.requiresVision(url: URL(fileURLWithPath: "/tmp/photo.PNG")))
        XCTAssertTrue(repo.requiresVision(url: URL(fileURLWithPath: "/tmp/diagram.webp")))
        XCTAssertFalse(repo.requiresVision(url: URL(fileURLWithPath: "/tmp/readme.txt")))
        XCTAssertFalse(repo.requiresVision(url: URL(fileURLWithPath: "/tmp/document.pdf")))
    }

    func testValidateRejectsNonFileURLsAsUnreadable() {
        let repo = AttachmentRepository()

        let result = repo.validate(url: URL(string: "https://example.com/file.txt")!)

        XCTAssertEqual(result, .unreadable)
    }
}
