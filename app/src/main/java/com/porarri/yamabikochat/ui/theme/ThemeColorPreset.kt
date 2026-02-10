package com.porarri.yamabikochat.ui.theme

import androidx.compose.ui.graphics.Color

enum class ThemeColorPreset(
    val key: String,
    val label: String,
    val seedColor: Color
) {
    BluePurple("BLUE_PURPLE", "青紫", Color(0xFF5A5FCF)),
    Blue("BLUE", "青", Color(0xFF1976D2)),
    Green("GREEN", "緑", Color(0xFF2E7D32)),
    Yellow("YELLOW", "黄色", Color(0xFFF9A825)),
    Pink("PINK", "ピンク", Color(0xFFD81B60)),
    Orange("ORANGE", "オレンジ", Color(0xFFF57C00)),
    Black("BLACK", "黒", Color(0xFF212121));

    companion object {
        const val KEY_DYNAMIC = "DYNAMIC"

        fun fromKey(key: String?): ThemeColorPreset {
            val normalized = key?.trim()?.uppercase().orEmpty()
            return entries.firstOrNull { it.key == normalized } ?: BluePurple
        }
    }
}

