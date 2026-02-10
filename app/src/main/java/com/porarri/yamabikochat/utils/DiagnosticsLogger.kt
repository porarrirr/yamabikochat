package com.porarri.yamabikochat.utils

import android.content.Context
import android.os.Build
import com.porarri.yamabikochat.BuildConfig
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object DiagnosticsLogger {
    private const val FILE_NAME = "yamabiko_diagnostics.log"
    private const val MAX_BYTES: Long = 512 * 1024

    private val lock = Any()
    private val timestampFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    @Volatile
    private var appContext: Context? = null

    fun isEnabled(): Boolean = BuildConfig.DEBUG || BuildConfig.DIAGNOSTIC

    fun initialize(context: Context) {
        appContext = context.applicationContext
        if (!isEnabled()) return

        log(
            "Diagnostics enabled. " +
                "version=${BuildConfig.VERSION_NAME}(${BuildConfig.VERSION_CODE}) " +
                "device=${Build.MANUFACTURER}/${Build.MODEL} api=${Build.VERSION.SDK_INT}"
        )
    }

    fun log(message: String, throwable: Throwable? = null) {
        if (!isEnabled()) return
        val context = appContext ?: return
        val timestamp = timestampFormat.format(Date())
        val entry = buildString {
            append(timestamp)
            append(" | ")
            append(message)
            append('\n')
            if (throwable != null) {
                append(throwable::class.java.name)
                throwable.message?.let {
                    if (it.isNotBlank()) {
                        append(": ")
                        append(it)
                    }
                }
                append('\n')
                append(throwable.stackTraceToString())
                append('\n')
            }
        }

        synchronized(lock) {
            val file = logFile(context)
            if (file.exists() && file.length() > MAX_BYTES) {
                file.writeText("")
            }
            file.appendText(entry)
        }
    }

    fun read(): String {
        val context = appContext ?: return ""
        val file = logFile(context)
        if (!file.exists()) return ""
        return runCatching { file.readText() }.getOrDefault("")
    }

    fun clear() {
        val context = appContext ?: return
        synchronized(lock) {
            val file = logFile(context)
            if (file.exists()) file.writeText("")
        }
    }

    private fun logFile(context: Context): File = File(context.filesDir, FILE_NAME)
}

