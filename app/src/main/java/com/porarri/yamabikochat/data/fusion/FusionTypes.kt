package com.porarri.yamabikochat.data.fusion

import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderRequestMessage
import com.porarri.yamabikochat.data.model.ProviderUsage
import com.porarri.yamabikochat.data.model.ToolCall
import com.porarri.yamabikochat.data.local.ToolActivityPayload
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class FusionPhase {
    panel,
    judge,
    synthesizer,
    fallback
}

enum class FusionPanelChipState {
    pending,
    running,
    succeeded,
    failed
}

data class FusionPanelChipStatus(
    val modelId: String,
    val provider: String,
    val state: FusionPanelChipState,
    val toolActivity: ToolActivityPayload? = null
)

data class FusionProgressSnapshot(
    val phase: FusionPhase,
    val panels: List<FusionPanelChipStatus>,
    val completedPanelCount: Int,
    val totalPanelCount: Int,
    val substatus: String? = null
) {
    companion object {
        fun panelPhase(
            panels: List<FusionPanelChipStatus>,
            substatus: String? = null
        ): FusionProgressSnapshot {
            val completed = panels.count {
                it.state == FusionPanelChipState.succeeded || it.state == FusionPanelChipState.failed
            }
            return FusionProgressSnapshot(
                phase = FusionPhase.panel,
                panels = panels,
                completedPanelCount = completed,
                totalPanelCount = panels.size,
                substatus = substatus
            )
        }

        fun initialPanels(from: FusionRequest): List<FusionPanelChipStatus> =
            from.panelModels.map { panel ->
                FusionPanelChipStatus(
                    modelId = panel.modelId,
                    provider = panel.provider.uppercase(),
                    state = FusionPanelChipState.running
                )
            }

        fun phaseOnly(
            phase: FusionPhase,
            panels: List<FusionPanelChipStatus>,
            substatus: String? = null
        ): FusionProgressSnapshot {
            val completed = panels.count {
                it.state == FusionPanelChipState.succeeded || it.state == FusionPanelChipState.failed
            }
            return FusionProgressSnapshot(
                phase = phase,
                panels = panels,
                completedPanelCount = completed,
                totalPanelCount = panels.size,
                substatus = substatus
            )
        }
    }

    fun applyingPanelResult(result: PanelResult): FusionProgressSnapshot {
        val updatedPanels = panels.map { chip ->
            if (chip.modelId == result.modelId) {
                chip.copy(
                    state = if (result.success) {
                        FusionPanelChipState.succeeded
                    } else {
                        FusionPanelChipState.failed
                    },
                    toolActivity = result.toolActivity
                )
            } else {
                chip
            }
        }
        return panelPhase(panels = updatedPanels, substatus = substatus)
    }
}

@Serializable
enum class FusionTaskType {
    @SerialName("research")
    research,
    @SerialName("coding")
    coding,
    @SerialName("auto")
    auto
}

@Serializable
enum class FusionConfidence {
    high,
    medium,
    low;

    companion object {
        fun fromRaw(raw: String?): FusionConfidence = when (raw?.trim()?.lowercase()) {
            "high" -> high
            "medium" -> medium
            "low" -> low
            else -> medium
        }
    }
}

@Serializable
data class PanelModelConfig(
    val modelId: String,
    val provider: String,
    val temperature: Double? = null,
    val timeoutMs: Int? = null,
    val role: String? = "generalist"
)

@Serializable
data class FusionRequest(
    val userPrompt: String,
    val systemPrompt: String? = null,
    val panelModels: List<PanelModelConfig>,
    val judgeModel: PanelModelConfig,
    val synthesizerModel: PanelModelConfig,
    val fallbackModel: PanelModelConfig? = null,
    val preset: String = "custom",
    val maxPanelTokens: Int = 4096,
    val maxJudgeTokens: Int = 2048,
    val maxSynthesizerTokens: Int = 4096,
    val timeoutMs: Int = 120_000,
    val allowWebSearch: Boolean = true,
    val taskType: FusionTaskType = FusionTaskType.auto,
    val metadata: Map<String, String> = emptyMap()
)

