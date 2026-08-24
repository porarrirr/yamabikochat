import CryptoKit
import XCTest
@testable import YamabikoChat

final class StrReplaceEditorToolTests: XCTestCase {
    private var root: URL!
    private var generated: URL!
    private var tool: StrReplaceEditorTool!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("editor-tests-\(UUID().uuidString)", isDirectory: true)
        generated = FileManager.default.temporaryDirectory.appendingPathComponent("editor-artifacts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        tool = StrReplaceEditorTool(
            workspaces: EditorWorkspaceStore(rootOverride: root),
            attachments: AttachmentRepository(generatedFilesRootOverride: generated)
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: generated)
    }

    func testCreateViewReplaceAndInsertReturnArtifacts() async throws {
        let created = try await call(#"{"command":"create","path":"/workspace/sample.txt","file_text":"one\ntwo\nthree"}"#)
        XCTAssertEqual(created.artifacts.map(\.name), ["sample.txt"])
        let artifactPath = try XCTUnwrap(created.artifacts.first?.path)

        let viewed = try await call(#"{"command":"view","path":"/workspace/sample.txt","view_range":[2,-1]}"#)
        XCTAssertTrue(viewed.content.contains("     2  two"))
        XCTAssertTrue(viewed.content.contains("     3  three"))

        let replaced = try await call(#"{"command":"str_replace","path":"/workspace/sample.txt","old_str":"two","new_str":"TWO"}"#)
        let inserted = try await call(#"{"command":"insert","path":"/workspace/sample.txt","insert_line":1,"new_str":"between"}"#)
        let final = try await call(#"{"command":"view","path":"/workspace/sample.txt"}"#)
        XCTAssertTrue(final.content.contains("     2  between"))
        XCTAssertTrue(final.content.contains("     3  TWO"))
        XCTAssertEqual(replaced.artifacts.first?.path, artifactPath)
        XCTAssertEqual(inserted.artifacts.first?.path, artifactPath)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: generated.appendingPathComponent("Editor session-one").path),
            ["sample.txt"]
        )
        XCTAssertEqual(try String(contentsOfFile: artifactPath, encoding: .utf8), "one\nbetween\nTWO\nthree")
    }

    func testSchemaContainsDShCommandsAndRequiredParameters() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(tool.definition.parametersJSON.utf8)) as? [String: Any])
        XCTAssertEqual(object["required"] as? [String], ["command", "path"])
        let properties = try XCTUnwrap(object["properties"] as? [String: Any])
        let command = try XCTUnwrap(properties["command"] as? [String: Any])
        XCTAssertEqual(command["enum"] as? [String], ["view", "create", "str_replace", "insert"])
    }

    func testEmptyFileCRLFDirectoryFilteringAndClipping() async throws {
        _ = try await call(#"{"command":"create","path":"/workspace/empty.txt","file_text":""}"#)
        _ = try await call(#"{"command":"insert","path":"/workspace/empty.txt","insert_line":0,"new_str":"first"}"#)
        let emptyView = try await call(#"{"command":"view","path":"/workspace/empty.txt"}"#)
        XCTAssertTrue(emptyView.content.contains("     1  first"))

        _ = try await call(#"{"command":"create","path":"/workspace/crlf.txt","file_text":"a\r\nb"}"#)
        _ = try await call(#"{"command":"insert","path":"/workspace/crlf.txt","insert_line":1,"new_str":"x\ny"}"#)
        let workspace = root.appendingPathComponent(EditorWorkspaceStore.testHash("session-one"), isDirectory: true)
        XCTAssertEqual(try String(contentsOf: workspace.appendingPathComponent("crlf.txt"), encoding: .utf8), "a\r\nx\r\ny\r\nb")

        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("b/sub/deep"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("a"), withIntermediateDirectories: true)
        try Data("hidden".utf8).write(to: workspace.appendingPathComponent(".hidden"))
        try Data("ok".utf8).write(to: workspace.appendingPathComponent("b/visible.txt"))
        try Data("deep".utf8).write(to: workspace.appendingPathComponent("b/sub/second.txt"))
        let listing = try await call(#"{"command":"view","path":"/workspace"}"#).content
        XCTAssertLessThan(try XCTUnwrap(listing.range(of: "/workspace/a")?.lowerBound), try XCTUnwrap(listing.range(of: "/workspace/b")?.lowerBound))
        XCTAssertTrue(listing.contains("visible.txt"))
        XCTAssertFalse(listing.contains("second.txt"))
        XCTAssertFalse(listing.contains(".hidden"))

        let longJSON = try JSONSerialization.data(withJSONObject: ["command": "create", "path": "/workspace/long.txt", "file_text": String(repeating: "z", count: 17_000)])
        _ = try await call(String(decoding: longJSON, as: UTF8.self))
        let longView = try await call(#"{"command":"view","path":"/workspace/long.txt"}"#)
        XCTAssertTrue(longView.content.contains("<response clipped>"))
    }

    func testRejectsTraversalDuplicateReplacementAndOverwriteWithoutMutation() async throws {
        _ = try await call(#"{"command":"create","path":"/workspace/repeated.txt","file_text":"same\nother\nsame"}"#)
        await XCTAssertThrowsErrorAsync {
            _ = try await self.call(#"{"command":"str_replace","path":"/workspace/repeated.txt","old_str":"same","new_str":"changed"}"#)
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await self.call(#"{"command":"create","path":"/workspace/repeated.txt","file_text":"overwrite"}"#)
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await self.call(#"{"command":"view","path":"/workspace/../outside"}"#)
        }
        let final = try await call(#"{"command":"view","path":"/workspace/repeated.txt"}"#)
        XCTAssertTrue(final.content.contains("     1  same"))
        XCTAssertTrue(final.content.contains("     3  same"))
    }

    func testSessionsAreIsolatedAndPersistentAcrossToolInstances() async throws {
        _ = try await call(#"{"command":"create","path":"/workspace/owned.txt","file_text":"session one"}"#)
        let secondTool = StrReplaceEditorTool(
            workspaces: EditorWorkspaceStore(rootOverride: root),
            attachments: AttachmentRepository(generatedFilesRootOverride: generated)
        )
        let persisted = try await secondTool.execute(call: ToolCall(
            id: "persisted",
            name: StrReplaceEditorTool.name,
            argumentsJSON: #"{"command":"view","path":"/workspace/owned.txt"}"#,
            providerMetadata: ["editorSessionId": "session-one"]
        ))
        XCTAssertTrue(persisted.content.contains("session one"))
        await XCTAssertThrowsErrorAsync {
            _ = try await secondTool.execute(call: ToolCall(
                id: "isolated",
                name: StrReplaceEditorTool.name,
                argumentsJSON: #"{"command":"view","path":"/workspace/owned.txt"}"#,
                providerMetadata: ["editorSessionId": "session-two"]
            ))
        }
        let orphan = root.appendingPathComponent(EditorWorkspaceStore.testHash("orphan"), isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try EditorWorkspaceStore(rootOverride: root).deleteOrphans(validSessionIDs: ["session-one"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(EditorWorkspaceStore.testHash("session-one")).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testRequestAttachmentsAreStagedUnderHashedDiscoverablePath() async throws {
        let source = generated.appendingPathComponent("input notes.txt")
        try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)
        try Data("attached".utf8).write(to: source)
        let encoded = String(decoding: try JSONEncoder().encode([source.path]), as: UTF8.self)
        let result = try await tool.execute(call: ToolCall(
            id: "stage",
            name: StrReplaceEditorTool.name,
            argumentsJSON: #"{"command":"view","path":"/workspace"}"#,
            providerMetadata: ["editorSessionId": "session-one", "editorAttachmentsJSON": encoded]
        ))
        let digest = SHA256.hash(data: Data("attached".utf8)).map { String(format: "%02x", $0) }.joined()
        let virtualPath = "/workspace/attachments/\(digest)/input_notes.txt"
        XCTAssertTrue(result.content.contains("/workspace/attachments/\(digest)"))
        let directory = try await call(#"{"command":"view","path":"/workspace/attachments/\#(digest)"}"#)
        XCTAssertTrue(directory.content.contains("input_notes.txt"))
        let viewed = try await call(#"{"command":"view","path":"\#(virtualPath)"}"#)
        XCTAssertTrue(viewed.content.contains("attached"))
    }

    private func call(_ arguments: String) async throws -> ToolResult {
        try await tool.execute(call: ToolCall(
            id: UUID().uuidString,
            name: StrReplaceEditorTool.name,
            argumentsJSON: arguments,
            providerMetadata: ["editorSessionId": "session-one"]
        ))
    }
}

private extension EditorWorkspaceStore {
    static func testHash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}
