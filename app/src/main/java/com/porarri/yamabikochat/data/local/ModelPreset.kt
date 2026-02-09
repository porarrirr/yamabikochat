package com.porarri.yamabikochat.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "model_presets")
data class ModelPreset(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val name: String,
    val model: String,
    val systemPrompt: String?,
    val systemPromptPresetName: String? = null,
    val thinkingEnabled: Boolean = false,
    val thinkingBudget: Int = 0,
    val thinkingLevel: String = "",
    val googleSearchEnabled: Boolean = false,
    val codeExecutionEnabled: Boolean = false,
    val urlContextEnabled: Boolean = false,
    val googleMapsEnabled: Boolean = false,
    val computerUseEnabled: Boolean = false,
    val responseMimeType: String = "",
    val responseJsonSchema: String = "",
    val functionDeclarations: String = "",
    val apiProvider: String = "GEMINI", // "GEMINI" or "OPENROUTER"
    val reasoningMode: String = "auto", // auto | effort | budget
    val reasoningEffort: String = "",
    val reasoningExclude: Boolean = false,
    val codexReasoningSummary: String = "auto",
    val codexVerbosity: String = "medium",
    val codexWebSearchEnabled: Boolean = false,
    val codexWebSearchContextSize: String = "medium",
    val codexPromptCacheEnabled: Boolean = true,
    val codexPromptCacheMinLength: Int = 512,
    val codexPromptCacheType: String = "ephemeral",
    val codexShowReasoningSummary: Boolean = true,
    val codexSupportsReasoningSummaries: Boolean = false,
    val openAiCompatPresetName: String? = null
)
