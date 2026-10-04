package com.warrantycave.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.plugin.common.MethodChannel

internal class PlayUpdates(private val activity: Activity, private val channel: MethodChannel) {
    companion object {
        const val REQUEST = 4210
        private val state = UpdateState()
        private var owner = 0L
        private var stoppedAt = 0L
        private var finishedVisit = true
        private var current: PlayUpdates? = null
    }
    private val identity = ++owner
    private val manager = AppUpdateManagerFactory.create(activity.applicationContext)
    private val handler = Handler(Looper.getMainLooper())
    private var resumed = false
    private var listening = false
    private var revision = 0L
    private var query = 0L
    private var queryStarted = 0L
    private var info: AppUpdateInfo? = null
    private val poll = object : Runnable {
        override fun run() { if (resumed) { check(); handler.postDelayed(this, 30_000) } }
    }
    private val listener = InstallStateUpdatedListener {
        if (owner != identity) return@InstallStateUpdatedListener
        revision++
        state.observe(state.version, stage(it.installStatus()), it.bytesDownloaded(), it.totalBytesToDownload())
        emit()
    }
    init {
        current = this
        @Suppress("DEPRECATION")
        state.installed = activity.packageManager.getPackageInfo(activity.packageName, 0).versionCode
        if (finishedVisit && !state.consent) state.newVisit()
        finishedVisit = false
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "state" -> { result.success(state.snapshot()); check() }
                "later" -> { state.later(); emit(); result.success(null) }
                "update" -> { download(); result.success(null) }
                "restart" -> { restart(); result.success(null) }
                "store" -> { openStore(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    fun resume() {
        if (owner != identity) return
        // Short interruptions (including a permission prompt) retain Later.
        if (!state.consent && stoppedAt != 0L && SystemClock.elapsedRealtime() - stoppedAt > 30_000) state.newVisit()
        resumed = true
        if (!listening) { manager.registerListener(listener); listening = true }
        handler.removeCallbacks(poll); handler.post(poll)
        emit()
    }
    fun pause() { resumed = false; stoppedAt = SystemClock.elapsedRealtime(); handler.removeCallbacks(poll) }
    fun destroy(changing: Boolean) {
        if (listening) manager.unregisterListener(listener)
        handler.removeCallbacksAndMessages(null)
        if (owner == identity) {
            query++; channel.setMethodCallHandler(null); current = null
            if (!changing && !state.consent) finishedVisit = true
        }
    }
    fun newIntent(intent: Intent) {
        if (intent.action == Intent.ACTION_MAIN && intent.hasCategory(Intent.CATEGORY_LAUNCHER) && !state.consent) {
            state.newVisit(); emit(); check()
        }
    }
    private fun emit() { if (owner == identity) channel.invokeMethod("changed", state.snapshot()) }
    private fun stage(status: Int) = when (status) {
        InstallStatus.PENDING -> "waiting"
        InstallStatus.DOWNLOADING -> "downloading"
        InstallStatus.DOWNLOADED -> "ready"
        InstallStatus.INSTALLING -> "installing"
        InstallStatus.INSTALLED -> "installed"
        InstallStatus.FAILED, InstallStatus.CANCELED -> "stopped"
        else -> "idle"
    }
    private fun check() {
        if (!resumed || state.consent || owner != identity) return
        val now = SystemClock.elapsedRealtime()
        if (queryStarted != 0L && now - queryStarted < 15_000) return
        val ticket = ++query; val observation = revision
        queryStarted = now
        manager.appUpdateInfo.addOnCompleteListener { task ->
            if (owner != identity || ticket != query) return@addOnCompleteListener
            queryStarted = 0
            if (!resumed || state.consent || revision != observation || !task.isSuccessful) return@addOnCompleteListener
            val next = task.result
            info = next
            state.flexible = next.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE)
            if (next.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE || next.installStatus() != InstallStatus.UNKNOWN) {
                state.observe(next.availableVersionCode(), stage(next.installStatus()), next.bytesDownloaded(), next.totalBytesToDownload())
            } else if (state.stage == "idle" || state.version <= state.installed) {
                state.version = 0; state.stage = "idle"
            }
            emit()
        }
    }
    private fun download() {
        if (state.offer() != "available" || state.consent) return
        val available = info ?: return
        info = null; query++; queryStarted = 0; revision++
        state.consent = true; emit()
        try {
            val started = manager.startUpdateFlowForResult(available, activity,
                AppUpdateOptions.newBuilder(AppUpdateType.FLEXIBLE).build(), REQUEST)
            if (!started) consentFailed()
        } catch (_: Exception) { consentFailed() }
    }
    private fun consentFailed() { state.consent = false; state.flexible = false; state.stage = "stopped"; emit() }
    fun result(code: Int) {
        state.consent = false; revision++
        if (state.stage !in listOf("ready", "downloading", "installing", "installed")) {
            if (code == Activity.RESULT_OK) state.stage = "waiting"
            else { state.stage = "idle"; state.later() }
        }
        query++; queryStarted = 0; emit(); check()
    }
    private fun restart() {
        if (!state.beginInstall()) return
        query++; queryStarted = 0; revision++; emit()
        manager.completeUpdate().addOnFailureListener {
            state.failInstall(); current?.emit()
        }
    }
    private fun openStore() {
        state.later(); emit()
        try {
            activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=${activity.packageName}")).setPackage("com.android.vending"))
        } catch (_: Exception) {
            activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=${activity.packageName}")))
        }
    }
}
