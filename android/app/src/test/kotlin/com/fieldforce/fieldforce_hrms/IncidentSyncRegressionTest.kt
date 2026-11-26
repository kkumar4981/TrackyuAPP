package com.fieldforce.fieldforce_hrms

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.net.ServerSocket
import kotlin.concurrent.thread

class IncidentSyncRegressionTest {
    @Test fun attendanceAndRegularVisitsCannotUseBackgroundOutbox() {
        for(route in listOf("FieldAttendance/punch-in","FieldAttendance/punch-out","OfficeAttendance/punch-in","OfficeAttendance/punch-out")) {
            assertTrue(LocalWorkspaceSync.requiresDirectServer(JSONObject().put("route",route)))
        }
        for(kind in listOf("Regular","REGULAR","regular")) {
            assertTrue(LocalWorkspaceSync.requiresDirectServer(JSONObject().put("route","MobileVisits/start").put("body",JSONObject().put("kind",kind))))
        }
        assertTrue(LocalWorkspaceSync.requiresDirectServer(JSONObject().put("route","MobileVisits/finish").put("localId",70).put("body",JSONObject()),
            org.json.JSONArray().put(JSONObject().put("id",70).put("kind","Regular"))))
        assertFalse(LocalWorkspaceSync.requiresDirectServer(JSONObject().put("route","MobileVisits/start").put("body",JSONObject().put("kind","Open"))))
        assertFalse(LocalWorkspaceSync.requiresDirectServer(JSONObject().put("route","MobileVisits/finish").put("localId",70).put("body",JSONObject().put("kind","Open")),
            org.json.JSONArray().put(JSONObject().put("id",70).put("kind","Open").put("isLegacy",true))))
    }
    @Test fun accessRecoveryUsesAuthenticatedGetWithoutAnOperationBody() {
        ServerSocket(0).use { server ->
            var requestLine=""
            var deviceHeader=""
            var tokenHeader=""
            val worker=thread(isDaemon=true) {
                server.accept().use { socket ->
                    val reader=socket.getInputStream().bufferedReader()
                    requestLine=reader.readLine()
                    while(true) {
                        val line=reader.readLine() ?: break
                        if(line.isEmpty())break
                        if(line.startsWith("X-Device-ID:",true))deviceHeader=line.substringAfter(':').trim()
                        if(line.startsWith("Authorization:",true))tokenHeader=line.substringAfter(':').trim()
                    }
                    val json="""{"success":true,"data":{"userId":"A"}}"""
                    socket.getOutputStream().write(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${json.toByteArray().size}\r\nConnection: close\r\n\r\n"+json).toByteArray())
                }
            }
            val auth=JSONObject().put("baseUrl","http://127.0.0.1:${server.localPort}/api").put("token","original-token").put("deviceId","original-phone")
            assertTrue(LocalWorkspaceSync.request(auth,"Employee/my-profile",JSONObject(),verifyAccess=true).getBoolean("success"))
            worker.join(3000)
            assertEquals("GET /api/Employee/my-profile HTTP/1.1",requestLine)
            assertEquals("original-phone",deviceHeader)
            assertEquals("Bearer original-token",tokenHeader)
        }
    }
    @Test fun conflictsBackOffAndSurviveSerialization() {
        var state:JSONObject?=null
        var now=1000L
        for(i in 1..12) {
            state=LocalWorkspaceSync.retryState(state,"checkout-op",now)
            state=JSONObject(state.toString()) // same serialized state used by encrypted local storage
            val wait=state.getLong("nextAt")-now
            assertTrue(wait in 5000L..300000L)
            if(i>=7)assertEquals(300000L,wait)
            assertFalse(LocalWorkspaceSync.retryReady(state,now))
            now=state.getLong("nextAt")
            assertTrue(LocalWorkspaceSync.retryReady(state,now))
        }
        assertEquals(1,LocalWorkspaceSync.retryState(state,"next-op",now).getInt("attempts"))
    }

    @Test fun oldPunchOutCannotStopNewDutyOrOtherEmployee() {
        val auth=JSONObject().put("userId","A").put("baseUrl","https://example.test/api")
        val op=JSONObject().put("route","FieldAttendance/punch-out").put("localId",9001)
        val receipt=JSONObject().put("id",101)
        val cfg=JSONObject().put("userId","A").put("baseUrl","https://example.test/api").put("mode","Field").put("attendanceId",102)
        assertFalse(LocalWorkspaceSync.matchesClosedAttendance(cfg,auth,op,receipt))
        cfg.put("attendanceId",101)
        assertTrue(LocalWorkspaceSync.matchesClosedAttendance(cfg,auth,op,receipt))
        cfg.put("userId","B")
        assertFalse(LocalWorkspaceSync.matchesClosedAttendance(cfg,auth,op,receipt))
        cfg.put("userId","A").put("mode","Office")
        assertFalse(LocalWorkspaceSync.matchesClosedAttendance(cfg,auth,op,receipt))
    }

    @Test fun locallyRemappedDutyMatchesOnlyItsOwnReceipt() {
        val auth=JSONObject().put("userId","A").put("baseUrl","https://example.test/api")
        val cfg=JSONObject(auth.toString()).put("mode","Field").put("attendanceId",9001)
        val op=JSONObject().put("route","FieldAttendance/punch-out").put("localId",9001)
        assertTrue(LocalWorkspaceSync.matchesClosedAttendance(cfg,auth,op,JSONObject().put("id",101)))
        assertFalse(LocalWorkspaceSync.matchesClosedAttendance(cfg,auth,op,JSONObject().put("id",0)))
    }

    @Test fun reauthenticationRequiresChangedCredentials() {
        val old=JSONObject().put("scope","api|A").put("deviceId","phone").put("token","expired")
        assertTrue(LocalWorkspaceSync.sameCredentials(old,JSONObject(old.toString())))
        assertFalse(LocalWorkspaceSync.sameCredentials(old,JSONObject(old.toString()).put("token","fresh")))
        assertFalse(LocalWorkspaceSync.sameCredentials(old,JSONObject(old.toString()).put("scope","api|B")))
    }

    @Test fun actualHttpRequestRetainsErrorCodeAndStableOperationId() {
        ServerSocket(0).use { server ->
            var operationHeader=""
            val worker=thread(isDaemon=true) {
                server.accept().use { socket ->
                    val reader=socket.getInputStream().bufferedReader()
                    while(true) {
                        val line=reader.readLine() ?: break
                        if(line.isEmpty())break
                        if(line.startsWith("X-Operation-ID:",true))operationHeader=line.substringAfter(':').trim()
                    }
                    val json="""{"success":false,"errorCode":"UNAUTHORIZED","message":"Sign in"}"""
                    socket.getOutputStream().write(("HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\nContent-Length: ${json.toByteArray().size}\r\nConnection: close\r\n\r\n"+json).toByteArray())
                }
            }
            val auth=JSONObject().put("baseUrl","http://127.0.0.1:${server.localPort}/api").put("token","qa-only").put("deviceId","qa-only")
            try {
                LocalWorkspaceSync.request(auth,"MobileVisits/start",JSONObject(),"same-operation")
                fail("Expected unauthorized response")
            } catch(e:LocalWorkspaceSync.SyncError) {
                assertEquals(401,e.status)
                assertEquals("UNAUTHORIZED",e.errorCode)
            }
            worker.join(3000)
            assertEquals("same-operation",operationHeader)
        }
    }
}
