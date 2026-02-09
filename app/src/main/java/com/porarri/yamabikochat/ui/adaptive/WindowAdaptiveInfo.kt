package com.porarri.yamabikochat.ui.adaptive

import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi
import androidx.compose.material3.windowsizeclass.WindowSizeClass
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.window.layout.DisplayFeature
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import kotlinx.coroutines.flow.map

/**
 * Represents the current device posture for foldable-aware layouts.
 */
sealed interface DevicePosture {
    /** Standard flat or unfolded posture with no separating hinge. */
    data object Normal : DevicePosture

    /** Book mode with a vertical hinge separating two pages. */
    data class Book(val feature: FoldingFeature) : DevicePosture

    /** Table-top (aka flex) mode with a horizontal hinge. */
    data class TableTop(val feature: FoldingFeature) : DevicePosture

    /** Flat but separating hinge (e.g., dual screen). */
    data class Separating(val feature: FoldingFeature) : DevicePosture
}

@Stable
data class WindowAdaptiveInfo(
    val windowSizeClass: WindowSizeClass,
    val displayFeatures: List<DisplayFeature>,
    val devicePosture: DevicePosture
) {
    val foldingFeature: FoldingFeature? = displayFeatures.filterIsInstance<FoldingFeature>().firstOrNull()
}

val LocalWindowAdaptiveInfo = staticCompositionLocalOf<WindowAdaptiveInfo> {
    error("WindowAdaptiveInfo not provided")
}

@OptIn(ExperimentalMaterial3WindowSizeClassApi::class)
@Composable
fun rememberWindowAdaptiveInfo(activity: ComponentActivity): WindowAdaptiveInfo {
    val windowSizeClass = calculateWindowSizeClass(activity)

    val windowLayoutInfoFlow = remember(activity) {
        WindowInfoTracker.getOrCreate(activity).windowLayoutInfo(activity)
    }

    val displayFeaturesFlow = remember(windowLayoutInfoFlow) {
        windowLayoutInfoFlow.map { it.displayFeatures }
    }
    val displayFeatures by displayFeaturesFlow.collectAsStateWithLifecycle(initialValue = emptyList(), lifecycleOwner = activity)

    val posture = remember(displayFeatures) {
        displayFeatures
            .filterIsInstance<FoldingFeature>()
            .firstOrNull()
            ?.let { foldingFeature ->
                when {
                    foldingFeature.state == FoldingFeature.State.HALF_OPENED &&
                        foldingFeature.orientation == FoldingFeature.Orientation.VERTICAL -> DevicePosture.Book(foldingFeature)

                    foldingFeature.state == FoldingFeature.State.HALF_OPENED &&
                        foldingFeature.orientation == FoldingFeature.Orientation.HORIZONTAL -> DevicePosture.TableTop(foldingFeature)

                    foldingFeature.isSeparating -> DevicePosture.Separating(foldingFeature)

                    else -> DevicePosture.Normal
                }
            } ?: DevicePosture.Normal
    }

    return remember(windowSizeClass, displayFeatures, posture) {
        WindowAdaptiveInfo(
            windowSizeClass = windowSizeClass,
            displayFeatures = displayFeatures,
            devicePosture = posture
        )
    }
}


