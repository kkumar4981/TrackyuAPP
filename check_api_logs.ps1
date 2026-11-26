$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User Id=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "--- ApiRequestLogs for OU005 today ---"
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT TOP 30 OccurredAtUtc, HttpMethod, Route, UserId, StatusCode, DurationMs, ErrorCode FROM ApiRequestLogs WHERE UserId = 'OU005' OR OccurredAtUtc >= '2026-11-12 07:20:00' ORDER BY OccurredAtUtc DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "TimeUtc: $($r['OccurredAtUtc']) | Method: $($r['HttpMethod']) | Route: $($r['Route']) | User: $($r['UserId']) | Status: $($r['StatusCode']) | Err: $($r['ErrorCode'])"
}
$r.Close()

$conn.Close()
