package com.fieldforce.fieldforce_hrms



import android.content.Context

import org.json.JSONObject

import java.net.HttpURLConnection

import java.net.URL

import java.time.Instant



/** Ordered durable outbox. A 4xx blocks the item; it never discards phone data. */

object LocalWorkspaceSync {

    val allowed=setOf("FieldAttendance/punch-in","FieldAttendance/punch-out","OfficeAttendance/punch-in","OfficeAttendance/punch-out","MobileVisits/start","MobileVisits/finish","OfficeLeave/apply","OfficeActivities/save","OfficeReminders/save","OfficePreIntimation/submit")

    fun requiresDirectServer(operation:JSONObject, projected:org.json.JSONArray?=null):Boolean {
        val route=operation.optString("route")
        if(route.contains("Attendance/punch-"))return true
        if(!route.startsWith("MobileVisits/"))return false
        val body=operation.optJSONObject("body") ?: JSONObject()
        if(body.optString("kind").equals("Regular",true) || body.optString("retailerId").let{it.isNotBlank()&&it!="null"})return true
        if(projected!=null)for(i in 0 until projected.length()) {
            val row=projected.getJSONObject(i)
            val id=operation.optLong("localId",-1L)
            if(id>0 && (row.optLong("id")==id || row.optLong("localId")==id)) {
                if(row.optString("kind").equals("Regular",true) || (row.optString("kind").isBlank() && row.optBoolean("isLegacy")))return true
            }
        }
        return false
    }

    fun auth(db:TrackingStore):JSONObject?=db.localRead("system","activeAuth")

    fun request(auth:JSONObject,route:String,body:JSONObject,operationId:String?=null,verifyAccess:Boolean=false):JSONObject {

        require(TrackingRuntime.validUrl(auth.getString("baseUrl")))

        val c=URL(auth.getString("baseUrl")+"/"+route).openConnection() as HttpURLConnection

        try {

            c.requestMethod=if(verifyAccess)"GET"else"POST";c.connectTimeout=8000;c.readTimeout=12000;c.doOutput=!verifyAccess

            c.setRequestProperty("Authorization","Bearer "+auth.getString("token"));c.setRequestProperty("X-Device-ID",auth.getString("deviceId"));c.setRequestProperty("Content-Type","application/json")

            if(operationId!=null)c.setRequestProperty("X-Operation-ID",operationId)

            if(!verifyAccess)c.outputStream.use{it.write(body.toString().toByteArray(Charsets.UTF_8))}

            val status=c.responseCode

            val text=(if(status in 200..299)c.inputStream else c.errorStream)?.bufferedReader()?.use{it.readText()}?:""

            val response=try{JSONObject(text)}catch(_:Exception){JSONObject()}

            if(status !in 200..299||!response.optBoolean("success"))throw SyncError(status,response.optString("message","Sync unavailable"),response.optString("errorCode"))

            return response

        } finally {c.disconnect()}

    }

    class SyncError(val status:Int,message:String,val errorCode:String=""):Exception(message)

    // Durable, scoped retry state survives service restarts without deleting outbox work.
    fun retryState(previous:JSONObject?, id:String, now:Long):JSONObject {
        val attempts = if(previous?.optString("id")==id) previous.optInt("attempts").coerceIn(0,20)+1 else 1
        val delay = (5000L * (1L shl (attempts-1).coerceIn(0,6))).coerceAtMost(300000L)
        return JSONObject().put("id",id).put("attempts",attempts).put("nextAt",now+delay)
    }

    fun retryReady(retry:JSONObject?,now:Long):Boolean = retry==null || now>=retry.optLong("nextAt")

    fun sameCredentials(a:JSONObject?,b:JSONObject):Boolean = a!=null &&
        a.optString("scope")==b.optString("scope") && a.optString("token")==b.optString("token") &&
        a.optString("deviceId")==b.optString("deviceId")

