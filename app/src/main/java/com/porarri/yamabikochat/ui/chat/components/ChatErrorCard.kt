package com.porarri.yamabikochat.ui.chat.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.R
import com.porarri.yamabikochat.utils.UserFacingError
import com.porarri.yamabikochat.utils.UserFacingErrorCopy
import com.porarri.yamabikochat.utils.UserFacingErrorFormatter

@Composable
fun rememberUserFacingErrorCopy(): UserFacingErrorCopy {
    return UserFacingErrorCopy(
        genericTitle = stringResource(R.string.user_facing_error_title),
        quotaTitle = stringResource(R.string.user_facing_error_quota_title),
        quotaSummary = stringResource(R.string.user_facing_error_quota_summary),
        authTitle = stringResource(R.string.user_facing_error_auth_title),
        authSummary = stringResource(R.string.user_facing_error_auth_summary),
        serverTitle = stringResource(R.string.user_facing_error_server_title),
        serverSummary = stringResource(R.string.user_facing_error_server_summary),
        fallbackSummary = stringResource(R.string.user_facing_error_fallback),
        details = stringResource(R.string.user_facing_error_details),
        dismiss = stringResource(R.string.user_facing_error_dismiss)
    )
}

@Composable
fun ChatErrorCard(
    text: String,
    modifier: Modifier = Modifier,
    copy: UserFacingErrorCopy = rememberUserFacingErrorCopy()
) {
    val formatted = remember(text, copy) { UserFacingErrorFormatter.format(text, copy) }
    ChatErrorCard(formatted = formatted, copy = copy, modifier = modifier)
}

@Composable
fun ChatErrorCard(
    formatted: UserFacingError,
    modifier: Modifier = Modifier,
    copy: UserFacingErrorCopy = rememberUserFacingErrorCopy()
) {
    var showDetail by remember(formatted.detail) { mutableStateOf(false) }

    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.45f),
        tonalElevation = 0.dp
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Top
            ) {
                Icon(
                    imageVector = Icons.Default.Warning,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.error,
                    modifier = Modifier.size(18.dp)
                )
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = formatted.title,
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                    Text(
                        text = formatted.summary,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }

            if (formatted.hasDetail) {
                TextButton(onClick = { showDetail = !showDetail }) {
                    Text(text = copy.details)
                }
                AnimatedVisibility(visible = showDetail) {
                    SelectionContainer {
                        Text(
                            text = formatted.detail,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.8f)
                        )
                    }
                }
            }
        }
    }
}
