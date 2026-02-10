import XCTest
import Network
@testable import YamabikoChat

final class LocalAuthCallbackServerTests: XCTestCase {
    func testBindFallsBackToSystemAssignedPortWhenPreferredPortIsUnavailable() throws {
        let preferredPort: UInt16 = 19155
        let occupiedListener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: preferredPort)!)
        let occupiedState = expectation(description: "Occupied listener state observed")
        occupiedListener.stateUpdateHandler = { state in
            if case .ready = state {
                occupiedState.fulfill()
            } else if case .failed = state {
                occupiedState.fulfill()
            }
        }
        occupiedListener.start(queue: DispatchQueue(label: "yamabiko.tests.occupied.listener"))
        wait(for: [occupiedState], timeout: 2.0)

        let server = LocalAuthCallbackServer(expectedPath: "/oauth2callback", preferredPort: preferredPort)
        let selectedPort = try server.bind()

        XCTAssertNotEqual(selectedPort, preferredPort)
        XCTAssertGreaterThan(selectedPort, 0)

        occupiedListener.cancel()
    }

    func testAwaitCallbackReceivesValidRequest() async throws {
        let server = LocalAuthCallbackServer(expectedPath: "/oauth2callback", preferredPort: 0)
        let selectedPort = try server.bind()

        let callbackTask = Task {
            try await server.awaitCallback(on: selectedPort, timeoutSeconds: 5)
        }
        defer { callbackTask.cancel() }

        try await Task.sleep(nanoseconds: 200_000_000)

        let url = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(selectedPort)/oauth2callback?state=test-state&code=test-code")
        )
        let (_, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        let callback = try await callbackTask.value
        XCTAssertEqual(callback.path, "/oauth2callback")
        let query = callback.queryItems.reduce(into: [String: String]()) { partialResult, item in
            partialResult[item.name] = item.value ?? ""
        }
        XCTAssertEqual(query["state"], "test-state")
        XCTAssertEqual(query["code"], "test-code")
    }

    func testFailedToBindErrorProvidesReadableDescription() {
        XCTAssertEqual(
            LocalAuthCallbackError.failedToBindAnyPort.localizedDescription,
            "Failed to start the local auth callback server on loopback. Please retry."
        )
    }
}
