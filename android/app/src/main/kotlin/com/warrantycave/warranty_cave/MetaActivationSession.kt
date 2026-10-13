package com.warrantycave.app

/** Rotation and brief external dialogs are part of the same activation. */
internal class MetaActivationSession {
    private var lastBackground: Long? = null
    private var logged = false
    fun foreground(now: Long): Boolean {
        val shouldLog = !logged || lastBackground?.let { now - it >= 30_000L } == true
        lastBackground = null
        logged = true
        return shouldLog
    }
    fun background(now: Long) { lastBackground = now }
    fun reset() { logged = false; lastBackground = null }
}
