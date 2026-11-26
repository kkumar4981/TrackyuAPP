package com.fieldforce.fieldforce_hrms

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.pm.LauncherApps
import android.provider.Settings
import android.net.Uri
import android.os.Build
import android.os.UserManager

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            window.statusBarColor = android.graphics.Color.TRANSPARENT
            window.navigationBarColor = android.graphics.Color.TRANSPARENT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
    }
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
                } else if (call.method == "installApk") {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                if (!packageManager.canRequestPackageInstalls()) {
                                    val permIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                        data = Uri.parse("package:$packageName")
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    startActivity(permIntent)
                                    result.success(false)
                                    return@setMethodCallHandler
                                }
                            }
                            val file = java.io.File(filePath)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "APK file does not exist", null)
                                return@setMethodCallHandler
                            }
                            file.setReadable(true, false)
                            val uri = androidx.core.content.FileProvider.getUriForFile(
                                this@MainActivity,
                                "${applicationContext.packageName}.fileprovider",
                                file
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            val resList = packageManager.queryIntentActivities(intent, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
                            for (res in resList) {
                                grantUriPermission(res.activityInfo.packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_PATH", "File path missing", null)
                    }
                } else if (call.method == "openDownloads") {
                    try {
                        val intent = Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(Uri.parse("content://downloads/public_downloads"), "*/*")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (_: Exception) {
                            result.error("UNAVAILABLE", "Cannot open downloads", null)
                        }
                    }
                } else if (call.method == "checkCloneApp") {
                    try {
                        val pkg = applicationContext.packageName
                        val path = filesDir.absolutePath.lowercase()
                        // Secondary Android user profiles (e.g. /data/user/999/, /data/user/10/) or virtual/clone sandboxes
                        val userDirRegex = Regex("/data/user/(\\d+)/")
                        val match = userDirRegex.find(path)
                        val userIdFromPath = match?.groupValues?.getOrNull(1)?.toIntOrNull() ?: 0
                        val isRunningInClone = userIdFromPath != 0 ||
                            path.contains("parallel") ||
                            path.contains("dual") ||
                            path.contains("clone") ||
                            path.contains("virtual")

                        var hasClonedInstance = false
                        var profileCount = 0
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                            val um = getSystemService(USER_SERVICE) as? UserManager
                            val la = getSystemService(LAUNCHER_APPS_SERVICE) as? LauncherApps
                            if (um != null && la != null) {
                                for (profile in um.userProfiles) {
                                    try {
                                        if (la.getActivityList(pkg, profile).isNotEmpty()) {
                                            profileCount++
                                        }
                                    } catch (_: Exception) {}
                                }
                                if (profileCount > 1) {
                                    hasClonedInstance = true
                                }
                            }
                        }

                        val isCloned = isRunningInClone || hasClonedInstance
                        val reason = when {
                            isRunningInClone -> "App is running inside a Cloned / Dual App environment (profile $userIdFromPath). Please open the official Trackyu app and remove the clone."
                            hasClonedInstance -> "Trackyu (Clone) / Dual App is installed on this phone ($profileCount instances found). Please uninstall/disable the cloned app."
                            else -> ""
                        }
                        result.success(
                            mapOf(
                                "isCloned" to isCloned,
                                "isRunningInClone" to isRunningInClone,
                                "hasClonedInstance" to hasClonedInstance,
                                "reason" to reason
                            )
                        )
                    } catch (e: Exception) {
                        result.success(mapOf("isCloned" to false, "reason" to ""))
                    }
                } else { result.notImplemented() }
            }
    }
}