@Serializable
data class SerializableToolCall(
    val id: String,
    val name: String,
    val argumentsJSON: String
)

fun ToolCall.toSerializable(): SerializableToolCall =
    SerializableToolCall(id = id, name = name, argumentsJSON = argumentsJSON)

@Serializable
data class PanelResult(
    val modelId: String,
    val provider: String,
    val success: Boolean,
    val content: String,
    val error: String? = null,
    val latencyMs: Long,
    val inputTokens: Int? = null,
    val outputTokens: Int? = null,
    val cost: Double? = null,
    val toolCalls: List<SerializableToolCall>? = null,
    val toolActivity: ToolActivityPayload? = null,
    val finishReason: String? = null,
    val role: String = "generalist"
)

@Serializable
data class JudgeContradiction(
    val topic: String,
    val positions: List<String>,
    val likelyResolution: String,
    val confidence: FusionConfidence
)

@Serializable
data class JudgeUniqueInsight(
    val model: String,
    val insight: String,
    val useInFinal: Boolean
)

@Serializable
data class JudgeSuspectedError(
    val model: String,
    val claim: String,
    val reason: String
)

@Serializable
data class JudgeStrongestPart(
    val model: String,
    val part: String,
    val reason: String
)

@Serializable
data class JudgeAnalysis(
    val consensus: List<String>,
    val contradictions: List<JudgeContradiction>,
    val uniqueInsights: List<JudgeUniqueInsight>,
    val coverageGaps: List<String>,
    val suspectedErrors: List<JudgeSuspectedError>,
    val sourceQualityIssues: List<String>,
    val strongestAnswerParts: List<JudgeStrongestPart>,
    val recommendedFinalPosition: String,
    val confidence: FusionConfidence,
    val notes: String? = null
)

@Serializable
data class JudgePhaseResult(
    val analysis: JudgeAnalysis? = null,
    val rawJSON: String? = null,
    val parseSucceeded: Boolean,
    val latencyMs: Long,
    val inputTokens: Int? = null,
    val outputTokens: Int? = null,
    val cost: Double? = null,
    val error: String? = null
)

@Serializable
data class SynthesisPhaseResult(
    val modelId: String,
    val provider: String,
    val success: Boolean,
    val content: String,
    val latencyMs: Long,
    val inputTokens: Int? = null,
    val outputTokens: Int? = null,
    val cost: Double? = null,
    val error: String? = null,
    val usedFallback: Boolean
)

@Serializable
data class FusionTrace(
    val requestId: String,
    val preset: String,
    val startedAtMs: Long,
    val completedAtMs: Long? = null,
    val panelResults: List<PanelResult>,
    val judgeResult: JudgePhaseResult? = null,
    val synthesisResult: SynthesisPhaseResult? = null,
    val totalLatencyMs: Long? = null,
    val totalCost: Double? = null,
    val failedModels: List<String>,
    val status: String,
    val userPrompt: String? = null,
    val finalAnswer: String? = null
)

data class FusionContext(
    val fusionDepth: Int = 0,
    val debugMode: Boolean = false,
    val logPrompts: Boolean = false,
    val conversationId: Long? = null,
    val clientToolsAllowed: Boolean = true
) {
    companion object {
        const val MAX_FUSION_DEPTH = 1
    }
}

data class FusionRunOptions(
    val taskType: FusionTaskType = FusionTaskType.auto,
    val systemPrompt: String? = null,
    val debugMode: Boolean = false,
    val logPrompts: Boolean = false,
    val fusionDepth: Int = 0,
    val conversationId: Long? = null,
    val allowWebSearch: Boolean? = null
)

data class FusionRunResult(
    val finalAnswer: String,
    val traceId: String,
    val judgeAnalysis: JudgeAnalysis? = null,
    val rawPanelResults: List<PanelResult>? = null,
    val totalLatencyMs: Long? = null,
    val totalCost: Double? = null
)

data class FusionTokenUsageRecord(
    val provider: String,
    val model: String,
    val usage: ProviderUsage?,
    val requestType: String
)

