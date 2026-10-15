package com.warrantycave.app

import android.content.Context
import android.os.Bundle
import android.util.AtomicFile
import com.google.firebase.analytics.FirebaseAnalytics
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Independent of UMP/Meta. No identifiers or user-supplied event parameters. */
internal object UsageAnalytics {
    private fun choiceFile(context: Context) = AtomicFile(File(context.noBackupFilesDir, "usage_analytics_choice_v1"))
    private fun choice(context: Context): String? = runCatching {
        choiceFile(context).openRead().use { it.readBytes().toString(Charsets.UTF_8) }
    }.getOrNull()

    private fun apply(context: Context, enabled: Boolean) {
        val analytics = FirebaseAnalytics.getInstance(context)
        analytics.setConsent(mapOf(
            FirebaseAnalytics.ConsentType.ANALYTICS_STORAGE to if (enabled) FirebaseAnalytics.ConsentStatus.GRANTED else FirebaseAnalytics.ConsentStatus.DENIED,
            FirebaseAnalytics.ConsentType.AD_STORAGE to FirebaseAnalytics.ConsentStatus.DENIED,
            FirebaseAnalytics.ConsentType.AD_USER_DATA to FirebaseAnalytics.ConsentStatus.DENIED,
            FirebaseAnalytics.ConsentType.AD_PERSONALIZATION to FirebaseAnalytics.ConsentStatus.DENIED))
        analytics.setAnalyticsCollectionEnabled(enabled)
        if (!enabled) analytics.resetAnalyticsData()
    }

    fun attach(context: Context, channel: MethodChannel) {
        // The manifest and backup exclusions keep first/ transferred installs off.
        runCatching { apply(context, choice(context) == "true") }
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "choice" -> result.success(choice(context)?.let { it == "true" })
                    "setConsent" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: error("Missing choice")
                        // Disable before persistence on revoke, so a disk error fails closed.
                        if (!enabled) apply(context, false)
                        val file = choiceFile(context)
                        val stream = file.startWrite()
                        try {
                            stream.write(enabled.toString().toByteArray(Charsets.UTF_8))
                            file.finishWrite(stream)
                        } catch (error: Exception) { file.failWrite(stream); throw error }
                        apply(context, enabled)
                        result.success(null)
                    }
                    "event" -> {
                        if (choice(context) == "true") {
                            val name = call.argument<String>("name")
                            val method = call.argument<String>("method")
                            when {
                                name == "warranty_created" -> FirebaseAnalytics.getInstance(context).logEvent(name, null)
                                name == FirebaseAnalytics.Event.SIGN_UP && method in setOf("password", "google") ->
                                    FirebaseAnalytics.getInstance(context).logEvent(name, Bundle().apply { putString(FirebaseAnalytics.Param.METHOD, method) })
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("measurement_unavailable", "Please try again", null) }
        }
    }
}
