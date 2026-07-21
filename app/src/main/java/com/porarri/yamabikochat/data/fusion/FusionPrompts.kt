package com.porarri.yamabikochat.data.fusion

object FusionPrompts {
    val panelBase = """
        You are one member of an analysis panel. Answer the user's request independently. Be precise. State uncertainty. Include assumptions. Do not mention other models.
        """.trimIndent()

    val researchAddendum = """
        Structure your answer with:
        - Direct answer
        - Evidence
        - Assumptions
        - Uncertainty
        - Missing information
        - Possible counterarguments
        """.trimIndent()

    val codingAddendum = """
        Structure your answer with:
        - Diagnosis
        - Proposed implementation
        - Risks
        - Tests
        - Edge cases
        """.trimIndent()

    val judgeJSONSchema = """
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
        """.trimIndent()

    fun panelSystemPrompt(taskType: FusionTaskType): String {
        return when (taskType) {
            FusionTaskType.coding -> panelBase + "\n\n" + codingAddendum
            FusionTaskType.research, FusionTaskType.auto -> panelBase + "\n\n" + researchAddendum
        }
    }

    fun judgeSystemPrompt(): String {
        return """
        You are a judge comparing independent panel answers. Do not write the final answer for the user.
        Compare answers critically. Identify disagreements and likely errors. Do not merge answers blindly.
        Return structured JSON only matching the required schema. No markdown fences. No prose outside JSON.
        Required schema:
        $judgeJSONSchema
        """.trimIndent()
    }

    fun judgeUserPrompt(
        userPrompt: String,
        successfulPanels: List<PanelResult>,
        failedModels: List<String>
    ): String {
        val sections = mutableListOf<String>()
        sections.add("Original user request:\n$userPrompt")
        sections.add("Successful panel answers:")
        for (panel in successfulPanels) {
            val label = panel.role?.let { "${panel.modelId} ($it)" } ?: panel.modelId
            sections.add("--- $label ---\n${panel.content}")
        }
        if (failedModels.isNotEmpty()) {
            sections.add("Failed models (no output): ${failedModels.joinToString(", ")}")
        }
        sections.add("Compare these answers. Return JSON only.")
        return sections.joinToString("\n\n")
    }

    fun jsonRepairPrompt(invalidJSON: String): String {
        return """
        Repair this JSON only. Return valid JSON matching the judge schema. No markdown. No explanation.
        Invalid JSON:
        $invalidJSON
        """.trimIndent()
    }

    fun synthesizerSystemPrompt(debugMode: Boolean): String {
        return if (debugMode) {
            """
            You write the final user-facing answer using judge analysis and raw panel outputs.
            Answer the user directly. Use strong consensus where supported. State remaining uncertainty.
            You may reference panel model names for debugging.
            Do not say "the panel said" unless summarizing disagreement.
            """.trimIndent()
        } else {
            """
            You write the final user-facing answer using judge analysis and raw panel outputs.
            Answer the user directly. Use strong consensus where supported. State remaining uncertainty.
            Do not expose internal model names. Do not say "the panel said" or reference multiple AI systems.
            Avoid presenting weakly supported claims as certain.
            """.trimIndent()
        }
    }

    fun synthesizerUserPrompt(
        userPrompt: String,
        judgeAnalysis: JudgeAnalysis?,
        rawPanels: List<PanelResult>,
        judgeParseFailed: Boolean
    ): String {
        val sections = mutableListOf<String>()
        sections.add("User request:\n$userPrompt")
        if (judgeAnalysis != null) {
            val json = FusionJudgeParser.encodeJudgeAnalysis(judgeAnalysis)
            if (json != null) {
                sections.add("Judge analysis (JSON):\n$json")
            }
        } else if (judgeParseFailed) {
            sections.add("Judge analysis unavailable. Synthesize directly from panel outputs.")
        }
        sections.add("Raw panel outputs:")
        for (panel in rawPanels.filter { it.success }) {
            sections.add("--- ${panel.modelId} ---\n${panel.content}")
        }
        sections.add("Write the final answer for the user.")
        return sections.joinToString("\n\n")
    }

    fun synthesizerUserPromptWithoutJudge(
        userPrompt: String,
        rawPanels: List<PanelResult>
    ): String = synthesizerUserPrompt(
        userPrompt = userPrompt,
        judgeAnalysis = null,
        rawPanels = rawPanels,
        judgeParseFailed = true
    )
}
