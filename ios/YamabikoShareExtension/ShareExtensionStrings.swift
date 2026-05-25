import Foundation

enum ShareExtensionStrings {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
    }

    static var screenTitle: String { text("share.screen_title") }
    static var previewHeading: String { text("share.preview_heading") }
    static var notePlaceholder: String { text("share.note_placeholder") }
    static var primaryButton: String { text("share.primary_button") }
    static var cancelButton: String { text("share.cancel_button") }
    static var loading: String { text("share.loading") }
    static var emptyPreview: String { text("share.empty_preview") }
}
