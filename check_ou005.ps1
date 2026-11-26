$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User ID=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "=== User Info for OU005 ==="
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT Sm_id, Sm_name, sm_user_id, ACTIVE, EMP_CODE, TYPE, TIME FROM Salesman WHERE sm_user_id = 'OU005'"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "Id: $($r['Sm_id']) | Name: $($r['Sm_name']) | UserId: $($r['sm_user_id']) | Active: $($r['ACTIVE']) | Type: $($r['TYPE'])"
}
$r.Close()

Write-Host "`n=== Device Bindings for OU005 ==="
$cmd.CommandText = "SELECT * FROM WorkforceDeviceBindings WHERE UserId = 'OU005'"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "BindingId: $($r['BindingId']) | DeviceId: $($r['DeviceId']) | Status: $($r['Status']) | BoundAtUtc: $($r['BoundAtUtc']) | LastSeenAtUtc: $($r['LastSeenAtUtc'])"
}
$r.Close()

Write-Host "`n=== Attendance for OU005 Today ==="
$cmd.CommandText = "SELECT TOP 5 * FROM Attendence WHERE SM_ID = 'OU005' ORDER BY DateInserted DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "Att_Date: $($r['Att_Date']) | Att_time: $($r['Att_time']) | XLOC: $($r['XLOC']) | YLOC: $($r['YLOC']) | DateInserted: $($r['DateInserted'])"
}
$r.Close()

Write-Host "`n=== Location Samples for OU005 Today ==="
$cmd.CommandText = "SELECT COUNT(*) as cnt, MIN(CapturedAtUtc) as min_utc, MAX(CapturedAtUtc) as max_utc FROM WorkforceLocationSamples WHERE UserId = 'OU005' AND CapturedAtUtc >= '2026-11-12 00:00:00'"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "WorkforceLocationSamples Count: $($r['cnt']) | MinUtc: $($r['min_utc']) | MaxUtc: $($r['max_utc'])"
}
$r.Close()

Write-Host "`n=== SMTRACK for OU005 Today ==="
$cmd.CommandText = "SELECT COUNT(*) as cnt, MIN(DateInserted) as min_ins, MAX(DateInserted) as max_ins FROM SMTRACK WHERE SM_id = 'OU005' AND DateInserted >= '2026-11-12 00:00:00'"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "SMTRACK Count: $($r['cnt']) | MinIns: $($r['min_ins']) | MaxIns: $($r['max_ins'])"
}
$r.Close()

Write-Host "`n=== Mobile Diagnostic Events for OU005 Today ==="
$cmd.CommandText = "SELECT TOP 10 EventType, EventMessage, CreatedAtUtc FROM MobileDiagnosticEvents WHERE UserId = 'OU005' ORDER BY CreatedAtUtc DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "Event: $($r['EventType']) | Msg: $($r['EventMessage']) | Time: $($r['CreatedAtUtc'])"
}
$r.Close()

$conn.Close()
