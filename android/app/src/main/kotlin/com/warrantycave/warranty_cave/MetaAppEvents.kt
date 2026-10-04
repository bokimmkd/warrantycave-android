package com.warrantycave.app

import android.app.Activity
import android.content.Context
import android.os.SystemClock
import android.util.AtomicFile
import com.facebook.FacebookSdk
import com.facebook.appevents.AppEventsConstants
import com.facebook.appevents.AppEventsLogger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/** Only install/activation measurement. No login, billing or warranty payloads. */
internal object MetaAppEvents {
    private const val CONSENT = "explicit_install_measurement_consent_v1"
    private val session = MetaActivationSession()
    private var activatedSdk = false

    // Android backup/device transfer must not opt another installation into measurement.
    private fun consent(context: Context): Boolean = runCatching {
        File(context.noBackupFilesDir, CONSENT).readText() == "true"
    }.getOrDefault(false)

    private fun saveConsent(context: Context, enabled: Boolean): Boolean {
        val file = AtomicFile(File(context.noBackupFilesDir, CONSENT))
        var output: FileOutputStream? = null
        return try {
            output = file.startWrite()
            output.write(enabled.toString().toByteArray(Charsets.UTF_8))
            file.finishWrite(output)
            true
        } catch (_: Exception) {
            file.failWrite(output)
            false
        }
    }

    fun attach(activity: Activity, channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getConsent" -> result.success(consent(activity))
                "setConsent" -> {
                    val enabled = call.argument<Boolean>("enabled")
                    if (enabled == null) {
                        result.error("invalid_consent", "Missing consent choice", null)
                    } else {
                        // Persist before doing any SDK work so a later launch respects the choice.
                        val saved = saveConsent(activity, enabled)
                        if (!saved) {
                            result.error("consent_not_saved", "Please try again", null)
                        } else try {
                            if (enabled) {
                                if (!foreground(activity)) throw IllegalStateException("SDK unavailable")
                            } else {
                                session.reset()
                                if (FacebookSdk.isInitialized()) {
                                    FacebookSdk.setAdvertiserIDCollectionEnabled(false)
                                    FacebookSdk.setAutoLogAppEventsEnabled(false)
                                    FacebookSdk.setLimitEventAndDataUsage(activity, true)
                                }
                            }
                            result.success(null)
                        } catch (_: Exception) {
                            // Keep the user's choice, allow retry, and never break the app.
                            result.error("measurement_unavailable", "Please try again", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    fun foreground(activity: Activity): Boolean {
        if (!consent(activity)) return false
        try {
            // FacebookInitProvider is removed from the merged manifest: even basic SDK
            // configuration requests must wait for the explicit choice above.
            if (!FacebookSdk.isInitialized()) FacebookSdk.sdkInitialize(activity.applicationContext)
            FacebookSdk.fullyInitialize()
            FacebookSdk.setAutoLogAppEventsEnabled(false)
            FacebookSdk.setAdvertiserIDCollectionEnabled(true)
            FacebookSdk.setLimitEventAndDataUsage(activity, false)
            AppEventsLogger.setFlushBehavior(AppEventsLogger.FlushBehavior.EXPLICIT_ONLY)
            if (!activatedSdk) {
                // The SDK install publisher deduplicates by its stored install timestamp.
                // Do not register activateApp's automatic ActivityLifecycleTracker: it
                // can start codeless/advanced-matching view observation. We emit only
                // our consent-gated activation events below.
                FacebookSdk.publishInstallAsync(activity.applicationContext, FacebookSdk.getApplicationId())
                activatedSdk = true
            }
            // Automatic/codeless/purchase logging stays off. Session events are gated here.
            if (session.foreground(SystemClock.elapsedRealtime())) {
                AppEventsLogger.newLogger(activity.applicationContext).apply {
                    logEvent(AppEventsConstants.EVENT_NAME_ACTIVATED_APP)
                    flush()
                }
            }
            return true
        } catch (_: Exception) {
            // Attribution availability must never affect Firebase, Play or rendering.
            return false
        }
    }

    fun background() { session.background(SystemClock.elapsedRealtime()) }
}
