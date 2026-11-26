$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User Id=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "--- Last 10 uploads for OU005 ---"
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT TOP 10 OccurredAtUtc, StatusCode, RequestBody, ResponseBody FROM ApiRequestLogs WHERE UserId = 'OU005' AND Route = 'api/DutyTracking/upload' ORDER BY OccurredAtUtc DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "Time: $($r['OccurredAtUtc']) | Status: $($r['StatusCode']) | Resp: $($r['ResponseBody'])"
    Write-Host "Req: $($r['RequestBody'])"
}
$r.Close()

$conn.Close()
