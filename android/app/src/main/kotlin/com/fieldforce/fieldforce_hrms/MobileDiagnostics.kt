package com.fieldforce.fieldforce_hrms

import android.app.ActivityManager
import android.app.Application
import android.content.Context
import android.os.Build
import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID

/** Bounded private journal. No GPS, payloads, tokens, selfies or exception messages. */
object MobileDiagnostics {
    private fun file(context:Context)=AtomicFile(File(context.filesDir,"mobile-diagnostics.json"))
    private fun prefs(context:Context)=context.getSharedPreferences("mobile-diagnostics",0)
    private fun hash(scope:String)=MessageDigest.getInstance("SHA-256").digest(scope.toByteArray()).joinToString(""){"%02x".format(it)}
    fun bind(context:Context,scope:String){prefs(context).edit().putString("scope",hash(scope)).commit()}
    private fun read(context:Context):JSONArray=try{JSONArray(file(context).openRead().use{it.bufferedReader().readText()})}catch(_:Exception){JSONArray()}
    private fun write(context:Context,rows:JSONArray) {
        val f=file(context);val stream=f.startWrite()
        try{stream.write(rows.toString().toByteArray());f.finishWrite(stream)}catch(error:Exception){f.failWrite(stream);throw error}
    }
    fun frames(error:Throwable):String=generateSequence(error){it.cause}.take(4).flatMap{it.stackTrace.asSequence()}.take(60)
        .joinToString("\n"){"at ${it.className}.${it.methodName}(${it.fileName}:${it.lineNumber})"}.take(12000)
    @Synchronized fun record(context:Context,kind:String,type:String,stack:String="",where:String="") {
        try {
            val rows=read(context)
            // Keep 200 reports; report overflow explicitly instead of growing without bound.
            val next=JSONArray();val first=(rows.length()-199).coerceAtLeast(0)
            for(i in first until rows.length())next.put(rows.get(i))
            val safeStack=stack.lineSequence().filter{it.trim().startsWith("at ")||it.trim().startsWith("#")}
                .map{it.replace(Regex("https?://\\S+"),"[source]").take(250)}.take(60).joinToString("\n")
            next.put(JSONObject().put("id",UUID.randomUUID().toString()).put("occurredAtUtc",Instant.now().toString())
                .put("scope",prefs(context).getString("scope",""))
                .put("kind",kind.take(30)).put("errorType",type.replace(Regex("[^A-Za-z0-9_.$]"),"").take(120))
                .put("stack",safeStack).put("context",where.replace(Regex("[^A-Za-z0-9_. /:-]"),"").take(120))
                .put("appVersion",BuildConfig.VERSION_NAME).put("buildNumber",BuildConfig.VERSION_CODE.toString())
                .put("androidVersion",Build.VERSION.SDK_INT.toString()).put("deviceModel",Build.MODEL.take(80))
                .put("droppedReports",first))
            write(context,next)
        }catch(_:Exception){/* Diagnostics must never break employee activity. */}
    }
    @Synchronized fun pending(context:Context,scope:String):List<JSONObject> {
        val owner=hash(scope);val rows=read(context)
        return (0 until rows.length()).mapNotNull{rows.optJSONObject(it)}
            .filter{it.optString("scope").isBlank()||it.optString("scope")==owner}.take(20)
    }
    @Synchronized fun acknowledge(context:Context,ids:Set<String>) {
        val rows=read(context);val remaining=JSONArray()
        for(i in 0 until rows.length()){val row=rows.getJSONObject(i);if(row.optString("id") !in ids)remaining.put(row)}
        write(context,remaining)
    }
    fun upload(context:Context,db:TrackingStore):Boolean=try {
        val auth=LocalWorkspaceSync.auth(db)
        if(auth==null||auth.optBoolean("paused"))true else {
            val rows=pending(context,auth.getString("scope"))
            if(rows.isEmpty())true else {
                val response=LocalWorkspaceSync.request(auth,"MobileDiagnostics/batch",JSONObject().put("events",JSONArray(rows)))
                val ack=response.optJSONObject("data")?.optJSONArray("acceptedIds")?:JSONArray()
                val sent=rows.map{it.getString("id")}.toSet()
                acknowledge(context,(0 until ack.length()).map{ack.getString(it)}.filter{it in sent}.toSet())
                ack.length()==rows.size && pending(context,auth.getString("scope")).isEmpty()
            }
        }
    }catch(_:Exception){false}
    fun collectExit(context:Context) {
        if(Build.VERSION.SDK_INT<30)return
        try{
            val p=prefs(context);val last=p.getLong("exitAt",0)
            val exits=(context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getHistoricalProcessExitReasons(context.packageName,0,10)
            for(exit in exits.filter{it.timestamp>last}.sortedBy{it.timestamp}) {
                if(exit.reason in setOf(3,4,5,6,9))record(context,"process_exit","AndroidExit${exit.reason}",where="exit:${exit.timestamp};status:${exit.status}")
            }
            exits.maxOfOrNull{it.timestamp}?.let{p.edit().putLong("exitAt",it).commit()}
        }catch(_:Exception){}
    }
}

class TrackyuApplication:Application() {
    override fun onCreate() {
        super.onCreate()
        val original=Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler {thread,error->
            try{MobileDiagnostics.record(this,"native_fatal",error.javaClass.name,MobileDiagnostics.frames(error),"uncaught")}catch(_:Throwable){}
            if(original!=null)original.uncaughtException(thread,error) else {android.os.Process.killProcess(android.os.Process.myPid());kotlin.system.exitProcess(10)}
        }
        Thread({MobileDiagnostics.collectExit(this);try{TrackingRuntime.schedule(this)}catch(_:Exception){}},"trackyu-diagnostics").start()
    }
}
