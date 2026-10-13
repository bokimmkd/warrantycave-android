package com.warrantycave.app

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var playUpdates: PlayUpdates? = null
    private val shortcutChannelName = "com.warrantycave.app/shortcuts"
    private var shortcutChannel: MethodChannel? = null
    private val saveRequestCode = 4209
    private var pendingPdf: ByteArray? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        playUpdates = PlayUpdates(this, MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.warrantycave.app/play_updates"))
        MetaAppEvents.attach(this, MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.warrantycave.app/meta_app_events"))
        shortcutChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shortcutChannelName)
        shortcutChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialShortcut") result.success(shortcutFrom(intent))
            else result.notImplemented()
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.warrantycave.app/document_saver")
            .setMethodCallHandler { call, result ->
                if (call.method != "savePdf") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.error("busy", "A PDF is already being saved.", null)
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val fileName = call.argument<String>("fileName")
                if (bytes == null || fileName.isNullOrBlank()) {
                    result.error("invalid_pdf", "Missing PDF data.", null)
                    return@setMethodCallHandler
                }
                pendingPdf = bytes
                pendingResult = result
                try {
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/pdf"
                        putExtra(Intent.EXTRA_TITLE, fileName)
                    }
                    startActivityForResult(intent, saveRequestCode)
                } catch (error: Exception) {
                    pendingPdf = null
                    pendingResult = null
                    result.error("save_unavailable", error.message, null)
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        playUpdates?.newIntent(intent)
        shortcutFrom(intent)?.let { shortcutChannel?.invokeMethod("openShortcut", it) }
    }

    override fun onResume() { super.onResume(); playUpdates?.resume(); MetaAppEvents.foreground(this) }
    override fun onPause() { MetaAppEvents.background(); playUpdates?.pause(); super.onPause() }
    override fun onDestroy() { playUpdates?.destroy(isChangingConfigurations); super.onDestroy() }

    private fun shortcutFrom(intent: Intent?): String? = when (intent?.action) {
        "com.warrantycave.app.ADD_WARRANTY" -> "add"
        "com.warrantycave.app.MY_ITEMS" -> "items"
        "com.warrantycave.app.REMINDERS" -> "reminders"
        "com.warrantycave.app.EXPIRING_SOON" -> "expiring"
        else -> null
    }

    @Deprecated("Uses the Android document picker result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PlayUpdates.REQUEST) { playUpdates?.result(resultCode); return }
        if (requestCode != saveRequestCode) return
        val result = pendingResult ?: return
        val bytes = pendingPdf
        pendingResult = null
        pendingPdf = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(false)
            return
        }
        try {
            contentResolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes ?: error("Missing PDF data"))
            } ?: error("Could not open the selected file")
            result.success(true)
        } catch (error: Exception) {
            result.error("save_failed", error.message, null)
        }
    }
}
