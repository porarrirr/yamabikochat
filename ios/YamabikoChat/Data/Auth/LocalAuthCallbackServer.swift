import Foundation
import Darwin

enum LocalAuthCallbackError: Error {
    case failedToBindAnyPort
    case timeout
    case invalidCallback(String)
}

extension LocalAuthCallbackError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .failedToBindAnyPort:
            return "Failed to start the local auth callback server on loopback. Please retry."
        case .timeout:
            return "Timed out waiting for the authentication callback."
        case let .invalidCallback(message):
            return message
        }
    }
}

final class LocalAuthCallbackServer {
    struct CallbackResult {
        var path: String
        var queryItems: [URLQueryItem]
    }

    private let expectedPath: String
    private let preferredPort: UInt16
    private let queue = DispatchQueue(label: "yamabiko.auth.callback.server")
    private let bindLock = NSLock()
    private var preparedSocketFD: Int32?
    private var preparedPort: UInt16?
    private static let bindRetryCount = 2

    init(expectedPath: String, preferredPort: UInt16) {
        self.expectedPath = expectedPath
        self.preferredPort = preferredPort
    }

    deinit {
        bindLock.lock()
        if let preparedSocketFD {
            Darwin.close(preparedSocketFD)
        }
        preparedSocketFD = nil
        preparedPort = nil
        bindLock.unlock()
    }

    func bind() throws -> UInt16 {
        for attempt in 1 ... Self.bindRetryCount {
            if let prepared = Self.tryPrepareListener(
                requestedPort: preferredPort,
                stage: "preferred",
                attempt: attempt
            ) {
                DiagnosticsLogger.log(
                    "Auth callback port available port=\(prepared.port) attempt=\(attempt)",
                    category: .auth
                )
                cachePreparedSocket(prepared.fd, port: prepared.port)
                return prepared.port
            }
        }

        for attempt in 1 ... Self.bindRetryCount {
            if let fallback = Self.tryPrepareListener(
                requestedPort: 0,
                stage: "fallback",
                attempt: attempt
            ) {
                DiagnosticsLogger.log(
                    "Auth callback fallback port selected port=\(fallback.port) attempt=\(attempt)",
                    category: .auth
                )
                cachePreparedSocket(fallback.fd, port: fallback.port)
                return fallback.port
            }
        }

        DiagnosticsLogger.log(
            "Auth callback failed to bind any port preferredPort=\(preferredPort)",
            level: .error,
            category: .auth
        )
        throw LocalAuthCallbackError.failedToBindAnyPort
    }

