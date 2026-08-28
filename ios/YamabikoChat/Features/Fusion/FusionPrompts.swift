import Foundation

enum FusionPrompts {
    static let panelBase = """
        You are one member of an analysis panel. Answer the user's request independently. Be precise. State uncertainty. Include assumptions. Do not mention other models.
        """

    static let judgeJSONSchema = """
        {
          "consensus": ["..."],
          "contradictions": [
            {
              "topic": "...",
              "positions": ["..."],
              "likely_resolution": "...",
              "confidence": "low|medium|high"
            }
          ],
          "unique_insights": [
            {
              "model": "...",
              "insight": "...",
              "use_in_final": true
            }
          ],
          "coverage_gaps": ["..."],
          "suspected_errors": [
            {
              "model": "...",
              "claim": "...",
              "reason": "..."
            }
          ],
          "strongest_answer_parts": [
            {
              "model": "...",
              "part": "...",
              "reason": "..."
            }
          ],
          "recommended_final_position": "...",
          "confidence": "low|medium|high"
        }
        """

    static func panelSystemPrompt() -> String {
        panelBase
    }

    static func judgeSystemPrompt() -> String {
        """
        You are a judge comparing independent panel answers. Do not write the final answer for the user.
        Compare answers critically. Identify disagreements and likely errors. Do not merge answers blindly.
        Return structured JSON only matching the required schema. No markdown fences. No prose outside JSON.
        Required schema:
        \(judgeJSONSchema)
        """
    }

    static func judgeUserPrompt(
        userPrompt: String,
        successfulPanels: [PanelResult],
        failedModels: [String]
    ) -> String {
        var sections: [String] = []
        sections.append("Original user request:\n\(userPrompt)")
        sections.append("Successful panel answers:")
        for panel in successfulPanels {
            let label = panel.role.map { "\(panel.modelId) (\($0))" } ?? panel.modelId
            sections.append("--- \(label) ---\n\(panel.content)")
        }
        if !failedModels.isEmpty {
            sections.append("Failed models (no output): \(failedModels.joined(separator: ", "))")
        }
        sections.append("Compare these answers. Return JSON only.")
        return sections.joined(separator: "\n\n")
    }

    static func jsonRepairPrompt(invalidJSON: String) -> String {
        """
        Repair this JSON only. Return valid JSON matching the judge schema. No markdown. No explanation.
        Invalid JSON:
        \(invalidJSON)
        """
    }

    static func synthesizerSystemPrompt(debugMode: Bool) -> String {
        if debugMode {
            return """
            You write the final user-facing answer using judge analysis and raw panel outputs.
            Answer the user directly. Use strong consensus where supported. State remaining uncertainty.
            You may reference panel model names for debugging.
            Do not say "the panel said" unless summarizing disagreement.
            """
        }
        return """
        You write the final user-facing answer using judge analysis and raw panel outputs.
        Answer the user directly. Use strong consensus where supported. State remaining uncertainty.
        Do not expose internal model names. Do not say "the panel said" or reference multiple AI systems.
        Avoid presenting weakly supported claims as certain.
        """
    }

    static func synthesizerUserPrompt(
        userPrompt: String,
        judgeAnalysis: JudgeAnalysis?,
        rawPanels: [PanelResult],
        judgeParseFailed: Bool
    ) -> String {
        var sections: [String] = []
        sections.append("User request:\n\(userPrompt)")
        if let judgeAnalysis {
            if let data = try? JSONEncoder().encode(judgeAnalysis),
               let json = String(data: data, encoding: .utf8) {
                sections.append("Judge analysis (JSON):\n\(json)")
            }
        } else if judgeParseFailed {
            sections.append("Judge analysis unavailable. Synthesize directly from panel outputs.")
        }
        sections.append("Raw panel outputs:")
        for panel in rawPanels where panel.success {
            sections.append("--- \(panel.modelId) ---\n\(panel.content)")
        }
        sections.append("Write the final answer for the user.")
        return sections.joined(separator: "\n\n")
    }

    static func synthesizerUserPromptWithoutJudge(
        userPrompt: String,
        rawPanels: [PanelResult]
    ) -> String {
        synthesizerUserPrompt(
            userPrompt: userPrompt,
            judgeAnalysis: nil,
            rawPanels: rawPanels,
            judgeParseFailed: true
        )
    }
}
