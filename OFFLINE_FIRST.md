# Offline-first mobile workspace

## Storage and sync

Android saves attendance, visits, leave applications, daily activities, reminders
and pre-intimation submissions in encrypted native SQLite before reporting success.
The same SQLite transaction writes the visible day record and its outbox operation.
GPS collection uses the foreground Android service and the encrypted location table;
it does not require internet or a server lease to start after a local punch-in.

Records are scoped by API base URL and employee ID. Reading today's attendance,
visits and route uses phone storage. Upload acknowledgement updates server IDs and
versions in that storage; it does not delete the phone copy or download the day
again. Menu configuration can refresh separately every five minutes.

The ordered outbox resolves dependent attendance/visit IDs and visit versions from
earlier receipts. HTTP uploads run separately from local reads. Native WorkManager
retries with connectivity, and the foreground service also initiates sync. Failed
requests remain saved. Authentication failures offer sign-in again; business
rejections block the queue visibly for reconciliation rather than dropping data.

The API uses `X-Operation-ID` and migration 018 receipts to replay acknowledged
responses. An uncertain server crash leaves a processing receipt requiring review;
it is intentionally not executed again blindly. This is duplicate prevention, not
a claim that every server failure can be resolved automatically.

GPS samples retain their original capture times and UUIDs. Temporary attendance
IDs are mapped before GPS upload, including late native callbacks. Pending,
acknowledged and rejected samples remain available locally. The former seven-day
deletion, 100,000-point storage cap and 10,000-point local day limit are removed.
No automatic monthly cleanup has been added. Any future cleanup must preserve
unacknowledged records and require a verified server copy.

## Route display

The route page reads only local data, refreshes every ten seconds, and never waits
for a day-report request. Integer JSON distances are accepted. Low-accuracy valid
coordinates remain visible; the last GPS timestamp and accuracy are shown instead
of presenting an old fix as a live current location. Missing coverage and implausible
jumps split the line. Stop smoothing requires both its time window and radius;
movement outside a stop cannot be collapsed into that stop. Gaps do not imply a
continuous travel path, and sparse/poor fixes do not establish a local stop.

Previously viewed map tiles are cached with a 96 MiB target size and reused offline,
including stale tiles without extending their saved HTTP expiry. An unseen area
still needs internet for map imagery. Raw GPS collection and route geometry work
independently of imagery. No bulk map download is performed.

## Recovery and existing installations

New phone workspaces offer an explicit restore, also available in the drawer.
Restore downloads the last 31 days of server-confirmed attendance, route reports and visit
metadata, plus personal leave, reminders, pre-intimation and office activity collections into local day records. Current attendance is restored separately.
Previously loaded retailer search results are cached for offline retailer selection.
Normal viewing does not repeat that download. Restore is blocked while the new
outbox has pending/rejected work, and submissions are blocked during restore.
Photos are retained when captured locally; historical photo files are not bulk
downloaded by metadata restore. Dates older than 31 days are not included in this
restore action.

Uninstall removes app-private data and encryption keys. Only previously uploaded
records can be recovered from the server. No implementation can recover GPS fixes
that the previous app never captured, or unsynced records after uninstall without
an independent backup. Update in place; do not uninstall or clear app data to test.

The previous secure-storage outboxes were global and lacked employee/workspace
ownership. They are preserved and counted for review, but are not automatically
replayed against whichever account signs in next. An administrator must verify
ownership before migrating such earlier pending activities. Native GPS rows whose
original configured workspace is known are migrated to the scoped owner key.

## Rollout and validation

1. Back up the target database and apply `018_MobileOperationReceipts.sql` after
   migrations 001–017. The schema application tool now includes 018.
2. Deploy the changed API before distributing the new mobile build. API changes
   accept captured attendance/visit times within 31 days and retain GPS uploads
   without the previous seven-day age floor, while still validating ownership,
   coordinates, future times and attendance windows. A captured offline punch-out
   can replace an automatic cutoff only when its audit row matches the closed
   session; it cannot overwrite a manual closure.
3. Update the APK in place. Use a test employee for airplane-mode punch-in, route
   movement, visit start/finish, app restart and reconnect. Confirm pending counts
   drain and server records do not duplicate. Test screen-off recording on the
   actual OPPO device with precise/background location and background battery use.

The development checks include Flutter regression tests, a seven-kilometre route
rendering regression, offline tile-cache tests, API regression checks and an
isolated Android instrumentation suite. Instrumentation uses disposable databases,
encryption keys and a loopback HTTP server, not employee records or production APIs.
Emulator tests do not establish real-world GPS reception or vendor battery behavior.

Database migration and production API deployment are not performed by these local
build/test commands.

### Verified build, 2026-11-09

- Full Flutter suite: 95 passed; final focused storage/restore/map suite: 6 passed.
- Changed Dart files: analyzer reports no issues.
- API compilation and migration/regression checks passed; no live database test or
  production migration was performed.
- Final APK instrumentation passed encrypted persistence, restart retention,
  transaction rollback, employee/workspace isolation, retained rejected/old GPS
  samples, original capture ordering, server acknowledgement, dependent attendance
  IDs and stable operation IDs across a 503 retry.
- ARM64 debug APK: `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
  SHA-256: `65B132366EEF0A053768F74FB89A98F8334A8C79D097EF354F779222E13C57B6`.
- Actual OPPO screen-off/airplane-mode road recording remains a device validation
  step after deploying the API changes. Existing missing GPS fixes cannot be
  reconstructed by these fixes.

Android platform references: [app-specific storage and uninstall](https://developer.android.com/training/data-storage/app-specific), [foreground location services](https://developer.android.com/develop/background-work/services/fgs/service-types#location).
