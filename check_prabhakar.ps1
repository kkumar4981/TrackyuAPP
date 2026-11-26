$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User ID=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

Write-Host "=== Salesman Query for Prabhakar & Krishna ==="
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT Sm_id, Sm_name, sm_user_id, ACTIVE, EMP_CODE FROM Salesman WHERE Sm_name LIKE '%Prabhakar%' OR Sm_name LIKE '%Krishna%' OR sm_user_id IN ('OU003', 'AR077', 'SM456')"
$r = $cmd.ExecuteReader()
$users = @()
while($r.Read()) {
    Write-Host "Id: $($r['Sm_id']) | Name: $($r['Sm_name']) | UserId: $($r['sm_user_id']) | Active: $($r['ACTIVE']) | EmpCode: $($r['EMP_CODE'])"
    $users += $r['sm_user_id']
}
$r.Close()

Write-Host "`n=== Attendence (Legacy) Today ==="
$cmd.CommandText = "SELECT TOP 10 SM_ID, Att_Date, Att_time, SIGNOFF, DateInserted FROM Attendence WHERE Att_Date >= '11/11/2026' OR Att_Date >= '2026-11-11' OR Att_Date1 >= '2026-11-11' ORDER BY DateInserted DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "User: $($r['SM_ID']) | Date: $($r['Att_Date']) | Time: $($r['Att_time']) | Signoff: $($r['SIGNOFF']) | Inserted: $($r['DateInserted'])"
}
$r.Close()

Write-Host "`n=== WorkforceAttendance Today ==="
$cmd.CommandText = "SELECT TOP 10 Id, UserId, WorkDate, PunchInUtc, PunchOutUtc FROM WorkforceAttendance WHERE WorkDate >= '2026-11-11' ORDER BY Id DESC"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "Id: $($r['Id']) | UserId: $($r['UserId']) | WorkDate: $($r['WorkDate']) | PunchInUtc: $($r['PunchInUtc']) | PunchOutUtc: $($r['PunchOutUtc'])"
}
$r.Close()

Write-Host "`n=== Location Samples Count Today ==="
$cmd.CommandText = "SELECT UserId, COUNT(*) as cnt, MIN(CapturedAtUtc) as min_utc, MAX(CapturedAtUtc) as max_utc FROM WorkforceLocationSamples WHERE CapturedAtUtc >= '2026-11-12 00:00:00' GROUP BY UserId"
$r = $cmd.ExecuteReader()
while($r.Read()) {
    Write-Host "UserId: $($r['UserId']) | Count: $($r['cnt']) | MinUtc: $($r['min_utc']) | MaxUtc: $($r['max_utc'])"
}
$r.Close()

$conn.Close()
