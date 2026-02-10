import Foundation

struct CodexUserAgentPresetOption: Identifiable, Equatable, Sendable {
    var id: String { key }
    let key: String
    let title: String
}

enum CodexUserAgentPresetCatalog {
    static let presetAndroid = "ANDROID"
    static let presetUbuntu = "UBUNTU"
    static let presetWindowsPowerShell = "WINDOWS_POWERSHELL"
    static let presetWindowsCmd = "WINDOWS_CMD"

    static let defaultCodexCLIVersion = "0.87.0"

    struct UAParts: Equatable, Sendable {
        let osName: String
        let osVersion: String
        let arch: String
        let terminalUA: String
    }

    static let options: [CodexUserAgentPresetOption] = [
        CodexUserAgentPresetOption(key: presetAndroid, title: "Android"),
        CodexUserAgentPresetOption(key: presetUbuntu, title: "Ubuntu"),
        CodexUserAgentPresetOption(key: presetWindowsPowerShell, title: "Windows PowerShell"),
        CodexUserAgentPresetOption(key: presetWindowsCmd, title: "Windows CMD")
    ]

    static func resolveParts(preset: String?, mobileOSVersion: String, mobileArch: String) -> UAParts {
        switch preset?.uppercased() {
        case presetAndroid:
            return UAParts(
                osName: "Android",
                osVersion: mobileOSVersion,
                arch: mobileArch,
                terminalUA: "unknown"
            )
        case presetUbuntu:
            return UAParts(
                osName: "Ubuntu",
                osVersion: "22.04",
                arch: "x86_64",
                terminalUA: "unknown"
            )
        case presetWindowsPowerShell:
            return UAParts(
                osName: "Windows",
                osVersion: "10.0.22631",
                arch: "x86_64",
                terminalUA: "powershell/5.1"
            )
        case presetWindowsCmd:
            return UAParts(
                osName: "Windows",
                osVersion: "10.0.22631",
                arch: "x86_64",
                terminalUA: "cmd/10.0"
            )
        default:
            return UAParts(
                osName: "Android",
                osVersion: mobileOSVersion,
                arch: mobileArch,
                terminalUA: "unknown"
            )
        }
    }

    static func displayName(for preset: String) -> String {
        options.first(where: { $0.key == preset.uppercased() })?.title ?? preset
    }

    static func buildUserAgent(
        originator: String,
        cliVersion: String = defaultCodexCLIVersion,
        preset: String?,
        mobileOSVersion: String,
        mobileArch: String,
        appID: String?,
        appVersion: String?
    ) -> String {
        let parts = resolveParts(preset: preset, mobileOSVersion: mobileOSVersion, mobileArch: mobileArch)
        let presetKey = preset?.uppercased()
        let terminal: String
        if presetKey == nil || presetKey == presetAndroid {
            let resolvedAppID = appID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedAppVersion = appVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let resolvedAppID, !resolvedAppID.isEmpty, let resolvedAppVersion, !resolvedAppVersion.isEmpty {
                terminal = "\(resolvedAppID)/\(resolvedAppVersion)"
            } else if let resolvedAppID, !resolvedAppID.isEmpty {
                terminal = resolvedAppID
            } else {
                terminal = parts.terminalUA
            }
        } else {
            terminal = parts.terminalUA
        }

        return "\(originator)/\(cliVersion) (\(parts.osName) \(parts.osVersion); \(parts.arch)) \(terminal)"
    }

    static func currentArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #elseif arch(arm)
        return "arm"
        #else
        return "unknown"
        #endif
    }
}
