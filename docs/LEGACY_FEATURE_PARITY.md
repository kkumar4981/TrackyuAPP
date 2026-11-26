# Legacy application feature comparison

Reviewed 2026-11-07 against `JioTracker/app/src/main/res/navigation/nav_salesman_graph.xml`, `activities/HostActivity.java`, the regular/open visit fragments and `utils/ApiInterface.java`. This compares actual mobile screens and write workflows, rather than counting API routes as completed app features.

| Legacy workflow | Current Flutter app |
| --- | --- |
| Login / logout / device mapping and replacement | Connected; replacement requires administrator approval |
| Field and office attendance | Connected; selfie, GPS, office policy and working-hours display |
| Regular retailer visit check-in / checkout | Connected through Visits → Start / manage visits; assigned retailers, mapped-location check, legacy 1500 m radius, camera photo, GPS and remarks |
| Open visit check-in / checkout | Connected through the same screen; shop/place/address, camera photo, GPS, owner/mobile/lead status and remarks |
| Old regular/open visit reports | Connected, read-only; old sessions are not automatically imported into the new session workflow |
| Leave / half day / approval / pre-intimation | Connected through the new office HR workflow; legacy leave is read-only |
| Attendance history / manager view | Connected; export of loaded history |
| Personal location map | Punch locations only; continuous route tracking is not active |
| Orders / old orders / order collection | Existing-order reports only; product selection, booking, editing and collection remain pending |
| Assigned tasks | Reports only; completion/update remains pending |
| Tour entry / tour checkout / tour list | Pending |
| Beat plan / PJP / daily plan | Pending |
| Retailer-location mapping / home-location changes | Pending. Office location proposals are available in My offices; administrator map/GPS setup and approval are connected |
| Inspection / claims | Pending; legacy navigation also contains development placeholders, which are not counted as live functionality |
| Detailed attendance/visit ECO, WOD and periodic summaries | Partial through scoped attendance/visit reports; dedicated legacy summary screens remain pending |
| Profile view/edit / contact/share / social screens | Pending dedicated screens |
| Notifications | Server inbox connected; push delivery is not configured |
| Daily activity / reminders | New HR forms connected; reminders appear in inbox, not phone alarms |
| KRA | Pending the user's separate workflow details |

## Visit implementation

Apply `TrackyuAPI/Database/008_MobileVisits.sql` to each deployment database. The local configured development database is updated. `/api/MobileVisits` derives the employee from the JWT and requires a mapped mobile session. Retailer search returns only personal mappings, up to 100 matches; narrow the search when needed.

Regular check-in preserves the legacy 1500 m retailer radius. Both visit types require a fresh GPS fix (maximum age 120 seconds, accuracy up to 50 m) and a camera photo (JPEG/PNG up to 2 MB). Open checkout uses legacy lead codes Y/N/L. A single active new visit is allowed per employee. The server controls dates and times in the configured field time zone. Older sessions stay in the read-only legacy report; resolve any existing old-app session before switching workflows.

The canonical visit, private photo and `Att_Smvisits`/`OPEN_VISIT` mirror commit in one transaction. No invented stored procedure is required. The regular insert accommodates the existing insert trigger. Photos are private and owner-only through an authenticated no-store endpoint; legacy public photo fields remain blank for new visits. The app provides View visit photo.

Write request IDs make retries idempotent; checkout also validates the row version. The app never automatically replays an uncertain write. Reload visits before retrying after a timeout. An active visit from a previous date is still shown for checkout. The new visit-management screen lists today's new sessions; use the existing Visits report date selector for historical mirrored records.

## Connection quality and branding

The foreground setup monitor measures the small `/api/Health` round trip. A successful response taking at least 2 seconds shows a slow-workspace-connection banner and checklist advisory; it does not block attendance. Healthy results are cached for up to 30 seconds; manual Check again forces a new probe. A failed/timed-out 5-second probe uses the existing blocking workspace-connection check. Transport changes invalidate the cache. This measures workspace response latency, which can include server delay; it is not a download-speed/Mbps measurement or a database health guarantee.

Launcher/adaptive icons use the existing legacy paper-plane/location artwork. Android startup, iOS icons/startup and web/PWA icons are updated. Committed `platform_config/branding` assets are restored by platform bootstrap. iOS changes require macOS/Xcode validation; no iOS build is claimed here.

Verification: Flutter analyzer clear; 55 mobile tests and 19 isolated API/portal tests passed. Tests cover visit camera cancellation, lost-response recovery, ownership, stale versions, duplicate writes, geofence and legacy report persistence. The final Android ARM64 debug APK built successfully. Disposable QA employees/retailers and workflow records were removed. API (5199) and portal (5173) are running with the update; phone installation and physical permission/camera checks remain pending USB connection.

Current update: employee pre-intimation no longer requires office membership. Administrators default to all-employee attendance; mobile home includes a compact selfie preview. See [employee workflow guide](../../TrackyuAPI/EMPLOYEE_WORKFLOWS.md). Latest checks: 58 mobile and 24 API/portal tests pass.


## Direct salesman visit workflow (2026-11-07)

The legacy `fragments/NavVisitFragment.java` (linked by `nav_salesman_graph.xml`) captures a retailer visit photo, in/out GPS and times, recovery/visit, order and other remarks. It also checks `GetDateTimeUtil.getCheckInAfter10Min` before checkout. This is now directly accessible from the home **Salesman visit** card and drawer item, rather than opening a reports screen first. Regular/Open visit entry remains available; history is a separate toolbar action.

The app automatically loads assigned retailers, shows the active visit and live elapsed duration, and restores active visits after reopening. Regular checkout is unavailable until `earliestCheckoutUtc`, ten minutes after server punch-in. The API independently rejects early checkout with `VISIT_TOO_SHORT`. Both punches still require fresh GPS; regular check-in retains the 1500 m mapped-retailer radius. Open visits retain owner/mobile/lead details on checkout. No new schema or invented procedure is required.

QA ages only a guarded disposable QAF01/QAV001 visit to verify the successful ten-minute checkout path; it does not modify real employee visits. Home shortcut navigation is tested to call MobileVisits directly without loading the legacy report first.

Latest salesman visit validation: 70 Flutter tests and 28 API/portal tests pass; analyzer is clear. Updated ARM64 debug APK built successfully and main API 5199 is running. Salesman visit APK installed successfully and launched on CPH2487 at 2026-11-07 10:57:16 IST, preserving app data. USB port 5199 forwarding restored; main API health returned 200.
