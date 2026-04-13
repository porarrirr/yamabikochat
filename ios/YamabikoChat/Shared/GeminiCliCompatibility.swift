import Foundation

enum GeminiCliCompatibilitySource: String, Codable, Sendable {
    case builtIn
    case remote
}

struct GeminiCliMetadata: Codable, Equatable, Sendable {
    var ideType: String
    var platform: String
    var pluginType: String

    var dictionary: [String: String] {
        [
            "ideType": ideType,
            "platform": platform,
            "pluginType": pluginType
        ]
    }
}

struct GeminiCliRequestFormat: Codable, Equatable, Sendable {
    var requestWrapperEnabled: Bool
    var projectFieldName: String
    var requestFieldName: String
    var modelFieldName: String
    var userPromptIDFieldName: String
    var systemInstructionFieldName: String
    var streamAction: String
    var generateAction: String
    var streamUsesAltSse: Bool
}

struct GeminiCliRemoteCompatibility: Codable, Equatable, Sendable {
    var version: String
    var defaultModel: String
    var metadata: GeminiCliMetadata
    var codeAssistEndpoint: String
    var codeAssistVersion: String
    var requestFormat: GeminiCliRequestFormat
    var oauthClient: GeminiOAuthClientConfig?
}

struct GeminiCliResolvedCompatibility: Equatable, Sendable {
    var source: GeminiCliCompatibilitySource
    var remote: GeminiCliRemoteCompatibility
    var lastSyncISO8601: String?

    var metadata: [String: String] {
        remote.metadata.dictionary
    }

    func buildUserAgent(model: String?) -> String {
        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedModel = trimmedModel.isEmpty ? remote.defaultModel : trimmedModel
        return "GeminiCLI/\(remote.version)/\(resolvedModel) (\(GeminiCliCompatibility.platformName); \(GeminiCliCompatibility.architectureName))"
    }
}

enum GeminiCliCompatibilityStore {
    static let remoteRepositoryURL = "https://github.com/jenslys/opencode-gemini-auth"
    static let remoteBranch = "main"

    static let remoteCompatibilityKey = "gemini_cli_remote_compat_json_v1"
    static let remoteLastSyncKey = "gemini_cli_remote_compat_last_sync_iso8601"

    static let builtIn = GeminiCliRemoteCompatibility(
        version: "0.30.0-nightly.20260210.a2174751d",
        defaultModel: "gemini-code-assist",
        metadata: GeminiCliMetadata(
            ideType: "IDE_UNSPECIFIED",
            platform: "PLATFORM_UNSPECIFIED",
            pluginType: "GEMINI"
        ),
        codeAssistEndpoint: "https://cloudcode-pa.googleapis.com",
        codeAssistVersion: "v1internal",
        requestFormat: GeminiCliRequestFormat(
            requestWrapperEnabled: true,
            projectFieldName: "project",
            requestFieldName: "request",
            modelFieldName: "model",
            userPromptIDFieldName: "user_prompt_id",
            systemInstructionFieldName: "systemInstruction",
            streamAction: "streamGenerateContent",
            generateAction: "generateContent",
            streamUsesAltSse: true
        ),
        oauthClient: nil
    )

    static let upstreamRawFileURLs: [String: URL] = [
        "gemini-cli-version.ts": URL(string: "https://raw.githubusercontent.com/jenslys/opencode-gemini-auth/main/src/plugin/gemini-cli-version.ts")!,
        "user-agent.ts": URL(string: "https://raw.githubusercontent.com/jenslys/opencode-gemini-auth/main/src/plugin/user-agent.ts")!,
        "project-types.ts": URL(string: "https://raw.githubusercontent.com/jenslys/opencode-gemini-auth/main/src/plugin/project/types.ts")!,
        "request-prepare.ts": URL(string: "https://raw.githubusercontent.com/jenslys/opencode-gemini-auth/main/src/plugin/request/prepare.ts")!,
        "constants.ts": URL(string: "https://raw.githubusercontent.com/jenslys/opencode-gemini-auth/main/src/constants.ts")!
    ]

    static func resolved(using credentialStore: SecureCredentialStore?) -> GeminiCliResolvedCompatibility {
        guard let credentialStore, let remote = loadRemote(using: credentialStore) else {
            return GeminiCliResolvedCompatibility(source: .builtIn, remote: builtIn, lastSyncISO8601: nil)
        }
        return remote
    }

