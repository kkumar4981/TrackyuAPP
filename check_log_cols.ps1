$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User Id=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "--- ApiRequestLogs Columns ---"
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='ApiRequestLogs'"
$r = $cmd.ExecuteReader()
$cols = @()
while($r.Read()) { $cols += $r[0] }
$r.Close()
Write-Host ($cols -join ", ")

$conn.Close()
