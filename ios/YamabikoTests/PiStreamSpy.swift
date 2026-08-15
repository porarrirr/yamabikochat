import Foundation
@testable import YamabikoChat

final class PiStreamSpy: @unchecked Sendable {
    struct Call: Sendable {
        var request: ProviderRequest
        var configuration: PiAgentConfiguration
    }

    typealias Handler = @Sendable (ProviderRequest, PiAgentConfiguration) async throws -> [ProviderStreamEvent]

    private let lock = NSLock()
    private var recordedCalls: [Call] = []
    private let handler: Handler

    init(handler: @escaping Handler = { _, _ in
        [.completed(ProviderResponse(text: "ok"))]
    }) {
        self.handler = handler
    }

    var calls: [Call] {
        lock.withLock { recordedCalls }
    }

    var stream: PiAgentStream {
        { [self] request, configuration, _ in
            lock.withLock {
                recordedCalls.append(Call(request: request, configuration: configuration))
            }
            let events = try await handler(request, configuration)
            return AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}
