package com.fieldforce.fieldforce_hrms







import android.Manifest



import android.content.Context



import android.content.Intent



import android.content.pm.PackageManager



import android.location.LocationManager



import android.os.PowerManager



import android.os.SystemClock



import android.provider.Settings



import androidx.core.content.ContextCompat



import androidx.work.*



import org.json.JSONObject



import org.json.JSONArray



import java.net.HttpURLConnection



import java.net.URI



import java.net.URL



import java.time.Instant



import java.util.concurrent.TimeUnit



import java.util.concurrent.atomic.AtomicBoolean







object TrackingRuntime {



    fun owner(cfg:JSONObject)=cfg.optString("baseUrl")+"|"+cfg.optString("userId")



    @Volatile internal var instance: TrackingStore?=null



    val syncing=AtomicBoolean(false)



    fun store(context: Context): TrackingStore = instance ?: synchronized(this) { instance ?: TrackingStore(context.applicationContext).also {instance=it} }



    fun fine(context: Context)=ContextCompat.checkSelfPermission(context,Manifest.permission.ACCESS_FINE_LOCATION)==PackageManager.PERMISSION_GRANTED



    fun background(context: Context)=ContextCompat.checkSelfPermission(context,Manifest.permission.ACCESS_BACKGROUND_LOCATION)==PackageManager.PERMISSION_GRANTED



