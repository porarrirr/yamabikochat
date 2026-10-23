import XCTest
@testable import YamabikoChat

final class AttachmentRepositoryTests: XCTestCase {
    func testGeneratedFilesArePrivateAndLegacyReferencesRemainProtectedAndDeletable() throws {
        let manager = FileManager.default
        let collection = "SecurityTest-\(UUID())"
        let repository = AttachmentRepository()
        let legacy = try manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Generated Files/\(collection)", isDirectory: true)
        defer { try? manager.removeItem(at: legacy) }
        try manager.createDirectory(at: legacy, withIntermediateDirectories: true)
        let old = legacy.appendingPathComponent("old.txt")
        try Data("keep legacy content".utf8).write(to: old)
        let new = try repository.persistGeneratedFile(data: Data("new content".utf8), filename: "new.txt", collection: collection)
        defer { try? manager.removeItem(at: new.deletingLastPathComponent()) }
        try repository.prepareProtectedStorage()
        XCTAssertTrue(new.path.contains("Library/Application Support/YamabikoChat/GeneratedFiles/"))
        XCTAssertFalse(new.path.contains("Documents/"))
        XCTAssertEqual(try String(contentsOf: old), "keep legacy content")
        for url in [old, new, legacy] {
            XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        }
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool, false)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool, false)
        try repository.deleteOwnedFiles(paths: [old.path, new.path])
        XCTAssertFalse(manager.fileExists(atPath: old.path))
        XCTAssertFalse(manager.fileExists(atPath: new.path))
    }

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
