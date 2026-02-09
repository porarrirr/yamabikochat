package com.porarri.yamabikochat.utils

import android.content.ContentResolver
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import com.porarri.yamabikochat.TestLogUtils
import io.mockk.clearAllMocks
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayInputStream

class FileValidationUtilsTest {

    private lateinit var context: Context
    private lateinit var contentResolver: ContentResolver
    private lateinit var uri: Uri

    @Before
    fun setup() {
        TestLogUtils.setup()
        clearAllMocks()
        context = mockk()
        contentResolver = mockk()
        uri = mockk()

        every { context.contentResolver } returns contentResolver
        every { uri.path } returns "test.jpg"
        every { uri.toString() } returns "content://test.jpg"
        every { contentResolver.openFileDescriptor(uri, "r") } returns null
        mockkStatic(MimeTypeMap::class)
        every { MimeTypeMap.getFileExtensionFromUrl(any<String>()) } answers {
            val url = it.invocation.args.first() as String
            url.substringAfterLast('.', "").takeIf { ext -> ext.isNotBlank() }
        }
    }

    @After
    fun tearDown() {
        TestLogUtils.tearDown()
        unmockkStatic(MimeTypeMap::class)
    }

    private fun stubFileSize(size: Long) {
        val cursor = mockk<Cursor>()
        every { cursor.getColumnIndex(OpenableColumns.SIZE) } returns 0
        every { cursor.moveToFirst() } returns true
        every { cursor.getLong(0) } returns size
        every { cursor.close() } returns Unit
        every { contentResolver.query(uri, any(), any(), any(), any()) } returns cursor
    }

    private fun stubFileContent(bytes: ByteArray) {
        every { contentResolver.openInputStream(uri) } answers {
            ByteArrayInputStream(bytes)
        }
    }

    private fun buildImageBytes(header: ByteArray, size: Int): ByteArray {
        require(size >= header.size)
        return ByteArray(size).also { target ->
            header.copyInto(target)
        }
    }

    @Test
    fun validateFile_returnsValidForJpeg() = runTest {
        val jpegHeader = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte())
        val fileSize = 1024
        stubFileSize(fileSize.toLong())
        stubFileContent(buildImageBytes(jpegHeader, fileSize))
        every { contentResolver.getType(uri) } returns "image/jpeg"

        val result = FileValidationUtils.validateFile(context, uri)

