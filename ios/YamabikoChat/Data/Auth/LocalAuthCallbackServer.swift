import Foundation
import Network

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
    private var preparedListener: NWListener?
    private var preparedPort: UInt16?
    private static let bindRetryCount = 2
    private static let listenerReadyTimeout: TimeInterval = 3.0

    init(expectedPath: String, preferredPort: UInt16) {
        self.expectedPath = expectedPath
        self.preferredPort = preferredPort
    }

    deinit {
        bindLock.lock()
        preparedListener?.cancel()
        preparedListener = nil
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
                cachePreparedListener(prepared.listener, port: prepared.port)
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
                cachePreparedListener(fallback.listener, port: fallback.port)
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
        let listener: NWListener
        if let prepared = consumePreparedListener(for: port) {
            listener = prepared
            usingPreparedListener = true
        } else {
            listener = try NWListener(
                using: Self.loopbackParameters(),
                on: NWEndpoint.Port(rawValue: port)!
            )
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
                listener.cancel()
                continuation.resume(with: result)
            }

            let timeoutWork = DispatchWorkItem {
                finish(.failure(LocalAuthCallbackError.timeout))
            }
            queue.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWork)

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    DiagnosticsLogger.log("Auth callback listener ready port=\(port)", category: .auth)
                    onReady?()
                case let .failed(error):
                    timeoutWork.cancel()
                    DiagnosticsLogger.log("Auth callback listener failed port=\(port)", category: .auth, error: error)
                    finish(.failure(error))
                default:
                    break
                }
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: self.queue)
                guard Self.isAllowedCallbackEndpoint(connection.endpoint) else {
                    DiagnosticsLogger.log(
                        "Auth callback rejected non-loopback endpoint endpoint=\(connection.endpoint)",
                        level: .warning,
                        category: .auth
                    )
                    self.respond(
                        connection: connection,
                        status: 403,
                        message: "Callback must originate from loopback."
                    )
                    connection.cancel()
                    return
                }
                self.receiveHTTPRequest(connection: connection) { request in
                    defer { connection.cancel() }
                    guard let request, !request.isEmpty
                    else {
                        DiagnosticsLogger.log("Auth callback received empty request", category: .auth)
                        return
                    }

                    let requestLine = request
                        .replacingOccurrences(of: "\r\n", with: "\n")
                        .components(separatedBy: "\n")
                        .first ?? ""
                    let methodAndPath = requestLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
                    guard methodAndPath.count >= 2 else {
                        self.respond(
                            connection: connection,
                            status: 400,
                            message: "Invalid callback request."
                        )
                        return
                    }

                    let pathWithQuery = String(methodAndPath[1])
                    guard let components = URLComponents(string: "http://127.0.0.1\(pathWithQuery)") else {
                        DiagnosticsLogger.log("Auth callback URL parse failed path=\(pathWithQuery)", category: .auth)
                        self.respond(
                            connection: connection,
                            status: 400,
                            message: "Invalid callback URL."
                        )
                        return
                    }

                    guard components.path == self.expectedPath else {
                        DiagnosticsLogger.log(
                            "Auth callback unexpected path expected=\(self.expectedPath) actual=\(components.path)",
                            category: .auth
                        )
                        self.respond(connection: connection, status: 404, message: "Not Found")
                        return
                    }

                    timeoutWork.cancel()
                    DiagnosticsLogger.log("Auth callback received path=\(components.path)", category: .auth)
                    self.respond(connection: connection, status: 200, message: "Login completed. You can return to the app.")
                    finish(.success(
                        CallbackResult(
                            path: components.path,
                            queryItems: components.queryItems ?? []
                        )
                    ))
                }
            }

            if usingPreparedListener {
                DiagnosticsLogger.log("Auth callback listener ready port=\(port) source=prepared", category: .auth)
                onReady?()
            } else {
                listener.start(queue: queue)
            }
        }
    }

    private func respond(connection: NWConnection, status: Int, message: String) {
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
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func receiveHTTPRequest(
        connection: NWConnection,
        received: Data = Data(),
        completion: @escaping (String?) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { chunk, _, isComplete, error in
            if let error {
                DiagnosticsLogger.log("Auth callback receive failed", category: .auth, error: error)
                completion(nil)
                return
            }

            var updated = received
            if let chunk, !chunk.isEmpty {
                updated.append(chunk)
            }

            if let request = String(data: updated, encoding: .utf8),
               request.contains("\r\n\r\n") || request.contains("\n\n") {
                completion(request)
                return
            }

            if isComplete {
                completion(String(data: updated, encoding: .utf8))
                return
            }

            self.receiveHTTPRequest(connection: connection, received: updated, completion: completion)
        }
    }

    private func cachePreparedListener(_ listener: NWListener, port: UInt16) {
        bindLock.lock()
        defer { bindLock.unlock() }
        preparedListener?.cancel()
        preparedListener = listener
        preparedPort = port
    }

    private func consumePreparedListener(for port: UInt16) -> NWListener? {
        bindLock.lock()
        defer { bindLock.unlock() }
        guard preparedPort == port, let listener = preparedListener else { return nil }
        preparedListener = nil
        preparedPort = nil
        return listener
    }

    private static func tryPrepareListener(
        requestedPort: UInt16,
        stage: String,
        attempt: Int
    ) -> (listener: NWListener, port: UInt16)? {
        let endpointPort: NWEndpoint.Port
        if requestedPort == 0 {
            endpointPort = .any
        } else if let explicitPort = NWEndpoint.Port(rawValue: requestedPort) {
            endpointPort = explicitPort
        } else {
            return nil
        }
        let listener: NWListener
        do {
            listener = try NWListener(using: loopbackParameters(), on: endpointPort)
        } catch {
            DiagnosticsLogger.log(
                "Auth callback bind init failed stage=\(stage) attempt=\(attempt) requestedPort=\(requestedPort)",
                level: .warning,
                category: .auth,
                error: error
            )
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var boundPort: UInt16?
        var failedError: NWError?
        listener.stateUpdateHandler = { state in
            stateLock.lock()
            defer { stateLock.unlock() }
            switch state {
            case .ready:
                boundPort = listener.port?.rawValue ?? requestedPort
                semaphore.signal()
            case let .failed(error):
                failedError = error
                semaphore.signal()
            default:
                break
            }
        }
        listener.start(queue: DispatchQueue(label: "yamabiko.auth.bind.prepare.\(requestedPort).\(attempt)"))
        let waitResult = semaphore.wait(timeout: .now() + Self.listenerReadyTimeout)
        listener.stateUpdateHandler = nil

        if let failedError {
            DiagnosticsLogger.log(
                "Auth callback bind failed stage=\(stage) attempt=\(attempt) requestedPort=\(requestedPort)",
                level: .warning,
                category: .auth,
                error: failedError
            )
            listener.cancel()
            return nil
        }

        if waitResult == .timedOut {
            DiagnosticsLogger.log(
                "Auth callback bind timed out stage=\(stage) attempt=\(attempt) requestedPort=\(requestedPort)",
                level: .warning,
                category: .auth
            )
            listener.cancel()
            return nil
        }

        guard let boundPort else {
            DiagnosticsLogger.log(
                "Auth callback bind missing bound port stage=\(stage) attempt=\(attempt) requestedPort=\(requestedPort)",
                level: .warning,
                category: .auth
            )
            listener.cancel()
            return nil
        }

        return (listener, boundPort)
    }

    private static func isAllowedCallbackEndpoint(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else {
            // Accept unknown endpoint styles because some Apple stacks can abstract loopback origins.
            return true
        }
        let normalized = host
            .debugDescription
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
        if normalized == "localhost" || normalized == "::1" || normalized == "0:0:0:0:0:0:0:1" {
            return true
        }
        if normalized.hasPrefix("127.") || normalized.contains("127.0.0.1") {
            return true
        }
        return false
    }

    private static func loopbackParameters() -> NWParameters {
        // Avoid requiredInterfaceType(.loopback) for listeners; it can fail on iOS with NWError(22).
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        return parameters
    }
}
