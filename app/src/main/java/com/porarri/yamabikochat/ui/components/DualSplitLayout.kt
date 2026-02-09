package com.porarri.yamabikochat.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.style.TextOverflow
import com.porarri.yamabikochat.data.local.SplitLayoutType
import com.porarri.yamabikochat.ui.chat.MarkdownText

@Composable
fun DualSplitLayout(
    modifier: Modifier = Modifier,
    layoutType: SplitLayoutType,
    splitRatio: Float,
    onSplitRatioChanged: (Float) -> Unit,
    leftContent: @Composable BoxScope.() -> Unit,
    rightContent: @Composable BoxScope.() -> Unit
) {
    val splitRatioState = rememberUpdatedState(splitRatio)

    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val totalWidthPx = constraints.maxWidth.toFloat()
        val totalHeightPx = constraints.maxHeight.toFloat()

        when (layoutType) {
            SplitLayoutType.VERTICAL -> {
                // 左右分割レイアウト
                Row(modifier = Modifier.fillMaxSize()) {
                    // 左側コンテンツ
                    Box(
                        modifier = Modifier
                            .fillMaxHeight()
                            .weight(splitRatio)
                    ) {
                        leftContent()
                    }

                    // ドラッグ可能なセパレーター
                    VerticalDragSeparator(
                        onDragDelta = { dragDelta ->
                            if (totalWidthPx > 0f) {
                                val newRatio = (splitRatioState.value + dragDelta / totalWidthPx)
                                    .coerceIn(0.1f, 0.9f)
                                onSplitRatioChanged(newRatio)
                            }
                        }
                    )

                    // 右側コンテンツ
                    Box(
                        modifier = Modifier
                            .fillMaxHeight()
                            .weight(1f - splitRatio)
                    ) {
                        rightContent()
                    }
                }
            }

            SplitLayoutType.HORIZONTAL -> {
                // 上下分割レイアウト
                Column(modifier = Modifier.fillMaxSize()) {
                    // 上側コンテンツ
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(splitRatio)
                    ) {
                        leftContent()
                    }

                    // ドラッグ可能なセパレーター
                    HorizontalDragSeparator(
                        onDragDelta = { dragDelta ->
                            if (totalHeightPx > 0f) {
                                val newRatio = (splitRatioState.value + dragDelta / totalHeightPx)
                                    .coerceIn(0.1f, 0.9f)
                                onSplitRatioChanged(newRatio)
                            }
                        }
                    )

                    // 下側コンテンツ
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f - splitRatio)
                    ) {
                        rightContent()
                    }
                }
            }
        }
    }
}

@Composable
private fun VerticalDragSeparator(
    onDragDelta: (Float) -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .width(8.dp)
            .fillMaxHeight()
            .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
            .pointerInput(Unit) {
                detectDragGestures { change, dragAmount ->
                    change.consume()
                    onDragDelta(dragAmount.x)
                }
            },
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .width(4.dp)
                .height(40.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(MaterialTheme.colorScheme.outline)
        )
    }
}

@Composable
private fun HorizontalDragSeparator(
    onDragDelta: (Float) -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .height(8.dp)
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
            .pointerInput(Unit) {
                detectDragGestures { change, dragAmount ->
                    change.consume()
                    onDragDelta(dragAmount.y)
                }
            },
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .height(4.dp)
                .width(40.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(MaterialTheme.colorScheme.outline)
        )
    }
}

@Composable
fun DualResponseDisplay(
    modifier: Modifier = Modifier,
    layoutType: SplitLayoutType,
    splitRatio: Float,
    onSplitRatioChanged: (Float) -> Unit,
    modelAName: String,
    modelBName: String,
    modelAContent: String,
    modelBContent: String,
    modelAProvider: String,
    modelBProvider: String
) {
    DualSplitLayout(
        modifier = modifier,
        layoutType = layoutType,
        splitRatio = splitRatio,
        onSplitRatioChanged = onSplitRatioChanged,
        leftContent = {
            ResponsePanel(
                modelName = modelAName,
                provider = modelAProvider,
                content = modelAContent,
                isLeft = true
            )
        },
        rightContent = {
            ResponsePanel(
                modelName = modelBName,
                provider = modelBProvider,
                content = modelBContent,
                isLeft = false
            )
        }
    )
}

@Composable
private fun ResponsePanel(
    modelName: String,
    provider: String,
    content: String,
    isLeft: Boolean,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier
            .fillMaxSize()
            .padding(4.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (isLeft) 
                MaterialTheme.colorScheme.surfaceVariant 
            else 
                MaterialTheme.colorScheme.surface
        )
    ) {
        Column(
            modifier = Modifier.padding(12.dp)
        ) {
            // ヘッダー部分
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = modelName,
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                
                Spacer(modifier = Modifier.width(8.dp))
                
                Surface(
                    color = MaterialTheme.colorScheme.secondaryContainer,
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Text(
                        text = provider,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSecondaryContainer
                    )
                }
            }
            
            Spacer(modifier = Modifier.height(8.dp))
            
            // コンテンツ部分（スクロール可能）
            if (content.isEmpty()) {
                Text(
                    text = "応答を待機中...",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxSize()
                )
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(4.dp)
                ) {
                    item {
                        MarkdownText(
                            markdown = content,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            }
        }
    }
}