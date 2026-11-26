[CmdletBinding()]
param([string]$DeviceId=$env:ANDROID_SERIAL,[switch]$CheckOnly)
$ErrorActionPreference='Stop'
$workspace=Split-Path (Split-Path $PSScriptRoot)
$apiRoot=Join-Path $workspace 'TrackyuAPI'
$sdk=Join-Path $workspace '.tools/android-sdk'
$adb=Join-Path $sdk 'platform-tools/adb.exe'
if(!(Test-Path $adb)) {
 throw 'Android SDK is missing. In VS Code run: Terminal > Run Task > Trackyu: Android SDK setup (one time).'
}
$env:ANDROID_HOME=$sdk
$env:ANDROID_SDK_ROOT=$sdk
$jdk='C:\Program Files\Android\openjdk\jdk-21.0.8'
if(Test-Path (Join-Path $jdk 'bin/java.exe')){$env:JAVA_HOME=$jdk}
$lines=& $adb devices
if($LASTEXITCODE -ne 0){throw 'Could not query Android devices.'}
$ready=@($lines|Where-Object {$_ -match '^\S+\s+device\s*$'}|ForEach-Object {($_ -split '\s+')[0]})
if($DeviceId) {
 if($DeviceId -notin $ready){throw 'The selected Android device is not ready. Check its USB cable and authorize USB debugging on the phone.'}
} elseif($ready.Count -eq 1) {$DeviceId=$ready[0]}
elseif($ready.Count -gt 1){throw 'Multiple Android devices are connected. Disconnect the extra devices or set ANDROID_SERIAL to the phone selected in VS Code.'}
else {throw 'No authorized Android device found. Connect your phone, turn on USB debugging and accept Allow USB debugging on the phone. Check the USB driver/cable if it is still missing.'}
if(!(Test-Path (Join-Path $sdk 'platforms/android-36/android.jar'))){throw 'Android SDK platform 36 is missing. Run the Android SDK setup task.'}
function Test-TrackyuApi {
 try {$r=Invoke-WebRequest 'http://localhost:5199/api/Misc/health' -UseBasicParsing -TimeoutSec 2;return $r.StatusCode -eq 200}catch{return $false}
}
if($CheckOnly) {
 Write-Output ('Android device ready: '+$DeviceId)
 Write-Output ('API reachable: '+(Test-TrackyuApi))
 return
}
if(!(Test-TrackyuApi)) {
 $dotnet=Get-Command dotnet -ErrorAction Stop
 $logs=Join-Path $apiRoot '.logs'
 New-Item -ItemType Directory -Force $logs|Out-Null
 # Start only the local development host. Do not alter database settings or stop existing hosts.
 $process=Start-Process -FilePath $dotnet.Source -ArgumentList @('run','--no-launch-profile','--urls','http://localhost:5199') -WorkingDirectory $apiRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs 'android-api.stdout.log') -RedirectStandardError (Join-Path $logs 'android-api.stderr.log') -PassThru
 $readyApi=$false
 for($attempt=0;$attempt -lt 40;$attempt++) {
  if(Test-TrackyuApi){$readyApi=$true;break}
  if($process.HasExited){break}
  Start-Sleep -Milliseconds 500
 }
 if(!$readyApi){throw 'The local API did not start. Check TrackyuAPI/.logs/android-api.stderr.log and its database configuration. Start the API on port 5199, then retry F5.'}
}
& $adb -s $DeviceId reverse tcp:5199 tcp:5199
if($LASTEXITCODE -ne 0){throw 'USB API port forwarding failed.'}
Write-Output ('USB ready: '+$DeviceId+' -> Trackyu API http://localhost:5199/api')
Write-Output 'Select this Android phone in the VS Code device selector. F5 will now launch Trackyu with breakpoints and hot reload.'
