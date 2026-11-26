$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User ID=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "--- WorkforceTrackingHealth for OU005 ---"
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT * FROM WorkforceTrackingHealth WHERE UserId = 'OU005'"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    $row = @()
    for($i=0; $i -lt $r.FieldCount; $i++) {
        $row += "$($r.GetName($i))=$($r.GetValue($i))"
    }
    Write-Host ($row -join " | ")
}
$r.Close()

Write-Host "`n--- WorkforceUserAppVersions columns ---"
$cmd.CommandText = "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='WorkforceUserAppVersions'"
$r = $cmd.ExecuteReader()
$cols = @()
while($r.Read()) { $cols += $r[0] }
$r.Close()
Write-Host ($cols -join ", ")

Write-Host "`n--- WorkforceUserAppVersions for OU005 ---"
$cmd.CommandText = "SELECT * FROM WorkforceUserAppVersions WHERE UserId = 'OU005'"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    $row = @()
    for($i=0; $i -lt $r.FieldCount; $i++) {
        $row += "$($r.GetName($i))=$($r.GetValue($i))"
    }
    Write-Host ($row -join " | ")
}
$r.Close()

Write-Host "`n--- WorkforceMobileLogins for OU005 ---"
$cmd.CommandText = "SELECT TOP 5 * FROM WorkforceMobileLogins WHERE UserId = 'OU005' ORDER BY 1 DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    $row = @()
    for($i=0; $i -lt $r.FieldCount; $i++) {
        $row += "$($r.GetName($i))=$($r.GetValue($i))"
    }
    Write-Host ($row -join " | ")
}
$r.Close()

$conn.Close()
