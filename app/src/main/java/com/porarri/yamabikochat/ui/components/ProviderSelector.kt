package com.porarri.yamabikochat.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.ArrowDropUp
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProviderSelector(
    availableProviders: List<String>,
    selectedProviders: List<String>,
    onProvidersChanged: (List<String>) -> Unit,
    modifier: Modifier = Modifier,
    label: String = "プロバイダー選択",
    maxSelection: Int = 3
) {
    var expanded by remember { mutableStateOf(false) }
    var showDialog by remember { mutableStateOf(false) }
    
    Column(modifier = modifier) {
        YamabikoTextField(
            value = if (selectedProviders.isEmpty()) "すべてのプロバイダー" else selectedProviders.joinToString(", "),
            onValueChange = { },
            readOnly = true,
            label = { Text(label) },
            trailingIcon = {
                IconButton(onClick = { expanded = !expanded }) {
                    Icon(
                        imageVector = if (expanded) Icons.Default.ArrowDropUp else Icons.Default.ArrowDropDown,
                        contentDescription = if (expanded) "閉じる" else "開く"
                    )
                }
            },
            modifier = Modifier.fillMaxWidth()
        )
        
        if (expanded) {
            ProviderDropdown(
                availableProviders = availableProviders,
                selectedProviders = selectedProviders,
                onProvidersChanged = onProvidersChanged,
                maxSelection = maxSelection,
                onDismiss = { expanded = false }
            )
        }
    }
}

@Composable
fun ProviderDropdown(
    availableProviders: List<String>,
    selectedProviders: List<String>,
    onProvidersChanged: (List<String>) -> Unit,
    maxSelection: Int,
    onDismiss: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
    ) {
        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 300.dp)
                .padding(8.dp)
        ) {
            item {
                // 全選択/全解除オプション
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    TextButton(
                        onClick = { onProvidersChanged(emptyList()) }
                    ) {
                        Text("すべて解除")
                    }
                    
                    TextButton(
                        onClick = { onProvidersChanged(availableProviders.take(maxSelection)) }
                    ) {
                        Text("人気プロバイダー")
                    }
                }
                
                HorizontalDivider()
            }
            
            items(availableProviders) { provider ->
                ProviderItem(
                    provider = provider,
                    isSelected = selectedProviders.contains(provider),
                    onToggle = { isSelected ->
                        if (isSelected) {
                            if (selectedProviders.size < maxSelection) {
                                onProvidersChanged(selectedProviders + provider)
                            }
                        } else {
                            onProvidersChanged(selectedProviders - provider)
                        }
                    },
                    enabled = selectedProviders.contains(provider) || selectedProviders.size < maxSelection
                )
            }
            
            item {
                Spacer(modifier = Modifier.height(8.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(onClick = onDismiss) {
                        Text("閉じる")
                    }
                }
            }
        }
    }
}

@Composable
fun ProviderItem(
    provider: String,
    isSelected: Boolean,
    onToggle: (Boolean) -> Unit,
    enabled: Boolean
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Checkbox(
            checked = isSelected,
            onCheckedChange = onToggle,
            enabled = enabled
        )
        
        Spacer(modifier = Modifier.width(8.dp))
        
        Column(
            modifier = Modifier.weight(1f)
        ) {
            Text(
                text = provider,
                fontWeight = FontWeight.Medium,
                color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
            )
            
            Text(
                text = getProviderDescription(provider),
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        
        if (isSelected) {
            Icon(
                imageVector = Icons.Default.Check,
                contentDescription = "選択済み",
                tint = MaterialTheme.colorScheme.primary
            )
        }
    }
}

@Composable
fun ProviderPreferenceDialog(
    showDialog: Boolean,
    availableProviders: List<String>,
    selectedProviders: List<String>,
    onProvidersChanged: (List<String>) -> Unit,
    onDismiss: () -> Unit
) {
    if (showDialog) {
        Dialog(onDismissRequest = onDismiss) {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 500.dp)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "プロバイダー優先順位",
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold
                        )
                        
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.Default.Close, contentDescription = "閉じる")
                        }
                    }
                    
                    Spacer(modifier = Modifier.height(16.dp))
                    
                    Text(
                        text = "優先順位を設定してください（最大3つまで）",
                        fontSize = 14.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    
                    Spacer(modifier = Modifier.height(16.dp))
                    
                    LazyColumn(
                        modifier = Modifier.weight(1f)
                    ) {
                        items(availableProviders) { provider ->
                            ProviderItem(
                                provider = provider,
                                isSelected = selectedProviders.contains(provider),
                                onToggle = { isSelected ->
                                    if (isSelected) {
                                        if (selectedProviders.size < 3) {
                                            onProvidersChanged(selectedProviders + provider)
                                        }
                                    } else {
                                        onProvidersChanged(selectedProviders - provider)
                                    }
                                },
                                enabled = selectedProviders.contains(provider) || selectedProviders.size < 3
                            )
                        }
                    }
                    
                    Spacer(modifier = Modifier.height(16.dp))
                    
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End
                    ) {
                        TextButton(onClick = onDismiss) {
                            Text("完了")
                        }
                    }
                }
            }
        }
    }
}

private fun getProviderDescription(provider: String): String {
    return when (provider.lowercase()) {
        "openai" -> "高品質、幅広い用途"
        "anthropic" -> "安全性重視、長いコンテキスト"
        "groq" -> "高速推論、リアルタイム応答"
        "together" -> "オープンソース、カスタマイズ可能"
        "google" -> "多言語対応、検索統合"
        "deepseek" -> "コード特化、高性能"
        "meta-llama" -> "オープンソース、高性能"
        "mistral" -> "効率的、多言語対応"
        "nvidia" -> "高性能GPU、大規模モデル"
        "cohere" -> "企業向け、安全性重視"
        else -> "高品質AIプロバイダー"
    }
}
