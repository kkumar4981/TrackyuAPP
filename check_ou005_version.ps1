$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User Id=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "--- Last login / requests for OU005 today ---"
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT TOP 5 OccurredAtUtc, Route, StatusCode, RequestBody FROM ApiRequestLogs WHERE UserId = 'OU005' AND Route LIKE '%login%' ORDER BY OccurredAtUtc DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "Time: $($r['OccurredAtUtc']) | Route: $($r['Route']) | Req: $($r['RequestBody'])"
}
$r.Close()

Write-Host "`n--- Check AppVersionPolicies vs OU005 ---"
$cmd.CommandText = "SELECT TOP 5 * FROM AppVersionPolicies WHERE IsDefault=1"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "VersionCode: $($r['VersionCode']) | VersionName: $($r['VersionName']) | Url: $($r['DownloadUrl'])"
}
$r.Close()

$conn.Close()
