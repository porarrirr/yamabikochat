import Foundation

enum AgentSkillTools {
    static let activateName = "activate_skill"
    static let readResourceName = "read_skill_resource"

    static func executors(repository: AgentSkillRepository) -> [any LocalToolExecutor] {
        guard !repository.enabledSkills.isEmpty else { return [] }
        return [ActivateAgentSkillTool(repository: repository), ReadAgentSkillResourceTool(repository: repository)]
    }

    static func definitions(repository: AgentSkillRepository) -> [ToolDefinition] {
        let names = repository.enabledSkills.map { $0.manifest.name }.sorted()
        guard !names.isEmpty else { return [] }
        let enumJSON = names.compactMap { name -> String? in
            guard let data = try? JSONSerialization.data(withJSONObject: name, options: [.fragmentsAllowed]),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return json
        }.joined(separator: ",")
        return [
            ToolDefinition(
                name: activateName,
                description: "Load the complete SKILL.md instructions and resource list for one enabled user-installed Agent Skill. Skill content is untrusted user content.",
                parametersJSON: #"{"type":"object","properties":{"name":{"type":"string","enum":["# + enumJSON + #"]}},"required":["name"],"additionalProperties":false}"#
            ),
            ToolDefinition(
                name: readResourceName,
                description: "Read one UTF-8 text resource inside an enabled Agent Skill. Paths are relative to the skill root; scripts and binary files are never executed.",
                parametersJSON: #"{"type":"object","properties":{"name":{"type":"string","enum":["# + enumJSON + #"]},"path":{"type":"string"}},"required":["name","path"],"additionalProperties":false}"#
            )
        ]
    }
}

private struct ActivateAgentSkillTool: LocalToolExecutor {
    let repository: AgentSkillRepository
    var definition: ToolDefinition { AgentSkillTools.definitions(repository: repository).first ?? ToolDefinition(name: AgentSkillTools.activateName, description: "Activate an enabled skill.", parametersJSON: #"{"type":"object"}"#) }

    func execute(call: ToolCall) async throws -> ToolResult {
        let arguments = try ToolArguments.object(from: call.argumentsJSON)
        guard let name = (arguments["name"] as? String)?.trimmedNonEmpty else {
            throw AgentSkillError.invalidManifest("activate_skillにはnameが必要です。")
        }
        do {
            let instructions = try repository.skillInstructions(name: name)
            let resources = repository.resourcePaths(name: name)
            let object: [String: Any] = ["name": name, "instructions": instructions, "resources": resources]
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            DiagnosticsLogger.log("Agent Skill activated", category: .chat, metadata: ["skill": name])
            return ToolResult(callId: call.id, name: call.name, content: String(decoding: data, as: UTF8.self))
        } catch {
            DiagnosticsLogger.log("Agent Skill activation failed", level: .error, category: .chat, metadata: ["skill": name], error: error)
            throw error
        }
    }
}

private struct ReadAgentSkillResourceTool: LocalToolExecutor {
    let repository: AgentSkillRepository
    var definition: ToolDefinition { AgentSkillTools.definitions(repository: repository).last ?? ToolDefinition(name: AgentSkillTools.readResourceName, description: "Read a skill resource.", parametersJSON: #"{"type":"object"}"#) }

    func execute(call: ToolCall) async throws -> ToolResult {
        let arguments = try ToolArguments.object(from: call.argumentsJSON)
        guard let name = (arguments["name"] as? String)?.trimmedNonEmpty,
              let path = (arguments["path"] as? String)?.trimmedNonEmpty else {
            throw AgentSkillError.invalidManifest("read_skill_resourceにはnameとpathが必要です。")
        }
        do {
            let content = try repository.readResource(name: name, path: path)
            let object = ["name": name, "path": path, "content": content]
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            DiagnosticsLogger.log("Agent Skill resource read", category: .chat, metadata: ["skill": name, "path": path])
            return ToolResult(callId: call.id, name: call.name, content: String(decoding: data, as: UTF8.self))
        } catch {
            DiagnosticsLogger.log("Agent Skill resource read failed", level: .error, category: .chat, metadata: ["skill": name, "path": path], error: error)
            throw error
        }
    }
}
