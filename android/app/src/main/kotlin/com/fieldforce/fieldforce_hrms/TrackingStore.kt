package com.fieldforce.fieldforce_hrms



import android.content.Context



import android.content.ContentValues



import android.database.sqlite.SQLiteDatabase



import android.database.sqlite.SQLiteOpenHelper



import android.security.keystore.KeyGenParameterSpec



import android.security.keystore.KeyProperties



import android.util.Base64



import org.json.JSONObject



import org.json.JSONArray



import java.time.Instant



import java.util.UUID



import java.security.KeyStore



import javax.crypto.Cipher



import javax.crypto.KeyGenerator



import javax.crypto.SecretKey



import javax.crypto.spec.GCMParameterSpec



class TrackingStore(private val context: Context, private val name: String = "duty_locations_v1.db", private val alias: String = "trackyu_duty_v1") : SQLiteOpenHelper(context,name,null,2) {



    interface CryptoProvider {

        fun encrypt(value: String): String

        fun decrypt(value: String): String

    }



    enum class ConfigStatus {

        EMPTY,

        VALID,

        DECRYPT_ERROR

    }



    var cryptoProvider: CryptoProvider? = null

    var testPrefs: android.content.SharedPreferences? = null



    private val prefs: android.content.SharedPreferences

        get() = testPrefs ?: context.getSharedPreferences(name + ".state", Context.MODE_PRIVATE)



    @Volatile var configStatus: ConfigStatus = ConfigStatus.EMPTY

        private set

    @Volatile var stateStatus: ConfigStatus = ConfigStatus.EMPTY

        private set



    @Volatile private var cachedKey:SecretKey?=null



    // Bounded memory cache only; encrypted SQLite remains the source of truth.



    private val routeCache=object:LinkedHashMap<String,Pair<String,String>>(256,0.75f,true){



        override fun removeEldestEntry(eldest:MutableMap.MutableEntry<String,Pair<String,String>>?):Boolean=size>6000



    }



    private fun routePayload(id:String,payload:String):JSONObject {



        val cached=synchronized(routeCache){routeCache[id]}



        val decoded=if(cached?.first==payload)cached.second else decrypt(payload).also{



            synchronized(routeCache){routeCache[id]=payload to it}



        }



        return JSONObject(decoded)



    }



    init { setWriteAheadLoggingEnabled(true) }



