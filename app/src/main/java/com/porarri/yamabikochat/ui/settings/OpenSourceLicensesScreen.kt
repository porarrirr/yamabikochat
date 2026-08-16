package com.porarri.yamabikochat.ui.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.porarri.yamabikochat.R
import java.io.IOException

private data class LegalDocument(
    val fileName: String,
    val titleRes: Int
)

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
        LegalDocumentBody(fileName = selected.fileName, modifier = modifier)
    }
}

@Composable
private fun LegalDocumentBody(
    fileName: String,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val body = remember(fileName) {
        try {
            context.assets.open("legal/$fileName").bufferedReader().use { it.readText() }
        } catch (_: IOException) {
            null
        }
    }
    SelectionContainer {
        Text(
            text = body ?: stringResource(R.string.license_load_failed),
            style = MaterialTheme.typography.bodySmall,
            fontFamily = FontFamily.Monospace,
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 24.dp)
        )
    }
}
