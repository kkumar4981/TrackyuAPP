$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User Id=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "--- Active Employees on Web Portal right now ---"
$cmd = $conn.CreateCommand()
$cmd.CommandText = @"
WITH attendance AS (
    SELECT UserId,'Field' Mode,PunchInUtc,PunchOutUtc,InLatitude,InLongitude,InAccuracyMeters FROM dbo.WorkforceFieldAttendance WHERE WorkDate='2026-11-12'
    UNION ALL
    SELECT UserId,'Office' Mode,PunchInUtc,PunchOutUtc,InLatitude,InLongitude,InAccuracyMeters FROM dbo.WorkforceAttendance WHERE WorkDate='2026-11-12'
)
SELECT a.UserId, s.Sm_name, a.PunchInUtc, a.PunchOutUtc,
       gps.CapturedAtUtc as GpsTime, gps.Latitude as GpsLat, gps.Longitude as GpsLon,
       a.InLatitude as PunchLat, a.InLongitude as PunchLon,
       h.Status as HealthStatus, h.LastFixAtUtc as HealthFix
FROM attendance a
JOIN Salesman s ON s.sm_user_id = a.UserId
OUTER APPLY (
    SELECT TOP 1 CapturedAtUtc, Latitude, Longitude FROM WorkforceLocationSamples g
    WHERE g.UserId = a.UserId AND CapturedAtUtc >= '2026-11-12'
    ORDER BY CapturedAtUtc DESC
) gps
OUTER APPLY (
    SELECT TOP 1 Status, LastFixAtUtc FROM WorkforceTrackingHealth h
    WHERE h.UserId = a.UserId
    ORDER BY LastSyncAtUtc DESC
) h
"@
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "User: $($r['UserId']) ($($r['Sm_name'])) | PunchIn: $($r['PunchInUtc']) | PunchOut: $($r['PunchOutUtc']) | GpsTime: $($r['GpsTime']) | HealthFix: $($r['HealthFix']) | Status: $($r['HealthStatus'])"
}
$r.Close()

$conn.Close()