    @Synchronized fun configureAuth(db:TrackingStore,value:JSONObject) {
        val previous=auth(db)
        if(sameCredentials(previous,value) && previous!!.optBoolean("authRequired")) {
            value.put("authRequired",true).put("authError",previous.optString("authError"))
        } else if(!sameCredentials(previous,value)) {
            db.localWrite(value.getString("scope"),"syncRetry",JSONObject())
            db.unblockOutbox(value.getString("scope"))
        }
        db.localWrite("system","activeAuth",value)
    }

    @Synchronized fun requireAuthentication(db:TrackingStore,expected:JSONObject,message:String) {
        val current=auth(db) ?: return
        // A delayed response from the previous login must not pause the new login.
        if(!sameCredentials(current,expected))return
        current.put("authRequired",true).put("authError",message.take(250))
        db.localWrite("system","activeAuth",current)
    }

    fun matchesClosedAttendance(cfg:JSONObject,auth:JSONObject,operation:JSONObject,result:JSONObject):Boolean {
        val mode=if(operation.optString("route").startsWith("FieldAttendance/"))"Field"else"Office"
        if(cfg.optString("userId")!=auth.optString("userId") || cfg.optString("baseUrl")!=auth.optString("baseUrl") || cfg.optString("mode")!=mode)return false
        val serverId=result.optLong("id")
        return serverId>0 && (cfg.optLong("attendanceId")==serverId ||
            (operation.optLong("localId")>0 && cfg.optLong("attendanceId")==operation.optLong("localId")))
    }

    private fun defer(db:TrackingStore,scope:String,id:String) {
        db.localWrite(scope,"syncRetry",retryState(db.localRead(scope,"syncRetry"),id,System.currentTimeMillis()))
    }



    fun renewLease(context:Context,db:TrackingStore) {

        val cfg=db.config()

        if(!cfg.optBoolean("offlineLocal"))return

        val auth=auth(db)?:return

        if(auth.optBoolean("paused")||auth.optBoolean("authRequired")||auth.optString("userId")!=cfg.optString("userId")||auth.optString("baseUrl")!=cfg.optString("baseUrl"))return

        val receipt=db.localResult(auth.getString("scope"),cfg.optString("requestId"))

        val attendanceId=receipt?.optLong("id")?:cfg.optLong("attendanceId")

        if(receipt==null&&cfg.optLong("serverId")==0L)return

        val expires=try{Instant.parse(cfg.optString("expiresAtUtc"))}catch(_:Exception){Instant.EPOCH}

        if(cfg.optString("rejectedTrackingKey")!=cfg.optString("trackingKey")&&cfg.optString("trackingKey").length>=32&&expires.isAfter(Instant.now().plusSeconds(86400)))return

        val lease=try { request(auth,"DutyTracking/lease",JSONObject().put("mode",cfg.getString("mode")).put("attendanceId",attendanceId)).getJSONObject("data") }
        catch(e:SyncError) { if(e.status==401)requireAuthentication(db,auth,"Sign in to resume sync"); throw e }

        val latest=db.config()

        if(latest.optString("requestId")!=cfg.optString("requestId"))return

        latest.put("attendanceId",attendanceId);latest.put("trackingKey",lease.getString("trackingKey"));latest.put("expiresAtUtc",lease.getString("expiresAtUtc"));latest.put("serverTimeUtc",lease.getString("serverTimeUtc"));latest.put("dutyCutoffUtc",lease.getString("dutyCutoffUtc"))

        TrackingRuntime.configure(context,latest)

    }

