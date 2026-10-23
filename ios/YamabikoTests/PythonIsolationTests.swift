import Foundation
import Network
import XCTest
@testable import YamabikoChat

final class PythonIsolationTests: XCTestCase {
    func testAuditBypassCannotReadHostFilesOrCallNativeSecurityFramework() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("python-isolation-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let canary = root.appendingPathComponent("private-canary.txt")
        try Data("SYNTHETIC-HOST-SECRET".utf8).write(to: canary)
        let path = String(decoding: try JSONEncoder().encode(canary.path), as: UTF8.self)
        let worker = PythonWorker(sessions: PythonSessionStore(rootOverride: root.appendingPathComponent("sessions")))
        let response = try await worker.execute(sessionID: "host-isolation", code: """
        __yamabiko_resolve_virtual_path.__globals__['_active_workspace'] = None
        try:
            print(open(\(path)).read())
            raise AssertionError('host file escaped')
        except FileNotFoundError:
            print('host-file-blocked')
        try:
            import ctypes
            ctypes.CDLL('/System/Library/Frameworks/Security.framework/Security')
            raise AssertionError('native framework escaped')
        except (ImportError, OSError):
            print('native-api-blocked')
        """, reset: true, attachmentPaths: [])
        XCTAssertEqual(response.status, "ok", response.error?.traceback ?? response.stderr)
        XCTAssertTrue(response.stdout.contains("host-file-blocked"))
        XCTAssertTrue(response.stdout.contains("native-api-blocked"))
        XCTAssertFalse(response.stdout.contains("SYNTHETIC-HOST-SECRET"))
        await worker.resetSession(sessionID: "host-isolation")
    }

    func testBrowserNetworkAPIsRemainBlockedAfterPythonGuardIsDisabled() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "network canary listening")
        let counter = PythonNetworkCanary()
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            counter.increment()
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                connection.send(content: Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok".utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .global())
        defer { listener.cancel() }
        await fulfillment(of: [ready], timeout: 3)
        let port = try XCTUnwrap(listener.port).rawValue
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/canary"))
        _ = try await URLSession.shared.data(from: url)
        XCTAssertEqual(counter.value, 1, "The canary must be reachable by native networking")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("python-network-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let worker = PythonWorker(sessions: PythonSessionStore(rootOverride: root))
        let response = try await worker.execute(sessionID: "network-isolation", code: """
        __yamabiko_resolve_virtual_path.__globals__['_active_workspace'] = None
        import js
        request = js.XMLHttpRequest.new()
        request.open('GET', 'http://127.0.0.1:\(port)/credential-exfiltration', False)
        try:
            request.send()
            raise AssertionError('network request escaped')
        except Exception as error:
            assert type(error).__name__ != 'AssertionError'
            print('browser-network-blocked')
        """, reset: true, attachmentPaths: [])
        XCTAssertEqual(response.status, "ok", response.error?.traceback ?? response.stderr)
        XCTAssertTrue(response.stdout.contains("browser-network-blocked"))
        XCTAssertEqual(counter.value, 1, "Python must not reach even a reachable loopback server")
        await worker.resetSession(sessionID: "network-isolation")
    }

    func testUntrustedFileTransferRejectsPathsSymlinksAndOversizedData() throws {
        let policy = PythonSandboxFiles(maximumFileBytes: 4)
        for path in ["/tmp/secret", "../secret", "a/../../secret", "a//secret", "a\\secret", "a\0secret"] {
            XCTAssertThrowsError(try policy.validate([PythonSandboxFile(path: path, data: Data("ok".utf8).base64EncodedString())]), path)
        }
        XCTAssertThrowsError(try policy.validate([PythonSandboxFile(path: "large", data: Data("12345".utf8).base64EncodedString())]))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("python-symlink-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("escape").path, withDestinationPath: "/tmp")
        XCTAssertThrowsError(try policy.read(workspace: root))
    }

    func testMaliciousTransferCannotOverwriteAParallelEditorChange() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("python-conflict-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let policy = PythonSandboxFiles()
        let baseline = try policy.read(workspace: root)
        try Data("editor change".utf8).write(to: root.appendingPathComponent("keep.txt"))
        XCTAssertThrowsError(try policy.commit([], workspace: root, baseline: baseline))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("keep.txt")), "editor change")
    }

    func testWorkspaceSnapshotsKeepRelativePathsAcrossAliasedRootsAndRepeatedCommits() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("python-paths-\(UUID())")
        let physical = root.appendingPathComponent("physical-workspaces", isDirectory: true)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try manager.createDirectory(at: physical, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        try manager.createSymbolicLink(at: alias, withDestinationURL: physical)
        let sessions = PythonSessionStore(rootOverride: alias)
        let paths = try sessions.prepare(sessionID: "stable-paths")
        let editor = EditorWorkspaceStore(rootOverride: alias)
        try editor.withWorkspace(sessionID: "stable-paths") { workspace in
            try manager.createDirectory(at: workspace.appendingPathComponent("audit"), withIntermediateDirectories: true)
            try Data("日本語 probe".utf8).write(to: workspace.appendingPathComponent("audit/probe.txt"))
        }

        let policy = PythonSandboxFiles()
        for _ in 0..<6 {
            let baseline = try policy.read(workspace: paths.workspace)
            XCTAssertEqual(baseline.map(\.path), ["audit", "audit/probe.txt", "outputs"])
            XCTAssertEqual(try sessions.workspaceUsage(in: paths).maximumDepth, 2)
            try policy.commit(baseline, workspace: paths.workspace, baseline: baseline)
            try editor.withWorkspace(sessionID: "stable-paths") { workspace in
                XCTAssertEqual(try String(contentsOf: workspace.appendingPathComponent("audit/probe.txt"), encoding: .utf8), "日本語 probe")
            }
        }
    }
}

private final class PythonNetworkCanary: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}
