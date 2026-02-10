package com.porarri.yamabikochat.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.window.layout.FoldingFeature
import com.porarri.yamabikochat.ui.adaptive.DevicePosture
import com.porarri.yamabikochat.ui.adaptive.LocalWindowAdaptiveInfo
import com.porarri.yamabikochat.ui.conversation.ConversationListScreen
import com.porarri.yamabikochat.ui.navigation.NavGraph
import kotlin.math.abs

@Composable
fun MainScreen(
    initialPrompt: String? = null,
    onInitialPromptConsumed: () -> Unit = {}
) {
    val navController = rememberNavController()
    val adaptiveInfo = LocalWindowAdaptiveInfo.current
    val density = LocalDensity.current

    val widthClass = adaptiveInfo.windowSizeClass.widthSizeClass
    val isDualPaneWidth = widthClass != WindowWidthSizeClass.Compact
    val isBookPosture = adaptiveInfo.devicePosture is DevicePosture.Book
    val isSeparating = adaptiveInfo.devicePosture is DevicePosture.Separating
    val isDualPane = isDualPaneWidth || isBookPosture || isSeparating
    val isTableTop = adaptiveInfo.devicePosture is DevicePosture.TableTop

    val verticalFeature = when (val posture = adaptiveInfo.devicePosture) {
        is DevicePosture.Book -> posture.feature
        is DevicePosture.Separating -> posture.feature
        else -> null
    }
    val tableTopFeature = (adaptiveInfo.devicePosture as? DevicePosture.TableTop)?.feature

    val hingeWidth = verticalFeature
        ?.takeIf { it.orientation == FoldingFeature.Orientation.VERTICAL }
        ?.bounds?.width()
        ?.let { with(density) { it.toDp() } } ?: 0.dp

    val hingeHeight = tableTopFeature
        ?.takeIf { it.orientation == FoldingFeature.Orientation.HORIZONTAL }
        ?.bounds?.height()
        ?.let { with(density) { it.toDp() } } ?: 0.dp

    var sidebarVisible by rememberSaveable { mutableStateOf(isDualPane || isTableTop) }

    LaunchedEffect(isDualPane, isTableTop) {
        when {
            isDualPane -> sidebarVisible = true
            !isTableTop -> sidebarVisible = false
        }
    }

    when {
        isDualPane -> DualPaneMainScreen(
            navController,
            hingeWidth,
            sidebarVisible,
            initialPrompt,
            onInitialPromptConsumed
        ) { sidebarVisible = it }
        isTableTop -> TableTopMainScreen(
            navController,
            hingeHeight,
            sidebarVisible,
            initialPrompt,
            onInitialPromptConsumed
        ) { sidebarVisible = it }
        else -> SinglePaneMainScreen(
            navController,
            sidebarVisible,
            initialPrompt,
            onInitialPromptConsumed
        ) { sidebarVisible = it }
    }
}

@Composable
private fun DualPaneMainScreen(
    navController: NavHostController,
    hingeWidth: Dp,
    sidebarVisible: Boolean,
    initialPrompt: String?,
    onInitialPromptConsumed: () -> Unit,
    onSidebarVisibilityChange: (Boolean) -> Unit
) {
    val targetSidebarWidth = if (sidebarVisible) 320.dp else 0.dp
    val sidebarWidth by animateDpAsState(targetValue = targetSidebarWidth, label = "sidebarWidth")
    val clampedSidebarWidth = sidebarWidth.coerceIn(0.dp, 360.dp)
    val shouldShowSidebar = clampedSidebarWidth > 1.dp

    Row(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        if (shouldShowSidebar) {
            Box(
                modifier = Modifier
                    .width(clampedSidebarWidth)
                    .fillMaxHeight()
            ) {
                ConversationListContainer(
                    navController = navController,
                    modifier = Modifier.fillMaxSize(),
                    onConversationClick = { onSidebarVisibilityChange(false) },
                    onClose = { onSidebarVisibilityChange(false) }
                )
            }

            if (hingeWidth > 0.dp) {
                Spacer(modifier = Modifier.width(hingeWidth))
            } else {
                VerticalDivider(
                    modifier = Modifier.fillMaxHeight(),
                    thickness = 1.dp,
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f)
                )
            }
        }

        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxHeight()
        ) {
            NavGraph(
                navController = navController,
                onMenuClick = { onSidebarVisibilityChange(!sidebarVisible) },
                initialPrompt = initialPrompt,
                onInitialPromptConsumed = onInitialPromptConsumed
            )
        }
    }
}

