$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User Id=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "--- WorkforceTrackingHealth all rows ---"
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT TOP 10 * FROM WorkforceTrackingHealth ORDER BY 1 DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    $row = @()
    for($i=0; $i -lt $r.FieldCount; $i++) {
        $row += "$($r.GetName($i))=$($r.GetValue($i))"
    }
    Write-Host ($row -join " | ")
}
$r.Close()

Write-Host "`n--- MobileDiagnosticEvents recent ---"
$cmd.CommandText = "SELECT TOP 10 * FROM MobileDiagnosticEvents ORDER BY 1 DESC"
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
