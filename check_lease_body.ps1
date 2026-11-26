$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User Id=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "--- ApiRequestLogs RequestBody & ResponseBody for OU005 lease ---"
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT TOP 1 OccurredAtUtc, RequestBody, ResponseBody FROM ApiRequestLogs WHERE UserId = 'OU005' AND Route = 'api/DutyTracking/lease' ORDER BY OccurredAtUtc DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "Occurred: $($r['OccurredAtUtc'])"
    Write-Host "Req: $($r['RequestBody'])"
    Write-Host "Resp: $($r['ResponseBody'])"
}
$r.Close()

$conn.Close()
