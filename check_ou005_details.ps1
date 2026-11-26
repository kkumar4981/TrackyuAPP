$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User ID=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "--- WorkforceDeviceBindings Columns ---"
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='WorkforceDeviceBindings'"
$r = $cmd.ExecuteReader()
$cols = @()
while($r.Read()) { $cols += $r[0] }
$r.Close()
Write-Host ($cols -join ", ")

Write-Host "`n--- WorkforceDeviceBindings rows for OU005 ---"
$cmd.CommandText = "SELECT * FROM WorkforceDeviceBindings WHERE UserId = 'OU005'"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    $row = @()
    for($i=0; $i -lt $r.FieldCount; $i++) {
        $row += "$($r.GetName($i))=$($r.GetValue($i))"
    }
    Write-Host ($row -join " | ")
}
$r.Close()

Write-Host "`n--- ApiRequestLogs for OU005 last 2 hours ---"
$cmd.CommandText = "SELECT TOP 15 RequestTimeUtc, Path, StatusCode, UserId, DeviceId, ResponseTimeMs, ErrorMessage FROM ApiRequestLogs WHERE UserId = 'OU005' OR Path LIKE '%tracking%' OR Path LIKE '%location%' ORDER BY RequestTimeUtc DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "Time: $($r['RequestTimeUtc']) | Path: $($r['Path']) | Status: $($r['StatusCode']) | User: $($r['UserId']) | Err: $($r['ErrorMessage'])"
}
$r.Close()

$conn.Close()
