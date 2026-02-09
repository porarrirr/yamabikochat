package com.porarri.yamabikochat.ui.preview

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi
import androidx.compose.material3.windowsizeclass.WindowSizeClass
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.ui.adaptive.DevicePosture
import com.porarri.yamabikochat.ui.adaptive.LocalWindowAdaptiveInfo
import com.porarri.yamabikochat.ui.adaptive.WindowAdaptiveInfo
import com.porarri.yamabikochat.ui.theme.MyApplicationTheme

@OptIn(ExperimentalMaterial3WindowSizeClassApi::class)
private fun previewAdaptiveInfo(): WindowAdaptiveInfo {
    val windowSizeClass = WindowSizeClass.calculateFromSize(DpSize(411.dp, 891.dp))
    return WindowAdaptiveInfo(
        windowSizeClass = windowSizeClass,
        displayFeatures = emptyList(),
        devicePosture = DevicePosture.Normal
    )
}

@Composable
fun YamabikoPreview(
    darkTheme: Boolean = false,
    provideAdaptiveInfo: Boolean = false,
    content: @Composable () -> Unit
) {
    MyApplicationTheme(darkTheme = darkTheme, dynamicColor = false) {
        val body: @Composable () -> Unit = {
            Surface(
                modifier = Modifier,
                color = MaterialTheme.colorScheme.background
            ) {
                content()
            }
        }

        if (provideAdaptiveInfo) {
            CompositionLocalProvider(LocalWindowAdaptiveInfo provides previewAdaptiveInfo()) {
                body()
            }
        } else {
            body()
        }
    }
}
