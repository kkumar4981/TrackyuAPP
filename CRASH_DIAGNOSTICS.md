# Mobile crash diagnostics

## Confirmed OPPO regression (9 November 2026)

Android recorded `APP CRASH(EXCEPTION)` in `TrackingChannel.kt:36`. A restored day contained nested JSON arrays (`report.route.segments`). `TrackingRuntime.jsonMap` converted array objects but left nested `org.json.JSONArray` and JSON null objects inside the response. Flutter's `StandardMessageCodec` threw `IllegalArgumentException` on the Android main thread, outside the worker's catch block. This was an application bug, not an inferred memory failure.

The converter now recursively converts every JSON object, array and null to supported channel values. Channel replies catch encoding failures and return a controlled error. Original day records, GPS samples and outbox entries are unchanged.

## Capture and delivery

- Flutter framework, dispatcher and root-zone failures feed the existing local logger and a private native journal. Startup never waits for logging.
- `TrackyuApplication` installs a native uncaught-exception handler that synchronously records exception type and stack frames before delegating to Android's original handler. It does not suppress a fatal exception or restart in a crash loop.
- On Android 11+, the next launch collects Android exit reasons (Java/native crash, ANR, low memory and resource termination). Exit reports are summaries, not full NDK tombstones. Android 10 has no exit-history API. A killed/hung process can only report its exit after it next starts.
- The private atomic journal retains the latest 200 reports, with explicit overflow counts. No GPS coordinates, business request bodies, tokens, passwords or photos are forwarded. Exception messages are deliberately excluded: the original codec exception embedded location records in its message.
- Reports are bound to a hash of the API/employee scope. Reports from another signed-in account are not uploaded under the current account. Reports captured before login can upload after the first login.
- An independent WorkManager job retries on connectivity, with exponential backoff and a 15-minute periodic fallback. Login re-enqueues it. Network/backend/authentication failures leave reports on the phone. Logged-out sessions do not upload. Android battery scheduling may delay delivery.
- Batches contain at most 20 stable event IDs. Only IDs explicitly acknowledged by the server are removed. A separate diagnostics job prevents a logging endpoint outage from blocking attendance/GPS sync.

## Server deployment and inspection

1. Apply `TrackyuAPI/Database/019_MobileDiagnostics.sql` to the target API database. This creates an operational table and does not change employee activity. The normal workforce migration script includes it.
2. Deploy the prepared API build in `.tools/mobile-diagnostics-api-publish` before declaring automatic remote reporting live.
3. `POST /api/MobileDiagnostics/batch` requires a mobile login. Actor identity comes from verified claims. It commits the batch transaction before acknowledging it; `(UserId, EventId)` deduplicates retries.
4. `GET /api/MobileDiagnostics?userId=...&before=...` requires an existing configured workforce administrator. It returns at most 100 reports ordered by server receipt time, with `Cache-Control: no-store`. Reports include version/build, Android version, device model, type, frames and time. There is no public anonymous log viewer.

No server deployment or production database migration was performed in this session. New clients retain reports while the endpoint is unavailable. Server retention/alerting and a dedicated portal log page are not yet configured.

## Validation and artifact

- Native JVM regression tests: nested restored route/JSON null round-trip through the actual Flutter `StandardMessageCodec`, and exclusion of exception payloads from native frames: 2 passed.
- Flutter startup/route/restore regression tests: 11 passed.
- Backend migration/validation checks, including bounded diagnostic batches, error types and stacks: passed. API build: no warnings/errors.
- Targeted Dart analysis: no issues.
- Built `C:\Development\Oyu\trackyu_v1.0.9.apk` and updated `trackyu_updated.apk`, version 1.0.9+11, arm64 and x64.
- APK SHA256: `4F003AFBD07167B98942C0D154110E3D8D845B41157DF23FB69495AF2AB48D32`.
- OPPO installation/launch was rejected by automatic approval review due to the unresolved prior usage restriction. The fixed APK has not been verified on the phone. No app data was cleared.