    override fun onCreate(db: SQLiteDatabase) { db.execSQL("CREATE TABLE samples(id TEXT PRIMARY KEY,user_id TEXT NOT NULL,captured INTEGER NOT NULL,ack INTEGER NOT NULL DEFAULT 0,payload TEXT NOT NULL)");db.execSQL("CREATE INDEX pending ON samples(user_id,ack,captured)") }



    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int,newVersion: Int) { journalSchema(db) }



    override fun onOpen(db: SQLiteDatabase) { 



        super.onOpen(db)



        journalSchema(db)



    }



    private fun journalSchema(db:SQLiteDatabase) {



        db.execSQL("CREATE TABLE IF NOT EXISTS local_records(scope TEXT NOT NULL, record_key TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(scope,record_key))")



        db.execSQL("CREATE TABLE IF NOT EXISTS local_outbox(seq INTEGER PRIMARY KEY AUTOINCREMENT, scope TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending', result TEXT, error TEXT, UNIQUE(scope,id))")



        db.execSQL("CREATE INDEX IF NOT EXISTS local_outbox_pending ON local_outbox(scope,state,seq)")



        db.execSQL("CREATE INDEX IF NOT EXISTS route_samples ON samples(user_id,captured,id)")



    }



    fun checkIntegrity(): String {



        return try {



            readableDatabase.rawQuery("PRAGMA quick_check", null).use {



                if (it.moveToFirst()) it.getString(0) else "unknown"



            }



        } catch (e: Exception) {



            "error: " + e.message



        }



    }



    /** Safely read potentially oversized text without exceeding SQLite CursorWindow limits. */



    fun readSafeText(db: SQLiteDatabase, table: String, column: String, whereClause: String, whereArgs: Array<String>): String? {



        val len = try {



            db.rawQuery("SELECT length(" + column + ") FROM " + table + " WHERE " + whereClause, whereArgs).use {



                if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else return null



            }



        } catch (_: Exception) { return null }



        if (len <= 400000L) {



            return try {



                db.rawQuery("SELECT " + column + " FROM " + table + " WHERE " + whereClause, whereArgs).use {



                    if (it.moveToFirst()) it.getString(0) else null



                }



            } catch (_: Exception) {



                readChunkedText(db, table, column, whereClause, whereArgs, len)



            }



        }



        return readChunkedText(db, table, column, whereClause, whereArgs, len)



    }



    private fun readChunkedText(db: SQLiteDatabase, table: String, column: String, whereClause: String, whereArgs: Array<String>, totalLen: Long): String? {



        val sb = StringBuilder(totalLen.coerceAtMost(25000000L).toInt())



        var offset = 1L



        val chunkSize = 200000L



        while (offset <= totalLen) {



            val chunk = db.rawQuery("SELECT substr(" + column + ", " + offset + ", " + chunkSize + ") FROM " + table + " WHERE " + whereClause, whereArgs).use {



                if (it.moveToFirst()) it.getString(0) else ""



            }



            if (chunk.isNullOrEmpty()) break



            sb.append(chunk)



            offset += chunkSize



        }



        return if (sb.isNotEmpty()) sb.toString() else null



    }



    @Synchronized fun localRead(scope:String,key:String):JSONObject? {



        try {



            val raw = readSafeText(readableDatabase, "local_records", "payload", "scope=? AND record_key=?", arrayOf(scope, key))



                ?: return null



            return JSONObject(decrypt(raw))



        } catch (e: Exception) {



            MobileDiagnostics.record(context, "store", e.javaClass.name, MobileDiagnostics.frames(e), "localRead." + key)



            return null



        }



    }



    @Synchronized fun localWrite(scope:String,key:String,value:JSONObject) {



        var toStore = value



        if (key.startsWith("day:") && key.length > 4) {



            val report = toStore.optJSONObject("report")



            val points = report?.optJSONArray("recordedPoints")



            if (points != null && points.length() > 300) {



                val trimmed = JSONObject(toStore.toString())



                trimmed.optJSONObject("report")?.let { rep ->



                    rep.remove("recordedPoints")



                    rep.optJSONObject("route")?.put("segments", JSONArray())



                    rep.put("gpsInSamples", true)



                }



                toStore = trimmed



            }



        }



        val payloadStr = encrypt(toStore.toString())



        // bounded write preserving all offline data



        val db = writableDatabase



        val ownTransaction = !db.inTransaction()



        if (ownTransaction) db.beginTransaction()



        try {



            db.execSQL("INSERT OR REPLACE INTO local_records(scope,record_key,payload) VALUES(?,?,?)", arrayOf(scope, key, payloadStr))



            if (key.startsWith("day:") && key.length > 4) {



                val summary = RouteProjection.build(value)



                val rawPoints = value.optJSONObject("report")?.optJSONArray("recordedPoints")



                val fingerprint = if (rawPoints != null && rawPoints.length() > 0) UUID.nameUUIDFromBytes(rawPoints.toString().toByteArray()).toString() else null



                val cached = localRead(scope, "timeline-v3:" + key.substring(4))?.optJSONObject("report")?.optString("gpsFingerprint")



                if ((fingerprint != null && cached == fingerprint) || stageRestoredPoints(scope, value)) summary.optJSONObject("report")?.let { report ->



                    report.remove("recordedPoints")



                    report.optJSONObject("route")?.put("segments", JSONArray())



                    report.put("gpsInSamples", true)



                    report.put("gpsFingerprint", fingerprint)



                }



                val summaryStr = encrypt(summary.toString())



                    writableDatabase.execSQL("INSERT OR REPLACE INTO local_records(scope,record_key,payload) VALUES(?,?,?)", arrayOf(scope, "timeline-v3:" + key.substring(4), summaryStr))



            }



            if (ownTransaction) db.setTransactionSuccessful()



        } finally {



            if (ownTransaction) db.endTransaction()



        }



    }



    @Synchronized fun routeSummary(scope:String,key:String):JSONObject? {



        val summaryKey = "timeline-v3:" + key.removePrefix("day:")



        localRead(scope, summaryKey)?.let { return it }



        val original = localRead(scope, key) ?: return null



        val summary = RouteProjection.build(original)



        val summaryStr = encrypt(summary.toString())



            writableDatabase.execSQL("INSERT OR REPLACE INTO local_records(scope,record_key,payload) VALUES(?,?,?)", arrayOf(scope, summaryKey, summaryStr))



        return summary



    }



    /** Restored fixes are read-only history (ack=1), never queued as new captures. */



    private fun stageRestoredPoints(scope:String,day:JSONObject):Boolean {



        val report=day.optJSONObject("report")?:return false



        val points=report.optJSONArray("recordedPoints")?:return false



        if(points.length()==0)return false



        if(report.has("userId")&&report.optString("userId")!=scope.substringAfterLast('|'))return false



        val boundaries=mutableSetOf<String>()



        report.optJSONObject("route")?.optJSONArray("segments")?.let{segments->



            for(i in 0 until segments.length())segments.optJSONArray(i)?.optJSONObject(0)?.optString("capturedAtUtc")?.let{boundaries.add(it)}



        }



        val statement=writableDatabase.compileStatement("INSERT OR IGNORE INTO samples(id,user_id,captured,ack,payload) VALUES(?,?,?,1,?)")



        var complete=true



        try {



            for(i in 0 until points.length()) {



                val original=points.optJSONObject(i)



                if(original==null){complete=false;continue}



                val at=try{Instant.parse(original.optString("capturedAtUtc"))}catch(_:Exception){complete=false;continue}



                val p=JSONObject(original.toString())



                val identity=p.optString("sampleId").ifBlank{p.optString("id")}.ifBlank{UUID.nameUUIDFromBytes((scope+p.toString()).toByteArray()).toString()}



                p.put("id",identity);p.put("mode",p.optString("mode").ifBlank{p.optString("attendanceMode")})



                if(p.optString("capturedAtUtc") in boundaries)p.put("breakBefore",true)



                val key="restored:"+UUID.nameUUIDFromBytes(scope.toByteArray())+":"+identity



                statement.clearBindings();statement.bindString(1,key);statement.bindString(2,scope);statement.bindLong(3,at.toEpochMilli());statement.bindString(4,encrypt(p.toString()));statement.executeInsert()



            }



        }finally{statement.close()}



        return complete



    }



    @Synchronized fun localCommit(scope:String,key:String,value:JSONObject,operation:JSONObject) {



        val db=writableDatabase;db.beginTransaction()



        try {



            val current=localRead(scope,key)



            fun metadata(incoming:JSONObject?,saved:JSONObject?) {



                if(incoming==null||saved==null)return



                if(incoming.optLong("localId",incoming.optLong("id"))!=saved.optLong("localId",saved.optLong("id")))return



                for(field in listOf("id","serverId","version"))if(saved.has("serverId")&&saved.has(field))incoming.put(field,saved.get(field))



            }



            metadata(value.optJSONObject("attendance"),current?.optJSONObject("attendance"))



            val rows=value.optJSONArray("visits");val oldRows=current?.optJSONArray("visits")



            if(rows!=null&&oldRows!=null)for(i in 0 until rows.length())for(j in 0 until oldRows.length())metadata(rows.optJSONObject(i),oldRows.optJSONObject(j))



            val field=when {operation.getString("route").contains("Attendance/punch-")->"attendance";operation.getString("route").startsWith("MobileVisits/")->"visits";else->"activities"}



            val merged=current?:JSONObject()



            if(value.has(field))merged.put(field,value.get(field))



            localWrite(scope,key,merged);db.insertOrThrow("local_outbox",null,ContentValues().apply{put("scope",scope);put("id",operation.getString("id"));put("payload",encrypt(operation.toString()))});db.setTransactionSuccessful() } finally {db.endTransaction()}



    }



    @Synchronized fun localNext(scope:String):JSONObject? {
        val raw = readSafeText(readableDatabase, "local_outbox", "payload", "scope=? AND state='pending' ORDER BY seq LIMIT 1", arrayOf(scope)) ?: return null
        return JSONObject(decrypt(raw))
    }



    @Synchronized fun localResult(scope:String,id:String):JSONObject? = readableDatabase.rawQuery("SELECT result FROM local_outbox WHERE scope=? AND id=? AND state='done'",arrayOf(scope,id)).use {if(it.moveToFirst()&&!it.isNull(0))JSONObject(decrypt(it.getString(0)))else null}



    @Synchronized fun localError(scope:String,id:String,error:String,blocked:Boolean) { writableDatabase.update("local_outbox",ContentValues().apply{put("error",error.take(250));put("state",if(blocked)"blocked"else"pending")},"scope=? AND id=?",arrayOf(scope,id)) }



    @Synchronized fun unblockOutbox(scope:String) { writableDatabase.execSQL("UPDATE local_outbox SET state='pending', error=NULL WHERE scope=? AND state='blocked'", arrayOf(scope)) }



    @Synchronized fun localSyncState(scope:String):JSONObject {



        val result=JSONObject().put("pending",0).put("blocked",0)



        readableDatabase.rawQuery("SELECT state,COUNT(*) FROM local_outbox WHERE scope=? GROUP BY state",arrayOf(scope)).use {while(it.moveToNext())result.put(it.getString(0),it.getInt(1))}



        readableDatabase.rawQuery("SELECT error FROM local_outbox WHERE scope=? AND state<>'done' AND error IS NOT NULL ORDER BY seq LIMIT 1",arrayOf(scope)).use {if(it.moveToFirst())result.put("error",it.getString(0))}



        val auth=localRead("system","activeAuth")
        if(auth?.optString("scope")==scope && auth.optBoolean("authRequired")) {
            result.put("authRequired",true).put("error",auth.optString("authError","Sign in to resume sync"))
        }
        return result



    }



    @Synchronized fun localAck(scope:String,operation:JSONObject,result:JSONObject) {

        val route = operation.getString("route")
        // Require valid positive server ID on attendance and visit receipts before marking done or removing body!
        if (route.contains("Attendance/punch-") || route.startsWith("MobileVisits/")) {
            val serverId = result.optLong("id", -1L)
            if (serverId <= 0L) {
                throw IllegalStateException("Server receipt for $route is missing valid server id. Aborting outbox acknowledgement: $result")
            }
        }



        val db=writableDatabase;db.beginTransaction()



        try {



            db.update("local_outbox",ContentValues().apply{put("state","done");put("payload",encrypt(JSONObject(operation.toString()).apply{remove("body")}.toString()));put("result",encrypt(result.toString()));putNull("error")},"scope=? AND id=?",arrayOf(scope,operation.getString("id")))



            val key=operation.optString("recordKey");val day=localRead(scope,key)



            if(day!=null) {



                val localId=operation.optLong("localId");val route=operation.getString("route")



                if(route.contains("Attendance/punch-")) {



                    val att=day.optJSONObject("attendance")



                    if(att!=null&&(att.optLong("id")==localId||att.optLong("localId")==localId)) {



                        val sId = result.optLong("id", -1L); if (sId > 0) { att.put("serverId", sId); att.put("id", sId) }



                        if(route.endsWith("punch-out")||att.isNull("punchOutUtc"))for(k in result.keys())att.put(k,result.get(k))



                        att.put("syncState",if(route.endsWith("punch-in") && !att.isNull("punchOutUtc"))"pending"else"synced")



                    }



                } else if(route.startsWith("MobileVisits/")) {



                    val visits=day.optJSONArray("visits")



                    if(visits!=null)for(i in 0 until visits.length()) {



                        val visit=visits.getJSONObject(i)



                        if(visit.optLong("id")==localId||visit.optLong("localId")==localId) {



                            if(route.endsWith("/finish")) {
                                val body=operation.optJSONObject("body")
                                val expected=body?.optLong("id",0L) ?: 0L
                                if(operation.optJSONObject("refs")?.has("id")!=true && expected>0L && expected!=result.getLong("id")) {
                                    throw IllegalStateException("Checkout receipt does not match the queued visit")
                                }
                                val serverClose=result.optString("checkOutUtc").takeIf{it.isNotBlank()&&it!="null"}
                                val captured=body?.optString("capturedAtUtc")?.takeIf{it.isNotBlank()&&it!="null"}
                                val close=serverClose ?: visit.optString("checkOutUtc").takeIf{it.isNotBlank()&&it!="null"} ?: captured
                                check(close!=null){"Checkout receipt lacks a verifiable close time; saved work retained"}
                                visit.put("checkOutUtc",close).put("localCheckout",false)
                                body?.optString("requestId")?.takeIf{it.isNotBlank()}?.let{visit.put("closeRequestId",it)}
                            }
                            val vId = result.optLong("id", -1L); if (vId > 0) { visit.put("serverId", vId); visit.put("id", vId); visit.put("version",result.optString("version"));visit.put("syncState",if(route.endsWith("/start") && !visit.isNull("checkOutUtc"))"pending"else"synced") } else { visit.put("syncState", result.optString("status", "conflict")) }



                        }



                    }



                }



                val activities=day.optJSONArray("activities")



                if(activities!=null)for(i in 0 until activities.length()) {



                    val activity=activities.getJSONObject(i)



                    if(activity.optString("operationId")==operation.getString("id")){activity.put("syncState","synced");activity.put("result",result)}



                }



                localWrite(scope,key,day)



            }



            db.setTransactionSuccessful()



        } finally {db.endTransaction()}



    }



    @Synchronized fun remapAttendance(user:String,mode:String,localId:Long,serverId:Long) {



        localWrite(user,"attendance:$mode:$localId",JSONObject().put("id",serverId))



        val changes=mutableListOf<Pair<String,JSONObject>>()



        readableDatabase.rawQuery("SELECT id,payload FROM samples WHERE user_id=? AND ack=0",arrayOf(user)).use {while(it.moveToNext()){val p=JSONObject(decrypt(it.getString(1)));if(p.optLong("attendanceId")==localId&&p.optString("mode")==mode){p.put("attendanceId",serverId);changes.add(it.getString(0) to p)}}}



        writableDatabase.beginTransaction();try {for((id,p)in changes)writableDatabase.update("samples",ContentValues().apply{put("payload",encrypt(p.toString()))},"id=?",arrayOf(id));writableDatabase.setTransactionSuccessful()}finally{writableDatabase.endTransaction()}



        try {



            val dayKeys = mutableListOf<String>()



            readableDatabase.rawQuery("SELECT record_key FROM local_records WHERE scope=? AND record_key LIKE 'day:%'", arrayOf(user)).use { cursor ->



                while (cursor.moveToNext()) {



                    dayKeys.add(cursor.getString(0))



                }



            }



            for (k in dayKeys) {



                val dayObj = localRead(user, k) ?: continue



                val att = dayObj.optJSONObject("attendance")



                if (att != null && (att.optLong("id") == localId || att.optLong("localId") == localId)) {



                    att.put("serverId", serverId)



                    att.put("id", serverId)



                    localWrite(user, k, dayObj)



                }



            }



        } catch (_: Exception) {}



    }



    private fun key(): SecretKey {



        cachedKey?.let{return it}



        val ks=KeyStore.getInstance("AndroidKeyStore").apply{load(null)}



        val value=(ks.getKey(alias,null) as? SecretKey)?:KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").run {



            init(KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());generateKey()



        }



        cachedKey=value



        return value



    }



    @Synchronized fun encrypt(value: String): String {

        cryptoProvider?.let { return it.encrypt(value) }

        val cipher=Cipher.getInstance("AES/GCM/NoPadding")

        cipher.init(Cipher.ENCRYPT_MODE,key())

        return Base64.encodeToString(cipher.iv+cipher.doFinal(value.toByteArray(Charsets.UTF_8)),Base64.NO_WRAP)

    }



    @Synchronized fun decrypt(value: String): String {

        cryptoProvider?.let { return it.decrypt(value) }

        val bytes=Base64.decode(value,Base64.NO_WRAP)

        require(bytes.size>28)

        val cipher=Cipher.getInstance("AES/GCM/NoPadding")

        cipher.init(Cipher.DECRYPT_MODE,key(),GCMParameterSpec(128,bytes.copyOfRange(0,12)))

        return String(cipher.doFinal(bytes.copyOfRange(12,bytes.size)),Charsets.UTF_8)

    }



    @Volatile private var cachedConfig: JSONObject? = null



    @Volatile private var cachedState: JSONObject? = null



    @Volatile private var cachedPending: Pair<String, Pair<Int, Long>>? = null



    @Synchronized fun clearMemoryCache() {

        cachedConfig = null

        cachedState = null

        cachedPending = null

        configStatus = ConfigStatus.EMPTY

        stateStatus = ConfigStatus.EMPTY

    }



    @Synchronized fun config(): JSONObject {

        val c = cachedConfig

        if (c != null) {

            configStatus = ConfigStatus.VALID

            return c

        }

        val raw = prefs.getString("config", null)

        if (raw == null) {

            configStatus = ConfigStatus.EMPTY

            return JSONObject()

        }

        val loaded = try {

            val json = JSONObject(decrypt(raw))

            configStatus = ConfigStatus.VALID

            json

        } catch (_: Exception) {

            // State 3: Encrypted config exists on disk, but Keystore decrypt failed.

            // NEVER remove "config"; transient Keystore errors must preserve ciphertext.

            configStatus = ConfigStatus.DECRYPT_ERROR

            return cachedConfig ?: JSONObject()

        }

        cachedConfig = loaded

        return loaded

    }



    @Synchronized fun saveConfig(value: JSONObject) {

        cachedConfig = JSONObject(value.toString())

        configStatus = ConfigStatus.VALID

        check(prefs.edit().putString("config", encrypt(value.toString())).commit())

    }



    @Synchronized fun state(): JSONObject {

        val s = cachedState

        if (s != null) {

            stateStatus = ConfigStatus.VALID

            return s

        }

        val raw = prefs.getString("state", null)

        if (raw == null) {

            stateStatus = ConfigStatus.EMPTY

            return JSONObject()

        }

        val loaded = try {

            val json = JSONObject(decrypt(raw))

            stateStatus = ConfigStatus.VALID

            json

        } catch (_: Exception) {

            // NEVER remove "state" on decrypt exception; transient Keystore errors must preserve ciphertext.

            stateStatus = ConfigStatus.DECRYPT_ERROR

            return cachedState ?: JSONObject()

        }

        cachedState = loaded

        return loaded

    }



    @Synchronized fun updateState(block: (JSONObject) -> Unit) {



        val value = state()



        block(value)



        cachedState = JSONObject(value.toString())



        check(prefs.edit().putString("state", encrypt(value.toString())).commit())



    }



    @Synchronized fun append(user: String, point: JSONObject) {



        cachedPending = null



        val mapping=localRead(user,"attendance:${point.optString("mode")}:${point.optLong("attendanceId")}")



        if(mapping!=null)point.put("attendanceId",mapping.getLong("id"))



        val values=ContentValues().apply { put("id",point.getString("id"));put("user_id",user);put("captured",java.time.Instant.parse(point.getString("capturedAtUtc")).toEpochMilli());put("payload",encrypt(point.toString())) }; val inserted=writableDatabase.insertWithOnConflict("samples",null,values,SQLiteDatabase.CONFLICT_IGNORE)



        if(inserted<0)check(readableDatabase.rawQuery("SELECT COUNT(*) FROM samples WHERE id=?",arrayOf(point.getString("id"))).use{it.moveToFirst();it.getInt(0)==1}){"Unable to persist GPS sample"}



    }



    fun total(): Int = readableDatabase.rawQuery("SELECT COUNT(*) FROM samples",null).use { it.moveToFirst();it.getInt(0) }



    fun pending(user: String): Int {



        val now = android.os.SystemClock.elapsedRealtime()



        val c = cachedPending



        if (c != null && c.first == user && (now - c.second.second) < 10000L) {



            return c.second.first



        }



        val count = readableDatabase.rawQuery("SELECT COUNT(*) FROM samples WHERE user_id=? AND ack=0",arrayOf(user)).use {



            if (it.moveToFirst()) it.getInt(0) else 0



        }



        cachedPending = Pair(user, Pair(count, now))



        return count



    }



    fun batch(user: String): List<JSONObject> = readableDatabase.rawQuery("SELECT payload FROM samples WHERE user_id=? AND ack=0 ORDER BY captured,id LIMIT 50",arrayOf(user)).use { cursor->buildList {while(cursor.moveToNext())add(JSONObject(decrypt(cursor.getString(0))))} }



    @Synchronized fun acknowledge(user: String, id: String, rejected: Boolean) { 



        cachedPending = null



        val v=ContentValues().apply {put("ack",if(rejected)2 else 1)}



        writableDatabase.update("samples",v,"user_id=? AND id=? AND ack=0",arrayOf(user,id)) 



    }



    @JvmOverloads fun route(user:String,from:Long,to:Long,maxPoints:Int=0,offset:Int=0,pageSize:Int=0):List<JSONObject> {



        val clean=user.trim();val u=clean.substringAfterLast('|')



        val owners=linkedSetOf(clean)



        if(clean.contains('|')) {



            val base=clean.substringBeforeLast('|').trimEnd('/')



            owners.add(base+"|"+u);owners.add(base+"/|"+u)



        }



        val where="user_id IN("+owners.joinToString(","){"?"}+") AND captured>=? AND captured<?"



        val args=(owners.toList()+listOf(from.toString(),to.toString())).toTypedArray()



        val total=readableDatabase.rawQuery("SELECT COUNT(*) FROM samples WHERE $where",args).use{it.moveToFirst();it.getInt(0)}



        val stride=if(pageSize>0||maxPoints<=1||total<=maxPoints)1 else (total+maxPoints-2)/(maxPoints-1)



        val paging=if(pageSize>0)" LIMIT ${pageSize.coerceIn(1,2000)} OFFSET ${offset.coerceAtLeast(0)}" else ""



        return readableDatabase.rawQuery("SELECT id,payload FROM samples WHERE $where ORDER BY captured,id$paging",args).use{cursor->



            buildList{var index=0;while(cursor.moveToNext()){



                if(index%stride==0||index==total-1){val point=routePayload(cursor.getString(0),cursor.getString(1));if(stride>1)point.put("displaySampled",true);add(point)}



                index++



            }}



        }



    }



    // Retention is explicit: never erase pending or rejected points during sync.



    @Synchronized fun prune(now: Long) { }



}

