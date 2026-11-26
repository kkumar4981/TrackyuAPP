package com.fieldforce.fieldforce_hrms
import org.json.JSONArray
import org.json.JSONObject
/** Media-free timeline projection. Map sampling belongs exclusively in the renderer. */
object RouteProjection {
 const val MAX_POINTS=1200
 private fun metadata(row:JSONObject):JSONObject {
  val copy=JSONObject()
  for(key in row.keys()){
   val name=key.lowercase();val value=row.get(key)
   if(name.contains("base64")||(value is String&&value.length>1024&&(name.contains("photo")||name.contains("selfie"))))continue
   copy.put(key,value)
  }
  if(row.optString("departureSelfieBase64").isNotBlank())copy.put("hasDepartureSelfie",true)
  if(row.optString("photoBase64").isNotBlank())copy.put("hasArrivalSelfie",true)
  return copy
 }
 private fun rows(source:JSONArray?):JSONArray {
  val result=JSONArray();if(source!=null)for(i in 0 until source.length())source.optJSONObject(i)?.let{result.put(metadata(it))};return result
 }
 fun build(day:JSONObject):JSONObject {
  val view=JSONObject()
  day.optJSONObject("attendance")?.let{view.put("attendance",metadata(it))}
  if(day.has("attendance")&&day.isNull("attendance"))view.put("attendance",JSONObject.NULL)
  if(day.has("visits"))view.put("visits",rows(day.optJSONArray("visits")))
  day.optJSONObject("report")?.let{report->
   val copy=JSONObject()
   for(key in listOf("userId","date","timeZoneId","truncated","recordedSampleCount"))if(report.has(key))copy.put(key,report.get(key))
   for(key in listOf("events","visits","attendance","recordedPoints"))if(report.has(key))copy.put(key,rows(report.optJSONArray(key)))
   report.optJSONObject("route")?.let{copy.put("route",it)}
   view.put("report",copy)
  }
  return view
 }
}