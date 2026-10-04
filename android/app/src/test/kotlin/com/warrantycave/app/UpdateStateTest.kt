package com.warrantycave.app
import org.junit.Assert.*
import org.junit.Test

class UpdateStateTest {
    private fun available() = UpdateState().apply { installed = 37; flexible = true; observe(38, "idle") }
    @Test fun laterDefersOnlyThisVisit() {
        val s = available(); assertEquals("available", s.offer()); s.later()
        repeat(10) { s.observe(38, "idle"); assertNull(s.offer()) }
        s.newVisit(); assertEquals("available", s.offer())
    }
    @Test fun consentAndDownloadDoNotReopenOffer() {
        val s = available(); s.consent = true; assertNull(s.offer())
        s.consent = false; s.observe(38, "waiting"); assertNull(s.offer())
        s.observe(38, "downloading", 100, 100); assertNull(s.offer())
        assertEquals("downloading", s.stage) // 100% is not DOWNLOADED.
        s.observe(38, "ready", 100, 100); assertEquals("ready", s.offer())
    }
    @Test fun fastDownloadHasNoArtificialDelayAndReadyLaterKeepsBytes() {
        val s = available(); s.observe(38, "ready", 100, 100); s.later()
        s.observe(38, "idle"); assertEquals("ready", s.stage); assertEquals(100L, s.bytes)
        assertNull(s.offer()); s.newVisit(); assertEquals("ready", s.offer())
    }
    @Test fun restartIsSingleShotAndFailureCanRetry() {
        val s = available(); s.observe(38, "ready"); assertTrue(s.beginInstall())
        assertFalse(s.beginInstall()); assertNull(s.offer())
        s.observe(38, "ready"); assertEquals("installing", s.stage)
        s.failInstall(); assertTrue(s.installFailed); assertEquals("ready", s.offer())
        assertTrue(s.beginInstall()); assertFalse(s.installFailed)
    }
    @Test fun installedAndOldCallbacksCannotOfferAgain() {
        val s = available(); s.observe(38, "installed"); s.observe(38, "ready"); assertNull(s.offer())
        s.installed = 38; s.observe(38, "idle"); assertEquals(0, s.version)
        s.observe(37, "ready"); assertNull(s.offer())
        s.observe(39, "downloading"); s.observe(38, "ready"); assertEquals(39, s.version)
    }
}
