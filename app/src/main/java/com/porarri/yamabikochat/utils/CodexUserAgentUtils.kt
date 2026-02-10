package com.porarri.yamabikochat.utils

object CodexUserAgentUtils {
    const val PRESET_ANDROID = "ANDROID"
    const val PRESET_UBUNTU = "UBUNTU"
    const val PRESET_WINDOWS_POWERSHELL = "WINDOWS_POWERSHELL"
    const val PRESET_WINDOWS_CMD = "WINDOWS_CMD"

    const val DEFAULT_CODEX_CLI_VERSION = "0.87.0"

    data class UaParts(
        val osName: String,
        val osVersion: String,
        val arch: String,
        val terminalUa: String
    )

    fun resolveParts(
        preset: String?,
        androidOsVersion: String,
        androidAbi: String
    ): UaParts {
        return when (preset?.uppercase()) {
            PRESET_ANDROID -> UaParts(
                osName = "Android",
                osVersion = androidOsVersion,
                arch = androidAbi,
                terminalUa = "unknown"
            )
            PRESET_UBUNTU -> UaParts(
                osName = "Ubuntu",
                osVersion = "22.04",
                arch = "x86_64",
                terminalUa = "unknown"
            )
            PRESET_WINDOWS_POWERSHELL -> UaParts(
                osName = "Windows",
                osVersion = "10.0.22631",
                arch = "x86_64",
                terminalUa = "powershell/5.1"
            )
            PRESET_WINDOWS_CMD -> UaParts(
                osName = "Windows",
                osVersion = "10.0.22631",
                arch = "x86_64",
                terminalUa = "cmd/10.0"
            )
            else -> UaParts(
                osName = "Android",
                osVersion = androidOsVersion,
                arch = androidAbi,
                terminalUa = "unknown"
            )
        }
    }

    fun buildUserAgent(
        originator: String,
        cliVersion: String,
        preset: String?,
        androidOsVersion: String,
        androidAbi: String,
        androidAppId: String? = null,
        androidAppVersion: String? = null
    ): String {
        val parts = resolveParts(preset, androidOsVersion, androidAbi)
        val presetKey = preset?.uppercase()
        val terminal = if (presetKey == null || presetKey == PRESET_ANDROID) {
            val appId = androidAppId?.takeIf { it.isNotBlank() }
            val appVersion = androidAppVersion?.takeIf { it.isNotBlank() }
            when {
                appId != null && appVersion != null -> "${appId}/${appVersion}"
                appId != null -> appId
                else -> parts.terminalUa
            }
        } else {
            parts.terminalUa
        }
        return "${originator}/${cliVersion} (${parts.osName} ${parts.osVersion}; ${parts.arch}) ${terminal}"
    }
}
