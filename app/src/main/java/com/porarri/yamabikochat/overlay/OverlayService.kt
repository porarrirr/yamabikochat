package com.porarri.yamabikochat.overlay

import android.content.Context
import android.content.Context.WINDOW_SERVICE
import android.content.Intent
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.ElevatedButton
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material.icons.filled.Close
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.unit.dp
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalSavedStateRegistryOwner
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import com.porarri.yamabikochat.MyApplication
import com.porarri.yamabikochat.ui.chat.ChatScreen
import com.porarri.yamabikochat.ui.chat.ChatViewModel
import com.porarri.yamabikochat.ui.theme.MyApplicationTheme

class OverlayService : LifecycleService(), ViewModelStoreOwner, SavedStateRegistryOwner {

    companion object {
        const val ACTION_SHOW_TOOLBAR = "com.porarri.yamabikochat.action.SHOW_TOOLBAR"
        const val ACTION_HIDE_ALL = "com.porarri.yamabikochat.action.HIDE_ALL"
        const val ACTION_SHOW_CHAT_CONFIRM = "com.porarri.yamabikochat.action.SHOW_CHAT_CONFIRM"
        const val ACTION_SHOW_CHAT_TRANSLATE = "com.porarri.yamabikochat.action.SHOW_CHAT_TRANSLATE"
        const val EXTRA_INITIAL_PROMPT = "com.porarri.yamabikochat.extra.INITIAL_PROMPT"

        fun startToolbar(context: Context) {
            val intent = Intent(context, OverlayService::class.java).apply {
                action = ACTION_SHOW_TOOLBAR
            }
            context.startService(intent)
        }

        fun hideAll(context: Context) {
            val intent = Intent(context, OverlayService::class.java).apply {
                action = ACTION_HIDE_ALL
            }
            context.startService(intent)
        }
    }

    private val savedStateController = SavedStateRegistryController.create(this)
    private val internalViewModelStore = ViewModelStore()

    private lateinit var windowManager: WindowManager
    private var toolbarView: View? = null
    private var chatView: View? = null

    override fun onCreate() {
        super.onCreate()
        savedStateController.performAttach()
        savedStateController.performRestore(null)
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
    }

    override fun onDestroy() {
        removeChat()
        removeToolbar()
        internalViewModelStore.clear()
        super.onDestroy()
    }

    override val savedStateRegistry: SavedStateRegistry
        get() = savedStateController.savedStateRegistry

    override val viewModelStore: ViewModelStore
        get() = internalViewModelStore

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Call super to satisfy lint's MissingSuperCall requirement
        super.onStartCommand(intent, flags, startId)
        // If an explicit initial prompt is supplied (e.g., from PROCESS_TEXT), honor it first
        val explicitPrompt = intent?.getStringExtra(EXTRA_INITIAL_PROMPT)
        if (!explicitPrompt.isNullOrBlank()) {
            ensurePermissionThen { showChatOverlay(initialPrompt = explicitPrompt) }
            return START_NOT_STICKY
        }

