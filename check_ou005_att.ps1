$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User Id=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "--- Attendence row for OU005 today ---"
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT * FROM Attendence WHERE SM_ID = 'OU005' AND Att_Date = '12/11/2026'"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    $row = @()
    for($i=0; $i -lt $r.FieldCount; $i++) {
        $row += "$($r.GetName($i))=$($r.GetValue($i))"
    }
    Write-Host ($row -join " | ")
}
$r.Close()

Write-Host "`n--- WorkforceAttendance row for OU005 today ---"
$cmd.CommandText = "SELECT * FROM WorkforceAttendance WHERE UserId = 'OU005' AND WorkDate = '2026-11-12'"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    $row = @()
    for($i=0; $i -lt $r.FieldCount; $i++) {
        $row += "$($r.GetName($i))=$($r.GetValue($i))"
    }
    Write-Host ($row -join " | ")
}
$r.Close()

Write-Host "`n--- WorkforceLocationSamples for OU005 any date ---"
$cmd.CommandText = "SELECT TOP 5 * FROM WorkforceLocationSamples WHERE UserId = 'OU005' ORDER BY CapturedAtUtc DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    $row = @()
    for($i=0; $i -lt $r.FieldCount; $i++) {
        $row += "$($r.GetName($i))=$($r.GetValue($i))"
    }
    Write-Host ($row -join " | ")
}
$r.Close()

Write-Host "`n--- SMTRACK for OU005 today details ---"
$cmd.CommandText = "SELECT TOP 10 * FROM SMTRACK WHERE SM_id = 'OU005' AND DateInserted >= '2026-11-12 00:00:00' ORDER BY DateInserted DESC"
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
