# Timeline repair — 10 November 2026

## Follow-up: phone read timeout (1.0.21+28)

The reported `DutyRoutePage.load` timeout came from a 15-second deadline around the complete GPS history download over the native channel. `Future.wait` consequently discarded usable attendance and visits when GPS was slow. A timeout does not cancel the underlying native operation.

The screen now publishes metadata first, then GPS pages of 250 records, retaining earlier pages if a later page fails. Deadlines apply to individual requests, and changing screen/date stops requesting subsequent pages. Recoverable failures show an inline warning and persist diagnostics with a component name and original stack, without repeated red snackbar interruptions. Refresh preserves already loaded fixes. Native reads cache up to 6,000 decrypted records in memory while validating encrypted payload equality; SQLite remains encrypted and authoritative. A cold summary read no longer rewrites the raw day or stages/encrypts every GPS point. Short same-session quality breaks stay disconnected on the map without flooding the activity list with technical gap cards.

Final focused Flutter regression suite: 25 passed, including a deliberately stalled native GPS request that times out while attendance remains visible. Device timing and continuous OPPO background capture remain unverified; these changes address read behavior, not a claim that GPS hardware can never stall. No local data reset or deletion is required.

## Corrected causes

- `controller.dart / restoreDataFromServer`: restored days previously shared the malformed `day:` key. Restore now writes `day:<yyyy-MM-dd>` independently, requests visits for that date, merges local closures, checks workspace identity after awaits, and reports partial failure honestly. The malformed key is preserved, not guessed or deleted.
- `timeline_reconciliation.dart`: timestamps are interpreted as instants and selected by the IST business date. Visits reconcile request/local/server identities; pending finish updates its visit instead of becoming a new event. Unknown or foreign ownership is excluded. Old/untimed fixes never acquire the current time.
- `tracking_status.dart`: reads local metadata and full native GPS pages. Partial local and restored history merge; rendering alone is sampled. Missing GPS coverage and session boundaries break lines and stop calculations. Removed inferred straight-line travel, assumed-speed arrival and unknown-gap stationary labels. Current versus last-known position uses the actual fix timestamp.
- `TrackingStore.kt`, `RouteProjection.kt`, `TrackingChannel.kt`: full-resolution, media-free day projection; exact employee/API scope; exclusive day end; restored server samples stored as acknowledged records, never queued for upload. Existing raw day records remain intact. Native storage errors record exception type and stack frames.

## Data path and safety

Activity commits local state and its outbox atomically before upload. Native GPS samples persist locally with acknowledgement state. Upload retries retain stable identities; acknowledgements mark records rather than deleting them. Pending local checkout survives an earlier or stale server response. Existing idempotency receipts remain the server contract. No monthly retention/deletion was introduced.

The timeline uses local records; it does not automatically redownload historical days on each screen open. Explicit Restore phone history retrieves seven daily timelines and up to 31 days of other request/activity history. Photos stay in the original records and are excluded from the timeline projection. Very large legacy records that cannot safely project display a partial-history warning rather than pretending history is complete.

## Recovery

1. Update the app without uninstalling or clearing storage.
2. Allow pending activity to sync with a working connection.
3. Use Restore phone history to recover the last seven server-synced days into separate local keys.
4. Older dates or malformed legacy data require explicit verified recovery; no date is invented. Unsynced data removed by a previous uninstall cannot be recovered from the server.

## Verification

- Full Flutter suite: 125 passed before the final gap-label adjustment; final focused timeline/restore/bridge/UI suite: 23 passed.
- Dart analysis of lib: no issues.
- Native JVM tests: 3 passed; Android instrumentation test source compiled.
- Debug APK built for arm64 and x64 (1.0.20+27).
- Real OPPO background movement, airplane-mode recovery, process death, reboot and live server acknowledgement were not runtime-verified in this change. Instrumentation was compiled, not executed on a device. These checks must precede production rollout; compilation and mocks do not prove device GPS continuity.

No private SQL export, employee records or production API deployment was changed.