    func awaitCallback(
        on port: UInt16,
        timeoutSeconds: TimeInterval = 300,
        onReady: (@Sendable () -> Void)? = nil
    ) async throws -> CallbackResult {
        let usingPreparedListener: Bool
        let listeningFD: Int32
        if let prepared = consumePreparedSocket(for: port) {
            listeningFD = prepared
            usingPreparedListener = true
        } else {
            listeningFD = try Self.createListeningSocket(requestedPort: port).fd
            usingPreparedListener = false
        }
        return try await withCheckedThrowingContinuation { continuation in
            let stateLock = NSLock()
            var completed = false

            func finish(_ result: Result<CallbackResult, Error>) {
                stateLock.lock()
                defer { stateLock.unlock() }
                guard !completed else { return }
                completed = true
                Darwin.close(listeningFD)
                continuation.resume(with: result)
            }

            func isCompleted() -> Bool {
                stateLock.lock()
                defer { stateLock.unlock() }
                return completed
            }

            let timeoutWork = DispatchWorkItem {
                finish(.failure(LocalAuthCallbackError.timeout))
            }
            queue.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWork)

            if usingPreparedListener {
                DiagnosticsLogger.log("Auth callback listener ready port=\(port) source=prepared", category: .auth)
            } else {
                DiagnosticsLogger.log("Auth callback listener ready port=\(port)", category: .auth)
            }
            onReady?()

            queue.async {
                while true {
                    let connectionFD: Int32
                    do {
                        connectionFD = try Self.acceptConnection(listeningFD: listeningFD)
                    } catch {
                        if isCompleted() {
                            return
                        }
                        timeoutWork.cancel()
                        DiagnosticsLogger.log("Auth callback listener failed port=\(port)", category: .auth, error: error)
                        finish(.failure(error))
                        return
                    }

                    defer {
                        Darwin.close(connectionFD)
                    }

                    let request: String
                    do {
                        guard let received = try self.receiveHTTPRequest(connectionFD: connectionFD),
                              !received.isEmpty
                        else {
                            DiagnosticsLogger.log("Auth callback received empty request", category: .auth)
                            continue
                        }
                        request = received
                    } catch {
                        DiagnosticsLogger.log("Auth callback receive failed", category: .auth, error: error)
                        continue
                    }

                    let requestLine = request
                        .replacingOccurrences(of: "\r\n", with: "\n")
                        .components(separatedBy: "\n")
                        .first ?? ""
                    let methodAndPath = requestLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
                    guard methodAndPath.count >= 2 else {
                        self.respond(
                            connectionFD: connectionFD,
                            status: 400,
                            message: "Invalid callback request."
                        )
                        continue
                    }

                    let pathWithQuery = String(methodAndPath[1])
                    guard let components = URLComponents(string: "http://127.0.0.1\(pathWithQuery)") else {
                        DiagnosticsLogger.log("Auth callback URL parse failed path=\(pathWithQuery)", category: .auth)
                        self.respond(
                            connectionFD: connectionFD,
                            status: 400,
                            message: "Invalid callback URL."
                        )
                        continue
                    }

                    guard components.path == self.expectedPath else {
                        DiagnosticsLogger.log(
                            "Auth callback unexpected path expected=\(self.expectedPath) actual=\(components.path)",
                            category: .auth
                        )
                        self.respond(connectionFD: connectionFD, status: 404, message: "Not Found")
                        continue
                    }

                    timeoutWork.cancel()
                    DiagnosticsLogger.log("Auth callback received path=\(components.path)", category: .auth)
                    self.respond(connectionFD: connectionFD, status: 200, message: "Login completed. You can return to the app.")
                    finish(.success(
                        CallbackResult(
                            path: components.path,
                            queryItems: components.queryItems ?? []
                        )
                    ))
                    return
                }
            }
        }
    }

    private func respond(connectionFD: Int32, status: Int, message: String) {
        let escaped = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let body = """
        <html>
          <head><meta charset="utf-8"/></head>
          <body style="font-family:sans-serif;">
            <h2>\(escaped)</h2>
          </body>
        </html>
        """

        let statusText: String
        switch status {
        case 200:
            statusText = "OK"
        case 400:
            statusText = "Bad Request"
        case 403:
            statusText = "Forbidden"
        case 404:
            statusText = "Not Found"
        default:
            statusText = "Error"
        }
        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        Self.sendString(response, to: connectionFD)
    }

    private func receiveHTTPRequest(connectionFD: Int32) throws -> String? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let maxRequestBytes = 64 * 1024

        while true {
            let count = Darwin.recv(connectionFD, &buffer, buffer.count, 0)
            if count > 0 {
                data.append(contentsOf: buffer[0 ..< Int(count)])
                if let request = String(data: data, encoding: .utf8),
                   request.contains("\r\n\r\n") || request.contains("\n\n") {
                    return request
                }
                if data.count >= maxRequestBytes {
                    return String(data: data, encoding: .utf8)
                }
                continue
            }

            if count == 0 {
                return String(data: data, encoding: .utf8)
            }

            let code = errno
            if code == EINTR {
                continue
            }
            throw Self.posixError(context: "recv", code: code)
        }
    }

    private func cachePreparedSocket(_ fd: Int32, port: UInt16) {
        bindLock.lock()
        defer { bindLock.unlock() }
            if let preparedSocketFD {
            Darwin.close(preparedSocketFD)
        }
        preparedSocketFD = fd
        preparedPort = port
    }

    private func consumePreparedSocket(for port: UInt16) -> Int32? {
        bindLock.lock()
        defer { bindLock.unlock() }
        guard preparedPort == port, let socketFD = preparedSocketFD else { return nil }
        preparedSocketFD = nil
        preparedPort = nil
        return socketFD
    }

    private static func tryPrepareListener(
        requestedPort: UInt16,
        stage: String,
        attempt: Int
    ) -> (fd: Int32, port: UInt16)? {
        do {
            return try createListeningSocket(requestedPort: requestedPort)
        } catch {
            DiagnosticsLogger.log(
                "Auth callback bind failed stage=\(stage) attempt=\(attempt) requestedPort=\(requestedPort)",
                level: .warning,
                category: .auth,
                error: error
            )
            return nil
        }
    }

    private static func createListeningSocket(requestedPort: UInt16) throws -> (fd: Int32, port: UInt16) {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw posixError(context: "socket")
        }

        do {
            var enableReuse: Int32 = 1
            if Darwin.setsockopt(
                fd,
                SOL_SOCKET,
                SO_REUSEADDR,
                &enableReuse,
                socklen_t(MemoryLayout<Int32>.size)
            ) < 0 {
                throw posixError(context: "setsockopt(SO_REUSEADDR)")
            }

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(requestedPort).bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            memset(&address.sin_zero, 0, MemoryLayout.size(ofValue: address.sin_zero))

            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bindResult < 0 {
                throw posixError(context: "bind")
            }

            if Darwin.listen(fd, SOMAXCONN) < 0 {
                throw posixError(context: "listen")
            }

            let boundPort = try socketBoundPort(fd: fd)
            return (fd, boundPort)
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    private static func socketBoundPort(fd: Int32) throws -> UInt16 {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.getsockname(fd, sockaddrPointer, &length)
            }
        }
        if result < 0 {
            throw posixError(context: "getsockname")
        }
        return UInt16(bigEndian: address.sin_port)
    }

    private static func acceptConnection(listeningFD: Int32) throws -> Int32 {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let fd = withUnsafeMutablePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.accept(listeningFD, sockaddrPointer, &length)
            }
        }
        guard fd >= 0 else {
            throw posixError(context: "accept")
        }
        return fd
    }

    private static func sendString(_ response: String, to fd: Int32) {
        let data = Data(response.utf8)
        _ = data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return 0 }
            var remaining = rawBuffer.count
            var sent = 0
            while remaining > 0 {
                let wrote = Darwin.send(fd, baseAddress.advanced(by: sent), remaining, 0)
                if wrote <= 0 {
                    return sent
                }
                sent += wrote
                remaining -= wrote
            }
            return sent
        }
    }

    private static func posixError(context: String, code: Int32 = errno) -> NSError {
        let description = String(cString: strerror(code))
        return NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "\(context): \(description)"]
        )
    }
}
