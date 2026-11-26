$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User Id=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "--- Samples for OU005 right now ---"
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT COUNT(*) FROM WorkforceLocationSamples WHERE UserId = 'OU005'"
$r = $cmd.ExecuteScalar()
Write-Host "Samples Count: $r"

Write-Host "`n--- Health for OU005 right now ---"
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

Write-Host "`n--- Recent ApiRequestLogs for OU005 in last 5 minutes ---"
$cmd.CommandText = "SELECT TOP 10 OccurredAtUtc, Route, StatusCode, DurationMs FROM ApiRequestLogs WHERE UserId = 'OU005' ORDER BY OccurredAtUtc DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "Time: $($r['OccurredAtUtc']) | Route: $($r['Route']) | Status: $($r['StatusCode'])"
}
$r.Close()

$conn.Close()
