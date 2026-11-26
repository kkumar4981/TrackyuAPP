$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User Id=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "--- Salesman tracking policy columns for OU005 ---"
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT sm_user_id, Sm_name, TYPE, TIME, DETIME, IsLocationUpdate, ACTIVE, SM_LEVEL FROM Salesman WHERE sm_user_id IN ('OU005', 'OU003', 'AR077')"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "User: $($r['sm_user_id']) | Name: $($r['Sm_name']) | Type: $($r['TYPE']) | Time: $($r['TIME']) | DeTime: $($r['DETIME']) | IsLocUpd: $($r['IsLocationUpdate'])"
}
$r.Close()

Write-Host "`n--- SMTRACK records for OU005 yesterday (11/11/2026) ---"
$cmd.CommandText = "SELECT TOP 10 Date_time, time, Xloc, Yloc, battary, DateInserted FROM SMTRACK WHERE SM_id = 'OU005' AND (Date_time LIKE '%11/11%' OR DateInserted >= '2026-11-11') ORDER BY DateInserted DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "Time: $($r['time']) | Lat: $($r['Xloc']) | Lon: $($r['Yloc']) | Battery: $($r['battary']) | DateInserted: $($r['DateInserted'])"
}
$r.Close()

Write-Host "`n--- WorkforceTrackingPolicy ---"
$cmd.CommandText = "SELECT * FROM WorkforceTrackingPolicy"
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
