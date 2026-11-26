package com.fieldforce.fieldforce_hrms

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.provider.Settings

class MainActivity : FlutterActivity() {
    override fun onResume() { super.onResume();try{TrackingRuntime.start(this)}catch(_:Exception){} }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TrackingChannel(this,flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "trackyu/device_settings")
            .setMethodCallHandler { call, result ->
                if (call.method == "network") {
                    try {
                        startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("SETTINGS_UNAVAILABLE", "Open Wi-Fi or mobile data from quick settings.", null)
                    }
                } else if (call.method == "identity") {
                    result.success(Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID))
                } else { result.notImplemented() }
            }
    }
}
