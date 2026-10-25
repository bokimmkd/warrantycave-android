package com.warrantycave.app

import android.app.Activity
import android.app.ActivityManager
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import java.io.File
import org.junit.After
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AdTaskNavigationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)
    private val manager get() = context.getSystemService(ActivityManager::class.java)
    private val evidence = File(context.getExternalFilesDir(null), "ad-task-evidence").apply { mkdirs() }

    @After fun cleanTasks() {
        device.pressHome()
        manager.appTasks.forEach { it.finishAndRemoveTask() }
        instrumentation.waitForIdleSync()
    }

    @Test fun resolvedAffinityMatchesOsSecurityBoundary() {
        val info = context.packageManager.getActivityInfo(ComponentName(context, MainActivity::class.java), 0)
        val ad = context.packageManager.getActivityInfo(ComponentName(context, "com.google.android.gms.ads.AdActivity"), 0)
        assertEquals("Preserve singleTop launch handling", android.content.pm.ActivityInfo.LAUNCH_SINGLE_TOP, info.launchMode)
        if (Build.VERSION.SDK_INT >= 30) {
            assertEquals(context.packageName, info.taskAffinity)
            assertEquals("Main and SDK bridge should share their task", ad.taskAffinity, info.taskAffinity)
        } else {
            assertTrue("Keep legacy task-hijacking mitigation", info.taskAffinity.isNullOrEmpty())
        }
    }

    @Test fun emptyAffinityControlReproducesSeparateBridgeTask() {
        ActivityScenario.launch<LegacyAffinityProbeActivity>(
            Intent(context, LegacyAffinityProbeActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ).use { scenario ->
            var rootTask = -1
            scenario.onActivity { rootTask = it.taskId }
            val probe = launchBridge()
            assertNotEquals("Control must expose the pre-fix task split", rootTask, probe.taskId)
            assertTrue(manager.appTasks.size >= 2)
            record("empty-affinity-control", rootTask, probe.taskId)
        }
    }

    @Test fun adBridgeAndExternalDestinationBackReturnToOriginalActivity() {
        assumeTrue("The fix intentionally leaves API24-29 affinity unchanged", Build.VERSION.SDK_INT >= 30)
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            var rootTask = -1
            scenario.onActivity { rootTask = it.taskId }
            val probe = launchBridge()
            assertEquals("Ad bridge must not create a second app task", rootTask, probe.taskId)
            assertEquals(1, manager.appTasks.size)
            val testPackage = instrumentation.context.packageName
            context.startActivity(Intent().setComponent(ComponentName(
                testPackage, "com.warrantycave.app.navigationfixture.ExternalDestinationActivity"
            )).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            waitUntil { device.currentPackageName == testPackage }
            device.takeScreenshot(File(evidence, "external-destination.png"))
            device.pressBack()
            waitUntil { device.currentPackageName == context.packageName }
            assertFalse(probe.isFinishing)
            device.pressBack()
            waitUntil { scenario.state == Lifecycle.State.RESUMED }
            scenario.onActivity { assertEquals(rootTask, it.taskId) }
            assertEquals("No dead app task after Back", 1, manager.appTasks.size)
            device.takeScreenshot(File(evidence, "returned-to-app.png"))
            record("fixed-back-navigation", rootTask, rootTask)
        }
    }

    @Test fun launcherReentryPreservesOneTask() {
        assumeTrue(Build.VERSION.SDK_INT >= 30)
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            var rootTask = -1
            scenario.onActivity { rootTask = it.taskId }
            device.pressHome()
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            context.startActivity(launch)
            waitUntil { device.currentPackageName == context.packageName }
            waitUntil { scenario.state == Lifecycle.State.RESUMED }
            scenario.onActivity { assertEquals(rootTask, it.taskId) }
            assertEquals(1, manager.appTasks.size)
            record("launcher-reentry", rootTask, rootTask)
        }
    }

    private fun launchBridge(): Activity {
        val monitor = instrumentation.addMonitor(AdNavigationProbeActivity::class.java.name, null, false)
        try {
            context.startActivity(Intent(context, AdNavigationProbeActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return instrumentation.waitForMonitorWithTimeout(monitor, 10000)
                ?: throw AssertionError("Local ad bridge did not resume")
        } finally { instrumentation.removeMonitor(monitor) }
    }

    private fun waitUntil(check: () -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 15000
        while (!check() && SystemClock.uptimeMillis() < deadline) SystemClock.sleep(100)
        assertTrue("Navigation did not reach the expected Activity", check())
    }

    private fun record(name: String, root: Int, bridge: Int) {
        File(evidence, name + ".txt").writeText(
            "sdk=" + Build.VERSION.SDK_INT + "\nrootTask=" + root + "\nbridgeTask=" + bridge +
                "\nappTasks=" + manager.appTasks.joinToString { it.taskInfo.baseActivity.toString() } + "\n"
        )
    }
}