        assertTrue("Expected Valid but was $result", result is FileValidationUtils.FileValidationResult.Valid)
        val validResult = result as FileValidationUtils.FileValidationResult.Valid
        assertEquals("image/jpeg", validResult.mimeType)
        assertEquals(fileSize.toLong(), validResult.fileSize)
    }

    @Test
    fun validateFile_returnsTooLargeForOversizedFile() = runTest {
        val oversized = 15 * 1024 * 1024L
        stubFileSize(oversized)
        every { contentResolver.getType(uri) } returns "image/jpeg"

        val result = FileValidationUtils.validateFile(context, uri)

        assertTrue("Expected TooLarge but was $result", result is FileValidationUtils.FileValidationResult.TooLarge)
        val tooLarge = result as FileValidationUtils.FileValidationResult.TooLarge
        assertEquals(oversized, tooLarge.fileSize)
    }

    @Test
    fun validateFile_returnsTooSmallForEmptyFile() = runTest {
        stubFileSize(0)
        every { contentResolver.getType(uri) } returns "image/jpeg"

        val result = FileValidationUtils.validateFile(context, uri)

        assertTrue("Expected TooSmall but was $result", result is FileValidationUtils.FileValidationResult.TooSmall)
    }

    @Test
    fun validateFile_returnsDangerousFileForExecutableExtension() = runTest {
        every { uri.path } returns "malware.exe"
        every { uri.toString() } returns "content://malware.exe"
        stubFileSize(1024)
        every { contentResolver.getType(uri) } returns "application/octet-stream"

        val result = FileValidationUtils.validateFile(context, uri)

        assertTrue("Expected DangerousFile but was $result", result is FileValidationUtils.FileValidationResult.DangerousFile)
    }

    @Test
    fun validateFile_handlesPdfFiles() = runTest {
        val pdfHeader = byteArrayOf(0x25, 0x50, 0x44, 0x46, 0x2D) // %PDF-
        val fileSize = 2048
        stubFileSize(fileSize.toLong())
        stubFileContent(buildImageBytes(pdfHeader, fileSize))
        every { contentResolver.getType(uri) } returns "application/pdf"

        val result = FileValidationUtils.validateFile(context, uri)

        assertTrue("Expected Valid but was $result", result is FileValidationUtils.FileValidationResult.Valid)
        val validResult = result as FileValidationUtils.FileValidationResult.Valid
        assertEquals("application/pdf", validResult.mimeType)
    }

    @Test
    fun validateFile_returnsCorruptedFileForInvalidSignature() = runTest {
        val invalidHeader = ByteArray(FileValidationUtilsTestSupport.FILE_HEADER_SIZE) { 0 }
        stubFileSize(1024)
        stubFileContent(invalidHeader)
        every { contentResolver.getType(uri) } returns "image/jpeg"

        val result = FileValidationUtils.validateFile(context, uri)

        assertTrue("Expected CorruptedFile but was $result", result is FileValidationUtils.FileValidationResult.CorruptedFile)
    }

    @Test
    fun validateFile_handlesPngFiles() = runTest {
        val pngHeader = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        val fileSize = 2048
        stubFileSize(fileSize.toLong())
        stubFileContent(buildImageBytes(pngHeader, fileSize))
        every { contentResolver.getType(uri) } returns "image/png"

        val result = FileValidationUtils.validateFile(context, uri)

        assertTrue("Expected Valid but was $result", result is FileValidationUtils.FileValidationResult.Valid)
        val validResult = result as FileValidationUtils.FileValidationResult.Valid
        assertEquals("image/png", validResult.mimeType)
    }

    @Test
    fun validateFile_handlesWebpFiles() = runTest {
        val webpHeader = byteArrayOf(0x52, 0x49, 0x46, 0x46)
        val fileSize = 4096
        stubFileSize(fileSize.toLong())
        stubFileContent(buildImageBytes(webpHeader, fileSize))
        every { contentResolver.getType(uri) } returns "image/webp"

        val result = FileValidationUtils.validateFile(context, uri)

        assertTrue("Expected Valid but was $result", result is FileValidationUtils.FileValidationResult.Valid)
        val validResult = result as FileValidationUtils.FileValidationResult.Valid
        assertEquals("image/webp", validResult.mimeType)
    }

    @Test
    fun validateFile_rejectsUnknownImageSubtype() = runTest {
        val pngHeader = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        val fileSize = 1024
        stubFileSize(fileSize.toLong())
        stubFileContent(buildImageBytes(pngHeader, fileSize))
        every { contentResolver.getType(uri) } returns "image/tiff"

        val result = FileValidationUtils.validateFile(context, uri)

        assertTrue("Expected UnsupportedType but was $result", result is FileValidationUtils.FileValidationResult.UnsupportedType)
    }

    @Test
    fun validateFile_returnsErrorWhenExceptionOccurs() = runTest {
        every { contentResolver.getType(uri) } throws RuntimeException("Content resolver error")

        val result = FileValidationUtils.validateFile(context, uri)

        assertTrue("Expected Error but was $result", result is FileValidationUtils.FileValidationResult.Error)
        val errorResult = result as FileValidationUtils.FileValidationResult.Error
        assertEquals("Content resolver error", errorResult.message)
    }

    @Test
    fun sanitizeFileName_removesDangerousCharacters() {
        val sanitized = FileValidationUtils.sanitizeFileName("file@#$.txt")
        assertEquals("file___.txt", sanitized)

        val emptySanitized = FileValidationUtils.sanitizeFileName("")
        assertTrue(emptySanitized.startsWith("file_"))

        val longSanitized = FileValidationUtils.sanitizeFileName("a".repeat(300))
        assertEquals(255, longSanitized.length)
    }

    @Test
    fun isFileSizeWithinLimit_validatesBoundaries() {
        assertTrue(FileValidationUtils.isFileSizeWithinLimit(1))
        assertTrue(FileValidationUtils.isFileSizeWithinLimit(10 * 1024 * 1024))
        assertFalse(FileValidationUtils.isFileSizeWithinLimit(0))
        assertFalse(FileValidationUtils.isFileSizeWithinLimit(15 * 1024 * 1024))
    }
}

private object FileValidationUtilsTestSupport {
    const val FILE_HEADER_SIZE = 32
}
