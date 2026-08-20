import XCTest
@testable import YamabikoChat

final class PythonRuntimeTests: XCTestCase {
    func testEmbeddedScientificPackagesRenderPNG() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("python-scientific-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = PythonSessionStore(rootOverride: root)
        let worker = PythonWorker(
            sessions: store,
            timeoutSeconds: 60,
            memoryLimitBytes: 4_000_000_000
        )
        let response = try await worker.execute(
            sessionID: "scientific-integration",
            code: #"""
import numpy as np
from PIL import Image
import matplotlib
import matplotlib.pyplot as plt

values = np.array([1.0, 2.0, 3.0])
Image.new("RGB", (4, 4), "red").save("pillow.png")
plt.plot(values, values ** 2)
plt.title("Embedded Python")
plt.savefig("matplotlib.png")
(float(np.sum(values)), matplotlib.get_backend())
"""#,
            reset: true,
            attachmentPaths: []
        )

        XCTAssertEqual(response.status, "ok", response.error?.traceback ?? response.stderr)
        XCTAssertNil(response.error)
        XCTAssertTrue(response.resultRepr?.contains("6.0") == true)
        XCTAssertTrue(response.resultRepr?.lowercased().contains("agg") == true)

        let artifacts = Dictionary(uniqueKeysWithValues: response.artifacts.map { ($0.name, $0) })
        let pillowArtifact = try XCTUnwrap(artifacts["pillow.png"])
        let matplotlibArtifact = try XCTUnwrap(artifacts["matplotlib.png"])
        XCTAssertGreaterThan(pillowArtifact.size, 0)
        XCTAssertGreaterThan(matplotlibArtifact.size, 0)

        let workspace = root
            .appendingPathComponent("scientific-integration", isDirectory: true)
            .appendingPathComponent("workspace", isDirectory: true)
        for filename in ["pillow.png", "matplotlib.png"] {
            let data = try Data(contentsOf: workspace.appendingPathComponent(filename))
            XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        }

        await worker.discard(sessionID: "scientific-integration")
    }

    func testEmbeddedCPythonExecutesStatefulCells() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("python-runtime-\(UUID().uuidString)", isDirectory: true)
        defer {
            if FileManager.default.fileExists(atPath: root.path) {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let store = PythonSessionStore(rootOverride: root)
        let worker = PythonWorker(
            sessions: store,
            timeoutSeconds: 0.5,
            memoryLimitBytes: 4_000_000_000
        )

        let first = try await worker.execute(
            sessionID: "integration",
            code: "value = 40\nvalue + 2",
            reset: true,
            attachmentPaths: []
        )
        let second = try await worker.execute(
            sessionID: "integration",
            code: "value + 3",
            reset: false,
            attachmentPaths: []
        )
        let timedOut = try await worker.execute(
            sessionID: "integration",
            code: "while True:\n    pass",
            reset: false,
            attachmentPaths: []
        )
        let afterInterrupt = try await worker.execute(
            sessionID: "integration",
            code: "value + 4",
            reset: false,
            attachmentPaths: []
        )

        XCTAssertEqual(first.status, "ok")
        XCTAssertEqual(first.resultRepr, "42")
        XCTAssertEqual(second.resultRepr, "43")
        XCTAssertEqual(timedOut.status, "error")
        XCTAssertEqual(timedOut.error?.type, "TimeoutError")
        XCTAssertEqual(afterInterrupt.resultRepr, "44")

        let exportedRoot = root.appendingPathComponent("exported", isDirectory: true)
        let tool = PythonExecuteTool(
            worker: worker,
            sessions: store,
            attachments: AttachmentRepository(generatedFilesRootOverride: exportedRoot)
        )
        let artifactResult = try await tool.execute(call: ToolCall(
            id: "artifact-call",
            name: PythonExecuteTool.name,
            argumentsJSON: #"{"code":"from pathlib import Path\nPath('weather.svg').write_text('<svg/>')"}"#,
            providerMetadata: ["pythonSessionId": "integration"]
        ))
        let exportedArtifact = try XCTUnwrap(artifactResult.artifacts.first)
        XCTAssertEqual(exportedArtifact.name, "weather.svg")
        XCTAssertTrue(exportedArtifact.path.contains("Chat integration/weather.svg"))
        XCTAssertEqual(
            try String(contentsOfFile: exportedArtifact.path, encoding: .utf8),
            "<svg/>"
        )
        await worker.discard(sessionID: "integration")
    }

    func testResultEnvelopeDecodesArtifactsAndError() throws {
        let json = #"{"status":"error","stdout":"out","stderr":"err","result_repr":null,"artifacts":[{"name":"plot.png","root":"workspace","relpath":"plot.png","mime":"image/png","size":12}],"duration_ms":8,"error":{"type":"ValueError","message":"bad","traceback":"trace"}}"#
        let response = try JSONDecoder().decode(PythonExecutionResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.status, "error")
        XCTAssertEqual(response.artifacts.first?.root, "workspace")
        XCTAssertEqual(response.artifacts.first?.mime, "image/png")
        XCTAssertEqual(response.error?.type, "ValueError")
    }

    func testSessionStoreResetAndDeleteLifecycle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("python-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PythonSessionStore(rootOverride: root)
        let paths = try store.prepare(sessionID: "42", reset: false)
        let file = paths.workspace.appendingPathComponent("state.txt")
        try Data("value".utf8).write(to: file)

        let reset = try store.prepare(sessionID: "42", reset: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reset.outputs.path))

        XCTAssertEqual(
            try store.artifactURL(sessionID: "42", root: "workspace", relativePath: "state.txt"),
            reset.workspace.appendingPathComponent("state.txt")
        )
        XCTAssertThrowsError(
            try store.artifactURL(sessionID: "42", root: "workspace", relativePath: "../outputs/file.txt")
        )

        try store.delete(sessionID: "42")
        XCTAssertFalse(FileManager.default.fileExists(atPath: reset.root.path))
    }

    func testLegacyToolResultDecodesWithoutArtifacts() throws {
        let json = #"{"callId":"1","name":"web_search","content":"{}","isError":false,"sources":[]}"#
        let result = try JSONDecoder().decode(ToolResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.artifacts, [])
    }
}
