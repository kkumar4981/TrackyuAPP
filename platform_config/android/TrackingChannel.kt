package com.fieldforce.fieldforce_hrms

import android.app.Activity

import android.content.ComponentName

import android.content.Context

import android.content.Intent

import android.content.pm.PackageManager

import android.net.Uri

import android.os.Build

import android.os.PowerManager

import android.provider.Settings

import io.flutter.plugin.common.BinaryMessenger

import io.flutter.plugin.common.MethodChannel

import org.json.JSONObject

import java.net.HttpURLConnection

import java.net.URL

import java.time.Instant

import java.util.concurrent.Executors

class TrackingChannel(private val activity: Activity, messenger: BinaryMessenger) {

  companion object {

    /**

     * Security Allowlist of trusted OEM system apps.

     * Prevents arbitrary third-party component launch requests from DB or network.

     */

    private val TRUSTED_OEM_PACKAGES = setOf(

      "com.miui.securitycenter",

      "com.miui.powerkeeper",

      "com.coloros.safecenter",

      "com.oplus.battery",

      "com.coloros.oppoguardelf",

      "com.iqoo.secure",

      "com.vivo.permissionmanager",

      "com.samsung.android.lool",

      "com.samsung.android.sm",

      "com.huawei.systemmanager",

      "com.transsion.phonemaster",

      "com.asus.mobilemanager",

      "com.lenovo.powersetting",

      "com.gionee.softmanager",

      "com.meizu.safe"

    )



    private val APPROVED_OEM_COMPONENTS = setOf(

      Pair("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),

      Pair("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity"),

      Pair("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),

      Pair("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"),

      Pair("com.oplus.battery", "com.oplus.battery.AppListActivity"),

      Pair("com.coloros.oppoguardelf", "com.coloros.powermanager.fuelgaue.PowerUsageModelActivity"),

      Pair("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"),

      Pair("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"),

      Pair("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),

      Pair("com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity"),

      Pair("com.samsung.android.sm", "com.samsung.android.sm.ui.battery.BatteryActivity"),

      Pair("com.transsion.phonemaster", "com.transsion.phonemaster.ui.activity.SelfStartManagerActivity"),

      Pair("com.transsion.phonemaster", "com.transsion.phonemaster.ui.activity.MainActivity"),

      Pair("com.asus.mobilemanager", "com.asus.mobilemanager.autostart.AutoStartManageActivity"),

      Pair("com.lenovo.powersetting", "com.lenovo.powersetting.ui.Settings\$HighPowerApplicationsActivity"),

      Pair("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"),

      Pair("com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity")

    )

  }

  private fun safeSuccess(result: MethodChannel.Result, value: Any?) {

    try {

      result.success(value)

    } catch (error: Exception) {

      MobileDiagnostics.record(activity, "channel", error.javaClass.name, MobileDiagnostics.frames(error), "channel.encode")

      try {

        result.error("CHANNEL_ENCODING_FAILED", "Unable to read phone data. Records are retained.", null)

      } catch (_: Exception) {}

    }

  }

  private val executor = Executors.newSingleThreadExecutor()

  private val networkExecutor = Executors.newSingleThreadExecutor()

  private fun isOemRequiringAutostart(): Boolean {

    val m = Build.MANUFACTURER.lowercase()

    val b = Build.BRAND.lowercase()

    return listOf(

      "xiaomi", "redmi", "poco", "oppo", "realme", "oneplus", "vivo", "iqoo",

      "huawei", "honor", "samsung", "infinix", "tecno", "itel", "transsion",

      "asus", "gionee", "meizu", "lenovo"

    ).any { m.contains(it) || b.contains(it) }

  }

  /**

   * Attempts to launch an Intent only if it is verified resolvable on the current device.

   * Returns true if successfully started, false otherwise.

   */

  private fun safeLaunch(intent: Intent): Boolean {

    return try {

      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

      val pm = activity.packageManager

      val resolved = pm.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)

      if (resolved != null) {

        activity.startActivity(intent)

        true

      } else {

        false

      }

    } catch (_: SecurityException) {

      false

    } catch (_: Exception) {

      false

    }

  }

  private fun openAutostartSettings(targetPackage: String? = null, targetActivity: String? = null) {

    val prefs = activity.getSharedPreferences("trackyu_oem_prefs", Context.MODE_PRIVATE)

    prefs.edit().putBoolean("autostart_settings_opened", true).apply()

    // 1. Try validated target from allowlist (both package AND activity must match approved pair)

    if (!targetPackage.isNullOrBlank() && !targetActivity.isNullOrBlank()) {

      val pkg = targetPackage.trim()

      val act = targetActivity.trim()

      if (APPROVED_OEM_COMPONENTS.contains(Pair(pkg, act))) {

        val customIntent = Intent().setComponent(ComponentName(pkg, act))

        if (safeLaunch(customIntent)) return

      }

    }

    val m = Build.MANUFACTURER.lowercase()

    val b = Build.BRAND.lowercase()

    val intents = mutableListOf<Intent>()

    if (m.contains("xiaomi") || m.contains("redmi") || m.contains("poco") || b.contains("xiaomi") || b.contains("redmi") || b.contains("poco")) {

      intents.add(Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")))

      intents.add(Intent("miui.intent.action.OP_AUTO_START").addCategory(Intent.CATEGORY_DEFAULT))

      intents.add(Intent().setComponent(ComponentName("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity")).putExtra("package_name", activity.packageName))

    } else if (m.contains("oppo") || m.contains("realme") || m.contains("oneplus") || b.contains("oppo") || b.contains("realme") || b.contains("oneplus")) {

      intents.add(Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")))

      intents.add(Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity")))

      intents.add(Intent().setComponent(ComponentName("com.oplus.battery", "com.oplus.battery.AppListActivity")))

      intents.add(Intent().setComponent(ComponentName("com.coloros.oppoguardelf", "com.coloros.powermanager.fuelgaue.PowerUsageModelActivity")))

    } else if (m.contains("vivo") || m.contains("iqoo") || b.contains("vivo") || b.contains("iqoo")) {

      intents.add(Intent().setComponent(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity")))

      intents.add(Intent().setComponent(ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")))

      intents.add(Intent().setComponent(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager")))

    } else if (m.contains("tecno") || m.contains("infinix") || m.contains("itel") || b.contains("tecno") || b.contains("infinix") || b.contains("itel") || m.contains("transsion") || b.contains("transsion")) {

      intents.add(Intent().setComponent(ComponentName("com.transsion.phonemaster", "com.transsion.phonemaster.ui.activity.SelfStartManagerActivity")))

      intents.add(Intent().setComponent(ComponentName("com.transsion.phonemaster", "com.transsion.phonemaster.ui.activity.MainActivity")))

    } else if (m.contains("asus") || b.contains("asus")) {

      intents.add(Intent().setComponent(ComponentName("com.asus.mobilemanager", "com.asus.mobilemanager.autostart.AutoStartManageActivity")))

    } else if (m.contains("lenovo") || b.contains("lenovo")) {

      intents.add(Intent().setComponent(ComponentName("com.lenovo.powersetting", "com.lenovo.powersetting.ui.Settings\$HighPowerApplicationsActivity")))

    } else if (m.contains("samsung") || b.contains("samsung")) {

      intents.add(Intent().setComponent(ComponentName("com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity")))

      intents.add(Intent().setComponent(ComponentName("com.samsung.android.sm", "com.samsung.android.sm.ui.battery.BatteryActivity")))

    } else if (m.contains("huawei") || m.contains("honor") || b.contains("huawei") || b.contains("honor")) {

      intents.add(Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity")))

      intents.add(Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity")))

    }

    for (intent in intents) {

      if (safeLaunch(intent)) return

    }

    // Fallback: Standard App Details Settings

    val fallbackIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {

      data = Uri.parse("package:${activity.packageName}")

    }

    if (!safeLaunch(fallbackIntent)) {

      safeLaunch(Intent(Settings.ACTION_SETTINGS))

    }

  }

  private fun openBatterySettings(targetPackage: String? = null, targetActivity: String? = null) {

    // 1. Try validated target from allowlist (both package AND activity must match approved pair)

    if (!targetPackage.isNullOrBlank() && !targetActivity.isNullOrBlank()) {

      val pkg = targetPackage.trim()

      val act = targetActivity.trim()

      if (APPROVED_OEM_COMPONENTS.contains(Pair(pkg, act))) {

        val customIntent = Intent().setComponent(ComponentName(pkg, act)).apply {

          putExtra("package_name", activity.packageName)

        }

        if (safeLaunch(customIntent)) return

      }

    }

    val m = Build.MANUFACTURER.lowercase()

    val b = Build.BRAND.lowercase()

    // 2. Xiaomi specific battery saver

    if (m.contains("xiaomi") || m.contains("redmi") || m.contains("poco") || b.contains("xiaomi") || b.contains("redmi") || b.contains("poco")) {

      val miuiBattery = Intent().setComponent(ComponentName("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity")).apply {

        putExtra("package_name", activity.packageName)

        putExtra("package_label", activity.applicationInfo.loadLabel(activity.packageManager))

      }

      if (safeLaunch(miuiBattery)) return

    }

    // 3. Android standard ignore battery optimization dialog

    val pm = activity.getSystemService(Context.POWER_SERVICE) as PowerManager

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !pm.isIgnoringBatteryOptimizations(activity.packageName)) {

      val reqIntent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {

        data = Uri.parse("package:${activity.packageName}")

      }

      if (safeLaunch(reqIntent)) return

    }

    // 4. Standard App Info Details

    val appIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {

      data = Uri.parse("package:${activity.packageName}")

    }

    if (!safeLaunch(appIntent)) {

      safeLaunch(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))

    }

  }

  init {

    MethodChannel(messenger, "trackyu/duty_tracking").setMethodCallHandler { call, result ->

      try {

        when (call.method) {

          "diagnostic" -> {

            val args = JSONObject(call.arguments as Map<*, *>)

            executor.execute {

              MobileDiagnostics.record(activity, "flutter", args.optString("errorType"), args.optString("stack"), args.optString("context"))

              try { TrackingRuntime.schedule(activity) } catch (_: Exception) {}

            }

            safeSuccess(result, null)

          }

          "localAuth", "localRead", "localReadSummary", "localWrite", "localCommit", "localSyncState", "localPause", "configureOffline" -> {

            val args = JSONObject(call.arguments as Map<*, *>)

            executor.execute {

              try {

                val db = TrackingRuntime.store(activity)

                var response: Any? = null

                when (call.method) {

                  "localAuth" -> {

                    require(TrackingRuntime.validUrl(args.getString("baseUrl")))

                    require(args.getString("scope") == args.getString("baseUrl") + "|" + args.getString("userId"))

                    db.localWrite("system", "activeAuth", args)

                    try {

                      db.writableDatabase.execSQL("UPDATE local_outbox SET error=NULL, state='pending' WHERE scope=? AND (error LIKE '%Sign in%' OR state='blocked')", arrayOf(args.getString("scope")))

                    } catch (_: Exception) {}

                    MobileDiagnostics.bind(activity, args.getString("scope"))

                    TrackingRuntime.schedule(activity)

                  }

                  "localPause" -> {

                    val auth = LocalWorkspaceSync.auth(db)

                    if (auth?.optString("scope") == args.optString("scope")) {

                      db.localWrite("system", "activeAuth", JSONObject().put("scope", args.getString("scope")).put("paused", true))

                    }

                  }

                  "localReadSummary" -> {

                    response = db.routeSummary(args.getString("scope"), args.getString("key"))?.let { TrackingRuntime.jsonMap(it) }

                  }

                  "localRead" -> {

                    response = db.localRead(args.getString("scope"), args.getString("key"))?.let { TrackingRuntime.jsonMap(it) }

                  }

                  "localWrite" -> {

                    db.localWrite(args.getString("scope"), args.getString("key"), args.getJSONObject("value"))

                  }

                  "localCommit" -> {

                    val op = args.getJSONObject("operation")

                    require(op.getString("route") in LocalWorkspaceSync.allowed)

                    db.localCommit(args.getString("scope"), args.getString("key"), args.getJSONObject("value"), op)

                  }

                  "localSyncState" -> {

                    response = TrackingRuntime.jsonMap(db.localSyncState(args.getString("scope")))

                  }

                  "configureOffline" -> {

                    val auth = LocalWorkspaceSync.auth(db) ?: throw IllegalStateException("Sign in first")

                    require(auth.optString("userId") == args.getString("userId"))

                    require(auth.optString("baseUrl") == args.getString("baseUrl"))

                    val existing = db.config()

                    val receipt = db.localResult(auth.getString("scope"), args.getString("requestId"))

                    if (receipt != null) args.put("attendanceId", receipt.getLong("id"))

                    if (existing.optString("requestId") == args.optString("requestId")) {

                      for (k in listOf("trackingKey", "expiresAtUtc", "serverId")) {

                        if (existing.has(k)) args.put(k, existing.get(k))

                      }

                    }

                    args.put("trackingKey", if (existing.optString("requestId") == args.optString("requestId")) existing.optString("trackingKey") else "")

                    args.put("deviceId", auth.getString("deviceId"))

                    args.put("offlineLocal", true)

                    TrackingRuntime.configure(activity, args)

                  }

                }

                activity.runOnUiThread { safeSuccess(result, response) }

              } catch (error: Exception) {

                MobileDiagnostics.record(activity, "channel", error.javaClass.name, MobileDiagnostics.frames(error), "timeline.storage")

                activity.runOnUiThread {

                  result.error("LOCAL_STORAGE_FAILED", "Unable to save phone data: ${error.localizedMessage ?: error.javaClass.simpleName}", null)

                }

              }

            }

          }

          "configure" -> {

            TrackingRuntime.configure(activity, JSONObject(call.arguments as Map<*, *>))

            safeSuccess(result, TrackingRuntime.jsonMap(TrackingRuntime.status(activity)))

          }

          "status" -> {

            executor.execute {

              try {

                val status = TrackingRuntime.jsonMap(TrackingRuntime.status(activity))

                activity.runOnUiThread { safeSuccess(result, status) }

              } catch (error: Exception) {

                MobileDiagnostics.record(activity, "channel", error.javaClass.name, MobileDiagnostics.frames(error), "timeline.status")

                activity.runOnUiThread { result.error("TRACKING_UNAVAILABLE", "Unable to read tracking status", null) }

              }

            }

          }

          "resume" -> {

            TrackingRuntime.start(activity)

            safeSuccess(result, null)

          }

          "refreshFix" -> {

            val args = JSONObject(call.arguments as Map<*, *>)

            val cfg = TrackingRuntime.store(activity).config()

            require(cfg.optString("userId") == args.getString("userId") && cfg.optString("baseUrl") == args.getString("baseUrl") && cfg.optBoolean("active"))

            TrackingRuntime.start(activity, true)

            safeSuccess(result, null)

          }

          "stop" -> {

            TrackingRuntime.stop(activity)

            safeSuccess(result, null)

          }

          "sync" -> {

            TrackingRuntime.schedule(activity)

            networkExecutor.execute {

              val db = TrackingRuntime.store(activity)

              val auth = LocalWorkspaceSync.auth(db)

              if (auth != null) db.unblockOutbox(auth.getString("scope"))

              TrackingRuntime.sync(activity, force = true)

            }

            safeSuccess(result, null)

          }

          "batterySettings" -> {

            val args = call.arguments as? Map<*, *>

            val targetPkg = args?.get("package") as? String

            val targetAct = args?.get("activity") as? String

            openBatterySettings(targetPkg, targetAct)

            safeSuccess(result, null)

          }

          "autostartSettings" -> {

            val args = call.arguments as? Map<*, *>

            val targetPkg = args?.get("package") as? String

            val targetAct = args?.get("activity") as? String

            openAutostartSettings(targetPkg, targetAct)

            safeSuccess(result, null)

          }

          "deviceInfo" -> {

            val prefs = activity.getSharedPreferences("trackyu_oem_prefs", Context.MODE_PRIVATE)

            val pm = activity.getSystemService(Context.POWER_SERVICE) as PowerManager

            val isBatteryExempt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) pm.isIgnoringBatteryOptimizations(activity.packageName) else true

            val data = mapOf(

              "manufacturer" to Build.MANUFACTURER,

              "brand" to Build.BRAND,

              "model" to Build.MODEL,

              "sdk" to Build.VERSION.SDK_INT,

              "buildDisplay" to Build.DISPLAY,

              "requiresAutostart" to isOemRequiringAutostart(),

              "autostartSettingsOpened" to prefs.getBoolean("autostart_settings_opened", false),

        "autostartVerifiable" to false,

              "batteryExempt" to isBatteryExempt

            )

            safeSuccess(result, data)

          }

          "trackingHealth" -> {

            executor.execute {

              try {

                val db = TrackingRuntime.store(activity)

                val cfg = db.config()

                val state = TrackingRuntime.status(activity, db)

                val pm = activity.getSystemService(Context.POWER_SERVICE) as PowerManager

                val isBatteryExempt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) pm.isIgnoringBatteryOptimizations(activity.packageName) else true

                val prefs = activity.getSharedPreferences("trackyu_oem_prefs", Context.MODE_PRIVATE)

                val lastPoint = state.optJSONObject("lastPoint")

                val healthMap = mutableMapOf<String, Any?>(

                  "deviceManufacturer" to Build.MANUFACTURER,

                  "deviceBrand" to Build.BRAND,

                  "deviceModel" to Build.MODEL,

                  "androidSdk" to Build.VERSION.SDK_INT,

                  "buildDisplay" to Build.DISPLAY,

                  "foregroundServiceRunning" to state.optBoolean("foregroundServiceRunning", false),

                  "serviceAlive" to state.optBoolean("serviceAlive", false),

                  "healthState" to state.optString("healthState", "IDLE"),

                  "healthReason" to state.optString("healthReason", ""),

                  "serviceStatus" to state.optString("status", "Idle"),

                  "gpsEnabled" to state.optBoolean("gpsEnabled", false),

                  "preciseLocation" to state.optBoolean("precisePermission", false),

                  "backgroundLocation" to state.optBoolean("backgroundPermission", false),

                  "batteryExempt" to isBatteryExempt,

                  "autostartSettingsOpened" to prefs.getBoolean("autostart_settings_opened", false),

                  "autostartVerifiable" to false,

                  "requiresAutostart" to isOemRequiringAutostart(),

                  "pendingCount" to state.optInt("pendingCount", 0),

                  "rejectedCount" to state.optInt("rejectedCount", 0),

                  "lastFixAtUtc" to state.optString("lastFixAtUtc", ""),

                  "lastGpsReceivedAtUtc" to state.optString("lastGpsReceivedAtUtc", ""),

                  "lastGpsPersistedAtUtc" to state.optString("lastGpsPersistedAtUtc", ""),

                  "lastSyncAtUtc" to state.optString("lastSyncAtUtc", ""),

                  "lastUploadAttemptedAtUtc" to state.optString("lastUploadAttemptedAtUtc", ""),

                  "dutyActive" to cfg.optBoolean("active", false),

                  "attendanceId" to cfg.optLong("attendanceId", 0L)

                )

                if (lastPoint != null) {

                  healthMap["lastLatitude"] = lastPoint.optDouble("latitude")

                  healthMap["lastLongitude"] = lastPoint.optDouble("longitude")

                  healthMap["lastAccuracyMeters"] = lastPoint.optDouble("accuracyMeters")

                  healthMap["lastProvider"] = lastPoint.optString("provider")

                  healthMap["lastBatteryPercent"] = lastPoint.optInt("batteryPercent", -1)

                }

                activity.runOnUiThread { safeSuccess(result, healthMap) }

              } catch (e: Exception) {

                activity.runOnUiThread {

                  result.error("DIAGNOSTICS_FAILED", e.message, null)

                }

              }

            }

          }

          "route" -> {

            val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()

            val from = (args["from"] as? Number)?.toLong() ?: 0L

            val to = (args["to"] as? Number)?.toLong() ?: Long.MAX_VALUE

            executor.execute {

              try {

                val store = TrackingRuntime.store(activity)

                val requestedUser = args["userId"] as? String

                val requestedBase = args["baseUrl"] as? String

                val cfg = if (requestedUser.isNullOrBlank() || requestedBase.isNullOrBlank()) store.config() else JSONObject()

                val userId = requestedUser?.takeIf { it.isNotBlank() } ?: cfg.optString("userId")

                val baseUrl = requestedBase?.takeIf { it.isNotBlank() } ?: cfg.optString("baseUrl")

                val points = if (userId.isNotBlank()) {

                  store.route(

                    baseUrl + "|" + userId,

                    from,

                    to,

                    if (args["timeline"] == true) 0 else RouteProjection.MAX_POINTS,

                    ((args["offset"] as? Number)?.toInt() ?: 0),

                    if (args["timeline"] == true) ((args["pageSize"] as? Number)?.toInt() ?: 250).coerceIn(1, 2000) else 0

                  )

                } else emptyList()

                activity.runOnUiThread { safeSuccess(result, points.map { TrackingRuntime.jsonMap(it) }) }

              } catch (error: Exception) {

                MobileDiagnostics.record(activity, "channel", error.javaClass.name, MobileDiagnostics.frames(error), "timeline.storage")

                activity.runOnUiThread { result.error("LOCAL_STORAGE_FAILED", "Unable to read saved locations", null) }

              }

            }

          }

          else -> result.notImplemented()

        }

      } catch (_: Exception) {

        result.error("TRACKING_UNAVAILABLE", "Unable to access location tracking. Check location permission and phone storage.", null)

      }

    }

  }

}

