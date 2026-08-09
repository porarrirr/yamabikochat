import Combine
import CryptoKit
import Foundation
import Yams
import ZIPFoundation

final class AgentSkillRepository: @unchecked Sendable {
    private struct PersistedState: Codable {
        var isEnabled: Bool
        var installedAt: Date
        var contentHash: String
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let lock = NSLock()
    private let subject: CurrentValueSubject<[InstalledAgentSkill], Never>
    private let hostedExecutionKey = "agentSkills.openAIHostedExecutionEnabled"

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let support = try! fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootURL = support.appendingPathComponent("YamabikoChat/AgentSkills", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        subject = CurrentValueSubject([])
        reload()
    }

    var skillsPublisher: AnyPublisher<[InstalledAgentSkill], Never> {
        subject.eraseToAnyPublisher()
    }

    var installedSkills: [InstalledAgentSkill] { subject.value }
    var enabledSkills: [InstalledAgentSkill] { subject.value.filter(\.isEnabled) }

    var openAIHostedExecutionEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: hostedExecutionKey) }
        set { UserDefaults.standard.set(newValue, forKey: hostedExecutionKey) }
    }

    func inspect(sourceURL: URL) throws -> AgentSkillInstallPreview {
        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer { if secured { sourceURL.stopAccessingSecurityScopedResource() } }

        let stagingParent = fileManager.temporaryDirectory
            .appendingPathComponent("yamabiko-agent-skill-\(UUID().uuidString)", isDirectory: true)
        let extracted = stagingParent.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
        do {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
                throw AgentSkillError.notFound("選択したSkillが見つかりません。")
            }
            if isDirectory.boolValue {
                try copyValidatedFolder(from: sourceURL, to: extracted)
            } else {
                try extractValidatedArchive(from: sourceURL, to: extracted)
            }
            let skillRoot = try locateSkillRoot(in: extracted)
            let parsed = try parseAndInventory(root: skillRoot)
            let canonicalRoot = stagingParent.appendingPathComponent("skill", isDirectory: true)
            try fileManager.moveItem(at: skillRoot, to: canonicalRoot)
            return AgentSkillInstallPreview(
                id: UUID(),
                manifest: parsed.manifest,
                files: parsed.files,
                hasScripts: parsed.files.contains(where: \.isScript),
                contentHash: parsed.hash,
                externalURLs: parsed.externalURLs,
                replacesExisting: fileManager.fileExists(atPath: skillURL(named: parsed.manifest.name).path),
                stagedRoot: canonicalRoot
            )
        } catch {
            try? fileManager.removeItem(at: stagingParent)
            throw error
        }
    }

    @discardableResult
    func install(_ preview: AgentSkillInstallPreview, trusted: Bool, allowReplacement: Bool) throws -> InstalledAgentSkill {
        guard trusted else { throw AgentSkillError.trustRequired }
        let destination = skillURL(named: preview.manifest.name)
        let existing = installedSkills.first { $0.manifest.name == preview.manifest.name }
        if existing != nil, !allowReplacement {
            throw AgentSkillError.invalidManifest("同名のSkillがあります。置換の確認が必要です。")
        }
        let state = PersistedState(
            isEnabled: existing?.isEnabled ?? true,
            installedAt: Date(),
            contentHash: preview.contentHash
        )
        let stateData = try JSONEncoder.agentSkill.encode(state)
        try stateData.write(to: preview.stagedRoot.appendingPathComponent("state.json"), options: .atomic)

        lock.lock()
        defer { lock.unlock() }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: preview.stagedRoot, backupItemName: nil)
        } else {
            try fileManager.moveItem(at: preview.stagedRoot, to: destination)
        }
        let installed = InstalledAgentSkill(
            manifest: preview.manifest,
            files: preview.files,
            hasScripts: preview.hasScripts,
            contentHash: preview.contentHash,
            isEnabled: state.isEnabled,
            installedAt: state.installedAt
        )
        reloadLocked()
        DiagnosticsLogger.log("Agent Skill installed", category: .settings, metadata: ["skill": installed.manifest.name])
        return installed
    }

    func discard(_ preview: AgentSkillInstallPreview) {
        try? fileManager.removeItem(at: preview.stagedRoot.deletingLastPathComponent())
    }

    func setEnabled(_ enabled: Bool, name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let skill = subject.value.first(where: { $0.manifest.name == name }) else {
            throw AgentSkillError.notFound("Skillが見つかりません: \(name)")
        }
        let state = PersistedState(isEnabled: enabled, installedAt: skill.installedAt, contentHash: skill.contentHash)
        try JSONEncoder.agentSkill.encode(state).write(to: skillURL(named: name).appendingPathComponent("state.json"), options: .atomic)
        reloadLocked()
        DiagnosticsLogger.log("Agent Skill enabled state changed", category: .settings, metadata: ["skill": name, "enabled": String(enabled)])
    }

    func delete(name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let url = skillURL(named: name)
        guard fileManager.fileExists(atPath: url.path) else { throw AgentSkillError.notFound("Skillが見つかりません: \(name)") }
        try fileManager.removeItem(at: url)
        reloadLocked()
        DiagnosticsLogger.log("Agent Skill deleted", category: .settings, metadata: ["skill": name])
    }

    func requestContext(for text: String, conversationID: String?, providerSupportsTools: Bool) throws -> SkillRequestContext? {
        let enabled = enabledSkills
        guard !enabled.isEmpty else { return nil }
        let names = Self.explicitSkillNames(in: text, allowed: Set(enabled.map { $0.manifest.name }))
        var instructions: [String] = []
        var resources: [String] = []
        for name in names {
            instructions.append(try skillInstructions(name: name))
            resources.append(resourcePaths(name: name).joined(separator: "\n"))
        }
        return SkillRequestContext(
            catalog: enabled.map { AgentSkillCatalogEntry(name: $0.manifest.name, description: $0.manifest.description) },
            explicitlyRequestedNames: names,
            explicitInstructions: instructions,
            resourceLists: resources,
            conversationID: conversationID,
            enabledSkillSetHash: Self.hashStrings(enabled.map { "\($0.manifest.name):\($0.contentHash)" }.sorted()),
            hostedExecutionEnabled: openAIHostedExecutionEnabled
        )
    }

    func skillInstructions(name: String) throws -> String {
        _ = try requireEnabled(name)
        let url = skillURL(named: name).appendingPathComponent("SKILL.md")
        return try readUTF8(url: url, limit: AgentSkillLimits.skillFileBytes)
    }

    func resourcePaths(name: String) -> [String] {
        guard let skill = enabledSkills.first(where: { $0.manifest.name == name }) else { return [] }
        return skill.files.map(\.path).filter { $0 != "SKILL.md" && $0 != "state.json" }
    }

    func readResource(name: String, path: String) throws -> String {
        _ = try requireEnabled(name)
        let normalized = try Self.normalizedRelativePath(path)
        guard normalized != "SKILL.md", normalized != "state.json" else {
            throw AgentSkillError.resourceNotText("このファイルは資料APIから読み込めません。")
        }
        let root = skillURL(named: name).standardizedFileURL
        let target = root.appendingPathComponent(normalized).standardizedFileURL
        guard target.path.hasPrefix(root.path + "/") else { throw AgentSkillError.unsafePath("Skill外のパスは読み込めません。") }
        return try readUTF8(url: target, limit: AgentSkillLimits.textResourceBytes)
    }

    func rootForEnabledSkill(name: String) throws -> URL {
        _ = try requireEnabled(name)
        return skillURL(named: name)
    }

    static func explicitSkillNames(in text: String, allowed: Set<String>) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9_-])\$([a-z0-9][a-z0-9-]{0,63})(?![A-Za-z0-9_-])"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return regex.matches(in: text, range: range).compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: text) else { return nil }
            let name = String(text[nameRange])
            guard allowed.contains(name), seen.insert(name).inserted else { return nil }
            return name
        }
    }

    private func requireEnabled(_ name: String) throws -> InstalledAgentSkill {
        guard let skill = enabledSkills.first(where: { $0.manifest.name == name }) else {
            throw AgentSkillError.notFound("有効なSkillが見つかりません: \(name)")
        }
        return skill
    }

    private func reload() {
        lock.lock()
        defer { lock.unlock() }
        reloadLocked()
    }

    private func reloadLocked() {
        let directories = (try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        let skills = directories.compactMap { url -> InstalledAgentSkill? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            guard let parsed = try? parseAndInventory(root: url),
                  let stateData = try? Data(contentsOf: url.appendingPathComponent("state.json")),
                  let state = try? JSONDecoder.agentSkill.decode(PersistedState.self, from: stateData),
                  state.contentHash == parsed.hash else { return nil }
            return InstalledAgentSkill(
                manifest: parsed.manifest,
                files: parsed.files,
                hasScripts: parsed.files.contains(where: \.isScript),
                contentHash: parsed.hash,
                isEnabled: state.isEnabled,
                installedAt: state.installedAt
            )
        }.sorted { $0.manifest.name < $1.manifest.name }
        subject.send(skills)
    }

    private func extractValidatedArchive(from source: URL, to destination: URL) throws {
        let size = (try source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard size <= AgentSkillLimits.archiveBytes else { throw AgentSkillError.limitExceeded("ZIPは50 MB以下にしてください。") }
        guard source.pathExtension.lowercased() == "zip" else { throw AgentSkillError.invalidArchive("ZIPまたはフォルダを選択してください。") }
        let archive: Archive
        do { archive = try Archive(url: source, accessMode: .read) }
        catch { throw AgentSkillError.invalidArchive("ZIPを開けません: \(error.localizedDescription)") }
        var paths = Set<String>()
        var count = 0
        var total: Int64 = 0
        for entry in archive {
            let path = try Self.normalizedRelativePath(entry.path)
            guard paths.insert(path).inserted else { throw AgentSkillError.duplicatePath("重複パスがあります: \(path)") }
            if entry.type == .symlink { throw AgentSkillError.symbolicLink("シンボリックリンクは使用できません: \(path)") }
            if entry.type == .file {
                count += 1
                let bytes = Int64(entry.uncompressedSize)
                total += bytes
                guard count <= AgentSkillLimits.fileCount else { throw AgentSkillError.limitExceeded("ファイル数は500以下にしてください。") }
                guard bytes <= AgentSkillLimits.singleFileBytes else { throw AgentSkillError.limitExceeded("1ファイルは25 MB以下にしてください: \(path)") }
                guard total <= AgentSkillLimits.expandedBytes else { throw AgentSkillError.limitExceeded("展開後合計は200 MB以下にしてください。") }
            }
            let target = destination.appendingPathComponent(path)
            if entry.type == .directory {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                do { _ = try archive.extract(entry, to: target) }
                catch { throw AgentSkillError.invalidArchive("ZIPの展開に失敗しました: \(path)") }
            }
        }
    }

    private func copyValidatedFolder(from source: URL, to destination: URL) throws {
        guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            throw AgentSkillError.invalidArchive("フォルダを読み込めません。")
        }
        var count = 0
        var total: Int64 = 0
        var paths = Set<String>()
        while let url = enumerator.nextObject() as? URL {
            let relative = String(url.path.dropFirst(source.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let path = try Self.normalizedRelativePath(relative)
            guard paths.insert(path).inserted else { throw AgentSkillError.duplicatePath("重複パスがあります: \(path)") }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true { throw AgentSkillError.symbolicLink("シンボリックリンクは使用できません: \(path)") }
            let target = destination.appendingPathComponent(path)
            if values.isDirectory == true {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                count += 1
                let bytes = Int64(values.fileSize ?? 0)
                total += bytes
                guard count <= AgentSkillLimits.fileCount else { throw AgentSkillError.limitExceeded("ファイル数は500以下にしてください。") }
                guard bytes <= AgentSkillLimits.singleFileBytes else { throw AgentSkillError.limitExceeded("1ファイルは25 MB以下にしてください: \(path)") }
                guard total <= AgentSkillLimits.expandedBytes else { throw AgentSkillError.limitExceeded("合計は200 MB以下にしてください。") }
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: url, to: target)
            }
        }
    }

    private func locateSkillRoot(in extracted: URL) throws -> URL {
        guard let enumerator = fileManager.enumerator(at: extracted, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            throw AgentSkillError.invalidSkillFile("SKILL.mdを検索できません。")
        }
        var matches: [URL] = []
        while let url = enumerator.nextObject() as? URL, matches.count < 2 {
            if url.lastPathComponent == "SKILL.md" { matches.append(url) }
        }
        guard matches.count == 1, let match = matches.first else {
            throw AgentSkillError.invalidSkillFile(matches.isEmpty ? "SKILL.mdがありません。" : "複数のSKILL.mdはインストールできません。")
        }
        return match.deletingLastPathComponent()
    }

    private func parseAndInventory(root: URL) throws -> (manifest: AgentSkillManifest, files: [AgentSkillFile], hash: String, externalURLs: [String]) {
        let skillURL = root.appendingPathComponent("SKILL.md")
        let markdown = try readUTF8(url: skillURL, limit: AgentSkillLimits.skillFileBytes)
        let manifest = try Self.parseManifest(markdown)
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            throw AgentSkillError.invalidSkillFile("Skillのファイル一覧を取得できません。")
        }
        var files: [AgentSkillFile] = []
        var hashParts: [String] = []
        var urls = Set<String>()
        let urlRegex = try? NSRegularExpression(pattern: #"https?://[^\s)\]>\"']+"#)
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true { throw AgentSkillError.symbolicLink("シンボリックリンクは使用できません。") }
            guard values.isRegularFile == true else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            if relative == "state.json" { continue }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let script = Self.isScript(path: relative, data: data)
            files.append(AgentSkillFile(path: relative, size: Int64(data.count), isScript: script))
            hashParts.append(relative + ":" + SHA256.hash(data: data).hex)
            if data.count <= Int(AgentSkillLimits.textResourceBytes), let text = String(data: data, encoding: .utf8), let urlRegex {
                let range = NSRange(text.startIndex..., in: text)
                for match in urlRegex.matches(in: text, range: range) {
                    if let matchRange = Range(match.range, in: text) { urls.insert(String(text[matchRange])) }
                }
            }
        }
        return (manifest, files.sorted { $0.path < $1.path }, Self.hashStrings(hashParts.sorted()), urls.sorted())
    }

    private static func parseManifest(_ markdown: String) throws -> AgentSkillManifest {
        let lines = markdown.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) else {
            throw AgentSkillError.invalidManifest("SKILL.mdのYAMLフロントマターがありません。")
        }
        let yamlText = lines[1..<end].joined(separator: "\n")
        let raw: Any
        do {
            guard let loaded = try Yams.load(yaml: yamlText) else {
                throw AgentSkillError.invalidManifest("YAMLフロントマターが空です。")
            }
            raw = loaded
        }
        catch { throw AgentSkillError.invalidManifest("YAMLを解析できません: \(error.localizedDescription)") }
        guard let mapping = raw as? [String: Any] else { throw AgentSkillError.invalidManifest("フロントマターはマップ形式で記述してください。") }
        guard let name = mapping["name"] as? String,
              name.range(of: #"^[a-z0-9][a-z0-9-]{0,63}$"#, options: .regularExpression) != nil else {
            throw AgentSkillError.invalidManifest("nameは小文字英数字とハイフンで1〜64文字にしてください。")
        }
        guard let description = mapping["description"] as? String, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentSkillError.invalidManifest("descriptionは必須です。")
        }
        let metadata = (mapping["metadata"] as? [String: Any])?.reduce(into: [String: String]()) { result, pair in
            result[pair.key] = String(describing: pair.value)
        } ?? [:]
        let allowed: [String]
        if let value = mapping["allowed-tools"] as? [String] { allowed = value }
        else if let value = mapping["allowed-tools"] as? String { allowed = value.split(whereSeparator: \.isWhitespace).map(String.init) }
        else { allowed = [] }
        return AgentSkillManifest(
            name: name,
            description: description,
            license: mapping["license"].map { String(describing: $0) },
            compatibility: mapping["compatibility"].map { String(describing: $0) },
            metadata: metadata,
            allowedTools: allowed
        )
    }

    private func readUTF8(url: URL, limit: Int64) throws -> String {
        guard fileManager.fileExists(atPath: url.path) else { throw AgentSkillError.notFound("ファイルが見つかりません: \(url.lastPathComponent)") }
        let size = Int64((try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard size <= limit else { throw AgentSkillError.limitExceeded("ファイルが読込上限を超えています: \(url.lastPathComponent)") }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8), !text.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw AgentSkillError.resourceNotText("UTF-8テキスト資料だけを読み込めます: \(url.lastPathComponent)")
        }
        return text
    }

    private func skillURL(named name: String) -> URL { rootURL.appendingPathComponent(name, isDirectory: true) }

    private static func normalizedRelativePath(_ raw: String) throws -> String {
        let value = raw.replacingOccurrences(of: "\\", with: "/")
        guard !value.isEmpty, !value.hasPrefix("/"), !value.hasPrefix("~"),
              value.range(of: #"^[A-Za-z]:/"#, options: .regularExpression) == nil else {
            throw AgentSkillError.unsafePath("絶対パスは使用できません: \(raw)")
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty, !components.contains(".."), !components.contains("."), !components.first!.contains(":") else {
            throw AgentSkillError.unsafePath("安全でないパスです: \(raw)")
        }
        return components.joined(separator: "/")
    }

    private static func isScript(path: String, data: Data) -> Bool {
        let extensions = Set(["sh", "bash", "zsh", "fish", "py", "rb", "pl", "js", "mjs", "cjs", "ts", "ps1", "bat", "cmd", "exe"])
        if extensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) { return true }
        return String(data: data.prefix(128), encoding: .utf8)?.hasPrefix("#!") == true
    }

    private static func hashStrings(_ values: [String]) -> String {
        SHA256.hash(data: Data(values.joined(separator: "\n").utf8)).hex
    }
}

private extension JSONEncoder {
    static var agentSkill: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var agentSkill: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
