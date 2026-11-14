package com.lifeos.lifeos

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth (fingerprint lock).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lifeos/system").setMethodCallHandler { call, result ->
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            when (call.method) {
                // Do Not Disturb during focus sessions (needs "Do Not Disturb access").
                "hasDndAccess" -> result.success(nm.isNotificationPolicyAccessGranted)
                "openDndSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                    result.success(null)
                }
                "setDnd" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    val until = call.argument<Number>("untilMillis")?.toLong()
                    if (!nm.isNotificationPolicyAccessGranted) {
                        result.success(false)
                    } else {
                        DndOffReceiver.cancel(this)
                        if (on) {
                            nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
                            // Switch DND off at the end even if the app has been closed.
                            if (until != null) DndOffReceiver.schedule(this, until)
                        } else {
                            nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
                        }
                        result.success(true)
                    }
                }
                // Hide the screen in "recent apps" and block screenshots (journal lock).
                "setSecure" -> {
                    if (call.argument<Boolean>("on") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
