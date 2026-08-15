package com.porarri.yamabikochat.data.attachments

import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import android.util.Base64
import android.util.Base64OutputStream
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.exifinterface.media.ExifInterface
import com.porarri.yamabikochat.data.model.InlineData
import com.porarri.yamabikochat.data.model.Part
import com.porarri.yamabikochat.utils.FileValidationUtils
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.OutputStream
import java.nio.charset.StandardCharsets
import java.util.LinkedHashMap
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlin.io.DEFAULT_BUFFER_SIZE
import java.io.IOException

/**
 * Handles persisting attachments to app storage and converting them into API compatible [Part]s.
 *
 * Previously this work lived directly in ChatRepository which mixed database, network and file I/O
 * responsibilities. Centralising the logic here improves testability and, together with the
 * in-memory cache, eliminates repeated Base64 conversions when the same attachment is reused.
 */
class AttachmentStorage(private val context: Context) {

    private class StringBuilderOutputStream : OutputStream() {
        private val builder = StringBuilder()

        override fun write(b: Int) {
            builder.append((b and 0xFF).toChar())
        }

        override fun write(b: ByteArray, off: Int, len: Int) {
            if (len <= 0) return
            builder.append(String(b, off, len, StandardCharsets.ISO_8859_1))
        }

        override fun close() {
            // no-op
        }

        fun build(): String = builder.toString()
    }

