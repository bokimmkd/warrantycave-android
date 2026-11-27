package com.warrantycave.app.navigationfixture;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

/** Separate test APK: an offline external destination, with no production data. */
public class ExternalDestinationActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        TextView text = new TextView(this);
        text.setText("Local external destination");
        setContentView(text);
    }
}
