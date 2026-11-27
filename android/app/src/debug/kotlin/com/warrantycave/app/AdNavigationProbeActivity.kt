package com.warrantycave.app

import android.app.Activity
import android.os.Bundle
import android.widget.TextView

/** Models the SDK's same-package NEW_TASK bridge without clicking live ads. */
class AdNavigationProbeActivity : Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        setContentView(TextView(this).apply { text = "Local ad navigation probe" })
    }
}

/** Counterfactual for the pre-fix empty-affinity root, including on newer OSs. */
class LegacyAffinityProbeActivity : Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        setContentView(TextView(this).apply { text = "Empty-affinity control" })
    }
}