    private val cacheMutex = Mutex()
    private val attachmentPartCache = object : LinkedHashMap<String, Part>(CACHE_CAPACITY, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Part>?): Boolean {
            return size > CACHE_CAPACITY
        }
    }

    private val appFilesCanonicalPath: String by lazy {
        runCatching { context.filesDir.canonicalPath }.getOrElse { context.filesDir.absolutePath }
    }

    suspend fun saveAttachment(uri: Uri): String? = withContext(Dispatchers.IO) {
        try {
            val mimeType = context.contentResolver.getType(uri)
            val sanitizedName = FileValidationUtils.sanitizeFileName("${UUID.randomUUID()}")

            if (mimeType?.startsWith("image/") == true) {
                val compressed = compressAndSaveImage(uri, sanitizedName)
                compressed?.absolutePath
            } else {
                val extension = MimeTypeMap.getSingleton()
                    .getExtensionFromMimeType(mimeType)
                    ?.takeIf { it.isNotBlank() }
                    ?: "bin"
                val targetFile = File(context.filesDir, "$sanitizedName.$extension")
                context.contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(targetFile).use { output ->
                        input.copyTo(output)
                    }
                } ?: return@withContext null
                targetFile.absolutePath
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    suspend fun getPartFromUri(uri: Uri): Part? = withContext(Dispatchers.IO) {
        val key = cacheKeyFor(uri)
        cacheMutex.withLock {
            attachmentPartCache[key]?.let { return@withContext it }
        }

        try {
            val (inputStream, mimeType) = openStream(uri) ?: return@withContext null
            inputStream.use { stream ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                var totalBytes = 0

                val collector = StringBuilderOutputStream()
                Base64OutputStream(collector, Base64.NO_WRAP).use { base64Stream ->
                    while (true) {
                        val read = stream.read(buffer)
                        if (read == -1) break

                        totalBytes += read
                        if (totalBytes > MAX_FILE_SIZE) {
                            throw IllegalArgumentException(
                                "File too large: ${totalBytes} bytes. Max size is ${MAX_FILE_SIZE / (1024 * 1024)}MB."
                            )
                        }

                        base64Stream.write(buffer, 0, read)
                    }
                    base64Stream.flush()
                }

                val base64 = collector.build()
                val part = Part(
                    inlineData = InlineData(
                        mimeType = mimeType ?: "application/octet-stream",
                        data = base64
                    )
                )
                val shouldCache = totalBytes <= MAX_CACHED_BYTES
                cacheMutex.withLock {
                    if (shouldCache) {
                        attachmentPartCache[key] = part
                    } else {
                        attachmentPartCache.remove(key)
                    }
                }
                if (!shouldCache) {
                    Log.d("AttachmentStorage", "Skipping cache for large attachment (${totalBytes} bytes)")
                }
                part
            }
        } catch (e: Exception) {
            e.printStackTrace()
            cacheMutex.withLock { attachmentPartCache.remove(key) }
            null
        }
    }

    suspend fun saveInlineData(inlineData: InlineData, displayName: String? = null): String? = withContext(Dispatchers.IO) {
        try {
            val mimeType = inlineData.mimeType
            val extension = when (mimeType.lowercase(Locale.ROOT)) {
                "application/pdf" -> "pdf"
                "text/plain" -> "txt"
                else -> MimeTypeMap.getSingleton()
                    .getExtensionFromMimeType(mimeType)
                    ?.takeIf { it.isNotBlank() }
                    ?: "bin"
            }
            val baseName = displayName?.substringBeforeLast('.')?.takeIf { it.isNotBlank() }
                ?: UUID.randomUUID().toString()
            val sanitizedName = FileValidationUtils.sanitizeFileName(baseName)
            val targetFile = File(context.filesDir, "$sanitizedName.$extension")

            val bytes = Base64.decode(inlineData.data, Base64.DEFAULT)
            if (bytes.size > MAX_FILE_SIZE) {
                Log.w("AttachmentStorage", "InlineData too large: ${bytes.size} bytes")
                return@withContext null
            }
            FileOutputStream(targetFile).use { output -> output.write(bytes) }
            targetFile.absolutePath
        } catch (e: Exception) {
            Log.w("AttachmentStorage", "Failed to save inline data: ${e.message}", e)
            null
        }
    }

    suspend fun clearCacheFor(uri: Uri) {
        val key = cacheKeyFor(uri)
        cacheMutex.withLock { attachmentPartCache.remove(key) }
    }

    private fun openStream(uri: Uri): Pair<java.io.InputStream, String?>? {
        return if (uri.scheme == ContentResolver.SCHEME_CONTENT) {
            val stream = context.contentResolver.openInputStream(uri) ?: return null
            stream to context.contentResolver.getType(uri)
        } else {
            val path = uri.path ?: return null
            val file = File(path)
            val canonicalFile = try {
                file.canonicalFile
            } catch (ioe: IOException) {
                Log.w("AttachmentStorage", "Failed to resolve canonical path for $path", ioe)
                return null
            }
            if (!isPathInAppStorage(canonicalFile)) {
                Log.w("AttachmentStorage", "Rejected attachment outside app storage: ${canonicalFile.path}")
                return null
            }
            if (!canonicalFile.exists()) return null
            val stream = FileInputStream(canonicalFile)
            val extension = MimeTypeMap.getFileExtensionFromUrl(canonicalFile.path)?.takeIf { it.isNotBlank() }
            val resolvedMime = extension?.let {
                MimeTypeMap.getSingleton().getMimeTypeFromExtension(it.lowercase(Locale.ROOT))
            }
            stream to resolvedMime
        }
    }

    private fun isPathInAppStorage(file: File): Boolean {
        val root = appFilesCanonicalPath
        val candidatePath = runCatching { file.canonicalPath }.getOrElse { return false }
        return candidatePath == root || candidatePath.startsWith("$root${File.separator}")
    }

    private fun compressAndSaveImage(uri: Uri, fileName: String): File? {
        var originalBitmap: Bitmap? = null
        var rotatedBitmap: Bitmap? = null
        var resizedBitmap: Bitmap? = null

        return try {
            val mimeType = context.contentResolver.getType(uri)
            val isTransparent = mimeType == "image/png" || mimeType == "image/webp"

            context.contentResolver.openInputStream(uri)?.use { stream ->
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeStream(stream, null, options)

                options.inSampleSize = calculateInSampleSize(options, MAX_IMAGE_SIZE, MAX_IMAGE_SIZE)
                options.inJustDecodeBounds = false

                context.contentResolver.openInputStream(uri)?.use { stream2 ->
                    originalBitmap = BitmapFactory.decodeStream(stream2, null, options)
                }
            }

            if (originalBitmap == null) return null

            rotatedBitmap = fixImageOrientation(uri, originalBitmap!!)
            resizedBitmap = resizeBitmap(rotatedBitmap!!, MAX_IMAGE_SIZE, MAX_IMAGE_SIZE)

            val (format, extension) = if (isTransparent) {
                Bitmap.CompressFormat.PNG to "png"
            } else {
                Bitmap.CompressFormat.JPEG to "jpg"
            }

            val file = File(context.filesDir, "$fileName.$extension")
            FileOutputStream(file).use { outputStream ->
                val quality = if (format == Bitmap.CompressFormat.PNG) 100 else IMAGE_QUALITY
                resizedBitmap!!.compress(format, quality, outputStream)
            }
            file
        } catch (e: Exception) {
            e.printStackTrace()
            null
        } finally {
            try {
                resizedBitmap?.takeIf { !it.isRecycled }?.recycle()
                if (rotatedBitmap != originalBitmap) {
                    rotatedBitmap?.takeIf { !it.isRecycled }?.recycle()
                }
                originalBitmap?.takeIf { !it.isRecycled }?.recycle()
            } catch (_: Exception) {
            }
        }
    }

    private fun fixImageOrientation(uri: Uri, bitmap: Bitmap): Bitmap {
        return try {
            val inputStream = context.contentResolver.openInputStream(uri)
            val exif = inputStream?.use { ExifInterface(it) }
            val orientation = exif?.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            ) ?: ExifInterface.ORIENTATION_NORMAL

            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
            }

            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        } catch (e: Exception) {
            e.printStackTrace()
            bitmap
        }
    }

    private fun resizeBitmap(bitmap: Bitmap, maxWidth: Int, maxHeight: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height

        if (width <= maxWidth && height <= maxHeight) {
            return bitmap
        }

        val scaleWidth = maxWidth.toFloat() / width
        val scaleHeight = maxHeight.toFloat() / height
        val scale = minOf(scaleWidth, scaleHeight)

        val newWidth = (width * scale).toInt()
        val newHeight = (height * scale).toInt()

        return Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
    }

    private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
        val (height: Int, width: Int) = options.run { outHeight to outWidth }
        var inSampleSize = 1

        if (height > reqHeight || width > reqWidth) {
            val halfHeight: Int = height / 2
            val halfWidth: Int = width / 2

            while (halfHeight / inSampleSize >= reqHeight && halfWidth / inSampleSize >= reqWidth) {
                inSampleSize *= 2
            }
        }

        return inSampleSize
    }

    private fun cacheKeyFor(uri: Uri): String = uri.toString()

    companion object {
        private const val MAX_IMAGE_SIZE = 2048
        private const val IMAGE_QUALITY = 80
        private const val MAX_FILE_SIZE = 10 * 1024 * 1024 // 10 MB
        private const val CACHE_CAPACITY = 8
        private const val MAX_CACHED_BYTES = 4 * 1024 * 1024 // 4 MB
    }
}
