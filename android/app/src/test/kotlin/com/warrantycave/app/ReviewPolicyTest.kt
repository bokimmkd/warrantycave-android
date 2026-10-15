package com.warrantycave.app
import org.junit.Assert.*
import org.junit.Test
class ReviewPolicyTest {
    @Test fun newUsersNeedTwoWarrantiesButExistingUsersNeedOne() {
        val now = 1_800_000_000_000L
        assertFalse(ReviewPolicy.eligible(0, true, 0, now))
        assertFalse(ReviewPolicy.eligible(1, false, 0, now))
        assertTrue(ReviewPolicy.eligible(2, false, 0, now))
        assertTrue(ReviewPolicy.eligible(1, true, 0, now))
    }
    @Test fun cooldownIncludesClockRollbackAndExactThirtyDayBoundary() {
        val attempted = 1_800_000_000_000L
        assertFalse(ReviewPolicy.eligible(2, true, attempted, attempted - 1))
        assertFalse(ReviewPolicy.eligible(2, true, attempted, attempted + ReviewPolicy.COOLDOWN - 1))
        assertTrue(ReviewPolicy.eligible(2, true, attempted, attempted + ReviewPolicy.COOLDOWN))
    }
}
