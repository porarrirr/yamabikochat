package com.porarri.yamabikochat.actions

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import com.porarri.yamabikochat.MainActivity
import com.porarri.yamabikochat.overlay.OverlayService

/**
 * Text selection "Process Text" entry point.
 * It receives the selected text and forwards it to [OverlayService]
 * with an initial prompt, then finishes immediately (no UI).
 */
class ProcessTextActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val launchIntent = intent
        if (!isValidProcessTextIntent(launchIntent)) {
            Log.w(TAG, "Rejected non-PROCESS_TEXT invocation: $launchIntent")
            finish()
            return
        }

        val selectedRaw = launchIntent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)
            ?.toString()
            ?.trim()
            ?: ""
        val selected = if (selectedRaw.length > MAX_PROCESS_TEXT_LENGTH) {
            selectedRaw.take(MAX_PROCESS_TEXT_LENGTH) + "…"
        } else {
            selectedRaw
        }

        // Determine which alias launched this activity (ask or translate)
        val mode = try {
            val info = packageManager.getActivityInfo(componentName, PackageManager.GET_META_DATA)
            info.metaData?.getString(META_MODE) ?: MODE_ASK
        } catch (_: Exception) {
            MODE_ASK
        }

        val initialPrompt = when (mode) {
            MODE_TRANSLATE -> if (selected.isNotEmpty()) {
                // Keep short and clear for the chat box input
                "日本語に翻訳:\n$selected"
            } else {
                "日本語に翻訳"
            }
            else -> selected
        }

        if (!Settings.canDrawOverlays(this)) {
            Toast.makeText(
                this,
                getString(com.porarri.yamabikochat.R.string.overlay_permission_required_for_process_text),
                Toast.LENGTH_LONG
            ).show()
            val appIntent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra(OverlayService.EXTRA_INITIAL_PROMPT, initialPrompt)
            }
            startActivity(appIntent)
            finish()
            return
        }

        // Start overlay with prefilled prompt
        val svc = Intent(this, OverlayService::class.java).apply {
            putExtra(OverlayService.EXTRA_INITIAL_PROMPT, initialPrompt)
        }
        startService(svc)

        // Finish instantly to return to the original app
        finish()
    }

    companion object {
        private const val TAG = "ProcessTextActivity"
        private const val META_MODE = "com.porarri.yamabikochat.PROCESS_TEXT_MODE"
        private const val MODE_ASK = "ask"
        private const val MODE_TRANSLATE = "translate"
        private const val MAX_PROCESS_TEXT_LENGTH = 4000
    }

    private fun isValidProcessTextIntent(intent: Intent?): Boolean {
        if (intent == null) {
            return false
        }
        if (intent.action != Intent.ACTION_PROCESS_TEXT) {
            return false
        }
        val mimeType = intent.type
        return mimeType?.startsWith("text/") == true || intent.hasExtra(Intent.EXTRA_PROCESS_TEXT)
    }
}
