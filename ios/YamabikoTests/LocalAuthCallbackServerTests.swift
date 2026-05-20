import XCTest
import Darwin
@testable import YamabikoChat

final class LocalAuthCallbackServerTests: XCTestCase {
    func testBindFallsBackToSystemAssignedPortWhenPreferredPortIsUnavailable() throws {
        let preferredPort: UInt16 = 19155
        let occupiedSocketFD = try occupyLocalPort(preferredPort)
        defer { close(occupiedSocketFD) }

        let server = LocalAuthCallbackServer(expectedPath: "/oauth2callback", preferredPort: preferredPort)
        let selectedPort = try server.bind()

        XCTAssertNotEqual(selectedPort, preferredPort)
        XCTAssertGreaterThan(selectedPort, 0)
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

    func testAwaitCallbackRejectsUnexpectedPathThenAcceptsValidCallback() async throws {
        let server = LocalAuthCallbackServer(expectedPath: "/oauth2callback", preferredPort: 0)
        let selectedPort = try server.bind()

        let callbackTask = Task {
            try await server.awaitCallback(on: selectedPort, timeoutSeconds: 5)
        }
        defer { callbackTask.cancel() }

        try await Task.sleep(nanoseconds: 200_000_000)

        let invalidURL = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(selectedPort)/wrong-path?state=test-state&code=test-code")
        )
        let (_, invalidResponse) = try await URLSession.shared.data(from: invalidURL)
        XCTAssertEqual((invalidResponse as? HTTPURLResponse)?.statusCode, 404)

        let validURL = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(selectedPort)/oauth2callback?state=ok&code=ok")
        )
        let (_, validResponse) = try await URLSession.shared.data(from: validURL)
        XCTAssertEqual((validResponse as? HTTPURLResponse)?.statusCode, 200)

        let callback = try await callbackTask.value
        XCTAssertEqual(callback.path, "/oauth2callback")
    }

    func testAwaitCallbackReturnsBadRequestForMalformedRequestLine() async throws {
        let server = LocalAuthCallbackServer(expectedPath: "/oauth2callback", preferredPort: 0)
        let selectedPort = try server.bind()

        let callbackTask = Task {
            try await server.awaitCallback(on: selectedPort, timeoutSeconds: 5)
        }
        defer { callbackTask.cancel() }

        try await Task.sleep(nanoseconds: 200_000_000)

        let malformedResponse = try sendRawRequest(
            port: selectedPort,
            request: "BADREQUEST\r\nHost: 127.0.0.1\r\n\r\n"
        )
        XCTAssertTrue(malformedResponse.contains("400 Bad Request"))

        let validURL = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(selectedPort)/oauth2callback?state=ready&code=ready")
        )
        let (_, response) = try await URLSession.shared.data(from: validURL)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        let callback = try await callbackTask.value
        XCTAssertEqual(callback.path, "/oauth2callback")
    }

    func testFailedToBindErrorProvidesReadableDescription() {
        XCTAssertEqual(
            LocalAuthCallbackError.failedToBindAnyPort.localizedDescription,
            "Failed to start the local auth callback server on loopback. Please retry."
        )
    }
}

private func occupyLocalPort(_ port: UInt16) throws -> Int32 {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    var reuse: Int32 = 1
    guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
        let code = errno
        close(fd)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(port).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    memset(&address.sin_zero, 0, MemoryLayout.size(ofValue: address.sin_zero))

    let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else {
        let code = errno
        close(fd)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    guard listen(fd, SOMAXCONN) == 0 else {
        let code = errno
        close(fd)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    return fd
}

private func sendRawRequest(port: UInt16, request: String) throws -> String {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    defer { close(fd) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(port).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    memset(&address.sin_zero, 0, MemoryLayout.size(ofValue: address.sin_zero))

    let connectResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard connectResult == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    let requestBytes = Array(request.utf8)
    let sentCount = requestBytes.withUnsafeBufferPointer { pointer in
        send(fd, pointer.baseAddress, pointer.count, 0)
    }
    guard sentCount == requestBytes.count else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    var response = Data()
    var buffer = [UInt8](repeating: 0, count: 2048)
    while true {
        let count = recv(fd, &buffer, buffer.count, 0)
        if count > 0 {
            response.append(contentsOf: buffer[0 ..< Int(count)])
            continue
        }
        if count == 0 {
            break
        }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    return String(data: response, encoding: .utf8) ?? ""
}
