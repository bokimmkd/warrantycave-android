package com.warrantycave.app

internal object ReviewPolicy {
    const val COOLDOWN = 30L * 24 * 60 * 60 * 1000
    fun eligible(count: Int, existing: Boolean, lastAttempt: Long, now: Long): Boolean =
        count > 0 && (existing || count >= 2) &&
            (lastAttempt == 0L || (now >= lastAttempt && now - lastAttempt >= COOLDOWN))
}
