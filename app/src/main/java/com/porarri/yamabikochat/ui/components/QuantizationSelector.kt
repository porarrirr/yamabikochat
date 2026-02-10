package com.porarri.yamabikochat.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.ArrowDropUp
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuantizationSelector(
    availableQuantizations: List<String>,
    selectedQuantizations: List<String>,
    onQuantizationsChanged: (List<String>) -> Unit,
    modifier: Modifier = Modifier,
    label: String = "量子化レベル（複数選択可）"
) {
    var expanded by remember { mutableStateOf(false) }
    
    Column(modifier = modifier) {
        YamabikoTextField(
            value = if (selectedQuantizations.isEmpty()) 
                "自動選択" 
            else 
                selectedQuantizations.joinToString(", ") { getQuantizationDisplayName(it) },
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
            QuantizationDropdown(
                availableQuantizations = availableQuantizations,
                selectedQuantizations = selectedQuantizations,
                onQuantizationsChanged = onQuantizationsChanged,
                onDismiss = { expanded = false }
            )
        }
    }
}

@Composable
fun QuantizationDropdown(
    availableQuantizations: List<String>,
    selectedQuantizations: List<String>,
    onQuantizationsChanged: (List<String>) -> Unit,
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
                .heightIn(max = 400.dp)
                .padding(8.dp)
        ) {
            item {
                // プリセット選択オプション
                Text(
                    text = "クイック選択",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(vertical = 8.dp)
                )
                
                // 品質重視プリセット
                OutlinedButton(
                    onClick = { onQuantizationsChanged(listOf("fp32", "fp16", "bf16")) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("品質重視（FP32, FP16, BF16）")
                }
                
                Spacer(modifier = Modifier.height(4.dp))
                
                // バランス重視プリセット
                OutlinedButton(
                    onClick = { onQuantizationsChanged(listOf("fp16", "bf16", "fp8")) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("バランス重視（FP16, BF16, FP8）")
                }
                
                Spacer(modifier = Modifier.height(4.dp))
                
                // 速度重視プリセット
                OutlinedButton(
                    onClick = { onQuantizationsChanged(listOf("fp8", "int8", "int4")) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("速度重視（FP8, INT8, INT4）")
                }
                
                Spacer(modifier = Modifier.height(8.dp))
                
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    TextButton(onClick = { onQuantizationsChanged(emptyList()) }) {
                        Text("すべて解除")
                    }
                    TextButton(onClick = { onQuantizationsChanged(availableQuantizations) }) {
                        Text("すべて選択")
                    }
                }
                
                HorizontalDivider()
                
                Text(
                    text = "個別選択",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(vertical = 8.dp)
                )
            }
            
            items(getSortedQuantizations(availableQuantizations)) { quantization ->
                QuantizationItem(
                    quantization = quantization,
                    displayName = getQuantizationDisplayName(quantization),
                    description = getQuantizationDescription(quantization),
                    isSelected = selectedQuantizations.contains(quantization),
                    onToggle = { isSelected ->
                        if (isSelected) {
                            onQuantizationsChanged(selectedQuantizations + quantization)
                        } else {
                            onQuantizationsChanged(selectedQuantizations - quantization)
                        }
                    }
                )
            }
            
            item {
                Spacer(modifier = Modifier.height(8.dp))
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

@Composable
fun QuantizationItem(
    quantization: String,
    displayName: String,
    description: String,
    isSelected: Boolean,
    onToggle: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .selectable(
                selected = isSelected,
                onClick = { onToggle(!isSelected) }
            )
            .padding(vertical = 8.dp, horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Checkbox(
            checked = isSelected,
            onCheckedChange = onToggle
        )
        
        Spacer(modifier = Modifier.width(8.dp))
        
        Column(
            modifier = Modifier.weight(1f)
        ) {
            Text(
                text = displayName,
                fontWeight = FontWeight.Medium
            )
            
            Text(
                text = description,
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        
        Column(
            horizontalAlignment = Alignment.End
        ) {
            Text(
                text = getPerformanceIndicator(quantization),
                fontSize = 10.sp,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.Medium
            )
            
            Text(
                text = getQuantizationPriority(quantization),
                fontSize = 9.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
fun QuantizationInfoCard(
    selectedQuantizations: List<String> = emptyList(),
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.Info,
                    contentDescription = "情報",
                    tint = MaterialTheme.colorScheme.primary
                )
                
                Spacer(modifier = Modifier.width(8.dp))
                
                Text(
                    text = "量子化について",
                    fontWeight = FontWeight.Bold
                )
            }
            
            Spacer(modifier = Modifier.height(8.dp))
            
            Text(
                text = "複数の量子化レベルを選択すると、OpenRouterが最適なプロバイダーを自動選択します。量子化は計算効率を向上させますが、精度とのトレードオフがあります。",
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            
            if (selectedQuantizations.isNotEmpty()) {
                Spacer(modifier = Modifier.height(12.dp))
                
                Text(
                    text = "選択された量子化レベル:",
                    fontWeight = FontWeight.Medium,
                    fontSize = 14.sp
                )
                
                Spacer(modifier = Modifier.height(4.dp))
                
                LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(selectedQuantizations) { quantization ->
                        AssistChip(
                            onClick = { },
                            label = { 
                                Text(
                                    text = getQuantizationDisplayName(quantization),
                                    fontSize = 12.sp
                                ) 
                            },
                            colors = AssistChipDefaults.assistChipColors(
                                containerColor = MaterialTheme.colorScheme.primaryContainer
                            )
                        )
                    }
                }
            }
            
            Spacer(modifier = Modifier.height(12.dp))
            
            Column {
                Text(
                    text = "量子化レベル比較:",
                    fontWeight = FontWeight.Medium,
                    fontSize = 14.sp
                )
                Spacer(modifier = Modifier.height(4.dp))
                QuantizationLevelInfo("FP32", "最高精度・最大サイズ", "基準速度")
                QuantizationLevelInfo("FP16/BF16", "高精度・標準サイズ", "高速")
                QuantizationLevelInfo("FP8", "良好精度・小サイズ", "高速")
                QuantizationLevelInfo("INT8", "実用精度・小サイズ", "高速")
                QuantizationLevelInfo("INT4", "基本精度・最小サイズ", "最高速")
            }
        }
    }
}

@Composable
fun QuantizationLevelInfo(
    level: String,
    precision: String,
    size: String
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = level,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium
        )
        
        Text(
            text = "$precision・$size",
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

private fun getQuantizationDisplayName(quantization: String): String {
    return when (quantization.lowercase()) {
        "fp32" -> "FP32 (32-bit浮動小数点)"
        "fp16" -> "FP16 (16-bit浮動小数点)"
        "bf16" -> "BF16 (16-bit Brain Float)"
        "fp8" -> "FP8 (8-bit浮動小数点)"
        "int8" -> "INT8 (8-bit整数)"
        "int4" -> "INT4 (4-bit整数)"
        "fp4" -> "FP4 (4-bit浮動小数点)"
        "fp6" -> "FP6 (6-bit浮動小数点)"
        "unknown" -> "不明"
        else -> quantization.uppercase()
    }
}

private fun getQuantizationDescription(quantization: String): String {
    return when (quantization.lowercase()) {
        "fp32" -> "最高精度・最大サイズ・標準速度"
        "fp16" -> "高精度・標準サイズ・高速"
        "bf16" -> "高精度・標準サイズ・高速（Google製）"
        "fp8" -> "良好な精度・小サイズ・高速"
        "int8" -> "実用的精度・小サイズ・高速"
        "int4" -> "基本精度・最小サイズ・最高速"
        "fp4" -> "基本精度・最小サイズ・最高速"
        "fp6" -> "良好な精度・小サイズ・高速"
        "unknown" -> "量子化レベル不明"
        else -> "カスタム量子化レベル"
    }
}

private fun getSortedQuantizations(quantizations: List<String>): List<String> {
    val priority = mapOf(
        "fp32" to 1,
        "fp16" to 2,
        "bf16" to 3,
        "fp8" to 4,
        "fp6" to 5,
        "int8" to 6,
        "fp4" to 7,
        "int4" to 8
    )
    
    return quantizations.sortedBy { priority[it.lowercase()] ?: 99 }
}

private fun getQuantizationPriority(quantization: String): String {
    return when (quantization.lowercase()) {
        "fp32" -> "最優先"
        "fp16", "bf16" -> "高優先"
        "fp8", "fp6" -> "中優先"
        "int8" -> "低優先"
        "int4", "fp4" -> "最低優先"
        else -> "不明"
    }
}

private fun getPerformanceIndicator(quantization: String): String {
    return when (quantization.lowercase()) {
        "fp32" -> "最高精度"
        "fp16", "bf16" -> "高精度"
        "fp8", "fp6" -> "良好"
        "int8" -> "実用的"
        "int4", "fp4" -> "基本"
        else -> "不明"
    }
}
