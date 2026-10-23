import XCTest
@testable import YamabikoChat

private final class RuntimeLaunchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var arguments: [[String]] = []
    private var failuresRemaining: Int

    init(failures: Int = 0) { failuresRemaining = failures }

    func start(_ arguments: [String]) throws {
        try lock.withLock {
            self.arguments.append(arguments)
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw URLError(.cannotOpenFile)
            }
        }
    }

    var launches: [[String]] { lock.withLock { arguments } }
}

private actor StartupHealthClient: PiRuntimeHealthClient {
    private var available = false
    private var requests: [URLRequest] = []
    private let delay: Duration

    init(delay: Duration = .zero) { self.delay = delay }

    func setAvailable() { available = true }
    func recordedRequests() -> [URLRequest] { requests }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if delay != .zero { try await Task.sleep(for: delay) }
        guard available else { throw URLError(.cannotConnectToHost) }
        return (
            Data(#"{"ok":true,"contractVersion":2}"#.utf8),
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
}

final class PiRuntimeStartupTests: XCTestCase {
    private func runtime(launcher: RuntimeLaunchRecorder, health: StartupHealthClient) -> PiAgentRuntime {
        PiAgentRuntime(
            readiness: PiRuntimeReadinessConfiguration(
                startupTimeout: .zero, resumeTimeout: .zero, retryDelay: .zero
            ),
            healthClient: health,
            startEngine: { try launcher.start($0) }
        )
    }

    func testStartupTimeoutAndRepeatedRetriesKeepTheOriginalEngineIdentity() async throws {
        let launcher = RuntimeLaunchRecorder()
        let health = StartupHealthClient()
        let runtime = runtime(launcher: launcher, health: health)

        // Reproduces the crash: Node has launched, but its listener is not yet
        // reachable (including a launch while the app is in the background).
        for _ in 0..<3 {
            do {
                try await runtime.verifyReady()
                XCTFail("Expected an unavailable runtime")
            } catch let ProviderClientError.parseFailure(message) {
                XCTAssertTrue(message.contains("Pi agent runtime did not"))
            }
        }
        await health.setAvailable()
        try await runtime.prepareForForeground()
        try await runtime.verifyReady()

        let launches = launcher.launches
        XCTAssertEqual(launches.count, 1, "A failed health check must never start Node again")
        let arguments = try XCTUnwrap(launches.first)
        let requests = await health.recordedRequests()
        XCTAssertEqual(requests.count, 5, "Foreground recovery must probe the timed-out launch")
        XCTAssertEqual(Set(requests.compactMap { $0.url?.port }), [Int(arguments[2])!])
        XCTAssertEqual(Set(requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") }),
                       ["Bearer \(arguments[3])"])
    }

    func testConcurrentFirstRequestsShareLaunchAndStartupReadiness() async throws {
        let launcher = RuntimeLaunchRecorder()
        let health = StartupHealthClient(delay: .milliseconds(100))
        await health.setAvailable()
        let runtime = runtime(launcher: launcher, health: health)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { try await runtime.verifyReady() } }
            try await group.waitForAll()
        }

        XCTAssertEqual(launcher.launches.count, 1)
        let requests = await health.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testConcurrentStartupFailuresCanRecoverWithoutRelaunch() async throws {
        let launcher = RuntimeLaunchRecorder()
        let health = StartupHealthClient(delay: .milliseconds(100))
        let runtime = runtime(launcher: launcher, health: health)
        let failures = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<20 {
                group.addTask {
                    do { try await runtime.verifyReady(); return false }
                    catch { return true }
                }
            }
            var results: [Bool] = []
            for await failed in group { results.append(failed) }
            return results
        }
        XCTAssertTrue(failures.allSatisfy { $0 })
        await health.setAvailable()
        try await runtime.verifyReady()
        XCTAssertEqual(launcher.launches.count, 1)
    }

    func testPreparationFailureDoesNotCacheAnUnstartedEndpoint() async throws {
        let launcher = RuntimeLaunchRecorder(failures: 1)
        let health = StartupHealthClient()
        await health.setAvailable()
        let runtime = runtime(launcher: launcher, health: health)

        do {
            try await runtime.verifyReady()
            XCTFail("Expected launch preparation failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cannotOpenFile)
        }
        let failedRequests = await health.recordedRequests()
        XCTAssertTrue(failedRequests.isEmpty)
        try await runtime.verifyReady()
        XCTAssertEqual(launcher.launches.count, 2)
        let requests = await health.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testNativeGuardRejectsConcurrentClientsWithoutDisturbingTheRunningEngine() async throws {
        try await PiAgentRuntime.shared.verifyReady()
        // Each actor has independent Swift state. Only the native process-wide
        // guard can prevent these clients from reaching node_start again.
        await withTaskGroup(of: NSError?.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    do { try await PiAgentRuntime().verifyReady(); return nil }
                    catch { return error as NSError }
                }
            }
            for await error in group {
                XCTAssertEqual(error?.domain, "PiNodeRunnerErrorDomain")
                XCTAssertEqual(error?.code, 1)
            }
        }
        try await PiAgentRuntime.shared.prepareForForeground()
        try await PiAgentRuntime.shared.verifyReady()
    }
}
