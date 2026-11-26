# .NET API integration contract

All paths are relative to HTTPS `API_BASE_URL`, which normally includes `/api`.
Use standard authenticated controllers/services/repositories. Never use client fields
to determine the acting employee, manager, tenant, approval state or policy applicability.
No server implementation, database credentials or real deployment is included.

## Endpoints consumed by this app

| Method/path | Request | Response |
|---|---|---|
| GET `/health` | no employee location | HTTP 200 if reachable |
| POST `/auth/login` | `email`, `password` | `{"accessToken":"…"}` |
| GET `/me` | bearer token | `{"id":"employee-uuid","name":"Aarav Sharma","roles":["Employee"]}` |
| GET `/me/policy` | bearer token | full resolved policy matching `assets/default_policy.json` |
| GET `/me/kras` | bearer token | array of `{id,title,target,unit,progress}` |
| POST `/attendance` | attendance event below | idempotent acknowledgement or explicit final rejection |
| POST `/locations/batch` | native SDK envelope below | HTTP 200/201 only after durable commit |
| POST `/telemetry/heartbeat` | sessionId,capturedAt,device,batteryPercent,latestFixAt | HTTP 200/204 |
| POST `/telemetry/event` | id,sessionId,code,message,capturedAt | standard acknowledgement |
| POST `/leave` | id,title,reason,date,toDate,capturedAt | standard acknowledgement; approval status |
| POST `/intimation` | id,title,reason,date,expectedArrival,capturedAt | standard acknowledgement |
| POST `/activity` | id,title,notes,date,kraId,capturedAt | standard acknowledgement |
| POST `/kra/assign` | id,employeeId,title,target,unit,date,notes,capturedAt | standard acknowledgement; manager-only |
| POST `/file` | multipart `file` and JSON-string `metadata` | standard acknowledgement |
| GET `/team/locations` | manager/admin token | team snapshot array below |
| SignalR `/hubs/tracking` | same bearer authentication | `LocationUpdated` with one team-member argument |

## Standard operation acknowledgement

Every POST sent through the encrypted application outbox includes an `Idempotency-Key`
header equal to its operation UUID. The response MUST repeat the ID and distinguish
durable submission from business approval:

```json
{"id":"same-operation-uuid","accepted":true,"status":"pendingApproval"}
```

Persist deduplication on `(tenant, employee, operationId)`. Return the original result
for retries. Commit the business operation, dedupe result and server outbox event in
one transaction. Do not reply success before persistence. A submitted leave is not an
approved leave; a pre-intimation is not automatically a late-arrival exemption.

Explicit terminal business rejection may use HTTP 422 or 200:

```json
{
  "id":"same-operation-uuid",
  "accepted":false,
  "final":true,
  "reason":"Check-in is outside the assigned office.",
  "authoritativeSession":{"id":"session-uuid","active":false,"pending":false}
}
```

For rejected attendance, `authoritativeSession` is mandatory. For an active session,
include `checkedInAt` and its ID. Reconcile sequential offline punches carefully; if
a check-in was rejected, later checkout/location records belong in an audit/quarantine
flow, not a valid attendance session. Transient errors should return non-success and
retain queued data. HTTP 401/403 require authentication/authorization recovery, not
silent deletion. The app never treats an unacknowledged upload as complete.

## Attendance event

```json
{
  "id":"event-uuid",
  "sessionId":"client-generated-session-uuid",
  "event":"checkIn",
  "policyId":"office-policy",
  "policyVersion":1,
  "reason":"Traffic delay",
  "capturedAt":"2026-11-06T04:15:00Z",
  "offlineAtCapture":false,
  "location":{
    "id":"point-uuid","lat":23.2599,"lng":77.4126,
    "accuracy":12,"capturedAt":"2026-11-06T04:14:58Z"
  }
}
```

