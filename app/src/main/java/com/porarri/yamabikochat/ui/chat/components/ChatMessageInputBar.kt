package com.porarri.yamabikochat.ui.chat.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.inputmethod.EditorInfoCompat
import com.porarri.yamabikochat.ui.components.YamabikoTextField
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.util.TypedValue
import android.view.inputmethod.EditorInfo
import androidx.appcompat.widget.AppCompatEditText

@Composable
fun ChatMessageInputBar(
    value: String,
    onValueChange: (String) -> Unit,
    attachments: List<android.net.Uri>,
    onSendClick: () -> Unit,
    onImagePick: () -> Unit,
    onFilePick: () -> Unit,
    isAutoConversationEnabled: Boolean,
    contextLabel: String?,
    isSecretMode: Boolean,
    skillSuggestions: List<String> = emptyList(),
    onSkillSelected: (String) -> Unit = {}
) {
    var showAttachmentMenu by remember { mutableStateOf(false) }
    val canSend = value.isNotBlank() || attachments.isNotEmpty()
    val placeholderText = if (isAutoConversationEnabled) "AIへの指示…" else "Ask Yamabiko"
    val keyboardOptions = KeyboardOptions.Default

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp)
    ) {
        if (!contextLabel.isNullOrBlank()) {
            Text(
                text = contextLabel,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 8.dp, bottom = 8.dp)
            )
        }

        if (skillSuggestions.isNotEmpty()) {
            LazyRow(horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(6.dp), modifier = Modifier.padding(bottom = 6.dp)) {
                items(skillSuggestions) { name ->
                    androidx.compose.material3.AssistChip(onClick = { onSkillSelected(name) }, label = { Text("\$$name") })
                }
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Bottom
        ) {
            Box {
                IconButton(
                    onClick = { showAttachmentMenu = true },
                    modifier = Modifier.size(40.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Add,
                        contentDescription = "Add Attachment",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                DropdownMenu(
                    expanded = showAttachmentMenu,
                    onDismissRequest = { showAttachmentMenu = false }
                ) {
                    DropdownMenuItem(
                        text = { Text("画像") },
                        leadingIcon = { Icon(Icons.Default.Image, null) },
                        onClick = {
                            showAttachmentMenu = false
                            onImagePick()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("ファイル") },
                        leadingIcon = { Icon(Icons.Default.Description, null) },
                        onClick = {
                            showAttachmentMenu = false
                            onFilePick()
                        }
                    )
                }
            }

            Spacer(modifier = Modifier.width(8.dp))

            if (isSecretMode) {
                SecretImeTextField(
                    value = value,
                    onValueChange = onValueChange,
                    modifier = Modifier.weight(1f),
                    placeholder = placeholderText,
                    minLines = 1,
                    maxLines = 6
                )
            } else {
                YamabikoTextField(
                    value = value,
                    onValueChange = onValueChange,
                    modifier = Modifier.weight(1f),
                    placeholder = {
                        Text(
                            text = placeholderText,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                        )
                    },
                    minLines = 1,
                    maxLines = 6,
                    keyboardOptions = keyboardOptions
                )
            }

            Spacer(modifier = Modifier.width(8.dp))

            FilledIconButton(
                onClick = onSendClick,
                enabled = canSend,
                modifier = Modifier.size(40.dp),
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = if (canSend) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.surfaceContainerHigh
                    },
                    contentColor = if (canSend) {
                        MaterialTheme.colorScheme.onPrimary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    }
                )
            ) {
                Icon(
                    imageVector = if (canSend) Icons.AutoMirrored.Filled.Send else Icons.Default.Mic,
                    contentDescription = if (canSend) "Send" else "Voice",
                    modifier = Modifier.size(20.dp)
                )
            }
        }
    }
}

@Composable
private fun SecretImeTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String,
    minLines: Int,
    maxLines: Int
) {
    val context = LocalContext.current
    val textStyle = LocalTextStyle.current
    val textColor = MaterialTheme.colorScheme.onSurface
    val hintColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
    val latestValue by rememberUpdatedState(value)
    val latestOnValueChange by rememberUpdatedState(onValueChange)
    val textWatcher = remember {
        object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
            override fun afterTextChanged(s: Editable?) {
                val updated = s?.toString().orEmpty()
                if (updated != latestValue) {
                    latestOnValueChange(updated)
                }
            }
        }
    }

    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surfaceContainerHighest
    ) {
        AndroidView(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            factory = {
                AppCompatEditText(context).apply {
                    setBackgroundColor(Color.Transparent.toArgb())
                    setPadding(0, 0, 0, 0)
                    setTextColor(textColor.toArgb())
                    setHintTextColor(hintColor.toArgb())
                    hint = placeholder
                    isSingleLine = false
                    setHorizontallyScrolling(false)
                    this.minLines = minLines
                    this.maxLines = maxLines
                    val baseInputType =
                        InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                    inputType = baseInputType
                    imeOptions = imeOptions or EditorInfoCompat.IME_FLAG_NO_PERSONALIZED_LEARNING
                    if (android.os.Build.VERSION.SDK_INT >= 26) {
                        imeOptions = imeOptions or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
                    }
                    setPrivateImeOptions("com.google.android.inputmethod.latin.noPersonalizedLearning")
                    if (textStyle.fontSize != TextUnit.Unspecified) {
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, textStyle.fontSize.value)
                    }
                    addTextChangedListener(textWatcher)
                }
            },
            update = { editText ->
                if (editText.text?.toString() != value) {
                    editText.setText(value)
                    editText.setSelection(editText.text?.length ?: 0)
                }
                editText.hint = placeholder
                editText.setTextColor(textColor.toArgb())
                editText.setHintTextColor(hintColor.toArgb())
            }
        )
    }
}
