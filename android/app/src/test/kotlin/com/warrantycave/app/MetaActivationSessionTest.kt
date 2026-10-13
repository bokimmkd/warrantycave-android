package com.warrantycave.app

import org.junit.Assert.*
import org.junit.Test

class MetaActivationSessionTest {
    @Test fun firstForegroundLogsOnce() {
        val session = MetaActivationSession()
        assertTrue(session.foreground(100))
        assertFalse(session.foreground(200))
    }
    @Test fun rotationAndShortPlayDialogDoNotDuplicate() {
        val session = MetaActivationSession()
        session.foreground(0)
        session.background(100)
        assertFalse(session.foreground(3_100))
    }
    @Test fun longBackgroundIsNewActivation() {
        val session = MetaActivationSession()
        session.foreground(0)
        session.background(100)
        assertTrue(session.foreground(30_100))
        assertFalse(session.foreground(30_200))
    }
    @Test fun revokingAndGrantingStartsFreshSession() {
        val session = MetaActivationSession()
        session.foreground(0)
        session.reset()
        assertTrue(session.foreground(100))
    }
}
