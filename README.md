# Trackyu Flutter application

The default app now uses the legacy JioTracker UI and the new TrackyuAPI for **login and
attendance**, employee HR workflows and reports. See [device setup and connected features](docs/DEVICE_SETUP_AND_FEATURES.md)
and [run instructions, table setup and verified limits](docs/TRACKYU_INTEGRATION.md).

```powershell
powershell -ExecutionPolicy Bypass -File tool/run_trackyu.ps1
```

The original wider HRMS demo is preserved at `lib/main_demo.dart`:

```powershell
../.tools/flutter/bin/flutter.bat run -t lib/main_demo.dart --dart-define=DEMO=true
```

That demo's proposed API contract in `docs/API_CONTRACT.md` is a separate design reference.
The live entry point uses the implemented routes documented in TRACKYU_INTEGRATION.md;
KRA remains pending its separate requirements. Regular/open visits support entry and reports; orders and assigned tasks remain connected reports;
new business-entry flows from the old demo are not silently enabled.

Checked on 2026-11-07: Flutter analysis, 79 tests (including network quality, visit entry, selfie cancellation, live working hours, setup recovery, HR forms, small screens and enlarged text),
Android debug APK build. The compact-home/employee-request APK was installed and launched on CPH2487 at 2026-11-07 08:40 IST; physical home/selfie verification awaits the location permissions shown in its checklist. Platform scaffolds are included,
and `pubspec.lock` records the resolved packages. Configure a trusted HTTPS API for
release and obtain production signing credentials. Android duty tracking now uses our native foreground service with an encrypted SQLite queue and WorkManager retries; no paid location SDK licence is needed. See [tracking](docs/DUTY_TRACKING.md).

Mobile device replacement requires administrator approval. See [device binding flow](../TrackyuAPI/DEVICE_BINDING.md). The new APK is required; old JWT sessions sign out once after the API update.

The login/home visual refresh uses a shared orbit illustration, soft blue/mint branding, workspace shortcuts and a rounded gradient punch slider. Tap/short-drag rejection and pending-submit protection are covered by tests. Render fresh previews with `flutter test test/design_preview_test.dart --dart-define=DESIGN_PREVIEWS=true`; PNGs are saved under ../.tools/qa/design-*.png.

Punch-in requires a fresh camera selfie. The home screen shows live working hours restored from server attendance; punch-out freezes the duration. See [selfie and hours setup](../TrackyuAPI/ATTENDANCE_SELFIES.md).

Regular/open visit entry is available under Visits → Start / manage visits. See [legacy feature comparison and visit/network setup](docs/LEGACY_FEATURE_PARITY.md) for connected workflows and remaining gaps.

See [employee requests and administrator reporting](../TrackyuAPI/EMPLOYEE_WORKFLOWS.md) for office-location proposals, employee pre-intimation without office mapping and all-employee attendance reporting.

Punch-out GPS recovery now waits for a fresh fix within the existing 50 m accuracy limit; invalid GPS and missing attendance identifiers show a recovery message. The GPS recovery APK was installed successfully and launched on CPH2487 at 2026-11-07 09:29:45 IST, preserving app data. Actual employee punch-out still requires user verification; automated tests use disposable QA records.

Leave update (2026-11-07): legacy full/first-half/second-half leave, active reason dropdown and remarks are available without office assignment. History uses a single period card; pre-intimation accepts only a future time today with disabled past slots. Verified 68 Flutter tests and 28 API/portal tests. API migration 011 enables administrator review of unmapped leave.

The leave/pre-intimation debug APK was rebuilt successfully on 2026-11-07 at 10:13 IST using the workspace Android SDK (including CMake 3.22.1). The earlier AppData SDK path lacked CMake; android/local.properties now points to the workspace SDK. The leave APK was installed at 10:16 IST, then superseded by the corrected calendar UI below.

Date-picker refinement: individual styled From/To calendar fields restored for leave and history. Pre-intimation uses the normal calendar (today only) followed by a clock picker; past arrival is rejected before saving and by the API. The custom time-slot grid and office-mapping explanations were removed from employee screens.

Corrected calendar UI APK installed and launched successfully on CPH2487 at 2026-11-07 10:26:08 IST, preserving app data. Verification: 68 Flutter tests passed; analyzer reports no issues; portal production build and lint pass.

Salesman visit update: direct home card and drawer entry open customer punch-in/out immediately; assigned retailers load automatically. Active visits show elapsed time and restore after reopening. Regular visits require the legacy ten-minute stay before checkout; API enforces the same deadline. Existing photo, fresh GPS, remarks and Att_Smvisits/OPEN_VISIT transaction remain in use. Verified 70 Flutter tests and clear analyzer.

Details/leave refinement: each leave displays once with readable duration and status; the legacy mirror remains stored for compatibility. Shared labelled detail rows, status badges and responsive layouts now cover attendance, leave, visits, location history, activity, reminders, intimations, inbox, orders, tasks and offices. Tested on narrow screens and enlarged text; 73 Flutter and 29 API/portal tests pass. Preview: ../.tools/qa/details-leave.png.

The details/leave APK built successfully and was transferred to the connected phone. Installation is waiting for the phone installer confirmation; installation success has not yet been observed. The main API and portal updates are running.

Retailer assignment update: admin portal /retailer-mapping adds selected customer mappings in the legacy table. Visit list/punch-in now share legacy level-one or hierarchy visibility. Current AR077 assignments were left for the user to select. Verified 73 Flutter and 32 API/portal checks; APK built, but this wording-only mobile update is pending phone reconnection. The prior details/leave APK installation was confirmed at 2026-11-07 11:21:59 IST.


Native duty tracking update (2026-11-07): encrypted offline GPS queue, scoped native uploads, route segments/coverage gaps, 10-minute/50-metre detected stops, owner/admin timeline and Open visit arrival/departure selfies. Current checks: 79 Flutter tests and 35 API/browser regressions, clean Flutter analyzer, API/portal builds, portal lint and Android debug/instrumentation builds. Phone queue/HTTP instrumentation passed on CPH2487 at the first native install (15:15 IST). The final account-isolation/recovery APK is built; physical re-install/locked-screen travel verification depends on reconnecting the phone. See [detailed behavior and limits](docs/DUTY_TRACKING.md). Development device mapping is currently disabled by the server flag per the requested alternate-account test; set DeviceMapping:Enabled=true in appsettings.Development.json to restore enforcement.
