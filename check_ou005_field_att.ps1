$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User Id=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "--- WorkforceFieldAttendance for OU005 ---"
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT * FROM WorkforceFieldAttendance WHERE UserId = 'OU005'"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    $row = @()
    for($i=0; $i -lt $r.FieldCount; $i++) {
        $row += "$($r.GetName($i))=$($r.GetValue($i))"
    }
    Write-Host ($row -join " | ")
}
$r.Close()

Write-Host "`n--- WorkforceAttendance for OU005 ---"
$cmd.CommandText = "SELECT * FROM WorkforceAttendance WHERE UserId = 'OU005'"
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