@Composable
private fun TableTopMainScreen(
    navController: NavHostController,
    hingeHeight: Dp,
    sidebarVisible: Boolean,
    initialPrompt: String?,
    onInitialPromptConsumed: () -> Unit,
    onSidebarVisibilityChange: (Boolean) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        Box(
            modifier = Modifier
                .weight(1.2f)
                .fillMaxWidth()
        ) {
            NavGraph(
                navController = navController,
                onMenuClick = { onSidebarVisibilityChange(!sidebarVisible) },
                initialPrompt = initialPrompt,
                onInitialPromptConsumed = onInitialPromptConsumed
            )
        }

        if (hingeHeight > 0.dp) {
            Spacer(modifier = Modifier.height(hingeHeight))
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
        ) {
            if (sidebarVisible) {
                ConversationListContainer(
                    navController = navController,
                    modifier = Modifier.fillMaxSize(),
                    onConversationClick = {
                        onSidebarVisibilityChange(false)
                    },
                    onClose = { onSidebarVisibilityChange(false) }
                )
            } else {
                FlexCollapsedPlaceholder(onShowMenu = { onSidebarVisibilityChange(true) })
            }
        }
    }
}

@Composable
private fun SinglePaneMainScreen(
    navController: NavHostController,
    sidebarVisible: Boolean,
    initialPrompt: String?,
    onInitialPromptConsumed: () -> Unit,
    onSidebarVisibilityChange: (Boolean) -> Unit
) {
    val density = LocalDensity.current
    val edgeSwipeAreaPx = with(density) { 80.dp.toPx() }
    val swipeThresholdPx = with(density) { 120.dp.toPx() }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .pointerInput(sidebarVisible) {
                var dragStartX = 0f
                var totalDragX = 0f
                var isDragging = false

                detectDragGestures(
                    onDragStart = { offset ->
                        dragStartX = offset.x
                        totalDragX = 0f
                        isDragging = true
                    },
                    onDragEnd = {
                        if (isDragging) {
                            if (!sidebarVisible) {
                                if (dragStartX <= edgeSwipeAreaPx && totalDragX > swipeThresholdPx) {
                                    onSidebarVisibilityChange(true)
                                } else if (dragStartX <= size.width * 0.3f && totalDragX > swipeThresholdPx * 1.5f) {
                                    onSidebarVisibilityChange(true)
                                }
                            } else {
                                if (totalDragX < -swipeThresholdPx) {
                                    onSidebarVisibilityChange(false)
                                } else if (dragStartX <= 320.dp.toPx() && totalDragX > swipeThresholdPx) {
                                    onSidebarVisibilityChange(false)
                                }
                            }
                        }
                        isDragging = false
                        totalDragX = 0f
                    }
                ) { _, dragAmount ->
                    if (isDragging) {
                        totalDragX += dragAmount.x
                    }
                }
            }
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            NavGraph(
                navController = navController,
                onMenuClick = { onSidebarVisibilityChange(!sidebarVisible) },
                initialPrompt = initialPrompt,
                onInitialPromptConsumed = onInitialPromptConsumed
            )
        }

        AnimatedVisibility(
            visible = sidebarVisible,
            enter = slideInHorizontally(initialOffsetX = { -it }),
            exit = slideOutHorizontally(targetOffsetX = { -it }),
            modifier = Modifier.zIndex(1f)
        ) {
            Row {
                ConversationListContainer(
                    navController = navController,
                    modifier = Modifier
                        .width(320.dp)
                        .fillMaxHeight(),
                    onConversationClick = {
                        onSidebarVisibilityChange(false)
                    },
                    onClose = { onSidebarVisibilityChange(false) }
                )

                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.4f))
                        .clickable(
                            indication = null,
                            interactionSource = remember { MutableInteractionSource() }
                        ) {
                            onSidebarVisibilityChange(false)
                        }
                )
            }
        }
    }
}

@Composable
private fun ConversationListContainer(
    navController: NavHostController,
    modifier: Modifier,
    onConversationClick: () -> Unit,
    onClose: (() -> Unit)?
) {
    Surface(
        modifier = modifier,
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = if (onClose == null) 1.dp else 2.dp,
        shadowElevation = if (onClose == null) 0.dp else 8.dp
    ) {
        ConversationListScreen(
            navController = navController,
            onConversationClick = onConversationClick,
            onClose = onClose
        )
    }
}

@Composable
private fun FlexCollapsedPlaceholder(onShowMenu: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f)),
        contentAlignment = Alignment.Center
    ) {
        FilledTonalButton(onClick = onShowMenu) {
            Icon(Icons.Default.Menu, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text(text = "Open conversations")
        }
    }
}
