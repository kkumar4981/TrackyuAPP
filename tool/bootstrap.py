"""Generate genuine Flutter platform scaffolds, then apply this project's native config.
Run once with Flutter 3.35+ and Python 3: python tool/bootstrap.py
Never overwrites an existing platform folder. No downloaded/generated SDK code is shipped.
"""
from pathlib import Path
import json, os, plistlib, re, shutil, subprocess, tempfile

root = Path(__file__).resolve().parents[1]
flutter = shutil.which('flutter')
if not flutter:
    raise SystemExit('Install Flutter stable and add flutter to PATH first.')
if any((root / name).exists() for name in ('android', 'ios', 'web')):
    raise SystemExit('Platform folders exist. Back them up/remove them before regenerating; refusing to overwrite.')
with tempfile.TemporaryDirectory(prefix='fieldforce-scaffold-') as temp:
    scaffold = Path(temp) / 'fieldforce_hrms'
    subprocess.run([flutter, 'create', '--no-pub', '--platforms=android,ios,web',
                    '--org', 'com.fieldforce', '--project-name', 'fieldforce_hrms',
                    '--ios-language', 'swift', '--android-language', 'kotlin', str(scaffold)], check=True)
    for name in ('android', 'ios', 'web'):
        shutil.copytree(scaffold / name, root / name)
    if (scaffold / '.metadata').exists():
        shutil.copy2(scaffold / '.metadata', root / '.metadata')

config = root / 'platform_config'
shutil.copy2(config / 'android/AndroidManifest.xml', root / 'android/app/src/main/AndroidManifest.xml')
for native in ('MainActivity.kt','TrackingStore.kt','TrackingRuntime.kt','TrackingChannel.kt','DutyLocationService.kt'):
    shutil.copy2(config / 'android' / native, root / 'android/app/src/main/kotlin/com/fieldforce/fieldforce_hrms' / native)
drawable = root / 'android/app/src/main/res/drawable'
drawable.mkdir(parents=True, exist_ok=True)
shutil.copy2(config / 'android/ic_stat_notification.xml', drawable / 'ic_stat_notification.xml')
gradle = root / 'android/app/build.gradle.kts'
if not gradle.exists():
    raise SystemExit('Expected modern Kotlin Gradle scaffold. Update Flutter stable; apply config manually if needed.')
text = gradle.read_text()
for key, value in [('minSdk', '29'), ('targetSdk', '36'), ('compileSdk', '36')]:
    text, count = re.subn(rf'{key}\s*=\s*[^\n]+', f'{key} = {value}', text)
    if count != 1:
        raise SystemExit(f'Unexpected Gradle template: cannot set {key}; inspect generated project.')
text = text.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true')
text = text.replace('release {', 'release {\n            isShrinkResources = false')
text = text.replace('android {', 'android {\n    buildFeatures { buildConfig = true }')
text += '\ndependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4"); implementation("com.google.android.gms:play-services-location:21.3.0"); implementation("androidx.work:work-runtime-ktx:2.10.0") }\n'
gradle.write_text(text)
root_gradle = root / 'android/build.gradle.kts'
root_gradle.write_text('apply(from = "../platform_config/android/native_dependencies.gradle.kts")\n\n' + root_gradle.read_text())
plist = root / 'ios/Runner/Info.plist'
with plist.open('rb') as f:
    info = plistlib.load(f)
info.update(json.loads((config / 'ios/permissions.json').read_text()))
info['CFBundleDisplayName'] = 'Trackyu'
with plist.open('wb') as f:
    plistlib.dump(info, f, sort_keys=False)
shutil.copy2(config / 'ios/Podfile', root / 'ios/Podfile')
shutil.copy2(config / 'ios/Runner.entitlements', root / 'ios/Runner/Runner.entitlements')
pbx = root / 'ios/Runner.xcodeproj/project.pbxproj'
text = pbx.read_text()
text = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [^;]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 15.0;', text)
text = text.replace('INFOPLIST_FILE = Runner/Info.plist;',
    'INFOPLIST_FILE = Runner/Info.plist;\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;')
pbx.write_text(text)
print('Native scaffolds generated. Review IDs/signing, then run flutter pub get, flutter analyze, flutter test.')
print('iOS: use macOS + Xcode, configure signing and check Background Modes / Keychain Sharing.')

# Restore committed Trackyu launcher artwork after Flutter scaffolding.
shutil.copytree(config / "branding", root, dirs_exist_ok=True)
