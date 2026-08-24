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
        fileprivate let encodedData: Data
    }

    init() {
        SharePayloadDarwinNotifier.startObserving {
            NotificationCenter.default.post(name: AppConstants.sharePayloadDidChangeNotification, object: nil)
        }
    }

    func save(_ payload: SharePayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        guard AppGroupShareStorage.writePayloadData(data) else { return }
        NotificationCenter.default.post(name: AppConstants.sharePayloadDidChangeNotification, object: nil)
    }

    func consumeLatest() -> SharePayload? {
        guard let data = AppGroupShareStorage.consumePayloadData() else { return nil }
        return try? JSONDecoder().decode(SharePayload.self, from: data)
    }

    func loadLatest() -> PendingPayload? {
        guard let data = AppGroupShareStorage.readPayloadData(),
              let payload = try? JSONDecoder().decode(SharePayload.self, from: data)
        else { return nil }
        return PendingPayload(payload: payload, encodedData: data)
    }

    @discardableResult
    func discard(_ pending: PendingPayload) -> Bool {
        AppGroupShareStorage.removePayloadData(matching: pending.encodedData)
    }
}

enum SharePayloadPersister {
    static func save(text: String, sourceApp: String?) {
        let payload = SharePayload(
            text: text,
            sourceApp: sourceApp,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        AppGroupShareStorage.writePayloadData(data)
    }
}