        when (intent?.action) {
            ACTION_SHOW_TOOLBAR -> ensurePermissionThen { showToolbar() }
            ACTION_SHOW_CHAT_CONFIRM -> ensurePermissionThen { showChatOverlay(initialPrompt = null) }
            ACTION_SHOW_CHAT_TRANSLATE -> ensurePermissionThen { showChatOverlay(initialPrompt = "日本語訳して") }
            ACTION_HIDE_ALL -> { removeChat(); removeToolbar(); stopSelf() }
            else -> ensurePermissionThen { showToolbar() }
        }
        return START_NOT_STICKY
    }

    private fun ensurePermissionThen(block: () -> Unit) {
        if (Settings.canDrawOverlays(this)) {
            block()
        } else {
            val uri = Uri.parse("package:$packageName")
            val permIntent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(permIntent)
        }
    }

    private fun showToolbar() {
        if (toolbarView != null) return

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 24
            y = 200
        }

        val view = ComposeView(this)
        view.setContent {
            MyApplicationTheme {
                CompositionLocalProvider(
                    LocalLifecycleOwner provides this@OverlayService,
                    LocalViewModelStoreOwner provides this@OverlayService,
                    LocalSavedStateRegistryOwner provides this@OverlayService
                ) {
                    ToolbarContent(
                        onConfirm = { showChatOverlay(initialPrompt = null) },
                        onTranslate = { showChatOverlay(initialPrompt = "日本語訳して") },
                        onClose = { removeChat(); removeToolbar(); stopSelf() }
                    )
                }
            }
        }

        // Simple drag to move
        view.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f
            override fun onTouch(v: View?, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = params.x
                        initialY = params.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        return false
                    }
                    MotionEvent.ACTION_MOVE -> {
                        params.x = initialX + (event.rawX - initialTouchX).toInt()
                        params.y = initialY + (event.rawY - initialTouchY).toInt()
                        windowManager.updateViewLayout(view, params)
                        return true
                    }
                }
                return false
            }
        })

        windowManager.addView(view, params)
        toolbarView = view
    }

    private fun removeToolbar() {
        toolbarView?.let { windowManager.removeView(it) }
        toolbarView = null
    }

    private fun showChatOverlay(initialPrompt: String?) {
        removeChat()

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            // Focusable to receive IME and touches
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }

        val app = application as MyApplication
        val chatVm = ViewModelProvider(this, app.viewModelFactory)[ChatViewModel::class.java]

        val view = ComposeView(this)
        view.setContent {
            MyApplicationTheme {
                CompositionLocalProvider(
                    LocalLifecycleOwner provides this@OverlayService,
                    LocalViewModelStoreOwner provides this@OverlayService,
                    LocalSavedStateRegistryOwner provides this@OverlayService
                ) {
                    // Dim scrim + translucent container for a modern overlay look
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(Color.Black.copy(alpha = 0.28f))
                    ) {
                        Surface(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(12.dp),
                            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f),
                            tonalElevation = 6.dp,
                            shadowElevation = 16.dp,
                            shape = RoundedCornerShape(18.dp),
                            border = androidx.compose.foundation.BorderStroke(
                                1.dp,
                                MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
                            )
                        ) {
                            ChatScreen(
                                viewModel = chatVm,
                                initialPrompt = initialPrompt,
                                showCloseButton = true,
                                onClose = { removeChat() }
                            )
                        }
                    }
                }
            }
        }

        windowManager.addView(view, params)
        chatView = view
    }

    private fun removeChat() {
        chatView?.let { windowManager.removeView(it) }
        chatView = null
    }

    @Composable
    private fun ToolbarContent(
        onConfirm: () -> Unit,
        onTranslate: () -> Unit,
        onClose: () -> Unit
    ) {
        val bg = MaterialTheme.colorScheme.surface.copy(alpha = 0.60f)
        val border = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f)
        Surface(
            color = bg,
            tonalElevation = 8.dp,
            shadowElevation = 16.dp,
            shape = RoundedCornerShape(20.dp),
            modifier = Modifier
                .border(1.dp, border, RoundedCornerShape(20.dp))
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)
            ) {
                val btnColors = ButtonDefaults.filledTonalButtonColors(
                    containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.55f),
                    contentColor = MaterialTheme.colorScheme.onSurface
                )
                ElevatedButton(onClick = onConfirm, colors = btnColors) {
                    Icon(Icons.Default.CheckCircle, contentDescription = null)
                    Text(" やまびこで確認")
                }
                ElevatedButton(onClick = onTranslate, colors = btnColors) {
                    Icon(Icons.Default.Translate, contentDescription = null)
                    Text(" やまびこで翻訳")
                }
                ElevatedButton(onClick = onClose, colors = btnColors) {
                    Icon(Icons.Default.Close, contentDescription = null)
                    Text(" 閉じる")
                }
            }
        }
    }
}