    fun drain(context:Context,db:TrackingStore,force:Boolean=false):Boolean {
        val auth=auth(db)?:return true
        if(auth.optBoolean("paused"))return true
        if(auth.optBoolean("authRequired")) {
            val retry=db.localRead(auth.getString("scope"),"authRetry")
            if(!force && !retryReady(retry,System.currentTimeMillis()))return false
            try {
                // Revalidate the exact existing signed token; never clear rejection on a health ping.
                request(auth,"Employee/my-profile",JSONObject(),verifyAccess=true)
                synchronized(this) {
                    val current=LocalWorkspaceSync.auth(db) ?: return false
                    if(!sameCredentials(current,auth))return false
                    current.put("authRequired",false).remove("authError")
                    db.localWrite("system","activeAuth",current)
                    db.localWrite(auth.getString("scope"),"authRetry",JSONObject())
                }
            } catch(_:Exception) {
                db.localWrite(auth.getString("scope"),"authRetry",retryState(retry,"session-access",System.currentTimeMillis()))
                return false
            }
        }

        val scope=auth.getString("scope")
        if (force) {
            db.localWrite(scope, "syncRetry", JSONObject())
            db.unblockOutbox(scope)
        } else {
            val retry=db.localRead(scope,"syncRetry")
            if(retry==null) {
                db.unblockOutbox(scope);db.localWrite(scope,"syncRetry",JSONObject())
            }
            if(!retryReady(retry,System.currentTimeMillis()))return false
            if(retry!=null && retry.optString("id").isNotBlank())db.unblockOutbox(scope)
        }

        repeat(30) {

            if(!sameCredentials(auth(db),auth)||auth(db)?.optBoolean("paused")==true||auth(db)?.optBoolean("authRequired")==true)return false

            val operation=db.localNext(scope)?:return db.localSyncState(scope).optInt("blocked")==0

            val id=operation.getString("id");val route=operation.getString("route")

            if(requiresDirectServer(operation,db.localRead(scope,operation.optString("recordKey"))?.optJSONArray("visits"))) {
                db.localError(scope,id,"Server-only action: earlier offline record retained for review; not submitted automatically",true)
                return@repeat
            }

            if(route !in allowed){db.localError(scope,id,"Unsupported operation; retained for review",true);return false}

            try {

                val body=JSONObject(operation.getJSONObject("body").toString())
                // Keep the original offline checkout capture time and GPS evidence on retries.

                val refs=operation.optJSONObject("refs")

                if(refs!=null)for(field in refs.keys()) {

                    val ref=refs.getJSONObject(field);val receipt=db.localResult(scope,ref.getString("operationId"))?:return false

                    val value=receipt.opt(ref.getString("field"))

                    if(value==null||value==JSONObject.NULL)throw IllegalStateException("Dependency receipt is incomplete")

                    body.put(field,value)

                }

                val response=request(auth,route,body,id)

                val value=response.opt("data")

                val saved=if(value is JSONObject)value else JSONObject().put("value",value)

                if(route.endsWith("Attendance/punch-in")) {

                    val mode=if(route.startsWith("Field"))"Field"else"Office"

                    db.remapAttendance(scope,mode,operation.getLong("localId"),saved.getLong("id"))
                }

                db.localAck(scope,operation,saved)
                db.localWrite(scope,"syncRetry",JSONObject())
                if(route.endsWith("Attendance/punch-out"))TrackingRuntime.stopAcknowledgedAttendance(context,db,auth,operation,saved)

            } catch(e:SyncError) {

                // Keep payload and operation ID; do not hammer the same conflict on every callback.
                val is10Min = e.message?.contains("10 minutes") == true
                val permanent = (e.status == 409 || e.status == 404) || (!is10Min && e.status in 400..499 && e.status !in listOf(401, 408, 429))
                if (permanent) {
                    db.localWrite(scope, "syncRetry", JSONObject())
                } else {
                    defer(db,scope,id)
                }
                if(e.status==401)requireAuthentication(db,auth,"Sign in to resume sync")

                if (e.status == 409 || e.status == 404) {

                    // Do not treat 404/409 as proof of success without verified receipt!

                    // Mark as blocked error so outbox state is observable and user is informed.

                    val msg = e.message ?: "Server conflict or record not found (${e.status})"

                    db.localError(scope, id, msg, blocked = true)

                    return false

                } else {

                    val is10Min = e.message?.contains("10 minutes") == true
                db.localError(scope,id,if(e.status==401)"Sign in to resume sync"else e.message?:"Sync failed",!is10Min && e.status in 400..499&&e.status !in listOf(401,408,429))

                    return false

                }

            } catch(_:Exception) {defer(db,scope,id);db.localError(scope,id,"Connection unavailable. Saved on this phone.",false);return false}

        }

        return false

    }

}

