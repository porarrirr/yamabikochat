import Foundation

struct SuperGrokModel: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let supportsVision: Bool
    let supportsReasoning: Bool
    let description: String
}

enum SuperGrokModelCatalog {
    static let defaultModel = "grok-4.5"

    static let supportedModels: [SuperGrokModel] = [
        SuperGrokModel(
            id: "grok-build-0.1",
            displayName: "Grok Build 0.1",
            supportsVision: false,
            supportsReasoning: true,
            description: "xAI Grok Build coding model for SuperGrok OAuth."
        ),
        SuperGrokModel(
            id: "grok-4.5",
            displayName: "Grok 4.5",
            supportsVision: true,
            supportsReasoning: true,
            description: "Flagship Grok for code, chat, and agentic tool calling."
        ),
        SuperGrokModel(
            id: "grok-4.3",
            displayName: "Grok 4.3",
            supportsVision: true,
            supportsReasoning: true,
            description: "General-purpose Grok model."
        ),
        SuperGrokModel(
            id: "grok-4.20-0309-reasoning",
            displayName: "Grok 4.20 Reasoning",
            supportsVision: true,
            supportsReasoning: true,
            description: "Reasoning-heavy Grok variant."
        ),
        SuperGrokModel(
            id: "grok-4.20-0309-non-reasoning",
            displayName: "Grok 4.20 Non-Reasoning",
            supportsVision: true,
            supportsReasoning: false,
            description: "Faster non-reasoning Grok variant."
        ),
        SuperGrokModel(
            id: "grok-4.20-multi-agent-0309",
            displayName: "Grok 4.20 Multi-Agent",
            supportsVision: true,
            supportsReasoning: true,
            description: "Multi-agent oriented Grok variant."
        )
    ]

    static func normalizedModelID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("supergrok/") {
            return String(trimmed.dropFirst("supergrok/".count))
        }
        if lower.hasPrefix("xai/") {
            return String(trimmed.dropFirst("xai/".count))
        }
        return trimmed
    }

    static func model(for raw: String) -> SuperGrokModel? {
        let normalized = normalizedModelID(raw).lowercased()
        return supportedModels.first { $0.id.lowercased() == normalized }
    }
}