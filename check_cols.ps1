$connStr = "Server=103.39.133.170,50001;Database=Trackyu;User ID=trackyu;Password=server#123456;TrustServerCertificate=True;MultipleActiveResultSets=True"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

foreach($tbl in @('Salesman', 'Attendence', 'WorkforceAttendance', 'WorkforceLocationSamples', 'SMTRACK')) {
    Write-Host "`n--- $tbl Columns ---"
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='$tbl'"
    $r = $cmd.ExecuteReader()
    $cols = @()
    while($r.Read()) {
        $cols += "$($r[0]) ($($r[1]))"
    }
    $r.Close()
    Write-Host ($cols -join ", ")
}

$conn.Close()
