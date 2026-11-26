package com.fieldforce.fieldforce_hrms
import android.app.Instrumentation
import android.os.Bundle
import org.json.JSONObject
import java.time.Instant
import java.util.UUID
import java.security.KeyStore

/** Runs against a dedicated disposable database and key; never changes employee tracking. */
class TrackingInstrumentation: Instrumentation(){
 override fun onCreate(arguments:Bundle?){super.onCreate(arguments);start()}
 override fun onStart(){
  val name="qa_tracking_${UUID.randomUUID()}.db";val alias="qa_trackyu_${UUID.randomUUID()}";var db:TrackingStore?=null
  val result=Bundle();var resultCode=-1;var stage="SQLite durability"
  try{
   val user="QA_QUEUE_ONLY";val now=System.currentTimeMillis()
   fun point(offset:Long)=JSONObject().put("id",UUID.randomUUID().toString()).put("mode","Field").put("attendanceId",1).put("capturedAtUtc",Instant.ofEpochMilli(now+offset).toString()).put("latitude",19.07612345).put("longitude",72.87771234).put("accuracyMeters",5)
   val first=point(-60000);val second=point(-30000);db=TrackingStore(targetContext,name,alias)
   db!!.saveConfig(JSONObject().put("trackingKey","qa-secret-not-plaintext").put("userId",user))
   db!!.append(user,second);db!!.append(user,first);db!!.append(user,first)
   check(db!!.pending(user)==2){"Duplicate location IDs must not grow the queue"}
   check(db!!.batch(user).first().getString("id")==first.getString("id")){"Queue must upload original capture order"}
   check(db!!.pending("ANOTHER_USER")==0){"Queue must isolate users"}
   db!!.readableDatabase.rawQuery("SELECT payload FROM samples",null).use{cursor->while(cursor.moveToNext())check(!cursor.getString(0).contains("latitude")){"GPS payload must be encrypted"}}
   check(!targetContext.getSharedPreferences(name+".state",0).getString("config","")!!.contains("qa-secret")){"Tracking authorization must be encrypted"}
   db!!.close();db=TrackingStore(targetContext,name,alias)
   check(db!!.pending(user)==2){"Network failure / process restart must retain unacknowledged fixes"}
   check(db!!.config().getString("trackingKey")=="qa-secret-not-plaintext"){"Keystore configuration must survive reopen"}
   db!!.acknowledge(user,first.getString("id"),false);db!!.acknowledge(user,first.getString("id"),false)
   check(db!!.pending(user)==1){"Acknowledgement must be idempotent"}
   check(db!!.route(user,now-120000,now).size==2){"Acknowledged trail must remain available for offline viewing"}
   db!!.acknowledge(user,second.getString("id"),true)
   check(db!!.pending(user)==0&&db!!.route(user,now-120000,now).size==2){"Rejected fixes must remain available in the phone route"}
   val old=point(-35*86400000L);db!!.append(user,old);db!!.prune(now)
   check(db!!.pending(user)==1&&db!!.route(user,now-36*86400000L,now).size==3){"Pending locations must never expire during sync"}
   db!!.acknowledge(user,old.getString("id"),false)
   val scope="https://qa.example/api|QA";val opId=UUID.randomUUID().toString();val key="day:2026-11-09"
   val secondKey="day:2026-11-10"
   db!!.localWrite(scope,key,JSONObject().put("report",JSONObject().put("date","2026-11-09")))
   db!!.localWrite(scope,secondKey,JSONObject().put("report",JSONObject().put("date","2026-11-10")))
   check(db!!.routeSummary(scope,key)!!.getJSONObject("report").getString("date")=="2026-11-09"){"First restored date must remain independently readable"}
   check(db!!.routeSummary(scope,secondKey)!!.getJSONObject("report").getString("date")=="2026-11-10"){"Second restored date must not replace the first"}
   val apiA="https://one.example/api|SHARED";val apiB="https://two.example/api|SHARED"
   db!!.append(apiA,point(-500));db!!.append(apiB,point(-400));db!!.append(apiA,point(0))
   check(db!!.route(apiA,now-1000,now).size==1){"API scope and exclusive day end must isolate samples"}
   check(db!!.route(apiB,now-1000,now).size==1){"Shared employee ID cannot combine two APIs"}
   val op=JSONObject().put("id",opId).put("route","FieldAttendance/punch-in").put("body",JSONObject()).put("recordKey",key).put("localId",123)
   val day=JSONObject().put("attendance",JSONObject().put("id",123).put("localId",123).put("punchOutUtc",JSONObject.NULL))
   db!!.localCommit(scope,key,day,op)
   check(db!!.localRead(scope,key)!=null&&db!!.localNext(scope)?.getString("id")==opId){"Activity and outbox must commit together"}
   check(db!!.localNext("different-account")==null){"Outbox must isolate workspaces and employees"}
   val changed=JSONObject().put("attendance",JSONObject().put("id",999))
   try{db!!.localCommit(scope,key,changed,op);error("Expected duplicate commit to fail")}catch(_:android.database.sqlite.SQLiteConstraintException){}
   check(db!!.localRead(scope,key)!!.getJSONObject("attendance").getLong("id")==123L){"Failed outbox insert must roll back visible record"}
   db!!.localError(scope,opId,"Needs review",true)
   check(db!!.localNext(scope)==null&&db!!.localSyncState(scope).getInt("blocked")==1&&db!!.localRead(scope,key)!=null){"Rejected operations must be retained and visible"}
   db!!.localError(scope,opId,"Retry",false)
   // Reject malformed server receipts without losing previously committed evidence.
   val beforeRejectedAck=db!!.localNext(scope)!!.toString()
   val beforeRejectedDay=db!!.localRead(scope,key)!!.toString()
   for(invalidId in listOf(0L,-1L)) {
    var rejected=false
    try { db!!.localAck(scope,op,JSONObject().put("id",invalidId)) }
    catch(expected:IllegalStateException) { rejected=true }
    check(rejected){"Invalid receipt must be rejected before acknowledgement"}
    db!!.close();db=TrackingStore(targetContext,name,alias)
    check(db!!.localNext(scope)!!.toString()==beforeRejectedAck){"Rejected acknowledgement must preserve full outbox body after disk reopen"}
    check(db!!.localRead(scope,key)!!.toString()==beforeRejectedDay){"Rejected acknowledgement must preserve attendance projection after disk reopen"}
    check(db!!.localSyncState(scope).getInt("pending")==1){"Rejected acknowledgement must retain pending sync state after reopen"}
    check(db!!.localResult(scope,opId)==null){"Invalid acknowledgement must not create a successful receipt"}
   }
   db!!.localAck(scope,op,JSONObject().put("id",456))
   check(db!!.localResult(scope,opId)!!.getLong("id")==456L&&db!!.localRead(scope,key)!!.getJSONObject("attendance").getLong("id")==456L){"Receipt must update the local projection atomically"}
   val temporary=point(-1000).put("attendanceId",123);db!!.remapAttendance(scope,"Field",123,456);db!!.append(scope,temporary)
   check(db!!.batch(scope).single().getLong("attendanceId")==456L){"Late GPS callbacks must resolve temporary attendance IDs"}
   db!!.acknowledge(scope,temporary.getString("id"),false)
   stage="GPS HTTP retention and explicit retry"
   // Exercise the real native HTTP transport against a local disposable server.
   val outgoing=point(-1000)
   val unused=java.net.ServerSocket(0);val port=unused.localPort;unused.close()
   val uploadOwner="http://127.0.0.1:$port/api|"+user;db!!.append(uploadOwner,outgoing)
   db!!.saveConfig(JSONObject().put("baseUrl","http://127.0.0.1:$port/api").put("userId",user).put("trackingKey","qa-write-only-grant-12345678901234567890").put("deviceId","qa-isolated-test-phone").put("mode","Field").put("attendanceId",1).put("active",false))
   check(!TrackingRuntime.sync(targetContext,db)&&db!!.pending(uploadOwner)==1){"Failed HTTP upload must preserve queue"}
   val server=java.net.ServerSocket(port);server.soTimeout=10000
   val failure=java.util.concurrent.atomic.AtomicReference<Throwable?>(null)
   val receiver=Thread {
    try{server.accept().use {socket->
      socket.soTimeout=10000;val input=socket.getInputStream().bufferedReader();var length=0;var keySeen=false
      while(true){val line=input.readLine()?:break;if(line.isEmpty())break;if(line.startsWith("Content-Length:",true))length=line.substringAfter(":").trim().toInt();if(line.startsWith("X-Tracking-Key:",true))keySeen=line.contains("qa-write-only-grant-12345678901234567890")}
      val chars=CharArray(length);var read=0;while(read<length){val count=input.read(chars,read,length-read);check(count>0);read+=count}
      val body=JSONObject(String(chars));check(keySeen&&body.getJSONArray("samples").getJSONObject(0).getString("capturedAtUtc")==outgoing.getString("capturedAtUtc")){"Transport must keep original capture time and scoped authorization"}
      val response=JSONObject().put("success",true).put("data",JSONObject().put("serverTimeUtc",Instant.now().toString()).put("acknowledgements",org.json.JSONArray().put(JSONObject().put("id",outgoing.getString("id")).put("disposition","accepted"))))
      val bytes=response.toString().toByteArray();socket.getOutputStream().write(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n").toByteArray()+bytes)
    }}catch(error:Throwable){failure.set(error)}finally{server.close()}
   };receiver.start();val uploaded=TrackingRuntime.sync(targetContext,db,force=true);receiver.join(12000);failure.get()?.let{throw it};check(uploaded){"Successful native upload must acknowledge the queue: "+db!!.state().optString("lastError")+"; pending="+db!!.pending(uploadOwner)};check(db!!.pending(uploadOwner)==0){"Only server-acknowledged points may leave the queue"}
   stage="Server-only legacy attendance and regular visit retention"
   val blockedScope="http://127.0.0.1:9/api|"+user
   db!!.localWrite("system","activeAuth",JSONObject().put("scope",blockedScope).put("baseUrl","http://127.0.0.1:9/api").put("userId",user).put("deviceId","qa-device").put("token","qa-not-real"))
   val oldAttendance=JSONObject().put("id",UUID.randomUUID().toString()).put("route","FieldAttendance/punch-in").put("localId",77).put("recordKey",key).put("body",JSONObject().put("selfieBase64","old-proof"))
   db!!.localCommit(blockedScope,key,JSONObject().put("attendance",JSONObject().put("id",77).put("syncState","pending")),oldAttendance)
   val oldRegular=JSONObject().put("id",UUID.randomUUID().toString()).put("route","MobileVisits/start").put("localId",88).put("recordKey",key).put("body",JSONObject().put("kind","REGULAR").put("photoBase64","regular-proof"))
   db!!.localCommit(blockedScope,key,JSONObject().put("visits",org.json.JSONArray().put(JSONObject().put("id",88).put("kind","Regular"))),oldRegular)
   check(!LocalWorkspaceSync.drain(targetContext,db,force=true)){"Server-only legacy records must not be uploaded by background sync"}
   check(db!!.localSyncState(blockedScope).getInt("blocked")==2){"Both old records must be retained for review before any HTTP call"}
   check(db!!.localResult(blockedScope,oldAttendance.getString("id"))==null){"No attendance receipt may be invented"}
   db!!.close();db=TrackingStore(targetContext,name,alias)
   check(db!!.localSyncState(blockedScope).getInt("blocked")==2){"Server-only legacy review state must survive SQLite reopen"}
   db!!.unblockOutbox(blockedScope)
   check(db!!.localNext(blockedScope)!!.getJSONObject("body").getString("selfieBase64")=="old-proof"){"Legacy evidence must not be deleted"}
   stage="Visit checkout acknowledgement and reopen"
   // A finish receipt must heal even a stale OPEN SQLite projection and survive restart.
   val finishServer=java.net.ServerSocket(0);finishServer.soTimeout=10000
   val finishBase="http://127.0.0.1:${finishServer.localPort}/api";val visitScope=finishBase+"|"+user
   db!!.localWrite("system","activeAuth",JSONObject().put("scope",visitScope).put("baseUrl",finishBase).put("userId",user).put("deviceId","qa-device").put("token","qa-not-a-real-token"))
   val visitKey="day:2026-11-24";val finishId=UUID.randomUUID().toString()
   val closedAt="2026-11-24T07:50:57Z"
   val staleVisit=JSONObject().put("id",437).put("shopName","s b marketing").put("checkOutUtc",JSONObject.NULL)
   val finishOp=JSONObject().put("id",finishId).put("route","MobileVisits/finish").put("localId",437).put("recordKey",visitKey)
       .put("body",JSONObject().put("id",437).put("requestId",finishId).put("capturedAtUtc",closedAt).put("departureSelfieBase64","pending-departure-proof"))
   db!!.localCommit(visitScope,visitKey,JSONObject().put("visits",org.json.JSONArray().put(staleVisit)),finishOp)
   var wrongReceiptRejected=false
   try { db!!.localAck(visitScope,finishOp,JSONObject().put("id",999).put("checkOutUtc",closedAt)) }
   catch(_:IllegalStateException){wrongReceiptRejected=true}
   check(wrongReceiptRejected && db!!.localNext(visitScope)!!.getJSONObject("body").getString("departureSelfieBase64")=="pending-departure-proof") {"Mismatched checkout receipt must retain departure photo"}
   val finishFailure=java.util.concurrent.atomic.AtomicReference<Throwable?>(null)
   val finishReceiver=Thread {
    try { finishServer.accept().use{socket->
     socket.soTimeout=10000;val input=socket.getInputStream().bufferedReader();var length=0
     while(true){val line=input.readLine()?:break;if(line.isEmpty())break;if(line.startsWith("Content-Length:",true))length=line.substringAfter(':').trim().toInt()}
     val chars=CharArray(length);var count=0;while(count<length){val got=input.read(chars,count,length-count);check(got>0);count+=got}
     val body=JSONObject(String(chars))
     check(body.getString("capturedAtUtc")==closedAt){"Offline checkout upload must retain original capture time, not sync time"}
     check(body.getString("departureSelfieBase64")=="pending-departure-proof"){"Departure photo must survive until HTTP acknowledgement"}
     val bytes=JSONObject().put("success",true).put("data",JSONObject().put("id",437).put("checkOutUtc",closedAt)).toString().toByteArray()
     socket.getOutputStream().write(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n").toByteArray()+bytes)
    }}catch(error:Throwable){finishFailure.set(error)}finally{finishServer.close()}
   };finishReceiver.start()
   val finishSynced=LocalWorkspaceSync.drain(targetContext,db,force=true)
   finishReceiver.join(12000);finishFailure.get()?.let{throw it}
   check(finishSynced){"Checkout HTTP acknowledgement must drain its exact outbox item"}
   db!!.close();db=TrackingStore(targetContext,name,alias)
   check(db!!.localRead(visitScope,visitKey)!!.getJSONArray("visits").getJSONObject(0).getString("checkOutUtc")==closedAt){"Server checkout must survive SQLite reopen and cannot remain overstay-open"}
   check(db!!.localSyncState(visitScope).getInt("pending")==0){"Verified checkout must acknowledge exactly its own queued operation"}
   // Hardware-only GPS acquisition: does not create attendance or send coordinates to any API.
   try {
    val lm=targetContext.getSystemService(android.content.Context.LOCATION_SERVICE) as android.location.LocationManager
    val fixRef=java.util.concurrent.atomic.AtomicReference<android.location.Location?>(null)
    val latch=java.util.concurrent.CountDownLatch(1)
    val cancellation=android.os.CancellationSignal()
    val gpsExecutor=java.util.concurrent.Executors.newSingleThreadExecutor()
    val started=android.os.SystemClock.elapsedRealtime()
    try {
     lm.getCurrentLocation(android.location.LocationManager.GPS_PROVIDER,cancellation,gpsExecutor){fix->fixRef.set(fix);latch.countDown()}
     val completed=latch.await(25,java.util.concurrent.TimeUnit.SECONDS)
     val fix=fixRef.get()
     if(completed && fix!=null) {
      val age=System.currentTimeMillis()-fix.time
      val mocked=if(android.os.Build.VERSION.SDK_INT>=31)fix.isMock else fix.isFromMockProvider
      val accepted=age in -15000L..180000L && fix.accuracy>0 && fix.accuracy<=50 && !mocked
      result.putString("hardwareGps",(if(accepted)"PASS"else"QUALITY_NOT_MET")+": real GPS callback; accuracyMeters="+fix.accuracy+"; ageMillis="+age+"; mocked="+mocked+"; waitMillis="+(android.os.SystemClock.elapsedRealtime()-started)+"; coordinates withheld")
     } else result.putString("hardwareGps","BLOCKED: no GPS fix within 25 seconds; no coordinates fabricated")
    } finally {cancellation.cancel();gpsExecutor.shutdownNow()}
   } catch(error:Exception){result.putString("hardwareGps","BLOCKED: "+error.javaClass.simpleName)}
   result.putString("stream","PASS: original offline checkout time/photo preserved over native HTTP, stale-open visit healed by checkout receipt after SQLite restart, wrong-visit receipt/photo retention, invalid-receipt outbox/body/attendance retention after file-backed SQLite reopen (id=0,-1), encrypted durable queue, restart retention, capture ordering, duplicate-safe acknowledgements, user isolation, unbounded pending retention, atomic activity/outbox, rejected item retention, dependency ID remapping, failed HTTP retention, successful native HTTP acknowledgement, server-only attendance/regular outbox blocked without HTTP, legacy evidence/review state retained after restart.")
  }catch(error:Throwable){resultCode=0;result.putString("stream","FAIL at "+stage+": "+error.javaClass.simpleName+": "+error.message+"\n"+error.stackTrace.take(5).joinToString("\n"))}
  finally{try{db?.close();targetContext.deleteDatabase(name);targetContext.getSharedPreferences(name+".state",0).edit().clear().commit();KeyStore.getInstance("AndroidKeyStore").apply{load(null);deleteEntry(alias)}}catch(_:Exception){resultCode=0;result.putString("stream","FAIL: isolated test cleanup failed")}}
  finish(resultCode,result)
 }
}
