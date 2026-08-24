import Foundation

struct SharePayload: Codable, Equatable {
    var text: String
    var sourceApp: String?
    var createdAtMs: Int64

    init(text: String, sourceApp: String? = nil, createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.text = text
        self.sourceApp = sourceApp
        self.createdAtMs = createdAtMs
    }
}

final class SharePayloadStore {
    struct PendingPayload: Equatable {
        let payload: SharePayload
        fileprivate let queued: AppGroupShareStorage.QueuedPayload
    }

    init() {
        SharePayloadDarwinNotifier.startObserving {
            NotificationCenter.default.post(name: AppConstants.sharePayloadDidChangeNotification, object: nil)
        }
    }

    func save(_ payload: SharePayload) throws {
        let data = try JSONEncoder().encode(payload)
        guard AppGroupShareStorage.writePayloadData(data) else {
            throw CocoaError(.fileWriteUnknown)
        }
        NotificationCenter.default.post(name: AppConstants.sharePayloadDidChangeNotification, object: nil)
    }

    func consumeLatest() -> SharePayload? {
        guard let data = AppGroupShareStorage.consumePayloadData() else { return nil }
        return try? JSONDecoder().decode(SharePayload.self, from: data)
    }

    func loadLatest() -> PendingPayload? {
        while let queued = AppGroupShareStorage.peekPayload() {
            if let payload = try? JSONDecoder().decode(SharePayload.self, from: queued.data) {
                return PendingPayload(payload: payload, queued: queued)
            }
            guard AppGroupShareStorage.quarantine(queued) else {
                NSLog("Invalid share payload could not be quarantined: %@", queued.id.uuidString)
                return nil
            }
            NSLog("Invalid share payload moved to failed queue: %@", queued.id.uuidString)
        }
        return nil
    }

    @discardableResult
    func discard(_ pending: PendingPayload) -> Bool {
        AppGroupShareStorage.acknowledge(pending.queued)
    }
}

enum SharePayloadPersister {
    static func save(text: String, sourceApp: String?) throws {
        let payload = SharePayload(
            text: text,
            sourceApp: sourceApp,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        let data = try JSONEncoder().encode(payload)
        guard AppGroupShareStorage.writePayloadData(data) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
