import Foundation

private enum ShareConstants {
    static let appGroupIdentifier = "group.com.porarri.yamabikochat"
    static let sharePayloadDefaultsKey = "share_payload"
}

struct SharePayload: Codable {
    var text: String
    var sourceApp: String?
    var createdAtMs: Int64
}

enum SharePayloadPersister {
    static func save(text: String, sourceApp: String?) {
        let payload = SharePayload(
            text: text,
            sourceApp: sourceApp,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        guard
            let data = try? JSONEncoder().encode(payload),
            let defaults = UserDefaults(suiteName: ShareConstants.appGroupIdentifier)
        else {
            return
        }
        defaults.set(data, forKey: ShareConstants.sharePayloadDefaultsKey)
    }
}