package com.porarri.yamabikochat.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.compose.foundation.isSystemInDarkTheme

private val DarkColorScheme = darkColorScheme(
    primary = YamabikoDarkPrimary,
    onPrimary = YamabikoDarkOnPrimary,
    primaryContainer = YamabikoDarkPrimaryContainer,
    onPrimaryContainer = YamabikoDarkOnPrimaryContainer,
    secondary = YamabikoDarkSecondary,
    onSecondary = YamabikoDarkOnSecondary,
    secondaryContainer = YamabikoDarkSecondaryContainer,
    onSecondaryContainer = YamabikoDarkOnSecondaryContainer,
    tertiary = YamabikoDarkTertiary,
    onTertiary = YamabikoDarkOnTertiary,
    tertiaryContainer = YamabikoDarkTertiaryContainer,
    onTertiaryContainer = YamabikoDarkOnTertiaryContainer,
    background = YamabikoDarkBackground,
    onBackground = YamabikoDarkOnBackground,
    surface = YamabikoDarkSurface,
    onSurface = YamabikoDarkOnSurface,
    surfaceVariant = YamabikoDarkSurfaceVariant,
    onSurfaceVariant = YamabikoDarkOnSurfaceVariant,
    outline = YamabikoDarkOutline,
    outlineVariant = YamabikoDarkOutlineVariant
)

private val LightColorScheme = lightColorScheme(
    primary = YamabikoLightPrimary,
    onPrimary = YamabikoLightOnPrimary,
    primaryContainer = YamabikoLightPrimaryContainer,
    onPrimaryContainer = YamabikoLightOnPrimaryContainer,
    secondary = YamabikoLightSecondary,
    onSecondary = YamabikoLightOnSecondary,
    secondaryContainer = YamabikoLightSecondaryContainer,
    onSecondaryContainer = YamabikoLightOnSecondaryContainer,
    tertiary = YamabikoLightTertiary,
    onTertiary = YamabikoLightOnTertiary,
    tertiaryContainer = YamabikoLightTertiaryContainer,
    onTertiaryContainer = YamabikoLightOnTertiaryContainer,
    background = YamabikoLightBackground,
    onBackground = YamabikoLightOnBackground,
    surface = YamabikoLightSurface,
    onSurface = YamabikoLightOnSurface,
    surfaceVariant = YamabikoLightSurfaceVariant,
    onSurfaceVariant = YamabikoLightOnSurfaceVariant,
    outline = YamabikoLightOutline,
    outlineVariant = YamabikoLightOutlineVariant
)

@Composable
fun MyApplicationTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    // Dynamic color is available on Android 12+
    dynamicColor: Boolean = true,
    themeColor: ThemeColorPreset = ThemeColorPreset.BluePurple,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {     
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }

        darkTheme -> staticDarkColorScheme(themeColor)
        else -> staticLightColorScheme(themeColor)
    }
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val activity = (view.context as? Activity)
            if (activity != null) {
                val window = activity.window
                window.statusBarColor = colorScheme.surface.toArgb()
                window.navigationBarColor = colorScheme.surface.toArgb()
                val controller = WindowCompat.getInsetsController(window, view)
                controller.isAppearanceLightStatusBars = !darkTheme
                controller.isAppearanceLightNavigationBars = !darkTheme
            }
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        shapes = Shapes,
        content = content
    )
}

private fun staticLightColorScheme(themeColor: ThemeColorPreset): ColorScheme {
    return when (themeColor) {
        ThemeColorPreset.BluePurple -> LightColorScheme
        else -> seededLightColorScheme(themeColor.seedColor)
    }
}

private fun staticDarkColorScheme(themeColor: ThemeColorPreset): ColorScheme {
    return when (themeColor) {
        ThemeColorPreset.BluePurple -> DarkColorScheme
        else -> seededDarkColorScheme(themeColor.seedColor)
    }
}

private fun seededLightColorScheme(seed: Color): ColorScheme {
    val primary = seed
    val onPrimary = autoOnColor(primary)
    val primaryContainer = blend(primary, Color.White, 0.82f)
    val onPrimaryContainer = autoOnColor(primaryContainer)

    return lightColorScheme(
        primary = primary,
        onPrimary = onPrimary,
        primaryContainer = primaryContainer,
        onPrimaryContainer = onPrimaryContainer,
        secondary = YamabikoLightSecondary,
        onSecondary = YamabikoLightOnSecondary,
        secondaryContainer = YamabikoLightSecondaryContainer,
        onSecondaryContainer = YamabikoLightOnSecondaryContainer,
        tertiary = YamabikoLightTertiary,
        onTertiary = YamabikoLightOnTertiary,
        tertiaryContainer = YamabikoLightTertiaryContainer,
        onTertiaryContainer = YamabikoLightOnTertiaryContainer,
        background = YamabikoLightBackground,
        onBackground = YamabikoLightOnBackground,
        surface = YamabikoLightSurface,
        onSurface = YamabikoLightOnSurface,
        surfaceVariant = YamabikoLightSurfaceVariant,
        onSurfaceVariant = YamabikoLightOnSurfaceVariant,
        outline = YamabikoLightOutline,
        outlineVariant = YamabikoLightOutlineVariant
    )
}

private fun seededDarkColorScheme(seed: Color): ColorScheme {
    val primary = blend(seed, Color.White, 0.55f)
    val onPrimary = autoOnColor(primary)
    val primaryContainer = blend(seed, Color.Black, 0.50f)
    val onPrimaryContainer = autoOnColor(primaryContainer)

    return darkColorScheme(
        primary = primary,
        onPrimary = onPrimary,
        primaryContainer = primaryContainer,
        onPrimaryContainer = onPrimaryContainer,
        secondary = YamabikoDarkSecondary,
        onSecondary = YamabikoDarkOnSecondary,
        secondaryContainer = YamabikoDarkSecondaryContainer,
        onSecondaryContainer = YamabikoDarkOnSecondaryContainer,
        tertiary = YamabikoDarkTertiary,
        onTertiary = YamabikoDarkOnTertiary,
        tertiaryContainer = YamabikoDarkTertiaryContainer,
        onTertiaryContainer = YamabikoDarkOnTertiaryContainer,
        background = YamabikoDarkBackground,
        onBackground = YamabikoDarkOnBackground,
        surface = YamabikoDarkSurface,
        onSurface = YamabikoDarkOnSurface,
        surfaceVariant = YamabikoDarkSurfaceVariant,
        onSurfaceVariant = YamabikoDarkOnSurfaceVariant,
        outline = YamabikoDarkOutline,
        outlineVariant = YamabikoDarkOutlineVariant
    )
}

private fun autoOnColor(background: Color): Color {
    return if (background.luminance() > 0.5f) Color.Black else Color.White
}

private fun blend(from: Color, to: Color, ratio: Float): Color {
    val r = ratio.coerceIn(0f, 1f)
    return Color(
        red = from.red + (to.red - from.red) * r,
        green = from.green + (to.green - from.green) * r,
        blue = from.blue + (to.blue - from.blue) * r,
        alpha = from.alpha + (to.alpha - from.alpha) * r
    )
}
