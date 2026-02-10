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
    private let defaults: UserDefaults?

    init() {
        defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
    }

    func save(_ payload: SharePayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults?.set(data, forKey: AppConstants.sharePayloadDefaultsKey)
        NotificationCenter.default.post(name: AppConstants.sharePayloadDidChangeNotification, object: nil)
    }

    func consumeLatest() -> SharePayload? {
        guard let data = defaults?.data(forKey: AppConstants.sharePayloadDefaultsKey) else { return nil }
        defaults?.removeObject(forKey: AppConstants.sharePayloadDefaultsKey)
        return try? JSONDecoder().decode(SharePayload.self, from: data)
    }
}