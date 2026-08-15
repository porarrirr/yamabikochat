import Foundation
import Darwin

struct SearchResult: Codable, Sendable, Equatable {
    var title: String
    var snippet: String
    var url: String
    var publishedAt: String? = nil
}

protocol SearchEngine: Sendable {
    func search(query: String, locale: Locale, maxResults: Int) async throws -> [SearchResult]
}

protocol WebToolHTTPClient: Sendable {
    func get(url: URL, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionWebToolHTTPClient: WebToolHTTPClient {
    static let maxResponseBytes = 2 * 1024 * 1024

    private let session: URLSession
    private let redirectDelegate: WebToolRedirectDelegate?

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            redirectDelegate = nil
        } else {
            let delegate = WebToolRedirectDelegate()
            redirectDelegate = delegate
            self.session = URLSession(
                configuration: .ephemeral,
                delegate: delegate,
                delegateQueue: nil
            )
        }
    }

    func get(url: URL, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        try WebToolURLPolicy.validatePublicHTTPURL(url)
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.1", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderClientError.invalidResponse
        }
        if let finalURL = http.url {
            try WebToolURLPolicy.validatePublicHTTPURL(finalURL)
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > Self.maxResponseBytes {
                throw ProviderClientError.parseFailure("HTTP response exceeds the 2 MB response limit")
            }
        }
        return (data, http)
    }
}

private final class WebToolRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let url = request.url else { return nil }
        do {
            try WebToolURLPolicy.validatePublicHTTPURL(url)
            return request
        } catch {
            DiagnosticsLogger.log(
                "Blocked client web tool redirect",
                level: .warning,
                category: .network,
                metadata: ["url": url.absoluteString],
                error: error
            )
            return nil
        }
    }
}

enum WebToolURLPolicy {
    static func validatePublicHTTPURL(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else {
            throw ProviderClientError.invalidBaseURL(url.absoluteString)
        }
        guard url.user == nil, url.password == nil else {
            throw ProviderClientError.invalidBaseURL("URL credentials are not allowed: \(url.absoluteString)")
        }

        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        guard !isBlockedLocalHostname(normalizedHost) else {
            throw ProviderClientError.invalidBaseURL("Local hostnames are not allowed: \(host)")
        }

        let addresses = try resolvedAddresses(for: normalizedHost)
        guard !addresses.isEmpty, addresses.allSatisfy(\.isPubliclyRoutable) else {
            throw ProviderClientError.invalidBaseURL("URL host is not publicly routable: \(host)")
        }
    }

    private static func isBlockedLocalHostname(_ host: String) -> Bool {
        host == "localhost" ||
            host.hasSuffix(".localhost") ||
            host.hasSuffix(".local")
    }

    private static func resolvedAddresses(for host: String) throws -> [ResolvedIPAddress] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0, let result else {
            throw ProviderClientError.invalidBaseURL("URL host could not be resolved: \(host)")
        }
        defer { freeaddrinfo(result) }

        var addresses: [ResolvedIPAddress] = []
        var current: UnsafeMutablePointer<addrinfo>? = result
        while let infoPointer = current {
            let info = infoPointer.pointee
            if info.ai_family == AF_INET, let address = info.ai_addr {
                let value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
                addresses.append(.ipv4(value))
            } else if info.ai_family == AF_INET6, let address = info.ai_addr {
                var value = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    $0.pointee.sin6_addr
                }
                let bytes = withUnsafeBytes(of: &value) { Array($0) }
                addresses.append(.ipv6(bytes))
            }
            current = info.ai_next
        }
        return addresses
    }

    private enum ResolvedIPAddress {
        case ipv4(UInt32)
        case ipv6([UInt8])

        var isPubliclyRoutable: Bool {
            switch self {
            case let .ipv4(value):
                return Self.isPublicIPv4(value)
            case let .ipv6(bytes):
                return Self.isPublicIPv6(bytes)
            }
        }

        private static func isPublicIPv4(_ value: UInt32) -> Bool {
            let first = Int((value >> 24) & 0xff)
            let second = Int((value >> 16) & 0xff)
            let third = Int((value >> 8) & 0xff)

            if first == 0 || first == 10 || first == 127 || first >= 224 { return false }
            if first == 100 && (64 ... 127).contains(second) { return false }
            if first == 169 && second == 254 { return false }
            if first == 172 && (16 ... 31).contains(second) { return false }
            if first == 192 && second == 168 { return false }
            if first == 192 && second == 0 { return false }
            if first == 198 && (second == 18 || second == 19 || second == 51) { return false }
            if first == 203 && second == 0 && third == 113 { return false }
            return true
        }

        private static func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
            guard bytes.count == 16 else { return false }
            if bytes.allSatisfy({ $0 == 0 }) { return false }
            if bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 { return false }
            if bytes[0] == 0xff { return false }
            if (bytes[0] & 0xfe) == 0xfc { return false }
            if bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 { return false }
            if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8 {
                return false
            }
            if let mapped = mappedIPv4(fromIPv6Bytes: bytes) {
                return isPublicIPv4(mapped)
            }
            return true
        }

        private static func mappedIPv4(fromIPv6Bytes bytes: [UInt8]) -> UInt32? {
            let prefixIsMapped = bytes[0 ..< 10].allSatisfy { $0 == 0 } &&
                bytes[10] == 0xff &&
                bytes[11] == 0xff
            guard prefixIsMapped else { return nil }
            return (UInt32(bytes[12]) << 24) |
                (UInt32(bytes[13]) << 16) |
                (UInt32(bytes[14]) << 8) |
                UInt32(bytes[15])
        }
    }
}