data class FusionJudgeOutcome(
    val trace: FusionTrace,
    val synthesisRequest: ProviderRequest,
    val synthesizerProvider: String,
    val synthesizerModel: PanelModelConfig,
    val staticFallbackAnswer: String,
    val panelTokenUsages: List<FusionTokenUsageRecord>,
    val judgeTokenUsage: FusionTokenUsageRecord?
)

sealed class FusionError(message: String) : Exception(message) {
    data class AllPanelsFailed(val panelResults: List<PanelResult>) :
        FusionError("Fusion: すべてのパネルモデルが失敗しました。")

    data class PresetNotFound(val name: String) :
        FusionError("Fusion: プリセット '$name' が見つかりません。")

    data class InvalidPreset(val reason: String) :
        FusionError("Fusion: 無効なプリセット — $reason")

    data object ServiceDeallocated :
        FusionError("Fusion: サービスが解放されました。")
}

@Serializable
data class JudgeAnalysisDto(
    val consensus: List<String>? = null,
    val contradictions: List<JudgeContradictionDto>? = null,
    @SerialName("unique_insights")
    val uniqueInsights: List<JudgeUniqueInsightDto>? = null,
    @SerialName("coverage_gaps")
    val coverageGaps: List<String>? = null,
    @SerialName("suspected_errors")
    val suspectedErrors: List<JudgeSuspectedErrorDto>? = null,
    @SerialName("source_quality_issues")
    val sourceQualityIssues: List<String>? = null,
    @SerialName("strongest_answer_parts")
    val strongestAnswerParts: List<JudgeStrongestPartDto>? = null,
    @SerialName("recommended_final_position")
    val recommendedFinalPosition: String? = null,
    val confidence: String? = null,
    val notes: String? = null
)

@Serializable
data class JudgeContradictionDto(
    val topic: String? = null,
    val positions: List<String>? = null,
    @SerialName("likely_resolution")
    val likelyResolution: String? = null,
    val confidence: String? = null
)

@Serializable
data class JudgeUniqueInsightDto(
    val model: String? = null,
    val insight: String? = null,
    @SerialName("use_in_final")
    val useInFinal: Boolean? = null
)

@Serializable
data class JudgeSuspectedErrorDto(
    val model: String? = null,
    val claim: String? = null,
    val reason: String? = null
)

@Serializable
data class JudgeStrongestPartDto(
    val model: String? = null,
    val part: String? = null,
    val reason: String? = null
)

fun JudgeAnalysisDto.toJudgeAnalysis(): JudgeAnalysis =
    JudgeAnalysis(
        consensus = consensus.orEmpty(),
        contradictions = contradictions.orEmpty().map {
            JudgeContradiction(
                topic = it.topic.orEmpty(),
                positions = it.positions.orEmpty(),
                likelyResolution = it.likelyResolution.orEmpty(),
                confidence = FusionConfidence.fromRaw(it.confidence)
            )
        },
        uniqueInsights = uniqueInsights.orEmpty().map {
            JudgeUniqueInsight(
                model = it.model.orEmpty(),
                insight = it.insight.orEmpty(),
                useInFinal = it.useInFinal ?: true
            )
        },
        coverageGaps = coverageGaps.orEmpty(),
        suspectedErrors = suspectedErrors.orEmpty().map {
            JudgeSuspectedError(
                model = it.model.orEmpty(),
                claim = it.claim.orEmpty(),
                reason = it.reason.orEmpty()
            )
        },
        sourceQualityIssues = sourceQualityIssues.orEmpty(),
        strongestAnswerParts = strongestAnswerParts.orEmpty().map {
            JudgeStrongestPart(
                model = it.model.orEmpty(),
                part = it.part.orEmpty(),
                reason = it.reason.orEmpty()
            )
        },
        recommendedFinalPosition = recommendedFinalPosition.orEmpty(),
        confidence = FusionConfidence.fromRaw(confidence),
        notes = notes
    )

/** History content for panel phase (role + text + optional attachment paths). */
data class FusionHistoryMessage(
    val role: String,
    val text: String,
    val attachments: List<String> = emptyList()
)
