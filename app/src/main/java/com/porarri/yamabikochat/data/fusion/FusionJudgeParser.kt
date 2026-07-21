package com.porarri.yamabikochat.data.fusion

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

object FusionJudgeParser {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    }

    fun parse(raw: String): JudgeAnalysis? {
        val trimmed = extractJSON(from = raw)
        if (trimmed.isEmpty()) return null
        return runCatching {
            json.decodeFromString(JudgeAnalysisDto.serializer(), trimmed).toJudgeAnalysis()
        }.getOrNull()
    }

    fun extractJSON(from: String): String {
        var candidate = from.trim()
        if (candidate.startsWith("```")) {
            candidate = candidate
                .replace("```json", "")
                .replace("```", "")
                .trim()
        }
        val start = candidate.indexOf('{')
        val end = candidate.lastIndexOf('}')
        if (start >= 0 && end > start) {
            return candidate.substring(start, end + 1)
        }
        return candidate
    }

    fun encodeJudgeAnalysis(analysis: JudgeAnalysis): String? {
        return runCatching {
            json.encodeToString(JudgeAnalysis.serializer(), analysis)
        }.getOrNull()
    }
}
