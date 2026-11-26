$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User Id=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "--- Any ApiRequestLogs for OU005 today (all routes) ---"
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT DISTINCT Route, StatusCode, COUNT(*) as cnt FROM ApiRequestLogs WHERE UserId = 'OU005' GROUP BY Route, StatusCode"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "Route: $($r['Route']) | Status: $($r['StatusCode']) | Count: $($r['cnt'])"
}
$r.Close()

Write-Host "`n--- Any ApiRequestLogs where ErrorCode is not null for OU005 ---"
$cmd.CommandText = "SELECT TOP 10 OccurredAtUtc, Route, StatusCode, ErrorCode, ResponseBody FROM ApiRequestLogs WHERE UserId = 'OU005' AND StatusCode != 200 ORDER BY OccurredAtUtc DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "Time: $($r['OccurredAtUtc']) | Route: $($r['Route']) | Status: $($r['StatusCode']) | Err: $($r['ErrorCode']) | Body: $($r['ResponseBody'])"
}
$r.Close()

$conn.Close()
