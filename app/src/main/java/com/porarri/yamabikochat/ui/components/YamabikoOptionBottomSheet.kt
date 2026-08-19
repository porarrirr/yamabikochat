package com.porarri.yamabikochat.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

data class YamabikoOption(
    val key: String,
    val title: String,
    val subtitle: String? = null,
    val enabled: Boolean = true
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun YamabikoOptionBottomSheet(
    title: String,
    options: List<YamabikoOption>,
    selectedKey: String?,
    onOptionSelected: (YamabikoOption) -> Unit,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    searchable: Boolean = options.size > 20,
    searchPlaceholder: String = "検索"
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var searchQuery by remember { mutableStateOf("") }
    val visibleOptions = remember(options, searchQuery) {
        val query = searchQuery.trim().lowercase()
        if (query.isEmpty()) options else options.filter { option ->
            option.key.lowercase().contains(query) ||
                option.title.lowercase().contains(query) ||
                option.subtitle.orEmpty().lowercase().contains(query)
        }
    }
    ModalBottomSheet(
        onDismissRequest = onDismissRequest,
        modifier = modifier,
        sheetState = sheetState,
        dragHandle = { BottomSheetDefaults.DragHandle() }
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(title, style = MaterialTheme.typography.titleMedium)
                IconButton(onClick = onDismissRequest) {
                    Icon(Icons.Default.Close, contentDescription = "Close")
                }
            }
            if (searchable) {
                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    label = { Text(searchPlaceholder) },
                    singleLine = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }
            HorizontalDivider()
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 24.dp)
            ) {
                itemsIndexed(visibleOptions, key = { _, item -> item.key }) { index, item ->
                    ListItem(
                        headlineContent = { Text(item.title) },
                        supportingContent = item.subtitle?.let { subtitle -> { Text(subtitle) } },
                        trailingContent = {
                            RadioButton(
                                selected = item.key == selectedKey,
                                onClick = null,
                                enabled = item.enabled
                            )
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(enabled = item.enabled) {
                                onOptionSelected(item)
                                onDismissRequest()
                            }
                    )
                    if (index != visibleOptions.lastIndex) {
                        HorizontalDivider(modifier = Modifier.padding(start = 16.dp))
                    }
                }
            }
        }
    }
}
