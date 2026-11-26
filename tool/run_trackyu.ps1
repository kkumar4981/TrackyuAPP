param(
 [string]$ApiUrl='http://localhost:5199/api',
 [string]$Device='web-server',
 [int]$Port=8085
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$flutter=Get-Command flutter -ErrorAction SilentlyContinue
$binary=if($flutter){$flutter.Source}else{Join-Path (Split-Path $root) '.tools/flutter/bin/flutter.bat'}
if(!(Test-Path $binary)){throw 'Install Flutter or use the workspace .tools/flutter SDK.'}
Set-Location $root
$arguments=@('run','-d',$Device,('--dart-define=API_BASE_URL='+$ApiUrl))
if($ApiUrl.StartsWith('http://')){$arguments+='--dart-define=ALLOW_LOCAL_HTTP=true'}
if($Device -eq 'web-server'){$arguments+=@('--web-hostname','127.0.0.1','--web-port',"$Port")}
& $binary @arguments
exit $LASTEXITCODE
