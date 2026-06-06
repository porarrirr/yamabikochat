import Foundation

struct HTTPRequest {
    var url: URL
    var method: String
    var headers: [String: String]
    var body: Data?

    init(url: URL, method: String = "POST", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

protocol HTTPClientProtocol {
    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse)
    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse)
}

struct URLSessionHTTPClient: HTTPClientProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        request.headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderClientError.invalidResponse
        }
        return (data, http)
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        request.headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }

        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderClientError.invalidResponse
        }

        if !(200 ... 299).contains(http.statusCode) {
            let errorBody = await Self.readResponseBody(from: bytes)
            let message = errorBody.isEmpty ? "HTTP \(http.statusCode)" : errorBody
            throw ProviderClientError.httpStatus(http.statusCode, message)
        }

        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (stream, http)
    }

    private static func readResponseBody(from bytes: URLSession.AsyncBytes, maxBytes: Int = 16_384) async -> String {
        var chunks: [String] = []
        var total = 0
        do {
            for try await line in bytes.lines {
                chunks.append(line)
                total += line.utf8.count + 1
                if total >= maxBytes {
                    break
                }
            }
        } catch {
            return chunks.joined(separator: "\n")
        }
        return chunks.joined(separator: "\n")
    }
}
