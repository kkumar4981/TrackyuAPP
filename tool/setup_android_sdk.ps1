[CmdletBinding()]
param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$workspace=Split-Path (Split-Path $PSScriptRoot)
$sdk=Join-Path $workspace '.tools/android-sdk'
$flutter=Join-Path $workspace '.tools/flutter/bin/flutter.bat'
$jdk='C:\Program Files\Android\openjdk\jdk-21.0.8'
$sdkManager=Join-Path $sdk 'cmdline-tools/latest/bin/sdkmanager.bat'
if(!(Test-Path (Join-Path $jdk 'bin/java.exe'))){throw 'Java 21 is not available at the configured JDK path. Update this script and .vscode/settings.json for your JDK.'}
if($CheckOnly){
 Write-Output ('Java 21 available: '+(Test-Path (Join-Path $jdk 'bin/java.exe')))
 Write-Output ('Android command-line tools installed: '+(Test-Path $sdkManager))
 Write-Output ('Android platform 36 installed: '+(Test-Path (Join-Path $sdk 'platforms/android-36/android.jar')))
 return
}
$env:JAVA_HOME=$jdk
$env:ANDROID_HOME=$sdk
$env:ANDROID_SDK_ROOT=$sdk
$env:PATH=(Join-Path $jdk 'bin')+';'+$env:PATH
if(!(Test-Path $sdkManager)) {
 Write-Output 'Android SDK tools are provided by Google under the Android SDK License Agreement.'
 Write-Output 'Read the agreement at https://developer.android.com/studio#terms-and-conditions'
 $answer=Read-Host 'If you accept the agreement and want to download/install the SDK, type ACCEPT (anything else cancels)'
 if($answer -cne 'ACCEPT'){throw 'SDK installation cancelled. No license was accepted automatically.'}
 $downloads=Join-Path $workspace '.tools/downloads'
 $stage=Join-Path $downloads 'android-commandlinetools-15859902'
 $zip=Join-Path $downloads 'commandlinetools-win-15859902_latest.zip'
 New-Item -ItemType Directory -Force $downloads|Out-Null
 if(!(Test-Path $zip)) {
  $ProgressPreference='SilentlyContinue'
  Invoke-WebRequest 'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip' -OutFile $zip -UseBasicParsing
 }
 $checksum=(Get-FileHash $zip -Algorithm SHA256).Hash
 if($checksum -ne '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a') {
  throw 'The Android tools archive checksum does not match the official download. Review/remove the downloaded ZIP and retry.'
 }
 Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
 $latest=Join-Path $sdk 'cmdline-tools/latest'
 New-Item -ItemType Directory -Force $latest|Out-Null
 Get-ChildItem (Join-Path $stage 'cmdline-tools') -Force|Copy-Item -Destination $latest -Recurse -Force
}
Write-Output 'Review the following SDK package licenses and answer their prompts yourself.'
& $sdkManager "--sdk_root=$sdk" --licenses
if($LASTEXITCODE -ne 0){throw 'SDK license review did not finish. Resolve the displayed issue and run this task again.'}
# Keep this in sync with android/app/build.gradle.kts and the workspace Flutter SDK.
& $sdkManager "--sdk_root=$sdk" 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358' 'cmake;3.22.1'
if($LASTEXITCODE -ne 0){throw 'Android SDK packages could not be installed. Check the terminal output and retry.'}
& $flutter doctor -v
Write-Output 'Android SDK setup finished. Reload VS Code, connect/authorize your USB phone, select it, then run Trackyu Android (USB) with F5.'
