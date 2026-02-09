package com.porarri.yamabikochat.utils

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object FileValidationUtils {
    
    private const val MAX_FILE_SIZE = 10 * 1024 * 1024 // 10MB
    private const val MIN_FILE_SIZE = 1 // 1 byte minimum
    private const val FILE_HEADER_SIZE = 32 // ファイルシグネチャチェック用のバイト数
    private const val MAX_FILENAME_LENGTH = 255 // ファイル名の最大長
    
    // 許可されたMIMEタイプのホワイトリスト
    private val ALLOWED_MIME_TYPES = setOf(
        "image/jpeg",
        "image/jpg", 
        "image/png",
        "image/gif",
        "image/webp",
        "application/pdf",
        "text/plain"
    )
    
    // 危険なファイル拡張子のブラックリスト
    private val DANGEROUS_EXTENSIONS = setOf(
        "exe", "bat", "cmd", "com", "pif", "scr", "vbs", "js", "jar",
        "app", "deb", "pkg", "rpm", "dmg", "iso", "msi", "apk",
        "sh", "bash", "fish", "csh", "ksh", "zsh"
    )
    
    // ファイルマジックナンバー（ファイルの最初のバイト）による検証
    private val FILE_SIGNATURES = mapOf(
        "image/jpeg" to listOf(
            byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte()),
        ),
        "image/png" to listOf(
            byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        ),
        "image/gif" to listOf(
            byteArrayOf(0x47, 0x49, 0x46, 0x38, 0x37, 0x61), // GIF87a
            byteArrayOf(0x47, 0x49, 0x46, 0x38, 0x39, 0x61)  // GIF89a
        ),
        "image/webp" to listOf(
            byteArrayOf(0x52, 0x49, 0x46, 0x46) // RIFF (WebP signature starts with RIFF)
        ),
        "application/pdf" to listOf(
            byteArrayOf(0x25, 0x50, 0x44, 0x46, 0x2D) // %PDF-
        )
    )
    
    sealed class FileValidationResult {
        data class Valid(val mimeType: String, val fileSize: Long) : FileValidationResult()
        data class TooLarge(val fileSize: Long) : FileValidationResult()
        data class TooSmall(val fileSize: Long) : FileValidationResult()
        object UnsupportedType : FileValidationResult()
        object DangerousFile : FileValidationResult()
        object CorruptedFile : FileValidationResult()
        data class Error(val message: String) : FileValidationResult()
    }
    
    suspend fun validateFile(context: Context, uri: Uri): FileValidationResult {
        return withContext(Dispatchers.IO) {
            try {
                val contentResolver = context.contentResolver
                val mimeType = contentResolver.getType(uri)?.let { canonicalizeMimeType(it) }

                // ファイルサイズチェック
                val fileSize = getFileSize(context, uri) ?: return@withContext FileValidationResult.Error("ファイルサイズを取得できませんでした")

                when {
                    fileSize > MAX_FILE_SIZE -> FileValidationResult.TooLarge(fileSize)
                    fileSize < MIN_FILE_SIZE -> FileValidationResult.TooSmall(fileSize)
                    else -> {
                        // MIMEタイプとファイル拡張子の検証
                        when (val extensionValidation = validateFileExtension(uri)) {
                            is FileValidationResult.Valid -> Unit
                            else -> return@withContext extensionValidation
                        }

                        // 実際のファイル内容の検証
                        val detectedMimeFromContent = when (val contentValidation = validateFileContent(context, uri, mimeType)) {
                            is FileValidationResult.Valid -> contentValidation.mimeType.takeIf { it.isNotBlank() }
                            else -> return@withContext contentValidation
                        }

                        val resolvedMimeType = mimeType ?: detectedMimeFromContent

                        // 最終的にMIMEタイプがサポートされているかチェック
                        when {
                            resolvedMimeType != null && ALLOWED_MIME_TYPES.contains(resolvedMimeType) -> {
                                FileValidationResult.Valid(resolvedMimeType, fileSize)
                            }
                            else -> FileValidationResult.UnsupportedType
                        }
                    }
                }
            } catch (e: Exception) {
                FileValidationResult.Error(e.message ?: "Unknown validation error")
            }
        }
    }
    
    private suspend fun getFileSize(context: Context, uri: Uri): Long? {
        return withContext(Dispatchers.IO) {
            val contentResolver = context.contentResolver

            contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && cursor.moveToFirst()) {
                    val size = cursor.getLong(sizeIndex)
                    if (size >= 0) {
                        return@withContext size
                    }
                }
            }

            contentResolver.openFileDescriptor(uri, "r")?.use { descriptor ->
                val size = descriptor.statSize
                if (size >= 0) {
                    return@withContext size
                }
            }

            contentResolver.openInputStream(uri)?.use { stream ->
                var total = 0L
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val read = stream.read(buffer)
                    if (read == -1) break
                    total += read
                    if (total > MAX_FILE_SIZE) {
                        return@withContext total
                    }
                }
                return@withContext total
            }

            null
        }
    }

    private fun validateFileExtension(uri: Uri): FileValidationResult {
        val path = uri.path ?: uri.toString()
        val extension = MimeTypeMap.getFileExtensionFromUrl(path)?.lowercase()
        
        return if (extension != null && DANGEROUS_EXTENSIONS.contains(extension)) {
            FileValidationResult.DangerousFile
        } else {
            FileValidationResult.Valid("", 0) // Extension is safe, continue validation
        }
    }
    
    private suspend fun validateFileContent(context: Context, uri: Uri, mimeType: String?): FileValidationResult {
        return withContext(Dispatchers.IO) {
            try {
                context.contentResolver.openInputStream(uri)?.use { inputStream ->
                    val header = ByteArray(FILE_HEADER_SIZE) // ファイルシグネチャチェック用
                    val bytesRead = inputStream.read(header)

                    if (bytesRead < 4) {
                        return@withContext FileValidationResult.CorruptedFile
                    }

                    val normalizedDeclaredMime = mimeType?.let { canonicalizeMimeType(it) }
                    val detectedMime = detectMimeTypeFromHeader(header)

                    if (detectedMime == null) {
                        return@withContext if (normalizedDeclaredMime == "text/plain") {
                            FileValidationResult.Valid("text/plain", 0)
                        } else if (normalizedDeclaredMime != null && FILE_SIGNATURES.containsKey(normalizedDeclaredMime)) {
                            FileValidationResult.CorruptedFile
                        } else {
                            FileValidationResult.UnsupportedType
                        }
                    }

                    if (normalizedDeclaredMime != null &&
                        FILE_SIGNATURES.containsKey(normalizedDeclaredMime) &&
                        normalizedDeclaredMime != detectedMime
                    ) {
                        return@withContext FileValidationResult.CorruptedFile
                    }

                    FileValidationResult.Valid(detectedMime, 0)
                } ?: FileValidationResult.Error("Cannot read file content")
            } catch (e: Exception) {
                FileValidationResult.Error("Content validation failed: ${e.message}")
            }
        }
    }
    
    private fun detectMimeTypeFromHeader(header: ByteArray): String? {
        FILE_SIGNATURES.forEach { (mime, signatures) ->
            val matched = signatures.any { signature ->
                header.size >= signature.size &&
                        header.sliceArray(0 until signature.size).contentEquals(signature)
            }
            if (matched) {
                return canonicalizeMimeType(mime)
            }
        }
        return null
    }

    private fun canonicalizeMimeType(mimeType: String): String {
        return when (mimeType.lowercase()) {
            "image/jpg" -> "image/jpeg"
            else -> mimeType.lowercase()
        }
    }
    
    fun sanitizeFileName(fileName: String): String {
        // Remove dangerous characters and limit length
        return fileName
            .replace(Regex("[^a-zA-Z0-9._-]"), "_")
            .take(MAX_FILENAME_LENGTH)
            .ifEmpty { "file_${System.currentTimeMillis()}" }
    }
    
    fun isFileSizeWithinLimit(sizeBytes: Long): Boolean {
        return sizeBytes in MIN_FILE_SIZE..MAX_FILE_SIZE
    }
}
