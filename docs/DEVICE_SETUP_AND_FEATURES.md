# Device setup and connected mobile features

The live Trackyu app starts with a device checklist. Its global overlay also covers forms, detail screens and dialogs without discarding their state. Required failures prevent new actions until resolved and the user chooses Continue. No attendance or pending request is automatically replayed after recovery.

Checks on Android/iOS:

- Wi-Fi/mobile network and actual API reachability, rather than treating a connected Wi-Fi icon as proof that the work server is available. The anonymous `GET /api/Health` endpoint checks process availability; it does not certify database availability.
- Device GPS, foreground location, precise location and background/Always location access. Foreground permission is requested before background access. Permanently denied/restricted permissions direct the user to Settings; the app does not repeatedly open permission dialogs.
- Private app storage using a temporary write/readiness probe. Android does not require a broad storage permission for this directory. Shared-file access must use a system picker when a feature needs it; this build does not request all-files access or pretend a storage permission was granted.
- Optional notification permission. Office reminders currently deliver into the server inbox, not phone alarms.

GPS and network loss events display the checklist immediately while the app is open. Other permission changes are checked on resume and every three seconds while foregrounded. Healthy network handoffs do not require setup again. API probes are cached for 30 seconds while healthy and retried when unavailable; private storage is checked at startup and once per minute. Settings changes are rechecked when the user returns.

Android/iOS can kill a process when permissions change. The next launch runs the same checklist. An app cannot forcibly display its screen over other apps when backgrounded or force-stopped. Battery/autostart switches specific to phone vendors are not claimed as verified. Background location permission alone does not activate continuous route tracking; the current connected attendance flow captures GPS when the employee punches.

The attendance menu now includes:

- Attendance history, with scoped team attendance for managers and CSV export of the currently loaded records through the system Save file dialog.
- Personal punch locations on a map, with date selection and recorded accuracy; this does not claim to be a continuous route.
- Leave application (full/first-half/second-half), own cancellation, manager approval/rejection, and read-only legacy leave records in the selected range.
- Daily activity create/edit with server version checks, status, planned/completed work and minutes.
- Reminder create/edit/enable/disable, weekdays and office-local schedule.
- Pre-intimation with a future arrival time converted from phone-local time to UTC.
- Inbox and owned notification read acknowledgements.
- Existing visits, orders and assigned-task reports; office-policy details.

HR request submission requires an active HR office/team membership configured by the administrator in the portal. Field attendance continues to work without office membership. The API decides manager permissions; the app does not grant access based on a locally inferred level. Expired API sessions sign out. Forms show errors without reporting failed saves as successful, and version conflicts preserve the form for review. KRA remains pending its separately agreed workflow.

Verification: 42 Flutter tests pass, including permission/network/storage blocking, retained drafts, safe failures, employee scoping, field employees without HR membership, expired sessions, activity version payloads, reminder validation/editing, leave and pre-intimation contracts, safe CSV exports, map-coordinate validation and existing attendance regressions. Flutter analyzer is clear; Android arm64 debug APK built for CPH2487. The complete map/export/telemetry APK was installed and launched on CPH2487 at 2026-11-06 23:26 IST after USB reconnection. Native permission choices must be accepted by the user on the phone; automated tests do not grant them silently.

Android permission references: [storage and permission alternatives](https://developer.android.com/privacy-and-security/minimize-permission-requests), [runtime permissions](https://developer.android.com/training/permissions/requesting).

Punch telemetry: the app collects current battery percentage, a legacy-compatible brand/model/OS description, and city/address resolved from the same GPS fix. The API maps these to SMTRACK.battary, v_name, City and add_by_map. v_name is not the attendance mode. City capacity is widened by 005_LegacyPunchTelemetry.sql in both SMTRACK and its delete archive. No historical battery/device values are fabricated. Geocoder or sensor failure leaves the unavailable value null and displays a post-punch notice; it does not substitute 0%, an office name or Field as fake telemetry.

Device-bound login and administrator-approved replacement are now enabled; see [device workflow](../../TrackyuAPI/DEVICE_BINDING.md). The device-binding APK is built; this final installation is pending because the phone is no longer connected. Previous HR/telemetry build installation remains the earlier verified device check.

Update 2026-11-07: camera checklist, selfie attendance, live hours, slow-connection advisory and regular/open visit entry are included. See [current legacy feature comparison](LEGACY_FEATURE_PARITY.md). The latest mobile suite contains 55 tests; the new APK still requires USB reconnection for installation.
