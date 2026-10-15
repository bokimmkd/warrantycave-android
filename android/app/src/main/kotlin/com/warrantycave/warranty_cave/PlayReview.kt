package com.warrantycave.app

import android.app.Activity
import android.os.SystemClock
import android.util.AtomicFile
import com.google.android.play.core.review.ReviewInfo
import com.google.android.play.core.review.ReviewManagerFactory
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

/** Attempt != rating: Play may silently suppress its UI. No automatic Store fallback. */
internal class PlayReview(private val activity: Activity, channel: MethodChannel) {
    companion object { private var sessionAttempted = false }
    private val file = AtomicFile(File(activity.noBackupFilesDir, "play_review_v1"))
    private val manager = ReviewManagerFactory.create(activity)
    private var prepared: ReviewInfo? = null
    private var preparedAt = 0L
    private fun state(): JSONObject = try {
        file.openRead().use { JSONObject(it.readBytes().toString(Charsets.UTF_8)) }
    } catch (_: Exception) { JSONObject() }
    private fun save(value: JSONObject) {
        val stream = file.startWrite()
        try { stream.write(value.toString().toByteArray(Charsets.UTF_8)); file.finishWrite(stream) }
        catch (error: Exception) { file.failWrite(stream); throw error }
    }
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                val count = call.argument<Int>("count") ?: 0
                when (call.method) {
                    "observe" -> {
                        val value = state()
                        if (!value.has("existing")) { value.put("existing", count > 0 || call.argument<Boolean>("existingAccount") == true); save(value) }
                        result.success(null)
                    }
                    "prepare" -> {
                        val value = state()
                        val now = System.currentTimeMillis()
                        @Suppress("DEPRECATION")
                        val installer = activity.packageManager.getInstallerPackageName(activity.packageName)
                        if (sessionAttempted || installer != "com.android.vending" || !activity.hasWindowFocus() ||
                            !ReviewPolicy.eligible(count, value.optBoolean("existing"), value.optLong("lastAttempt"), now)) {
                            result.success(false)
                        } else {
                            // Claim before async work, surviving rotation/restart and API failure.
                            value.put("lastAttempt", now); save(value); sessionAttempted = true
                            manager.requestReviewFlow().addOnCompleteListener { task ->
                                if (task.isSuccessful && !activity.isFinishing && !activity.isDestroyed) {
                                    prepared = task.result; preparedAt = SystemClock.elapsedRealtime()
                                    result.success(true)
                                } else result.success(false)
                            }
                        }
                    }
                    "launch" -> {
                        val info = prepared; prepared = null
                        if (info == null || activity.isFinishing || activity.isDestroyed || !activity.hasWindowFocus() ||
                            SystemClock.elapsedRealtime() - preparedAt > 10_000) result.success(false)
                        else manager.launchReviewFlow(activity, info).addOnCompleteListener { result.success(true) }
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.success(false) }
        }
    }
}