Server validates identity, shift/date, holiday, geofence, accuracy, reason, duplicate
punches, approval facts and policy effective version. Use capturedAt and receivedAt
separately. Offline/client clocks are not inherently trustworthy: suspicious timestamps
must be flagged for review. Resolve half-day/late exemptions for this shift/date on the
server. Do not expose employee controls that can manufacture approved facts.

Checkout can have `location:null` when location is unavailable, so it is still possible
to stop tracking. Server may route such checkout to review. Client stops native tracking
on local checkout; rejected checkout response can explicitly restore the active session.

## Native location ingest

The native tracking SDK sends its own JSON representation, NOT the UI's `Fix` schema:

```json
{
  "locations":[
    {
      "uuid":"native-sdk-point-uuid",
      "timestamp":"2026-11-06T04:20:00.000Z",
      "coords":{"latitude":23.2599,"longitude":77.4126,"accuracy":12,"speed":1.2,"heading":90},
      "extras":{"sessionId":"session-uuid","policyId":"office-policy","policyVersion":1}
    }
  ]
}
```

Verify a captured SDK payload against the pinned version during integration; it may
include activity, battery, odometer and geofence metadata. Use `uuid` for dedupe, validate
coordinates/time and persist capture + receive times. SDK native retention is bounded
at seven days / 20,000 records; reaching that bound can lose oldest queued points.
Treat unknown offline session IDs as pending/quarantined until the attendance event
arrives. Do not accept them as authorized duty solely because the client supplied an ID.

Return 200/201 only after the batch is durably stored or durably quarantined. A transient
failure must produce a retryable non-2xx response. Malformed/permanently rejected points
need a durable audit/quarantine decision so they do not block all native retries forever.

Store immutable history and update `EmployeeLatestLocation` only when a newer captured
point arrives. Validate unreasonable jumps and accuracy; do not claim GPS-only fraud
prevention. Serialize any office-boundary state per employee/session and apply an accuracy
margin/hysteresis or consecutive fixes; a single native geofence event is not proof.

**Authentication:** integrate scoped duty credentials and native refresh before rollout.
This source does not implement token refresh. Do not solve this with an unrestricted
long-lived account token. Session close must reject new post-checkout points while
allowing authorized delayed historical uploads under your retention/review policy.

## Team snapshot and SignalR event

```json
{
  "id":"employee-uuid",
  "name":"Aarav Sharma",
  "status":"onDuty",
  "lastContact":"2026-11-06T04:20:03Z",
  "location":{
    "id":"point-uuid","lat":23.2599,"lng":77.4126,
    "accuracy":12,"capturedAt":"2026-11-06T04:20:00Z"
  }
}
```

GET returns an array; SignalR sends one object as the single `LocationUpdated` argument.
Authorize hub connections and groups by tenant/team on the SERVER. Broadcast only after
ingest commits. Send status changes/heartbeat expiry even when coordinates did not move.
Do not let an employee choose another team's SignalR group. Snapshot queries must apply
the same authorization as live events. On reconnect the mobile map refreshes its snapshot.

Keep these facts separate:

* last authenticated server contact,
* last received point and its capture time,
* last reported device condition,
* inferred connection timeout.

Stationary employees need a server-side heartbeat policy, but there is no fixed-frequency
background heartbeat in this client. Native motion/OS behavior can suppress updates.
Use `Unknown / stale` rather than asserting the user disabled internet or GPS.

## Backend tables / services to implement

Employee, Office, Shift, PolicyVersion/Assignment, Attendance, TrackingSession,
LocationHistory, LatestLocation, DeviceTelemetry, LeaveRequest, ApprovalInstance,
Intimation, KRA, DailyActivity, Reminder (if server-synced), Attachment, DedupeResult,
AuditLog and Outbox. Separate operational latest-location reads from historical analytics.
Configure retention, backups, tenant isolation, private object storage, malware/type/size
validation and manager access. Scale the ingest worker and SignalR deployment based on
measured fleet/update volume; Redis and microservices are not prerequisites.
