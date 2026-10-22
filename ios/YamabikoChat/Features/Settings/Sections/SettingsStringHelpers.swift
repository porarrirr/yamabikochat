import Foundation

enum SettingsStringHelpers {
    static func nilIfBlank(_ value: String) -> String? {
        value.trimmedNonEmpty
    }
}
