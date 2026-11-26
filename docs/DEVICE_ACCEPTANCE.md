# Physical-device release checklist

Do not label a device/OS combination supported merely because it installs. Record
model, manufacturer skin, exact OS/build, app/SDK version, test date, tester and evidence.
Support scope is Android 10+ and iOS 15+ subject to resolved plugin requirements.
Minimum version is a project choice, not a promise that all devices behave identically.

## Build / configuration

- [ ] Bootstrap completes on developer Windows/macOS/Linux; no source overwrite.
- [ ] `flutter pub get`, `flutter analyze`, `flutter test` pass; commit lockfile.
- [ ] Android debug/release build and iOS simulator/device build pass.
- [ ] Native duty tracking tested on each supported Android/OEM version; no purchased location SDK is used.
- [ ] Release signing, privacy disclosures and store background-location declaration reviewed.
- [ ] Backend integration and schema validated with captured native HTTP payloads.
- [ ] Native token refresh/scoped duty-token flow reviewed and tested.
- [ ] Licensed production map provider configured; attribution retained.

## Test on real phones

Cover Samsung, Xiaomi/Redmi/POCO, Oppo, Vivo/iQOO, Realme, OnePlus, Motorola, Pixel,
other employee-fleet vendors and multiple supported iPhone generations. Include non-GMS
Android devices if they are in scope; Google Play Services location availability is not
universal. If those devices are required, add/test an alternate location provider SDK.

For every supported OS family/model:

- [ ] Fresh install: deny once, allow once, precise/approximate, permanent denial.
- [ ] Foreground/background upgrade permission flow; no popup loops.
- [ ] GPS off/on, permission revoked during duty, app resumed from Settings.
- [ ] Late reason, early-exit reason, office radius, field rule, approved exemptions.
- [ ] Shift timezone and overnight shift; server effective policy version.
- [ ] Screen lock while walking/driving; stationary employee; full shift.
- [ ] Measure battery cost and point gaps; define acceptable accuracy/update delay.
- [ ] Weak GPS indoors; jump readings; office boundary oscillation.
- [ ] Battery saver, extreme power saver, low battery, charging, vendor autostart controls.
- [ ] Swipe-away, OS memory kill, force-stop and reboot separately documented.
- [ ] Phone off: admin shows timeout/unknown, never an invented cause.
- [ ] Network disabled; Wi-Fi without internet; captive portal; weak or intermittent data.
- [ ] API down, timeout, token expired, permission revoked server-side, 5xx, 422 rejection.
- [ ] Offline attendance and locations; duplicate/reordered upload; checkout before reconnect.
- [ ] Pending queue survives restart; acknowledged items are not uploaded as new operations.
- [ ] Old points never rewind latest marker; future/old device clocks flagged server-side.
- [ ] Camera deny/cancel; Android activity killed during camera picker (recovery below).
- [ ] File size cap, file corruption, low disk space and queue cap.
- [ ] File upload interrupted; retry retains encrypted file until durable acknowledgement.
- [ ] Route export destination, cancel, inaccessible destination.
- [ ] Reminders offline, notification denial, reboot, timezone changes, DND/silent.
- [ ] Team authorization, stale status, reconnect snapshot, multiple admin connections.
- [ ] Expected peak fleet size; add clustering/viewport queries if needed.
- [ ] Logout queue guard, account isolation and no off-duty collection.

## Known gaps requiring work before production

* No Flutter build/device checks were possible in the source authoring environment.
* No production backend or approval UI, token refresh, push notifications or generic
  dynamic form builder is included. Integrate/test against API_CONTRACT.md.
* No unattended background file worker; queue resumes while app/Dart is active.
* Native SDK database encryption is not configured. Review local location-data protection.
* Fleet-scale marker clustering and historical team-route playback are not implemented.
* Reminders are local, daily, India-time and inexact; not exact/alarm-clock functionality.

Do not remove these release gates until they have actually been implemented and tested.
