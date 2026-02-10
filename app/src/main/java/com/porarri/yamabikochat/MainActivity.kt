package com.porarri.yamabikochat

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import com.porarri.yamabikochat.overlay.OverlayService
import com.porarri.yamabikochat.ui.MainScreen
import com.porarri.yamabikochat.ui.adaptive.LocalWindowAdaptiveInfo
import com.porarri.yamabikochat.ui.adaptive.rememberWindowAdaptiveInfo
import com.porarri.yamabikochat.ui.theme.MyApplicationTheme
import com.porarri.yamabikochat.ui.theme.ThemeColorPreset

class MainActivity : ComponentActivity() {
    private val initialPromptState = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initialPromptState.value = intent?.getStringExtra(OverlayService.EXTRA_INITIAL_PROMPT)
        setContent {
            val adaptiveInfo = rememberWindowAdaptiveInfo(this)
            val app = applicationContext as MyApplication
            val settings by app.repository.getSettings().collectAsState(initial = null)
            val dynamicColorEnabled = settings?.dynamicColorEnabled ?: true     
            val themeColor = ThemeColorPreset.fromKey(settings?.themeColor)
            val themeMode = settings?.themeMode?.uppercase() ?: "SYSTEM"        
            val darkTheme = when (themeMode) {
                "LIGHT" -> false
                "DARK" -> true
                else -> isSystemInDarkTheme()
            }
            MyApplicationTheme(
                darkTheme = darkTheme,
                dynamicColor = dynamicColorEnabled,
                themeColor = themeColor
            ) {
                CompositionLocalProvider(LocalWindowAdaptiveInfo provides adaptiveInfo) {
                    Surface(
                        modifier = Modifier.fillMaxSize(),
                        color = MaterialTheme.colorScheme.background
                    ) {
                        MainScreen(
                            initialPrompt = initialPromptState.value,
                            onInitialPromptConsumed = { initialPromptState.value = null }
                        )
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        initialPromptState.value = intent.getStringExtra(OverlayService.EXTRA_INITIAL_PROMPT)
    }
}
