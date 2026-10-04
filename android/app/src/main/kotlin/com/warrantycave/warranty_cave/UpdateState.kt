package com.warrantycave.app

// Process-retained state: activity recreation and Play consent are not a new visit.
internal class UpdateState {
    var version = 0
    var installed = 0
    var stage = "idle"
    var bytes = 0L
    var total = 0L
    var deferredOffer = 0
    var deferredRestart = 0
    var consent = false
    var installFailed = false
    var flexible = false
    var completed = 0

    fun newVisit() { deferredOffer = 0; deferredRestart = 0 }
    fun observe(v: Int, status: String, downloaded: Long = 0, size: Long = 0) {
        if (v <= installed || v <= completed) {
            if (version <= installed) { version = 0; stage = "idle"; bytes = 0; total = 0 }
            return
        }
        if (v < version) return
        if (v == version && stage in listOf("ready", "installing") && status in listOf("idle", "waiting", "downloading", "ready")) return
        if (v == version && stage in listOf("waiting", "downloading") && status == "idle") return
        version = v; stage = status; bytes = downloaded; total = size
        if (status == "installed") completed = v
    }
    fun offer(): String? {
        if (consent || version <= maxOf(installed, completed)) return null
        return when (stage) {
            "ready" -> if (deferredRestart != version) "ready" else null
            "idle", "stopped" -> if (deferredOffer != version) (if (flexible && stage == "idle") "available" else "store") else null
            else -> null
        }
    }
    fun later() { if (stage == "ready") deferredRestart = version else deferredOffer = version }
    fun beginInstall(): Boolean {
        if (stage != "ready") return false
        stage = "installing"; installFailed = false; return true
    }
    fun failInstall() { if (stage == "installing") { stage = "ready"; installFailed = true; deferredRestart = 0 } }
    fun snapshot() = mapOf("version" to version, "stage" to stage, "bytes" to bytes, "total" to total,
        "offer" to offer(), "installFailed" to installFailed)
}