    fun unrestricted(context: Context)=(context.getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(context.packageName)



    fun gps(context: Context)=(context.getSystemService(Context.LOCATION_SERVICE) as LocationManager).isLocationEnabled



    fun validUrl(value: String): Boolean = try { val clean = value.trimEnd('/'); val uri=URI(clean); uri.host!=null&&uri.userInfo==null&&uri.query==null&&uri.fragment==null&&clean.endsWith("/api")&&(uri.scheme=="https"||uri.scheme=="http") } catch(_:Exception){false}



    @Synchronized fun configure(context: Context, value: JSONObject) {



        require(validUrl(value.getString("baseUrl"))) {"Secure workspace URL required"};require(value.getString("userId").isNotBlank());require(value.optBoolean("offlineLocal")||value.getString("trackingKey").length>=32);require(value.getString("mode") in listOf("Field","Office"));require(value.optLong("attendanceId", 0L)>0)



        val db=store(context);val old=db.config();val same=old.optString("userId")==value.getString("userId")&&old.optLong("attendanceId")==value.optLong("attendanceId")&&old.optString("mode")==value.getString("mode")



        value.put("anchorElapsed",SystemClock.elapsedRealtime());value.put("bootTime",bootTime());val nowServerMs=Instant.parse(value.getString("serverTimeUtc")).toEpochMilli();value.put("anchorUtc",nowServerMs)
val punchInStr=value.optString("punchInUtc")
val punchInMs=if(punchInStr.isNotEmpty()){try{Instant.parse(punchInStr).toEpochMilli()}catch(_:Exception){0L}}else 0L
if(punchInMs>0L){value.put("dutyStartUtc",punchInMs)}else if(!same||old.optLong("dutyStartUtc",0L)<=0L){value.put("dutyStartUtc",nowServerMs)}else{value.put("dutyStartUtc",old.getLong("dutyStartUtc"))}
db.saveConfig(value)



        db.updateState {if(!same){it.remove("stopCandidate");it.remove("stationary");it.remove("lastPoint");it.remove("lastFixAtUtc");it.remove("lastSyncAtUtc")};it.put("rejectedCount",0);it.put("lastError","")}



        val end=try{Instant.parse(value.optString("dutyCutoffUtc")).toEpochMilli()}catch(_:Exception){0L}



        if(value.optBoolean("active")&&end>0){



            val manager=WorkManager.getInstance(context)



            for((name,at) in listOf("reminder" to end-30*60*1000,"cutoff" to end)){



                manager.enqueueUniqueWork("trackyu-duty-"+name,ExistingWorkPolicy.REPLACE,OneTimeWorkRequestBuilder<DutyDeadlineWorker>().setInitialDelay((at-utcNow(context,value)).coerceAtLeast(0),TimeUnit.MILLISECONDS).build())



            }



        }



        schedule(context)



        if(value.optBoolean("active")){start(context)}else{stop(context)}



    }



    @Synchronized fun start(context: Context,fresh:Boolean=false) { val db=store(context);if(!db.config().optBoolean("active")||checkDutyCutoff(context))return;try{if(!fine(context))throw SecurityException();ContextCompat.startForegroundService(context,Intent(context,DutyLocationService::class.java).putExtra("freshFix",fresh))}catch(_:Exception){db.updateState {it.put("status","Permission or background start restricted");it.put("running",false)}} }



    @Synchronized fun stop(context: Context) {
        val db=store(context);val value=db.config();value.put("active",false);db.saveConfig(value);
        try { DutyLocationService.activeService?.stopTrackingNow() } catch(_: Exception) {}
        try { context.startService(Intent(context, DutyLocationService::class.java).apply { action = "ACTION_STOP" }) } catch(_: Exception) {}
        context.stopService(Intent(context,DutyLocationService::class.java));
        try { (context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager).cancel(418) } catch(_: Exception) {}
        db.updateState {it.put("running",false);it.put("status","Location tracking stopped")};
        if (db.pending(owner(value)) > 0) { schedule(context) } else {
            try { androidx.work.WorkManager.getInstance(context).cancelUniqueWork("trackyu-sync-periodic") } catch(_: Exception) {}
        }
    }



    @Synchronized fun stopAcknowledgedAttendance(context:Context,db:TrackingStore,auth:JSONObject,operation:JSONObject,result:JSONObject) {
        val latest=db.config()
        if(!LocalWorkspaceSync.matchesClosedAttendance(latest,auth,operation,result))return
        if(db===store(context))stop(context)else {latest.put("active",false);db.saveConfig(latest)}
    }

    @Synchronized private fun pauseRevokedTracking(context:Context,db:TrackingStore,expected:JSONObject) {
        val current=db.config()
        if(owner(current)!=owner(expected) || current.optLong("attendanceId")!=expected.optLong("attendanceId") || current.optString("trackingKey")!=expected.optString("trackingKey"))return
        stopIfCurrent(context,db,expected)
        val stopped=db.config()
        stopped.put("active",false).put("trackingKey","")
        db.saveConfig(stopped)
        db.updateState { it.put("lastError","Device authorization changed. Saved activity remains on phone.").put("status","Sign-in required for sync") }
    }

    @Synchronized private fun stopIfCurrent(context:Context,db:TrackingStore,expected:JSONObject) {



        val latest=db.config()



        if(latest.optString("userId")==expected.optString("userId")&&latest.optLong("attendanceId")==expected.optLong("attendanceId")&&latest.optString("mode")==expected.optString("mode")&&latest.optString("trackingKey")==expected.optString("trackingKey")) {



            if(db===store(context))stop(context) else {latest.put("active",false);db.saveConfig(latest)}



        }



    }



    fun checkDutyCutoff(context: Context): Boolean {



        val db=store(context);val cfg=db.config()



        if(!cfg.optBoolean("active"))return false



        val now=utcNow(context,cfg)







        // 1. Check explicit dutyCutoffUtc from server lease/grant



        val cutoffStr = cfg.optString("dutyCutoffUtc")



        if (cutoffStr.isNotEmpty()) {



            val cutoffMillis = try { Instant.parse(cutoffStr).toEpochMilli() } catch (_: Exception) { 0L }



            if (cutoffMillis > 0 && now >= cutoffMillis) {



                stop(context)



                return true



            }



        }







        // 2. Enforce server 23:00 IST (17:30 UTC) cutoff rule for the duty date



        val anchorUtc = cfg.optLong("dutyStartUtc", cfg.optLong("anchorUtc", 0L))



        if (anchorUtc > 0) {



            val istOffset = 330 * 60 * 1000L // +05:30



            val dutyDayIst = (anchorUtc + istOffset) / 86400000L



            val cutoffUtc = (dutyDayIst * 86400000L) + (17 * 3600000L + 30 * 60000L)



            if (now >= cutoffUtc) {



                stop(context)



                return true



            }



        }







        // 3. Absolute ceiling: 24 hours



        val maxDuration=24*60*60*1000L



        if(anchorUtc>0&&now-anchorUtc>maxDuration){



            stop(context)



            return true



        }



        return false



    }



    fun schedule(context: Context) { MobileDiagnosticsScheduler.schedule(context);val manager=WorkManager.getInstance(context);val constraints=Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build();manager.enqueueUniqueWork("trackyu-sync-now",ExistingWorkPolicy.KEEP,OneTimeWorkRequestBuilder<TrackingSyncWorker>().setConstraints(constraints).setBackoffCriteria(BackoffPolicy.EXPONENTIAL,30,TimeUnit.SECONDS).build());manager.enqueueUniquePeriodicWork("trackyu-sync-periodic",ExistingPeriodicWorkPolicy.KEEP,PeriodicWorkRequestBuilder<TrackingSyncWorker>(15,TimeUnit.MINUTES).setConstraints(constraints).build()) }



    private fun bootTime() = System.currentTimeMillis() - SystemClock.elapsedRealtime()



    private fun anchored(context:Context,cfg:JSONObject)=cfg.optLong("anchorUtc")>0&&Math.abs(bootTime()-cfg.optLong("bootTime",0L))<600000L



    private fun utcNow(context:Context,cfg:JSONObject)=if(anchored(context,cfg))cfg.getLong("anchorUtc")+SystemClock.elapsedRealtime()-cfg.getLong("anchorElapsed") else System.currentTimeMillis()



    @Synchronized private fun rememberServerTime(context:Context,db:TrackingStore,expected:JSONObject,time:String) {



        val latest=db.config()



        if(latest.optString("userId")==expected.optString("userId")&&latest.optString("trackingKey")==expected.optString("trackingKey")) {



            latest.put("anchorUtc",Instant.parse(time).toEpochMilli());latest.put("anchorElapsed",SystemClock.elapsedRealtime());latest.put("bootTime",bootTime());db.saveConfig(latest)



        }



    }



    fun computeHealthState(



        isAlive: Boolean,



        active: Boolean,



        finePerm: Boolean,



        gpsEnabled: Boolean,



        lastCallbackElapsed: Long,



        pendingCount: Int,



        nowElapsed: Long = SystemClock.elapsedRealtime(),



        isMocked: Boolean = false



    ): Pair<String, String> {



        if (isMocked) {



            return Pair("MOCK_LOCATION", "Mock / Fake GPS detected on device")



        }



        if (!active) {



            return Pair("IDLE", "Duty tracking is not active")



        }



        if (!isAlive) {



            return Pair("SERVICE_DEAD", "Tracking service stopped or terminated unexpectedly")



        }



        if (!finePerm) {



            return Pair("PERMISSION_REVOKED", "Location permission is not granted")



        }



        if (!gpsEnabled) {



            return Pair("NO_GPS", "GPS location provider is turned off")



        }



        val callbackSilence = if (lastCallbackElapsed > 0L) nowElapsed - lastCallbackElapsed else -1L



        if (callbackSilence > 90000L || callbackSilence == -1L) {



            return Pair("NO_GPS", "No GPS signals received from hardware in > 90s")



        }



        if (pendingCount > 0) {



            return Pair("SYNC_PENDING", "$pendingCount location points queued for upload")



        }



        return Pair("HEALTHY", "GPS active and route recording reliably")



    }







    fun status(context: Context, db: TrackingStore = store(context)): JSONObject {



        val cfg = db.config()



        val s = db.state()



        val isAlive = DutyLocationService.isServiceAlive



        val finePerm = fine(context)



        val gpsOn = gps(context)



        val pendingCount = db.pending(owner(cfg))



        val active = cfg.optBoolean("active")



        val isMocked = s.optBoolean("hasMockLocation", false) || s.optBoolean("isMocked", false)



        val (healthState, healthReason) = computeHealthState(



            isAlive = isAlive,



            active = active,



            finePerm = finePerm,



            gpsEnabled = gpsOn,



            lastCallbackElapsed = DutyLocationService.lastRawCallbackElapsed,



            pendingCount = pendingCount,



            isMocked = isMocked



        )



        return s.apply {



            put("clockAnchored", anchored(context, cfg))



            if (anchored(context, cfg)) put("serverTimeUtc", Instant.ofEpochMilli(utcNow(context, cfg)).toString())



            put("userId", cfg.optString("userId"))



            put("mode", cfg.optString("mode"))



            put("attendanceId", cfg.optLong("attendanceId"))



            put("active", active)



            put("expiresAtUtc", cfg.optString("expiresAtUtc"))



            put("dutyCutoffUtc", cfg.optString("dutyCutoffUtc"))



            put("pendingCount", pendingCount)



            put("gpsEnabled", gpsOn)



            put("precisePermission", finePerm)



            put("backgroundPermission", background(context))



            put("batteryUnrestricted", unrestricted(context))



            put("baseUrl", cfg.optString("baseUrl"))



            put("foregroundServiceRunning", isAlive)



            put("serviceAlive", isAlive)



            put("running", isAlive && s.optBoolean("running", false))



            put("healthState", healthState)



            put("healthReason", healthReason)



            put("hasMockLocation", isMocked)



            put("isMocked", isMocked)



            put("mockDetected", isMocked)



            put("lastGpsReceivedElapsed", DutyLocationService.lastRawCallbackElapsed)



            put("lastGpsAcceptedElapsed", DutyLocationService.lastAcceptedElapsed)



            put("lastGpsPersistedElapsed", DutyLocationService.lastPersistedElapsed)



        }



    }



    @JvmOverloads fun sync(context: Context, db: TrackingStore = store(context), force: Boolean = false): Boolean {



        if(!syncing.compareAndSet(false,true))return false



        try {



            if(db===store(context)) {



                checkDutyCutoff(context)



                val network=context.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager



                if(network.activeNetwork==null)return false



            }



            val actionsDone=LocalWorkspaceSync.drain(context,db,force)



            try { LocalWorkspaceSync.renewLease(context,db) } catch(_:Exception) {}



            val cfg=db.config();val user=owner(cfg);if(cfg.optString("userId").isBlank())return actionsDone
            val uploadAuth=LocalWorkspaceSync.auth(db)
            if(uploadAuth?.optString("scope")==user && uploadAuth.optBoolean("authRequired"))return false
            if(cfg.optString("trackingKey").isNotBlank() && cfg.optString("rejectedTrackingKey")==cfg.optString("trackingKey"))return false



            if(cfg.optString("trackingKey").length<32)return false



            val samples=db.batch(user);val state=status(context,db)



            val lastSync=try{Instant.parse(state.optString("lastSyncAtUtc")).toEpochMilli()}catch(_:Exception){0L}



            val elapsed=System.currentTimeMillis()-lastSync



            if(samples.size == 0&&(!cfg.optBoolean("active")||elapsed in 0..299999))return actionsDone



            val isStrictOnline = cfg.optString("mode").equals("StrictOnline", true) || cfg.optLong("uploadSeconds", 60L) <= 10L; val syncWindow = (cfg.optLong("uploadSeconds", 60L).coerceIn(5L, 600L) * 1000L) - 1L; if(!force && !isStrictOnline && samples.size in 1..99 && elapsed in 0..syncWindow) return false



            val healthStatusText = if (state.optBoolean("hasMockLocation") || state.optBoolean("isMocked") || state.optString("healthState") == "MOCK_LOCATION") "Mock GPS detected • Rejected" else state.optString("status","Waiting for location").take(64)



          val health=JSONObject().put("mode",cfg.getString("mode")).put("attendanceId",cfg.getLong("attendanceId")).put("trackingEnabled",state.optBoolean("running")).put("gpsEnabled",state.optBoolean("gpsEnabled")).put("precisePermission",state.optBoolean("precisePermission")).put("backgroundPermission",state.optBoolean("backgroundPermission")).put("batteryUnrestricted",state.optBoolean("batteryUnrestricted")).put("pendingCount",state.optInt("pendingCount")).put("rejectedCount",state.optInt("rejectedCount")).put("status",healthStatusText)



            state.optString("lastFixAtUtc").takeIf {it.isNotBlank()}?.let {health.put("lastFixAtUtc",it)}



            val body=JSONObject().put("samples",JSONArray(samples)).put("health",health)



            val uploadAttemptUtc = Instant.now().toString()



            db.updateState { it.put("lastUploadAttemptedAtUtc", uploadAttemptUtc) }



            val conn=URL(cfg.getString("baseUrl")+"/DutyTracking/upload").openConnection() as HttpURLConnection



            try {



                conn.requestMethod="POST";conn.connectTimeout=15000;conn.readTimeout=60000;conn.doOutput=true;conn.setRequestProperty("Content-Type","application/json");conn.setRequestProperty("X-Tracking-Key",cfg.getString("trackingKey"));conn.setRequestProperty("X-Device-ID",cfg.getString("deviceId"));conn.outputStream.use {it.write(body.toString().toByteArray(Charsets.UTF_8))}



                val code=conn.responseCode



                if(code!=200){
                    if(code==401) {
                        val current=db.config()
                        if(current.optString("trackingKey")==cfg.optString("trackingKey")) {
                            current.put("rejectedTrackingKey",cfg.optString("trackingKey"));db.saveConfig(current)
                        }
                    }



                    var isExplicitRevoke = false



                    if (code == 401 || code == 403) {



                        try {



                            val errStream = conn.errorStream ?: conn.inputStream



                            val errText = errStream?.bufferedReader()?.use { it.readText() } ?: ""



                            if (errText.contains("DEVICE_REVOKED") || errText.contains("TRACKING_REVOKED")) {



                                isExplicitRevoke = true



                            }



                        } catch (_: Exception) {}



                    }



                    if (isExplicitRevoke) {
                        if(uploadAuth?.optString("scope")==user)LocalWorkspaceSync.requireAuthentication(db,uploadAuth,"Device authorization changed. Sign in to resume sync.")
                        pauseRevokedTracking(context,db,cfg)
                        return false
                    } else {



                        db.updateState {



                            it.put("lastError", if (code == 401) "Sign in to renew location syncing" else "Upload pending; locations saved on phone")



                            it.put("status", if (code == 401) "Sign-in required for sync" else "Locations saved on phone")



                        }



                        return code == 401



                    }



                }



                val envelope=JSONObject(conn.inputStream.bufferedReader().use {it.readText()});if(!envelope.optBoolean("success"))return false



                val data=envelope.getJSONObject("data");val acks=data.getJSONArray("acknowledgements");val sent=samples.map {it.getString("id")}.toSet();var rejected=0



                for(i in 0 until acks.length()){val ack=acks.getJSONObject(i);val id=ack.optString("id");val disposition=ack.optString("disposition");if(id in sent&&disposition in listOf("accepted","duplicate","rejected")){db.acknowledge(user,id,disposition=="rejected");if(disposition=="rejected")rejected++}}



                val ackTimeUtc = data.getString("serverTimeUtc")



                rememberServerTime(context,db,cfg,ackTimeUtc)



                db.updateState {



                    it.put("lastSyncAtUtc", ackTimeUtc)



                    it.put("lastUploadAcknowledgedAtUtc", ackTimeUtc)



                    it.put("lastError", "")



                    it.put("rejectedCount", it.optInt("rejectedCount") + rejected)



                }



                val window=data.optJSONObject("window");if(window!=null&&window.optLong("id")==cfg.optLong("attendanceId")&&window.optString("mode")==cfg.optString("mode")&&!window.isNull("punchOutUtc")){stopIfCurrent(context,db,cfg)}



                return db.pending(user)==0&&actionsDone



            } finally {conn.disconnect()}



        } catch(_:Exception) {try{db.updateState {it.put("lastError","Connection unavailable; locations are saved on this phone")}}catch(_:Exception){};return false} finally {syncing.set(false)}



    }



    fun jsonMap(value: JSONObject): Map<String,Any?> = value.keys().asSequence().associateWith { jsonValue(value.get(it)) }



    private fun jsonValue(value:Any?):Any? = when(value) {



        null, JSONObject.NULL -> null



        is JSONObject -> jsonMap(value)



        is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }



        else -> value



    }



}



class TrackingSyncWorker(context: Context,params: WorkerParameters): Worker(context,params) {



 override fun doWork(): Result {



  val deadline=SystemClock.elapsedRealtime()+120000



  repeat(8){



   if(isStopped)return Result.retry()



   if(TrackingRuntime.sync(applicationContext))return Result.success()



   if(SystemClock.elapsedRealtime()>deadline)return Result.retry()



   try{if(TrackingRuntime.store(applicationContext).state().optString("lastError").isNotBlank())return Result.retry()}catch(_:Exception){return Result.retry()}



  }



  return Result.retry()



 }



}







class DutyDeadlineWorker(context: Context,params: WorkerParameters): Worker(context,params) {



    override fun doWork(): Result {



        return try { TrackingRuntime.checkDutyCutoff(applicationContext);Result.success() }



        catch(_:Exception){Result.retry()}



    }



}



