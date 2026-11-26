bool isValidGpsFix({
  required double? lat,
  required double? lng,
  required double? acc,
  required DateTime? capturedAt,
  required bool isMocked,
  required DateTime now,
}) {
  if (lat == null || lng == null || acc == null || capturedAt == null) return false;
  if (!lat.isFinite || !lng.isFinite || !acc.isFinite) return false;
  if (lat < -90.0 || lat > 90.0 || lng < -180.0 || lng > 180.0) return false;
  if (lat == 0.0 && lng == 0.0) return false;
  if (isMocked) return false;
  if (acc <= 0 || acc > 500.0) return false;
  final ageSec = now.difference(capturedAt).inSeconds;
  if (ageSec < -15 || ageSec > 900) return false;
  return true;
}