    static func loadRemote(using credentialStore: SecureCredentialStore) -> GeminiCliResolvedCompatibility? {
        guard let rawValue = try? credentialStore.readSecret(key: remoteCompatibilityKey),
              let raw = rawValue,
              let rawData = raw.data(using: .utf8),
              let remote = try? JSONDecoder().decode(GeminiCliRemoteCompatibility.self, from: rawData)
        else {
            return nil
        }

        guard remote.isUsable else {
            return nil
        }

        let lastSync = try? credentialStore.readSecret(key: remoteLastSyncKey)
        return GeminiCliResolvedCompatibility(source: .remote, remote: remote, lastSyncISO8601: lastSync ?? nil)
    }

    static func saveRemote(
        _ compatibility: GeminiCliRemoteCompatibility,
        syncedAtISO8601: String,
        using credentialStore: SecureCredentialStore
    ) throws {
        let data = try JSONEncoder().encode(compatibility)
        try credentialStore.saveSecret(String(decoding: data, as: UTF8.self), key: remoteCompatibilityKey)
        try credentialStore.saveSecret(syncedAtISO8601, key: remoteLastSyncKey)
    }

    static func parseUpstreamFiles(_ files: [String: String]) throws -> GeminiCliRemoteCompatibility {
        let versionSource = try requireFile(named: "gemini-cli-version.ts", in: files)
        let userAgentSource = try requireFile(named: "user-agent.ts", in: files)
        let projectTypesSource = try requireFile(named: "project-types.ts", in: files)
        let requestPrepareSource = try requireFile(named: "request-prepare.ts", in: files)
        let constantsSource = try requireFile(named: "constants.ts", in: files)

        let version = try requireFirstMatch(
            in: versionSource,
            pattern: #"GEMINI_CLI_VERSION\s*=\s*"([^"]+)""#,
            label: "Gemini CLI version"
        )
        let defaultModel = try requireFirstMatch(
            in: userAgentSource,
            pattern: #"GEMINI_CLI_DEFAULT_MODEL\s*=\s*"([^"]+)""#,
            label: "Gemini CLI default model"
        )
        let ideType = try requireFirstMatch(
            in: projectTypesSource,
            pattern: #"ideType:\s*"([^"]+)""#,
            label: "Gemini CLI ideType"
        )
        let platform = try requireFirstMatch(
            in: projectTypesSource,
            pattern: #"platform:\s*"([^"]+)""#,
            label: "Gemini CLI metadata platform"
        )
        let pluginType = try requireFirstMatch(
            in: projectTypesSource,
            pattern: #"pluginType:\s*"([^"]+)""#,
            label: "Gemini CLI pluginType"
        )
        let codeAssistEndpoint = try requireFirstMatch(
            in: constantsSource,
            pattern: #"GEMINI_CODE_ASSIST_ENDPOINT\s*=\s*"([^"]+)""#,
            label: "Gemini Code Assist endpoint"
        )
        let oauthClientID = try requireFirstMatch(
            in: constantsSource,
            pattern: #"GEMINI_CLIENT_ID\s*=\s*"([^"]+)""#,
            label: "Gemini OAuth client ID"
        )
        let oauthClientSecret = try requireFirstMatch(
            in: constantsSource,
            pattern: #"GEMINI_CLIENT_SECRET\s*=\s*"([^"]+)""#,
            label: "Gemini OAuth client secret"
        )
        let codeAssistVersion = try requireFirstMatch(
            in: requestPrepareSource,
            pattern: #"GEMINI_CODE_ASSIST_ENDPOINT\}\/([^:`?]+):"#,
            label: "Gemini Code Assist API version"
        )
        let streamAction = try requireFirstMatch(
            in: requestPrepareSource,
            pattern: #"STREAM_ACTION\s*=\s*"([^"]+)""#,
            label: "Gemini CLI stream action"
        )
        let projectFieldName = try requireFirstObjectKey(
            in: requestPrepareSource,
            objectName: "wrappedBody",
            expectedKey: "project",
            label: "Gemini CLI project field"
        )
        let modelFieldName = try requireFirstObjectKey(
            in: requestPrepareSource,
            objectName: "wrappedBody",
            expectedKey: "model",
            label: "Gemini CLI model field"
        )
        let userPromptIDFieldName = try requireFirstObjectKey(
            in: requestPrepareSource,
            objectName: "wrappedBody",
            expectedKey: "user_prompt_id",
            label: "Gemini CLI user prompt field"
        )
        let requestFieldName = try requireFirstObjectKey(
            in: requestPrepareSource,
            objectName: "wrappedBody",
            expectedKey: "request",
            label: "Gemini CLI request field"
        )
        let systemInstructionFieldName = try requireFirstMatch(
            in: requestPrepareSource,
            pattern: #"requestPayload\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*requestPayload\.system_instruction"#,
            label: "Gemini CLI system instruction field"
        )
        let usesAltSse = requestPrepareSource.contains(#""?alt=sse""#)
        guard usesAltSse else {
            throw ProviderClientError.parseFailure("Gemini CLI streaming format is missing alt=sse.")
        }

        let compatibility = GeminiCliRemoteCompatibility(
            version: version,
            defaultModel: defaultModel,
            metadata: GeminiCliMetadata(
                ideType: ideType,
                platform: platform,
                pluginType: pluginType
            ),
            codeAssistEndpoint: codeAssistEndpoint,
            codeAssistVersion: codeAssistVersion,
            requestFormat: GeminiCliRequestFormat(
                requestWrapperEnabled: true,
                projectFieldName: projectFieldName,
                requestFieldName: requestFieldName,
                modelFieldName: modelFieldName,
                userPromptIDFieldName: userPromptIDFieldName,
                systemInstructionFieldName: systemInstructionFieldName,
                streamAction: streamAction,
                generateAction: "generateContent",
                streamUsesAltSse: true
            ),
            oauthClient: GeminiOAuthClientConfig(
                clientID: oauthClientID,
                clientSecret: oauthClientSecret
            )
        )

        guard compatibility.isUsable else {
            throw ProviderClientError.parseFailure("Fetched Gemini CLI compatibility data is incomplete.")
        }
        return compatibility
    }

    private static func requireFile(named name: String, in files: [String: String]) throws -> String {
        guard let file = files[name], !file.isEmpty else {
            throw ProviderClientError.parseFailure("Missing upstream Gemini CLI source file: \(name)")
        }
        return file
    }

    private static func requireFirstMatch(
        in source: String,
        pattern: String,
        label: String
    ) throws -> String {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: source)
        else {
            throw ProviderClientError.parseFailure("Failed to parse \(label) from upstream Gemini CLI sources.")
        }
        let value = String(source[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw ProviderClientError.parseFailure("\(label) parsed as empty from upstream Gemini CLI sources.")
        }
        return value
    }

    private static func requireFirstObjectKey(
        in source: String,
        objectName: String,
        expectedKey: String,
        label: String
    ) throws -> String {
        let bodyPattern = #"const\s+\#(objectName)\s*=\s*\{([\s\S]*?)\n\s*\};"#
        let objectBody = try requireFirstMatch(in: source, pattern: bodyPattern, label: "\(label) object body")
        let keyPattern = #"(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:"# 
        let regex = try NSRegularExpression(pattern: keyPattern)
        let range = NSRange(objectBody.startIndex..<objectBody.endIndex, in: objectBody)
        let matches = regex.matches(in: objectBody, range: range)
        let keys = matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1, let keyRange = Range(match.range(at: 1), in: objectBody) else {
                return nil
            }
            return String(objectBody[keyRange])
        }
        guard keys.contains(expectedKey) else {
            throw ProviderClientError.parseFailure("Failed to parse \(label) from upstream Gemini CLI sources.")
        }
        return expectedKey
    }
}

