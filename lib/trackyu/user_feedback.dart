import 'api.dart';

/// Translates technical codes, exceptions, and network errors into clean,
/// clear, and user-friendly messages for end users in standard English.
String userFriendlyErrorMessage(dynamic error) {
  if (error == null) return 'No information available.';

  if (error is ApiFailure) {
    final code = error.code.toUpperCase();
    final msg = error.message.trim();
    final lower = msg.toLowerCase();

    if (code == 'INVALID_CREDENTIALS' ||
        lower.contains('invalid username or password') ||
        lower.contains('invalid_credentials') ||
        lower.contains('user not found') ||
        lower.contains('wrong password')) {
      return 'Incorrect User ID or Password. Please check and try again.';
    }
    if (code == 'OUTSIDE_SHIFT_HOURS' || lower.contains('outside office timing')) {
      return 'You are outside your scheduled working hours.';
    }
    if (code == 'DEVICE_CHANGE_REQUIRED' || lower.contains('mapped to another phone')) {
      return 'Your account is registered on another device. Please tap "Request device change" to link this phone.';
    }
    if (code == 'DEVICE_REQUEST_PENDING' || lower.contains('already awaiting review')) {
      return 'A device change request is already awaiting administrator review and approval.';
    }
    if (code == 'INVALID_PASSWORD' || lower.contains('current password is incorrect')) {
      return 'Current password is incorrect. Please enter your valid current password.';
    }
    if (code == 'SESSION_ACCESS_REQUIRED' || code == 'DEVICE_SESSION_INVALID' ||
        code == 'DEVICE_HEADER_MISSING') {
      return 'Device access needs verification. Saved attendance is safe. Contact your administrator and refresh after access is restored.';
    }
    if (code == 'FORBIDDEN' || code == 'UNAUTHORIZED' || error.status == 401) {
      return 'Your session has expired. Please sign in again.';
    }
    if (code == 'CONNECTION_TIMEOUT' ||
        code == 'CONNECTION_FAILED' ||
        lower.contains('cannot reach') ||
        lower.contains('connection')) {
      return 'Unable to connect to server. Please check your internet connection and try again.';
    }
    if (code == 'GPS_DISABLED' || lower.contains('location services')) {
      return 'Location (GPS) is turned off. Please turn on Location in your device settings.';
    }
    if (code == 'LOCATION_PERMISSION' || lower.contains('location permission')) {
      return 'Location permission is required for attendance. Please allow location access in App Settings.';
    }
    if (code == 'BACKGROUND_LOCATION_REQUIRED' || lower.contains('allow all the time')) {
      return 'Work tracking requires background location ("Allow all the time"). Please update in App Settings.';
    }
    if (code == 'LOCATION_INACCURATE' || code == 'LOCATION_EXPIRED') {
      return 'Weak GPS signal. Please move to an open area or near a window and refresh location.';
    }
    if (code == 'SELFIE_REQUIRED') {
      return 'Taking a selfie is required to mark attendance.';
    }
    if (code == 'OPEN_VISIT_IN_PROGRESS') {
      return 'A client visit is currently in progress. Please check out of the visit before punching out.';
    }
    if (code == 'ALREADY_PUNCHED_OUT' || code == 'ATTENDANCE_ALREADY_EXISTS') {
      return 'Attendance for today is already completed.';
    }
    if (code == 'OPEN_OFFICE_SESSION') {
      return 'An office attendance session is currently open. Please contact your administrator.';
    }
    return msg.replaceAll(RegExp(r'^[A-Z_]+:\s*'), '').trim();
  }

  final text = error.toString().trim();
  final lower = text.toLowerCase();

  if (lower.contains('invalid_credentials') ||
      lower.contains('invalid username or password') ||
      lower.contains('user not found') ||
      lower.contains('wrong password')) {
    return 'Incorrect User ID or Password. Please check and try again.';
  }
  if (lower.contains('current password is incorrect') ||
      lower.contains('invalid_password')) {
    return 'Current password is incorrect. Please enter your valid current password.';
  }
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('connection timed out') ||
      lower.contains('connection_failed') ||
      lower.contains('connection_timeout') ||
      lower.contains('cannot reach') ||
      lower.contains('clientexception')) {
    return 'Unable to connect to server. Please check your internet connection and try again.';
  }
  if (lower.contains('outside office timing') || lower.contains('outside_shift_hours')) {
    return 'You are outside your scheduled working hours.';
  }
  if (lower.contains('timeout') || lower.contains('timeoutexception')) {
    return 'Connection timed out. Please check your internet connection and try again.';
  }
  if (lower.contains('device_change_required')) {
    return 'Your account is registered on another device. Please tap "Request device change".';
  }
  if (lower.contains('gps_disabled')) {
    return 'Location (GPS) is turned off. Please turn on Location in settings.';
  }
  if (lower.contains('location_permission')) {
    return 'Location permission is required for attendance.';
  }
  if (lower.contains('background_location_required')) {
    return 'Work tracking requires background location ("Allow all the time").';
  }
  if (lower.contains('open_visit_in_progress')) {
    return 'A client visit is currently in progress. Please complete the visit before punching out.';
  }
  if (lower.contains('typeerror') ||
      lower.contains('is not a subtype') ||
      lower.contains('null check operator') ||
      lower.contains('formatexception') ||
      lower.contains('nosuchmethoderror')) {
    return 'A technical issue occurred. Please refresh the screen or restart the app.';
  }

  var cleaned = text.replaceAll(
    RegExp(r'^(Exception|ApiFailure|DioException|StateError|ArgumentError):\s*'),
    '',
  );
  cleaned = cleaned.replaceAll(RegExp(r'\s*Reference:\s*[a-zA-Z0-9_-]+'), '');
  cleaned = cleaned.replaceAll(RegExp(r'^[A-Z_]+:\s*'), '');

  if (cleaned.trim().isEmpty) {
    return 'A technical issue occurred. Please try again after some time.';
  }

  return cleaned.trim();
}
