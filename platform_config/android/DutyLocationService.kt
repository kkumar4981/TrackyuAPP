package com.fieldforce.fieldforce_hrms

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.os.*
import android.provider.Settings
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.location.*
import org.json.JSONObject
import java.time.Instant
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.math.max

data class LocationSnapshot(
    val latitude: Double,
    val longitude: Double,
    val accuracy: Float,
    val hasSpeed: Boolean,
    val speed: Float,
    val hasBearing: Boolean,
    val bearing: Float,
    val provider: String,
    val captured: Long,
    val elapsed: Long,
    var retryCount: Int = 0
)

class DutyLocationService: Service(), LocationListener {
    companion object {
        @Volatile var isServiceAlive = false
            internal set
        @Volatile var lastRawCallbackElapsed = 0L
            internal set
        @Volatile var lastAcceptedElapsed = 0L
            internal set
        @Volatile var lastPersistedElapsed = 0L
            internal set

        fun resetDiagnosticsForTest() {
            isServiceAlive = false
            lastRawCallbackElapsed = 0L
            lastAcceptedElapsed = 0L
            lastPersistedElapsed = 0L
        }
    }
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val persistenceLock = Any()
    internal val persistenceQueue = java.util.concurrent.LinkedBlockingQueue<LocationSnapshot>(500)
    internal val retryQueue = java.util.ArrayDeque<LocationSnapshot>()
    private val persistenceScheduled = java.util.concurrent.atomic.AtomicBoolean(false)
    private val persistenceExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "trackyu-persistence-worker").apply { priority = Thread.NORM_PRIORITY }
    }
    private val uploadQueued = java.util.concurrent.atomic.AtomicBoolean(false)
    private var fused: FusedLocationProviderClient? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var fallback = false
    private var lastElapsed = 0L
    private var lastCaptured = 0L
    private var lastCoarse = 0L
    private var running = false
    private var freshPending = false

    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            for (location in result.locations) accept(location, "fused")
        }
    }

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { upload() }
    }

    private var decryptRetryCount = 0

    private val retryDecrypt = object : Runnable {
        override fun run() {
            if (running) return
            val store = TrackingRuntime.store(this@DutyLocationService)
            val cfg = store.config()
            if (cfg.optBoolean("active")) {
                decryptRetryCount = 0
                startTrackingAfterConfig(cfg)
            } else if (store.configStatus == TrackingStore.ConfigStatus.DECRYPT_ERROR) {
                decryptRetryCount++
                if (decryptRetryCount <= 30) {
                    handler.postDelayed(this, 10000)
                } else {
                    recordStartupFailure("Keystore decryption timed out after bounded retries")
                    isServiceAlive = false
                    running = false
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            } else {
                isServiceAlive = false
                running = false
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
    }

    private fun startTrackingAfterConfig(cfg: JSONObject) {
        if (!running) {
            running = true
            // Maintain stationary 10-minute heartbeat anchor across service recreation
            if (lastCaptured == 0L) {
                val lastPt = TrackingRuntime.store(this).state().optJSONObject("lastPoint")
                val prevCaptured = try { Instant.parse(lastPt?.optString("capturedAtUtc")).toEpochMilli() } catch (_: Exception) { 0L }
                if (prevCaptured > 0L) lastCaptured = prevCaptured
            }
            TrackingRuntime.store(this).updateState {
                it.put("running", true)
                it.put("status", "Waiting for accurate GPS")
            }
            startLocations()
            try {
                (getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager).registerDefaultNetworkCallback(networkCallback)
            } catch (_: Exception) {}
            handler.post(tick)
        }
    }

    private val tick = object : Runnable {
        override fun run() {
            if (!running) return
            try {
                if (TrackingRuntime.checkDutyCutoff(this@DutyLocationService)) return
                if (!TrackingRuntime.fine(this@DutyLocationService)) {
                    state("Location permission removed")
                    stopSelf()
                    return
                }
                val now = SystemClock.elapsedRealtime()
                val callbackSilence = if (lastRawCallbackElapsed > 0L) now - lastRawCallbackElapsed else (if (lastElapsed > 0L) now - lastElapsed else 46000L)
                if (callbackSilence > 90000L) {
                    fallback()
                    freshFix()
                }
                upload()
                notification()
            } catch (_: Exception) {
                state("Waiting for accurate GPS")
            }
            handler.postDelayed(this, 30000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        val hasFine = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
        val hasCoarse = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!hasFine && !hasCoarse) {
            isServiceAlive = false
            MobileDiagnostics.record(this, "foreground_service", "SecurityException_NoLocationPermission", "", "DutyLocationService.onCreate_permCheck")
            recordStartupFailure("Location permission missing")
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(417, buildInitialNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(417, buildInitialNotification())
            }
            isServiceAlive = true
        } catch (e: SecurityException) {
            isServiceAlive = false
            MobileDiagnostics.record(this, "foreground_service", "SecurityException", MobileDiagnostics.frames(e), "DutyLocationService.onCreate_startForeground_perm")
            recordStartupFailure("Permission failure: " + e.message)
        } catch (e: Exception) {
            isServiceAlive = false
            val errType = if (Build.VERSION.SDK_INT >= 31 && e.javaClass.simpleName == "ForegroundServiceStartNotAllowedException") {
                "ForegroundServiceStartNotAllowedException"
            } else {
                e.javaClass.simpleName
            }
            val stage = if (e.javaClass.name.contains("Notification") || e.javaClass.name.contains("RemoteService")) "notification" else "service_startup"
            MobileDiagnostics.record(this, "foreground_service", errType, MobileDiagnostics.frames(e), "DutyLocationService.onCreate_" + stage)
            recordStartupFailure("Foreground startup failed: " + e.message)
        }
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "trackyu:location_service")
            wakeLock?.setReferenceCounted(false)
            wakeLock?.acquire(24 * 60 * 60 * 1000L)
        } catch (_: Exception) {}
    }

    private fun recordStartupFailure(msg: String) {
        try {
            TrackingRuntime.store(this).updateState {
                it.put("running", false)
                it.put("status", msg.take(64))
                it.put("lastError", msg)
            }
        } catch (_: Exception) {}
    }

    private fun buildInitialNotification(): Notification {
        val intent = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, "trackyu_duty")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("Trackyu location tracking")
            .setContentText("Location service active")
            .setContentIntent(intent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val hasFine = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
        val hasCoarse = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!hasFine && !hasCoarse) {
            isServiceAlive = false
            running = false
            MobileDiagnostics.record(this, "foreground_service", "SecurityException_NoLocationPermission", "", "DutyLocationService.onStartCommand_permCheck")
            recordStartupFailure("Open the app and allow precise background location")
            stopSelf()
            return START_NOT_STICKY
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(417, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(417, buildNotification())
            }
            isServiceAlive = true
        } catch (e: SecurityException) {
            isServiceAlive = false
            running = false
            MobileDiagnostics.record(this, "foreground_service", "SecurityException", MobileDiagnostics.frames(e), "DutyLocationService.onStartCommand_startForeground_perm")
            recordStartupFailure("Location permission error: " + e.message)
            stopSelf()
            return START_NOT_STICKY
        } catch (e: Exception) {
            isServiceAlive = false
            running = false
            val errType = if (Build.VERSION.SDK_INT >= 31 && e.javaClass.simpleName == "ForegroundServiceStartNotAllowedException") {
                "ForegroundServiceStartNotAllowedException"
            } else {
                e.javaClass.simpleName
            }
            val stage = if (e.javaClass.name.contains("Notification") || e.javaClass.name.contains("RemoteService")) "notification" else "bg_restriction"
            MobileDiagnostics.record(this, "foreground_service", errType, MobileDiagnostics.frames(e), "DutyLocationService.onStartCommand_" + stage)
            recordStartupFailure("Foreground start restricted: " + e.message)
            stopSelf()
            return START_NOT_STICKY
        }

        try {
            val store = TrackingRuntime.store(this)
            val cfg = store.config()
            if (cfg.optBoolean("active")) {
                decryptRetryCount = 0
                handler.removeCallbacks(retryDecrypt)
                startTrackingAfterConfig(cfg)
            } else if (store.configStatus == TrackingStore.ConfigStatus.DECRYPT_ERROR) {
                // State 3: Encrypted config exists on disk, but Keystore decrypt failed temporarily.
                // Do NOT terminate service; retain START_STICKY and retry on bounded schedule.
                MobileDiagnostics.record(this, "crypto", "KeyStoreLockedOnStartup", "", "DutyLocationService.onStartCommand")
                handler.removeCallbacks(retryDecrypt)
                handler.postDelayed(retryDecrypt, 10000)
                return START_STICKY
            } else {
                // State 1: EMPTY or State 2: INACTIVE
                isServiceAlive = false
                running = false
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            if (intent?.getBooleanExtra("freshFix", false) == true) {
                fallback()
                freshFix()
            }
        } catch (e: Exception) {
            isServiceAlive = false
            running = false
            MobileDiagnostics.record(this, "foreground_service", e.javaClass.simpleName, MobileDiagnostics.frames(e), "DutyLocationService.onStartCommand_outer")
            recordStartupFailure("Tracking error: " + e.message)
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    private fun createChannel() {
        val channel = NotificationChannel("trackyu_duty", "Attendance location tracking", NotificationManager.IMPORTANCE_DEFAULT)
        channel.description = "Maintains continuous GPS and route recording while punched in"
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val intent = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val state = try { TrackingRuntime.status(this) } catch (_: Exception) { JSONObject() }
        val text = if (!TrackingRuntime.gps(this)) "GPS is off - turn it on to record your route" else "${state.optInt("pendingCount")} locations pending sync. Tracking while punched in."
        return Notification.Builder(this, "trackyu_duty")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("Trackyu location tracking")
            .setContentText(text)
            .setContentIntent(intent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun notification() {
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(417, buildNotification())
    }

    private fun state(message: String) {
        try {
            TrackingRuntime.store(this).updateState {
                it.put("status", message.take(64))
                it.put("lastError", message)
            }
        } catch (_: Exception) {}
    }

    @Suppress("MissingPermission")
    private fun startLocations() {
        if (!TrackingRuntime.fine(this)) throw SecurityException()
        val cfg = TrackingRuntime.store(this).config()
        val intervalSec = cfg.optLong("intervalSeconds", 60L).coerceIn(10L, 600L)
        val distanceMeters = cfg.optDouble("distanceFilterMeters", 30.0).toFloat().coerceIn(3f, 500f)
        val intervalMillis = intervalSec * 1000L

        val manager = getSystemService(LOCATION_SERVICE) as LocationManager
        try {
            if (manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                // Use 0f minDistance so Android hardware never suppresses periodic fixes during movement
                manager.requestLocationUpdates(LocationManager.GPS_PROVIDER, intervalMillis, 0f, this, Looper.getMainLooper())
            }
        } catch (_: Exception) {}
        try {
            if (manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                manager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, intervalMillis * 2, 0f, this, Looper.getMainLooper())
            }
        } catch (_: Exception) {}
        if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(this) == ConnectionResult.SUCCESS) {
            try {
                fused = LocationServices.getFusedLocationProviderClient(this)
                val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, intervalMillis)
                    .setMinUpdateIntervalMillis((intervalMillis / 2).coerceAtLeast(3000L))
                    .setMaxUpdateDelayMillis(intervalMillis * 2)
                    .setWaitForAccurateLocation(false)
                    .build()
                fused!!.requestLocationUpdates(request, callback, Looper.getMainLooper()).addOnFailureListener { fallback() }
            } catch (_: Exception) {
                fallback()
            }
        } else {
            fallback()
        }
    }

    @Suppress("MissingPermission")
    private fun freshFix() {
        if (freshPending) return
        freshPending = true
        try {
            fused?.getCurrentLocation(
                CurrentLocationRequest.Builder()
                    .setPriority(Priority.PRIORITY_HIGH_ACCURACY)
                    .setMaxUpdateAgeMillis(5000)
                    .setDurationMillis(10000)
                    .build(),
                com.google.android.gms.tasks.CancellationTokenSource().token
            )?.addOnSuccessListener { location ->
                if (location != null) accept(location, "fused")
            }?.addOnCompleteListener { freshPending = false }

            val manager = getSystemService(LOCATION_SERVICE) as LocationManager
            for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                try {
                    val last = manager.getLastKnownLocation(provider)
                    if (last != null && Math.abs(System.currentTimeMillis() - last.time) < 60000) {
                        accept(last, provider)
                    }
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {
            freshPending = false
        }
    }

    @Suppress("MissingPermission")
    private fun fallback() {
        if (fallback) return
        fallback = true
        val manager = getSystemService(LOCATION_SERVICE) as LocationManager
        for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
            try {
                if (manager.isProviderEnabled(provider)) {
                    manager.requestLocationUpdates(provider, 10000L, 0f, this, Looper.getMainLooper())
                }
            } catch (_: Exception) {
                state("Enable precise location and GPS")
            }
        }
        if (!TrackingRuntime.gps(this)) {
            fallback = false
            state("GPS is off")
        }
    }

    override fun onLocationChanged(location: Location) { accept(location, location.provider ?: "gps") }
    override fun onProviderEnabled(provider: String) { fallback = false; fallback() }
    override fun onProviderDisabled(provider: String) { state("GPS provider unavailable") }
    @Deprecated("Android legacy callback") override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

    private fun accept(location: Location, provider: String) {
        if (!running) return
        val elapsed = SystemClock.elapsedRealtime()
        lastRawCallbackElapsed = elapsed

        val captured = if (location.time > 0 && Math.abs(System.currentTimeMillis() - location.time) < 86400000L) {
            location.time
        } else {
            System.currentTimeMillis()
        }

        val locSnapshot = LocationSnapshot(
            latitude = location.latitude,
            longitude = location.longitude,
            accuracy = location.accuracy,
            hasSpeed = location.hasSpeed(),
            speed = if (location.hasSpeed()) location.speed else 0f,
            hasBearing = location.hasBearing(),
            bearing = if (location.hasBearing()) location.bearing else 0f,
            provider = provider,
            captured = captured,
            elapsed = elapsed
        )

        // Non-blocking enqueue to offload ALL heavy work from the Android Main thread
        val enqueued = persistenceQueue.offer(locSnapshot)
        if (!enqueued) {
            try {
                MobileDiagnostics.record(
                    this,
                    "persistence_backpressure",
                    "QueueSaturated_EvictingOldestCoarse",
                    "Queue size: ${persistenceQueue.size}",
                    "DutyLocationService.accept"
                )
            } catch (_: Exception) {}
            // Evict oldest to preserve latest fix without blocking main thread
            persistenceQueue.poll()
            persistenceQueue.offer(locSnapshot)
        }
        schedulePersistence()
    }

    private fun schedulePersistence() {
        if (!persistenceExecutor.isShutdown && persistenceScheduled.compareAndSet(false, true)) {
            try {
                persistenceExecutor.execute {
                    try {
                        drainPersistenceQueue()
                    } finally {
                        persistenceScheduled.set(false)
                        if (persistenceQueue.isNotEmpty() || retryQueue.isNotEmpty()) {
                            schedulePersistence()
                        }
                    }
                }
            } catch (_: java.util.concurrent.RejectedExecutionException) {
                persistenceScheduled.set(false)
            }
        }
    }

    internal fun drainPersistenceQueue() {
        synchronized(persistenceLock) {
            // 1. Process failed retry queue first (maintains strict FIFO)
            while (retryQueue.isNotEmpty()) {
                val retryLoc = retryQueue.peekFirst() ?: break
                val success = tryPersistSnapshot(retryLoc)
                if (success) {
                    retryQueue.pollFirst()
                } else {
                    break // Keep in retry queue for next cycle
                }
            }

            // 2. Process incoming queue
            while (true) {
                val loc = persistenceQueue.poll() ?: break
                val success = tryPersistSnapshot(loc)
                if (!success) {
                    break // Stop draining if disk error occurred; retryQueue holds the item
                }
            }
        }
    }

    internal fun tryPersistSnapshot(loc: LocationSnapshot): Boolean {
        try {
            val db = TrackingRuntime.store(this)
            val cfg = db.config()
            if (!cfg.optBoolean("active")) return true

            // Validate accuracy & mock
            val maxAcc = Math.max(cfg.optDouble("maxAccuracyMeters", 50.0).coerceIn(10.0, 500.0), 100.0)
            if (!loc.accuracy.isFinite() || loc.accuracy < 0 || loc.accuracy > maxAcc) {
                db.updateState {
                    it.put("rejectedCount", it.optInt("rejectedCount") + 1)
                    it.put("lastGpsReceivedAtUtc", Instant.now().toString())
                    it.put("status", if (loc.accuracy > maxAcc) "GPS accuracy ${loc.accuracy.toInt()}m above limit" else "Waiting for a fresh GPS fix")
                }
                return true
            }

            val captured = loc.captured
            val elapsed = loc.elapsed

            if (captured <= lastCaptured && elapsed - lastElapsed < 2000) return true

            val minDistance = cfg.optDouble("distanceFilterMeters", 30.0).toFloat().coerceIn(15f, 500f)
            val lastP = db.state().optJSONObject("lastPoint")
            if (lastP != null) {
                val lastLat = lastP.optDouble("latitude")
                val lastLng = lastP.optDouble("longitude")
                if (lastLat.isFinite() && lastLng.isFinite()) {
                    val moved = distance(lastLat, lastLng, loc.latitude, loc.longitude)
                    val timeDiff = captured - lastCaptured
                    val deadband = Math.max(minDistance.toDouble(), (loc.accuracy * 0.8).coerceIn(15.0, 45.0))
                    if (moved < deadband && timeDiff < 600000L) {
                        lastAcceptedElapsed = elapsed
                        db.updateState { s ->
                            s.put("lastFixAtUtc", Instant.ofEpochMilli(captured).toString())
                            s.put("lastGpsReceivedAtUtc", Instant.ofEpochMilli(captured).toString())
                            s.put("status", "Stationary • On duty")
                            s.put("running", true)
                        }
                        return true
                    }
                }
            }

            lastAcceptedElapsed = elapsed

            val battery = (getSystemService(BATTERY_SERVICE) as? BatteryManager)?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
            val attId = cfg.optLong("attendanceId").takeIf { it > 0 } ?: 0L
            val mode = cfg.optString("mode").takeIf { it.isNotBlank() } ?: "Field"

            val point = JSONObject()
                .put("id", UUID.randomUUID().toString())
                .put("mode", mode)
                .put("attendanceId", attId)
                .put("capturedAtUtc", Instant.ofEpochMilli(loc.captured).toString())
                .put("latitude", loc.latitude)
                .put("longitude", loc.longitude)
                .put("accuracyMeters", loc.accuracy.toDouble())
                .put("isMocked", false)
                .put("provider", loc.provider.take(24))
                .put("batteryPercent", if (battery in 0..100) battery else JSONObject.NULL)

            if (loc.hasSpeed) point.put("speedMps", loc.speed.toDouble())
            if (loc.hasBearing) point.put("bearing", loc.bearing.toDouble())

            val owner = TrackingRuntime.owner(cfg)
            db.append(owner, point)
            lastCaptured = loc.captured
            lastElapsed = loc.elapsed
            lastPersistedElapsed = SystemClock.elapsedRealtime()
            if (loc.accuracy > 50) lastCoarse = loc.elapsed

            db.updateState { s ->
                s.put("lastPoint", point)
                s.put("lastFixAtUtc", point.getString("capturedAtUtc"))
                s.put("lastGpsReceivedAtUtc", point.getString("capturedAtUtc"))
                s.put("lastGpsPersistedAtUtc", point.getString("capturedAtUtc"))
                s.put("status", if (loc.accuracy <= 50) "Recording your route" else "GPS accuracy: ${loc.accuracy.toInt()}m")
                s.put("running", true)
                if (loc.accuracy <= 50) {
                    val anchor = s.optJSONObject("stationary")
                    if (anchor == null || loc.captured - anchor.optLong("last") > 180000 || distance(anchor.optDouble("lat"), anchor.optDouble("lng"), loc.latitude, loc.longitude) > 50) {
                        s.put("stationary", JSONObject().put("lat", loc.latitude).put("lng", loc.longitude).put("start", loc.captured).put("last", loc.captured))
                        s.remove("stopCandidate")
                    } else {
                        anchor.put("last", loc.captured)
                        if (loc.captured - anchor.getLong("start") >= 600000) {
                            s.put("stopCandidate", JSONObject().put("latitude", anchor.getDouble("lat")).put("longitude", anchor.getDouble("lng")).put("startUtc", Instant.ofEpochMilli(anchor.getLong("start")).toString()).put("minutes", (loc.captured - anchor.getLong("start")) / 60000))
                        }
                    }
                }
            }
            upload()
            handler.post { notification() }
            return true
        } catch (e: Exception) {
            MobileDiagnostics.record(this, "channel", e.javaClass.name, MobileDiagnostics.frames(e), "DutyLocationService.tryPersistSnapshot")
            state("Location persist failed: ${e.message?.take(32)}")

            // Explicit Durable Retry Buffer
            if (loc.retryCount < 3) {
                loc.retryCount++
                if (!retryQueue.contains(loc)) {
                    retryQueue.offerLast(loc)
                }
            } else {
                MobileDiagnostics.record(
                    this,
                    "persistence_failure",
                    "WriteRetryExhausted",
                    "Failed after 3 retries: ${e.javaClass.simpleName} - ${e.message?.take(64)}",
                    "DutyLocationService.tryPersistSnapshot"
                )
            }
            return false
        }
    }

    private fun distance(a: Double, b: Double, c: Double, d: Double): Float {
        val result = FloatArray(1)
        Location.distanceBetween(a, b, c, d, result)
        return result[0]
    }

    private fun upload() {
        if (!executor.isShutdown && uploadQueued.compareAndSet(false, true)) {
            try {
                executor.execute {
                    try {
                        TrackingRuntime.sync(this)
                    } finally {
                        uploadQueued.set(false)
                    }
                }
            } catch (_: java.util.concurrent.RejectedExecutionException) {
                uploadQueued.set(false)
            }
        }
    }

    override fun onDestroy() {
        isServiceAlive = false
        running = false
        handler.removeCallbacksAndMessages(null)
        try {
            fused?.removeLocationUpdates(callback)
            (getSystemService(LOCATION_SERVICE) as LocationManager).removeUpdates(this)
            (getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(networkCallback)
        } catch (_: Exception) {}

        // Ensure WakeLock is held during drain to prevent CPU sleep before SQLite writes finish
        try {
            if (wakeLock?.isHeld != true) {
                val pm = getSystemService(POWER_SERVICE) as? PowerManager
                wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "trackyu:drain_shutdown")
                wakeLock?.acquire(15000L)
            }
        } catch (_: Exception) {}

        // 1. Gracefully initiate executor shutdown
        persistenceExecutor.shutdown()
        var drainedCleanly = false
        try {
            drainedCleanly = persistenceExecutor.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS)
        } catch (ie: InterruptedException) {
            Thread.currentThread().interrupt()
        }

        // 2. Safe queue draining under concurrency lock:
        // Ensures background worker has fully completed its in-flight transaction
        // before manual drain starts. Prevents concurrent writes, races, and duplicates.
        synchronized(persistenceLock) {
            val remaining = mutableListOf<LocationSnapshot>()
            while (retryQueue.isNotEmpty()) {
                remaining.add(retryQueue.pollFirst()!!)
            }
            persistenceQueue.drainTo(remaining)
            if (remaining.isNotEmpty()) {
                MobileDiagnostics.record(
                    this,
                    "service_shutdown",
                    "QueueDrainRequired",
                    "Draining ${remaining.size} unpersisted location tasks synchronously on destroy",
                    "DutyLocationService.onDestroy"
                )
                for (snap in remaining) {
                    try {
                        tryPersistSnapshot(snap)
                    } catch (e: Exception) {
                        MobileDiagnostics.record(
                            this,
                            "service_shutdown",
                            "QueueDrainTaskFailure",
                            MobileDiagnostics.frames(e),
                            "DutyLocationService.onDestroy_drainTask"
                        )
                    }
                }
            }
        }

        executor.shutdown()
        try {
            executor.awaitTermination(2, java.util.concurrent.TimeUnit.SECONDS)
        } catch (_: InterruptedException) {}

        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {}

        try {
            TrackingRuntime.store(this).updateState { it.put("running", false) }
            TrackingRuntime.schedule(this)
        } catch (_: Exception) {}
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}

class TrackingBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            val cfg = TrackingRuntime.store(context).config()
            if (cfg.optString("userId").isNotBlank()) {
                TrackingRuntime.schedule(context)
                if (cfg.optBoolean("active") && TrackingRuntime.background(context) && TrackingRuntime.fine(context)) {
                    TrackingRuntime.start(context)
                }
            }
        } catch (_: Exception) {}
    }
}
