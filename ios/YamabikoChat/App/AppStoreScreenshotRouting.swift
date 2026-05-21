import Foundation

enum AppStoreScreenshotRouting {
    enum Scene: String {
        case list
        case chat
        case settingsAPI = "settings-api"
        case settingsAppearance = "settings-appearance"
        case settingsDual = "settings-dual"
        case settingsAuto = "settings-auto"
        case project
    }

    struct LaunchConfiguration {
        var scene: Scene
        var conversationID: Int64?
        var projectID: Int64?
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-AppStoreScreenshotDemo")
    }

    static func launchConfiguration() -> LaunchConfiguration? {
        guard isEnabled else { return nil }
        guard let rawScene = argumentValue(for: "-ScreenshotScene"),
              let scene = Scene(rawValue: rawScene)
        else {
            return nil
        }

        return LaunchConfiguration(
            scene: scene,
            conversationID: argumentValue(for: "-ScreenshotConversationId").flatMap(Int64.init),
            projectID: argumentValue(for: "-ScreenshotProjectId").flatMap(Int64.init)
        )
    }

    private static func argumentValue(for key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: key), args.index(after: index) < args.endIndex else {
            return nil
        }
        let value = args[args.index(after: index)].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
