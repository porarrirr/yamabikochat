package com.porarri.yamabikochat.data.files

import android.content.Context
import android.net.Uri
import com.porarri.yamabikochat.data.attachments.AttachmentStorage
import com.porarri.yamabikochat.data.remote.InlineData
import com.porarri.yamabikochat.data.remote.Part
import com.porarri.yamabikochat.utils.FileValidationUtils

class FileProcessingRepository(
    private val context: Context,
    private val attachmentStorage: AttachmentStorage
) {

    suspend fun validateFile(uri: Uri): FileValidationUtils.FileValidationResult {
        return FileValidationUtils.validateFile(context, uri)
    }

    suspend fun saveAttachment(uri: Uri): String? = attachmentStorage.saveAttachment(uri)

    suspend fun getPartFromUri(uri: Uri): Part? = attachmentStorage.getPartFromUri(uri)

    suspend fun saveInlineData(inlineData: InlineData, displayName: String? = null): String? =
        attachmentStorage.saveInlineData(inlineData, displayName)
}
