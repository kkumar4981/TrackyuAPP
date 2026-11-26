# Trackyu login and attendance — live API integration

The default entry point (`lib/main.dart`) now opens the Trackyu login and attendance flow.
It uses the original JioTracker login illustration/logo, blue colour (#1C6799), welcome
header and slide-to-punch interaction. Android XML layouts were ported to Flutter widgets.
The earlier broad HRMS demo is preserved at `lib/main_demo.dart`; it is not the live app.

## Run

From `fieldforce_hrms`, using the Flutter SDK installed in `../.tools/flutter`:

```powershell
powershell -ExecutionPolicy Bypass -File tool/run_trackyu.ps1
```

This opens a web-server target on http://127.0.0.1:8085, using the local Trackyu API
at http://localhost:5199/api. Open the preview URL in Chrome/Edge. That API process
must be running; the launcher does not start it. For IIS Express explicitly pass
`-ApiUrl https://localhost:44363/api` after starting the API with that profile.
Start/rebuild the current TrackyuAPI project so the new attendance endpoints are available.

For a local API on another address:

```powershell
powershell -ExecutionPolicy Bypass -File tool/run_trackyu.ps1 -ApiUrl http://localhost:5199/api
```

For an Android emulator (after installing Android SDK and creating/starting an emulator):

```powershell
powershell -ExecutionPolicy Bypass -File tool/run_trackyu.ps1 -Device emulator-5554 -ApiUrl http://10.0.2.2:5128/api
```

For a phone use the PC's reachable LAN address or deployed HTTPS host, not localhost.
Bind the API to the appropriate interface and use a certificate trusted by that phone.
HTTP is accepted only in a debug build with ALLOW_LOCAL_HTTP=true; the helper sets this
for a supplied HTTP address. The Android debug manifest permits local cleartext traffic.
Release builds require HTTPS. No certificate-validation bypass is installed.
Web geolocation requires localhost or HTTPS; a plain LAN HTTP web page cannot obtain GPS.
iOS HTTP testing is not configured; use trusted HTTPS and build/sign on macOS.

## Existing employees and office tables

Login uses the existing username/password checked by `VW_SALESMAN`; no sample accounts
or passwords are embedded. The API currently selects one configured TrackingDB.
Legacy company/dbid routing is not implemented, so a company-ID input is not presented
as if it could select a tenant.

`Database/003_Workforce.sql` was applied to the configured local Trackyu database. For
another database apply that additive migration before running this API version:

```powershell
powershell -ExecutionPolicy Bypass -File ../TrackyuAPI/tools/apply_workforce_schema.ps1
```

The local verification used `-LocalUnencryptedTest` only for the test process; committed
connection encryption settings were not modified.

Enabled legacy office assignments are now imported on first office-profile/office-list read.
New/manual office assignments can still be configured in the database or through the admin APIs. Set:

| Table | Required configuration |
|---|---|
| `WorkforceOffices` | Office name, latitude/longitude, radius 100 or 500, local shift start/end, time zone (e.g. Asia/Kolkata), grace (10), GPS accuracy/age limits, checkout geofence flag, enabled flag, UpdatedBy/UpdatedAtUtc |
| `WorkforceMembers` | OfficeId, UserId matching `VW_SALESMAN.sm_user_id`, IsActive=1, IsManager, UpdatedBy/UpdatedAtUtc |

Prefer the `WorkforceOffices/save` and `assign-member` APIs if using the API's policy
history and employee-existence checks. These require an administrator explicitly
configured in `Workforce:Administrators`; no existing user's role was changed.
Direct table changes are possible but do not create policy-history entries automatically.
Office shifts currently start and end on the same local day. HalfDayBoundary may be null
(default halfway through the shift), or set explicitly inside the shift.

With default `Workforce:MirrorLegacyData=true`, a punch also writes legacy Attendence and
SMTRACK in the same transaction. The existing SMTRACK employee-ID column allows only
5 characters. Longer IDs receive LEGACY_SCHEMA_INCOMPATIBLE instead of being truncated.
Use MirrorLegacyData=false for canonical Workforce-only attendance until the legacy
schema/reporting migration is handled. That setting does not update legacy reports.

## API calls used by this first stage

| Method | Route | Purpose |
|---|---|---|
| POST | /api/Auth/login | username / userPassword -> data.token, data.user |
| GET | /api/AttendanceProfile/mine | Server-authoritative Field/Office mode; legacy office import |
| GET | /api/FieldAttendance/state | Own field attendance without office membership |
| POST | /api/FieldAttendance/punch-in | Fresh GPS; no office radius/shift requirement |
| POST | /api/FieldAttendance/punch-out | Own field attendanceId and fresh GPS |
| GET | /api/WorkforceOffices/mine | Assigned offices and policy |
| POST | /api/OfficeAttendance/state | Own open session or selected-office attendance for today |
| POST | /api/OfficeAttendance/punch-in | Fresh GPS + officeId + lateReason when required |
| POST | /api/OfficeAttendance/punch-out | Own attendanceId + fresh GPS + earlyReason when required |

The server selects the employee from the signed JWT. The app never supplies an employee
ID to create attendance. State is reloaded after restart, resume and an ambiguous write
failure. A previous open session takes priority over a different selected office/date.
The app stores its token in FlutterSecureStorage, bound to the API origin; passwords are
not stored. A 401 clears the expired session. No attendance is confirmed offline and no
write is automatically replayed following a timeout.

Radius, GPS freshness/accuracy, late grace and approved leave are enforced on the server.
Late/early reason dialogs appear only when requested by its error code. A client-supplied
location can still be spoofed; the mobile mock-location flag is an additional check.
Punch times shown in the app use the device's local time; the policy names its office zone.

This stage includes login and attendance only. Background route tracking, reminders,
leave screens, files, manager screens and KRA are not wired into this live entry point.
KRA remains pending the user's separate flow details.

## Verification (2026-11-06)

- Flutter 3.47.9 / Dart 3.13.7 installed locally; package lockfile generated.
- Flutter analysis: no issues; web debug build passed.
- 23 Flutter tests passed, including a 390x844 login-to-slide-punch widget test.
- .NET build passed. Existing Pkcs package vulnerability warnings remain.
- 14 live HTTP checks passed against the local database using synthetic Workforce-only
  records with legacy mirroring disabled for the test process. Fixtures were removed;
  no real employee attendance was changed. Evidence: `TrackyuAPI/tools/mobile_attendance_results.json`.
- Valid-credential login was checked with a mocked API contract; invalid credentials
  and JWT-protected attendance were checked against the live API. Actual employee login
  and physical-device GPS still need a run using the user's employee/office setup.
- Browser UI automation host was unavailable; preview HTTP served successfully and the
  mobile layout interaction passed its widget test.
- Android SDK is absent, so APK compilation/device testing has not been performed.
  iOS compilation requires macOS/Xcode.

Commands for repeat checks:

```powershell
../.tools/flutter/bin/flutter.bat analyze
../.tools/flutter/bin/flutter.bat test
```

`validate_mobile_attendance.ps1` is an isolated integration-test script, not a setup
script. It expects a local API process with administrator `wf-mobile-check` and
MirrorLegacyData=false via process-only configuration. Do not use these fixture
settings for the normal app server.

## VS Code Android USB debugging

VS Code configuration is supplied in both `Oyu/.vscode` and `fieldforce_hrms/.vscode`,
so either folder may be open. The launch profile is **Trackyu Android (USB)**. It uses
the workspace Flutter SDK, Microsoft Java 21 and local API on port 5199.

Android SDK is not installed yet. To finish the one-time setup inside VS Code:

1. Terminal > Run Task > **Trackyu: Android SDK setup (one time)**.
2. Read Google's Android SDK License Agreement linked by the task. Type ACCEPT only
   if you agree, then review/respond to SDK package license prompts. The task does not
   automatically accept them. It downloads the official command-line tools, verifies
   their published SHA-256, then installs platform-tools, platform 36, build-tools,
   Flutter's pinned NDK and CMake under `Oyu/.tools/android-sdk`.
3. Run **Developer: Reload Window**, connect the phone by USB, enable USB debugging
   and authorize the computer on the phone. Select that phone in VS Code's device picker.
4. Select **Trackyu Android (USB)** under Run and Debug, then press F5.

The pre-launch task validates the SDK and connected device, starts the local API if it
is not already healthy, and runs adb reverse for port 5199. A missing SDK, unauthorized
phone or multiple connected devices produces an actionable message before launch.
If multiple devices are connected, disconnect extra ones or set ANDROID_SERIAL to the
same device selected in VS Code. No firewall rule or global environment setting is changed.
If the task starts the API it remains running for reuse; stdout/stderr are written to
`TrackyuAPI/.logs/android-api.*.log`. Existing database/connection settings are used.

Configuration checks passed: launch/task JSON and referenced paths, PowerShell syntax,
Java 21 presence and the expected missing-SDK preflight message. APK build, actual USB
forwarding and F5 device launch remain unverified until the SDK is installed and a
phone is connected/authorized.

## Physical Android debug verification (2026-11-06)

The debug APK was successfully built, installed and launched on the connected CPH2487
(Android 16 / API 36, arm64). Flutter connected to the Dart VM Service and DevTools;
the app process and USB reverse mapping for port 5199 were verified. Local API login
was verified without recording credentials or the returned JWT. No attendance punch
was submitted as part of this launch verification.

Android duty tracking now uses the app-owned native foreground service, encrypted SQLite storage and WorkManager retries. The previous flutter_background_geolocation dependency and its native SDK/Maven configuration were removed. Shared compileSdk remains 36 and Play Services Location 21.3.0 supplies Fused Location; Android LocationManager is the fallback. See [duty tracking](DUTY_TRACKING.md).

Kotlin-plugin migration and Java/deprecation warnings remain; the debug build passed.
This was an arm64 debug build, not a release build or full background-tracking test.
The field-attendance limitation from this initial launch was subsequently corrected;
see the field/office integration update below.

For VS Code breakpoints while this app is already running, select
**Trackyu Android (Attach running app)** and press F5. For a fresh build/install use
**Trackyu Android (USB)**. The generated APK is at
`build/app/outputs/flutter-apk/app-debug.apk`; local build output is in the ignored
`android-debug-build.log`. Runtime debug service addresses are session-specific.


## Field/office integration correction (2026-11-06)

The server now reads employee TYPE from VW_SALESMAN on every attendance-profile refresh.
F routes to FieldAttendance; O routes to OfficeAttendance. A field employee never needs
an office merely because the legacy Salesman record also has office coordinates.
An office employee cannot call the FieldAttendance API to bypass the radius/reason rules.
Unknown/inactive accounts are denied by the profile/field workflow; client-stored roles
or a supplied employee ID do not select the mode.

Field records are stored in WorkforceFieldAttendance (migration 004), with one record
per employee/workdate and one open session. GPS must be finite, within valid coordinate
ranges, <=50 m accuracy, no more than 120 seconds old and at most 30 seconds in the future.
Field mode has no office radius or office late/early reason checks. Approved full-day
leave still blocks check-in. With MirrorLegacyData=true, legacy Attendence/SMTRACK writes
occur in the same transaction. v_name stores client-reported phone brand/model/OS; attendance mode is stored separately in the canonical attendance table. Failed legacy writes roll back the
canonical field record too. Field/office writes share an employee transaction lock and
check both tables to prevent duplicate sessions after an employee-type change.
Changing employee type with an open session requires administrator review; it does not
silently move or close the old attendance. Existing legacy attendance is not fabricated
or overwritten; a same-day legacy duplicate is rejected for review.

For office users with no new membership record, the API imports an enabled legacy
Salesman assignment (TYPE=O, OFF_STATUS=1, valid OFF_LAT1/OFF_LONG1, valid TIME/DETIME).
The import is serialized per employee and creates an office, active non-manager member
and source/policy history. Repeated requests reuse that mapping. Existing new memberships,
including disabled ones, are never overwritten/reactivated. Legacy field users and disabled
legacy office assignments are not imported. Subsequent legacy edits do not overwrite an
already configured Workforce policy; maintain that policy through the admin API/tables.
No automatic manager or administrator role is granted.

Workforce configuration defaults:

| Setting | Default |
|---|---|
| ImportLegacyOffices | true |
| LegacyOfficeRadiusMeters | 100 (set 500 before import if that is your policy) |
| LegacyOfficeTimeZoneId | Asia/Kolkata |
| FieldTimeZoneId | Asia/Kolkata |

Imported offices use the actual legacy shift, 10-minute grace, 50 m GPS accuracy limit,
120-second GPS age limit and checkout geofence. Radius/grace can be edited afterward
using WorkforceOffices/save with the current row version. Overnight office shifts still
require a separate policy implementation; invalid shift data returns a safe setup error.

Verification: 26 Flutter tests passed, Flutter analysis clean, .NET migration/error/GPS
regressions passed, and 19 live HTTP checks passed with disposable legacy employee fixtures.
Those checks cover field punch-in/out far from legacy office coordinates, status restore,
duplicates, stale GPS, ownership, office-user field-endpoint denial, office radius checks,
legacy Field-labelled mirroring, import idempotency and disabled mapping protection.
Fixtures were cleaned up; no real employee attendance was marked. Actual profiles were
verified: IN016 -> Field with state loaded and no office requirement; BT014 -> one imported
office, original shift 10:00?21:00 and default radius 100 m.
