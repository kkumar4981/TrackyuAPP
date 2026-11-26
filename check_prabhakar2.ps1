$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User ID=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "=== User App Versions ==="
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT UserId, Version, Platform, DeviceModel, LastSeenAtUtc FROM WorkforceUserAppVersions WHERE UserId IN ('OU003', 'AR077', 'SM456')"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "User: $($r['UserId']) | Version: $($r['Version']) | Platform: $($r['Platform']) | Device: $($r['DeviceModel']) | LastSeen: $($r['LastSeenAtUtc'])"
}
$r.Close()

Write-Host "`n=== SMTRACK for AR077 vs OU003 today ==="
$cmd.CommandText = "SELECT SM_id, COUNT(*) as cnt, MIN(Date_time) as min_dt, MAX(Date_time) as max_dt FROM SMTRACK WHERE DateInserted >= '2026-11-12 00:00:00' GROUP BY SM_id"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "SM_id: $($r['SM_id']) | Count: $($r['cnt']) | Min: $($r['min_dt']) | Max: $($r['max_dt'])"
}
$r.Close()

Write-Host "`n=== Sample points for AR077 ==="
$cmd.CommandText = "SELECT TOP 5 CapturedAtUtc, Latitude, Longitude, SpeedMps, Address FROM WorkforceLocationSamples WHERE UserId='AR077' ORDER BY CapturedAtUtc DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "Utc: $($r['CapturedAtUtc']) | Lat: $($r['Latitude']) | Lon: $($r['Longitude']) | Speed: $($r['SpeedMps']) | Addr: $($r['Address'])"
}
$r.Close()

$conn.Close()
