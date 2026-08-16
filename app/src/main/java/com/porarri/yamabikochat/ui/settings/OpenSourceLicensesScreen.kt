package com.porarri.yamabikochat.ui.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.R
import com.porarri.yamabikochat.utils.LegalMarkdownBlock
import com.porarri.yamabikochat.utils.LegalMarkdownParser
import java.io.IOException

private data class LegalDocument(
    val fileName: String,
    val titleRes: Int
) {
    val isMarkdown: Boolean get() = fileName.endsWith(".md")
}

private val legalDocuments = listOf(
    LegalDocument("LICENSE.txt", R.string.license_yamabiko),
    LegalDocument("THIRD_PARTY_NOTICES.md", R.string.license_third_party),
    LegalDocument("npm-licenses.md", R.string.license_npm),
    LegalDocument("NODEJS_LICENSE.txt", R.string.license_nodejs)
)

@Composable
fun OpenSourceLicensesScreen(
    modifier: Modifier = Modifier
) {
    var selectedFile by rememberSaveable { mutableStateOf<String?>(null) }
    BackHandler(enabled = selectedFile != null) {
        selectedFile = null
    }

    val selected = legalDocuments.firstOrNull { it.fileName == selectedFile }
    if (selected == null) {
        Column(modifier = modifier.fillMaxSize()) {
            legalDocuments.forEachIndexed { index, document ->
                ListItem(
                    headlineContent = { Text(stringResource(document.titleRes)) },
                    trailingContent = {
                        Icon(
                            Icons.AutoMirrored.Filled.KeyboardArrowRight,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary
                        )
                    },
                    colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { selectedFile = document.fileName }
                )
                if (index != legalDocuments.lastIndex) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                }
            }
        }
    } else {
        LegalDocumentBody(document = selected, modifier = modifier)
    }
}

@Composable
private fun LegalDocumentBody(
    document: LegalDocument,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val body = remember(document.fileName) {
        try {
            context.assets.open("legal/${document.fileName}").bufferedReader().use { it.readText() }
        } catch (_: IOException) {
            null
        }
    }
    if (body == null) {
        Text(
            text = stringResource(R.string.license_load_failed),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = modifier.fillMaxSize()
        )
        return
    }
    if (document.isMarkdown) {
        LegalMarkdownDocument(
            blocks = remember(body) { LegalMarkdownParser.parse(body) },
            modifier = modifier
        )
    } else {
        SelectionContainer {
            LazyColumn(modifier = modifier.fillMaxSize()) {
                item {
                    Text(
                        text = body,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.padding(bottom = 24.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun LegalMarkdownDocument(
    blocks: List<LegalMarkdownBlock>,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        blocks.forEachIndexed { blockIndex, block ->
            when (block) {
                is LegalMarkdownBlock.Heading -> {
                    item(key = "h-$blockIndex") {
                        Text(
                            text = block.text,
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                }
                is LegalMarkdownBlock.Paragraph -> {
                    item(key = "p-$blockIndex") {
                        SelectionContainer {
                            Text(
                                text = block.text,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                        }
                    }
                }
                is LegalMarkdownBlock.Table -> {
                    itemsIndexed(
                        items = block.rows,
                        key = { rowIndex, _ -> "t-$blockIndex-$rowIndex" }
                    ) { _, row ->
                        LegalTableRowCard(values = row)
                    }
                }
                is LegalMarkdownBlock.Code -> {
                    item(key = "c-$blockIndex") {
                        SelectionContainer {
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surfaceContainerHigh
                                )
                            ) {
                                Text(
                                    text = block.text,
                                    style = MaterialTheme.typography.bodySmall,
                                    fontFamily = FontFamily.Monospace,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(12.dp)
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LegalTableRowCard(
    values: List<String>
) {
    val uriHandler = LocalUriHandler.current
    val title = values.firstOrNull().orEmpty()
    val details = values.drop(1).map { it.trim() }.filter { it.isNotEmpty() }
    val metaLine = details.filter { !it.startsWith("http") }.joinToString(" · ")
    val urls = details.filter { it.startsWith("http") }
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh)
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            if (title.isNotEmpty()) {
                SelectionContainer {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                }
            }
            if (metaLine.isNotEmpty()) {
                SelectionContainer {
                    Text(
                        text = metaLine,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            urls.forEach { url ->
                Text(
                    text = url,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.clickable {
                        runCatching { uriHandler.openUri(url) }
                    }
                )
            }
        }
    }
}
