package com.fieldforce.fieldforce_hrms

import io.flutter.plugin.common.StandardMessageCodec
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ChannelCodecTest {
    @Test fun timelineProjectionKeepsEveryFixButRemovesSelfies() {
        val points=org.json.JSONArray()
        repeat(3000){points.put(JSONObject().put("id",it).put("latitude",23).put("longitude",77).put("capturedAtUtc","2026-11-10T04:30:00Z"))}
        val day=JSONObject().put("attendance",JSONObject().put("id",1).put("selfieBase64","secret-photo"))
            .put("report",JSONObject().put("date","2026-11-10").put("userId","QA").put("recordedPoints",points))
        val view=RouteProjection.build(day)
        assertEquals(3000,view.getJSONObject("report").getJSONArray("recordedPoints").length())
        assertFalse(view.getJSONObject("attendance").has("selfieBase64"))
        assertTrue(day.getJSONObject("attendance").has("selfieBase64"))
        assertEquals("2026-11-10",view.getJSONObject("report").getString("date"))
        StandardMessageCodec.INSTANCE.encodeMessage(TrackingRuntime.jsonMap(view))
    }
    @Test fun restoredNestedRouteAndNullsCanCrossFlutterChannel() {
        val source=JSONObject("""{"report":{"route":{"segments":[[{"latitude":23,"longitude":77,"nullable":null}],[]]},"recordedPoints":[],"visits":[{"photos":[null,{"ok":true}]}]}}""")
        val encoded=StandardMessageCodec.INSTANCE.encodeMessage(TrackingRuntime.jsonMap(source))!!
        encoded.flip()
        val decoded=StandardMessageCodec.INSTANCE.decodeMessage(encoded) as Map<*,*>
        val report=decoded["report"] as Map<*,*>
        val route=report["route"] as Map<*,*>
        val segments=route["segments"] as List<*>
        val point=(segments[0] as List<*>)[0] as Map<*,*>
        assertEquals(23,point["latitude"])
        assertNull(point["nullable"])
        assertTrue((segments[1] as List<*>).isEmpty())
        val visit=(report["visits"] as List<*>)[0] as Map<*,*>
        assertNull((visit["photos"] as List<*>)[0])
        assertEquals(true,((visit["photos"] as List<*>)[1] as Map<*,*>)["ok"])
    }
    @Test fun fatalFramesDoNotContainExceptionPayloads() {
        val error=IllegalArgumentException("secret-token GPS latitude password selfie")
        val frames=MobileDiagnostics.frames(error)
        assertTrue(frames.contains("ChannelCodecTest"))
        assertFalse(frames.contains("secret-token"))
        assertFalse(frames.contains("password"))
    }
}