private extension GeminiCliRemoteCompatibility {
    var isUsable: Bool {
        !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !defaultModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !codeAssistEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !codeAssistVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !metadata.ideType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !metadata.platform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !metadata.pluginType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            requestFormat.requestWrapperEnabled &&
            !requestFormat.projectFieldName.isEmpty &&
            !requestFormat.requestFieldName.isEmpty &&
            !requestFormat.modelFieldName.isEmpty &&
            !requestFormat.userPromptIDFieldName.isEmpty &&
            !requestFormat.systemInstructionFieldName.isEmpty &&
            !requestFormat.streamAction.isEmpty &&
            !requestFormat.generateAction.isEmpty
    }
}

enum GeminiCliCompatibility {
    static var metadata: [String: String] {
        GeminiCliCompatibilityStore.builtIn.metadata.dictionary
    }

    static func resolved(using credentialStore: SecureCredentialStore? = nil) -> GeminiCliResolvedCompatibility {
        GeminiCliCompatibilityStore.resolved(using: credentialStore)
    }

    static func buildUserAgent(model: String?, credentialStore: SecureCredentialStore? = nil) -> String {
        resolved(using: credentialStore).buildUserAgent(model: model)
    }

    static func makeActivityRequestID() -> String {
        let candidate = String(UInt64.random(in: 0..<(1 << 48)), radix: 36)
        return candidate.isEmpty ? "0" : candidate
    }

    static let platformName = "darwin"

    static var architectureName: String {
        #if arch(arm64)
            return "arm64"
        #elseif arch(x86_64)
            return "x64"
        #elseif arch(i386)
            return "x86"
        #else
            return "unknown"
        #endif
    }
}
