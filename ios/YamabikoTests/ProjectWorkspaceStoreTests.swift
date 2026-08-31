import XCTest
@testable import YamabikoChat

final class ProjectWorkspaceStoreTests: XCTestCase {
    private var root: URL!
    private var sources: URL!
    private var workspaces: EditorWorkspaceStore!
    private var store: ProjectWorkspaceStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-workspace-tests-\(UUID().uuidString)", isDirectory: true)
        sources = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-workspace-sources-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        workspaces = EditorWorkspaceStore(rootOverride: root)
        store = ProjectWorkspaceStore(
            workspaces: workspaces,
            sourcesRootOverride: sources.appendingPathComponent("project-sources", isDirectory: true)
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: sources)
    }

    func testImportedFilesAreRealFilesInFreshExecutionWorkspace() async throws {
        let source = sources.appendingPathComponent("imports/notes.txt")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("project facts".utf8).write(to: source)

        let files = try store.importFiles(from: [source], projectID: 42)
        let executionSessionID = try store.prepareExecutionWorkspace(projectID: 42)

        XCTAssertEqual(files.map(\.relativePath), ["notes.txt"])
        let tool = StrReplaceEditorTool(
            workspaces: workspaces,
            attachments: AttachmentRepository(generatedFilesRootOverride: sources.appendingPathComponent("generated"))
        )
        let result = try await tool.execute(call: ToolCall(
            id: "read-project-file",
            name: StrReplaceEditorTool.name,
            argumentsJSON: #"{"command":"view","path":"/workspace/notes.txt"}"#,
            providerMetadata: [
                "editorSessionId": executionSessionID
            ]
        ))
        XCTAssertTrue(result.content.contains("project facts"))
    }

    func testDuplicateNamesArePreservedWithUniqueWorkspaceNames() throws {
        let first = sources.appendingPathComponent("first", isDirectory: true)
        let second = sources.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let firstFile = first.appendingPathComponent("data.csv")
        let secondFile = second.appendingPathComponent("data.csv")
        try Data("a".utf8).write(to: firstFile)
        try Data("b".utf8).write(to: secondFile)

        let files = try store.importFiles(from: [firstFile, secondFile], projectID: 7)

        XCTAssertEqual(files.map(\.name), ["data (2).csv", "data.csv"])
        XCTAssertEqual(try store.files(projectID: 7), files)
    }

    func testProjectsAreIsolatedAndRemovalDeletesOnlyTargetFile() throws {
        let source = sources.appendingPathComponent("brief.md")
        try Data("brief".utf8).write(to: source)
        _ = try store.importFiles(from: [source], projectID: 1)
        _ = try store.importFiles(from: [source], projectID: 2)

        let remaining = try store.removeFile(relativePath: "brief.md", projectID: 1)

        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(try store.files(projectID: 2).map(\.name), ["brief.md"])
    }

    func testHiddenUserFileIsListedAndSeededIntoExecutionWorkspace() throws {
        let source = sources.appendingPathComponent(".project-config")
        try Data("visible to tools".utf8).write(to: source)

        let files = try store.importFiles(from: [source], projectID: 5)
        let sessionID = try store.prepareExecutionWorkspace(projectID: 5)

        XCTAssertEqual(files.map(\.name), [".project-config"])
        try workspaces.withWorkspace(sessionID: sessionID) { workspace in
            XCTAssertEqual(
                try String(
                    contentsOf: workspace.appendingPathComponent(".project-config"),
                    encoding: .utf8
                ),
                "visible to tools"
            )
        }
    }

    func testEachExecutionGetsFreshCopyWithoutMutatingProjectSources() throws {
        let source = sources.appendingPathComponent("seed.txt")
        try Data("original".utf8).write(to: source)
        _ = try store.importFiles(from: [source], projectID: 12)

        let firstSession = try store.prepareExecutionWorkspace(projectID: 12)
        try workspaces.withWorkspace(sessionID: firstSession) { workspace in
            try Data("changed in run".utf8).write(to: workspace.appendingPathComponent("seed.txt"))
            try Data("run only".utf8).write(to: workspace.appendingPathComponent("generated.txt"))
        }

        let secondSession = try store.prepareExecutionWorkspace(projectID: 12)

        XCTAssertNotEqual(firstSession, secondSession)
        try workspaces.withWorkspace(sessionID: secondSession) { workspace in
            XCTAssertEqual(
                try String(contentsOf: workspace.appendingPathComponent("seed.txt"), encoding: .utf8),
                "original"
            )
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: workspace.appendingPathComponent("generated.txt").path
            ))
        }
        XCTAssertEqual(try store.files(projectID: 12).map(\.name), ["seed.txt"])
    }
}
