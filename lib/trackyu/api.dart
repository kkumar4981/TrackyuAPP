import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'device_identity.dart';

typedef Json = Map<String, dynamic>;

class ApiFailure implements Exception {
  final String code, message;
  final String? traceId;
  final String? route;
  final int? status;
  const ApiFailure(this.code, this.message, {this.traceId, this.status, this.route});
  Map<String,String> get diagnosticMetadata => {
    'code': code.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '').substring(0, code.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '').length.clamp(0,64)),
    if(status!=null) 'status': '$status',
    if(route!=null && RegExp(r'^[A-Za-z]+/[A-Za-z-]+$').hasMatch(route!.split('?').first)) 'route': route!.split('?').first,
    if(traceId!=null && RegExp(r'^[A-Za-z0-9-]{1,80}$').hasMatch(traceId!)) 'traceId': traceId!,
  };
  @override
  String toString() => message;
}

abstract class SessionVault {
  Future<String?> read();
  Future<void> write(String? value);
  Future<String?> readPendingPunches() async => null;
  Future<void> writePendingPunches(String? value) async {}
  Future<String?> readPendingVisits() async => null;
  Future<void> writePendingVisits(String? value) async {}
  Future<String?> readCachedVisits() async => null;
  Future<void> writeCachedVisits(String? value) async {}
  Future<String?> readTheme() async => null;
  Future<void> writeTheme(String? value) async {}
}

class SecureSessionVault implements SessionVault {
  static const _storage = FlutterSecureStorage();
  static const _key = 'trackyu.live.session.v1';
  static const _pendingKey = 'trackyu.pending_punches.v1';
  static const _pendingVisitsKey = 'trackyu.pending_visits.v1';
  static const _cachedVisitsKey = 'trackyu.cached_visits.v1';
  static const _themeKey = 'trackyu.theme_mode.v1';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String? value) => value == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: value);
  @override
  Future<String?> readPendingPunches() => _storage.read(key: _pendingKey);
  @override
  Future<void> writePendingPunches(String? value) => value == null
      ? _storage.delete(key: _pendingKey)
      : _storage.write(key: _pendingKey, value: value);
  @override
  Future<String?> readPendingVisits() => _storage.read(key: _pendingVisitsKey);
  @override
  Future<void> writePendingVisits(String? value) => value == null
      ? _storage.delete(key: _pendingVisitsKey)
      : _storage.write(key: _pendingVisitsKey, value: value);
  @override
  Future<String?> readCachedVisits() => _storage.read(key: _cachedVisitsKey);
  @override
  Future<void> writeCachedVisits(String? value) => value == null
      ? _storage.delete(key: _cachedVisitsKey)
      : _storage.write(key: _cachedVisitsKey, value: value);
  @override
  Future<String?> readTheme() => _storage.read(key: _themeKey);
  @override
  Future<void> writeTheme(String? value) => value == null
      ? _storage.delete(key: _themeKey)
      : _storage.write(key: _themeKey, value: value);
}

class TrackyuApi {
  final Dio dio;
  Future<void> Function(String token)? onSessionRevoked;
  void Function()? onSessionAccessChanged;
  bool sessionRejected = false;
  void requireSessionAccess() {
    if (sessionRejected) {
      throw const ApiFailure('SESSION_ACCESS_REQUIRED',
          'Device access needs verification. Saved work is safe. Restore access and refresh before recording a new punch.', status: 401);
    }
  }
  Future<bool> verifyPunchAccess() async {
    var reachable = false;
    try {
      await request('Employee/my-profile');
      reachable = true;
    } on ApiFailure catch (e) {
      if (e.status == 401 || e.status == 403) {
        sessionRejected = true;
        rethrow;
      }
      if (e.status != null && e.status! < 500) rethrow;
    }
    requireSessionAccess();
    return reachable;
  }
  String _baseUrl;
  String get baseUrl => _baseUrl;
  set baseUrl(String value) {
    _baseUrl = validateUrl(value);
    dio.options.baseUrl = '$_baseUrl/';
  }
  final Future<Json> Function() deviceIdentity;
  Json? _device;
  TrackyuApi(String url, {Dio? client, Future<Json> Function()? deviceIdentity})
    : _baseUrl = validateUrl(url),
      deviceIdentity = deviceIdentity ?? mobileDeviceIdentity,
      dio = client ?? Dio() {
    dio.options = BaseOptions(
      baseUrl: '$_baseUrl/',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
    );
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (options.headers.containsKey('Authorization') && !options.headers.containsKey('X-Device-ID')) {
          try {
            final identity = await currentDevice();
            final deviceId = identity['deviceId']?.toString();
            if (deviceId != null && deviceId.isNotEmpty) {
              options.headers['X-Device-ID'] = deviceId;
            }
          } catch (_) {}
        }
        handler.next(options);
      },
      onError: (error, handler) {
      dynamic payload=error.response?.data;
      if(payload is String){try{payload=jsonDecode(payload);}catch(_){}}
      final sentToken=error.requestOptions.headers['Authorization'];
      if (error.response?.statusCode == 401 && sentToken is String &&
          sentToken == dio.options.headers['Authorization']) {
        sessionRejected = true;
        onSessionAccessChanged?.call();
      }
      if(error.response?.statusCode==401 && payload is Map &&
          payload['errorCode']=='DEVICE_SESSION_REVOKED' && sentToken is String &&
          sentToken==dio.options.headers['Authorization']) {
        final callback=onSessionRevoked;
        if(callback!=null)unawaited(callback(sentToken));
      }
      handler.next(error);
    }));
  }
  static String validateUrl(String value) {
    final url = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(url);
    const allowHttp = bool.fromEnvironment('ALLOW_LOCAL_HTTP');
    final isLocal = uri != null &&
        (uri.host == '10.0.2.2' ||
            uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host.startsWith('192.168.') ||
            uri.host.startsWith('10.'));
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !(uri.scheme == 'https' ||
            (kDebugMode && allowHttp && uri.scheme == 'http') ||
            (isLocal && uri.scheme == 'http')) ||
        !uri.path.endsWith('/api')) {
      throw const ApiFailure(
        'API_CONFIGURATION',
        'Set API_BASE_URL to your Trackyu server URL ending in /api. HTTPS is required unless testing on local emulator/network.',
      );
    }
    return url;
  }

  bool get authorized => dio.options.headers.containsKey('Authorization');

  void authorize(String? token) {
    if (dio.options.headers['Authorization'] != (token == null ? null : 'Bearer $token')) {
      sessionRejected = false;
    }
    dio.options.headers.remove('Authorization');
    if (token != null) dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<dynamic> request(String route, {Json? body}) async {
    final requestToken = dio.options.headers['Authorization'];
    if (requestToken != null) {
      final identity = await currentDevice();
      if(dio.options.headers['Authorization'] != requestToken) {
        throw ApiFailure('SESSION_CHANGED','Your account changed. Retry in the current session.',status:401,route:route);
      }
      dio.options.headers['X-Device-ID'] = identity['deviceId'];
    }
    try {
      final r = body == null
          ? await dio.get(route)
          : await dio.post(route, data: body);
      if (r.data is! Map) {
        throw const ApiFailure(
          'INVALID_RESPONSE',
          'Unexpected response from the API.',
        );
      }
      final envelope = Map<String, dynamic>.from(r.data as Map);
      if (envelope['success'] != true) {
        throw ApiFailure(
          envelope['errorCode']?.toString() ?? 'REQUEST_FAILED',
          envelope['message']?.toString() ??
              'The API could not complete this request.',
          traceId: envelope['traceId']?.toString(),
          status: r.statusCode,
          route: route,
        );
      }
      if (route == 'Employee/my-profile' && requestToken != null &&
          requestToken == dio.options.headers['Authorization']) {
        sessionRejected = false;
        onSessionAccessChanged?.call();
      }
      return envelope['data'];
    } on DioException catch (e) {
      dynamic data = e.response?.data;
      if (data is String && data.trim().startsWith('{')) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          final match = RegExp(r'^(\{.*?\})(?=\{|\s*$)').firstMatch(data.trim());
          if (match != null) {
            try {
              data = jsonDecode(match.group(1)!);
            } catch (_) {}
          }
        }
      }
      final json = data is Map ? data : const {};
      final status = e.response?.statusCode;
      final punch = route.contains('Attendance/punch-');
      final visitWrite =
          route == 'MobileVisits/start' || route == 'MobileVisits/finish';
      final retryHelp = punch
          ? 'Please reload attendance screen to verify.'
          : visitWrite
          ? 'Please reload visits screen to verify.'
          : 'Please reload the screen and try again.';
      throw ApiFailure(
        json['errorCode']?.toString() ??
            (status == 401
                ? 'UNAUTHORIZED'
                : e.type == DioExceptionType.connectionTimeout ||
                      e.type == DioExceptionType.receiveTimeout ||
                      e.type == DioExceptionType.sendTimeout
                ? 'CONNECTION_TIMEOUT'
                : status != null
                ? 'HTTP_$status'
                : 'CONNECTION_FAILED'),
        validationMessage(json) ??
            json['message']?.toString() ??
            (status == 401
                ? 'Your session has expired. Please sign in again.'
                : e.type == DioExceptionType.connectionTimeout ||
                      e.type == DioExceptionType.receiveTimeout ||
                      e.type == DioExceptionType.sendTimeout
                ? 'Server response timed out. $retryHelp'
                : status != null
                ? (data is String && data.isNotEmpty && !data.contains('<html') ? data : 'Server returned error ($status). $retryHelp')
                : 'Unable to reach server. $retryHelp'),
        traceId: json['traceId']?.toString() ?? e.response?.headers.value('X-Correlation-ID'),
        status: status,
        route: route,
      );
    }
  }

  static String? validationMessage(Map json) {
    if (json['errorCode'] != 'VALIDATION_ERROR' || json['errors'] is! Map) {
      return null;
    }
    final fields = (json['errors'] as Map).keys
        .map((k) => k.toString().split('.').last.toLowerCase())
        .toSet();
    if (fields.contains('accuracymeters')) {
      return 'GPS accuracy is low. Please enable high accuracy location and refresh in an open area.';
    }
    if (fields.contains('capturedatutc') ||
        fields.contains('latitude') ||
        fields.contains('longitude')) {
      return 'A fresh GPS location is required. Please refresh location and try again.';
    }
    if (fields.contains('attendanceid')) {
      return 'Unable to verify attendance record. Please reload attendance screen and try again.';
    }
    if (fields.contains('officeid')) {
      return 'Unable to verify assigned office. Please contact your administrator.';
    }
    return null;
  }

  Future<Json> login(String username, String password) async =>
      Map<String, dynamic>.from(
        await request(
              'Auth/login',
              body: {
                'username': username.trim(),
                'userPassword': password,
                'clientType': 'mobile',
                ...await currentDevice(),
              },
            )
            as Map,
      );
  Future<Json> currentDevice() async => _device ??= await deviceIdentity();
  Future<Uint8List> attendanceSelfie(String mode, int id, {String? type}) async {
    final normalized = mode.toLowerCase() == 'office' ? 'Office' : 'Field';
    if (id < 1) {
      throw const ApiFailure('SELFIE_NOT_FOUND', 'Selfie not found.');
    }
    final q = (type != null && type.isNotEmpty) ? '?type=$type' : '';
    return privatePhoto('AttendanceSelfies/$normalized/$id$q');
  }

  Future<Uint8List> visitPhoto(int id, {String phase = 'in'}) {
    if (id < 1) throw const ApiFailure('VISIT_NOT_FOUND', 'Visit not found.');
    return privatePhoto('MobileVisits/$id/photo?phase=$phase');
  }

  Future<Json> monthlyGoals({String? month}) async {
    if (!authorized) return <String, dynamic>{};
    final query = month != null && month.isNotEmpty ? '?month=${Uri.encodeQueryComponent(month)}' : '';
    return Map<String,dynamic>.from(await request('MobileVisits/goals$query') as Map);
  }

  Future<Uint8List> privatePhoto(String route) async {
    dio.options.headers['X-Device-ID'] = (await currentDevice())['deviceId'];
    try {
      final response = await dio.get<List<int>>(
        route,
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data!);
    } on DioException catch (e) {
      throw ApiFailure(
        'SELFIE_LOAD_FAILED',
        e.response?.statusCode == 401
            ? 'Your login expired. Sign in again.'
            : 'Unable to load this photo. Check access and retry.',
        status: e.response?.statusCode,
        traceId: e.response?.headers.value('X-Correlation-ID'),
      );
    }
  }

  Future<Json> deviceChange(
    String username,
    String password, {
    String? reason,
  }) async => Map<String, dynamic>.from(
    await request(
          'DeviceBindings/${reason == null ? 'request-status' : 'request-change'}',
          body: {
            'username': username.trim(),
            'userPassword': password,
            'clientType': 'mobile',
            ...await currentDevice(),
            if (reason != null) 'reason': reason,
          },
        )
        as Map,
  );
  Future<List<Json>> offices() async =>
      (await request('WorkforceOffices/mine') as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Future<Json> attendanceProfile() async =>
      Map<String, dynamic>.from(await request('AttendanceProfile/mine') as Map);
  Future<Json> fieldState() async =>
      Map<String, dynamic>.from(await request('FieldAttendance/state') as Map);
  Future<Json> fieldPunch(bool out, Json payload) async =>
      Map<String, dynamic>.from(
        await request(
              'FieldAttendance/${out ? 'punch-out' : 'punch-in'}',
              body: payload,
            )
            as Map,
      );
  Future<Json> state(int officeId) async => Map<String, dynamic>.from(
    await request('OfficeAttendance/state', body: {'officeId': officeId})
        as Map,
  );
  Future<Json> punch(bool out, Json payload) async => Map<String, dynamic>.from(
    await request(
          'OfficeAttendance/${out ? 'punch-out' : 'punch-in'}',
          body: payload,
        )
        as Map,
  );

  Future<Json> myProfile() async =>
      Map<String, dynamic>.from(await request('Employee/my-profile') as Map);

  Future<Json> updateProfileDetails({
    String? name,
    String? mobile,
    String? email,
    String? photoBase64,
  }) async =>
      Map<String, dynamic>.from(
        await request(
              'Employee/update-profile-details',
              body: {
                if (name != null) 'name': name.trim(),
                if (mobile != null) 'mobile': mobile.trim(),
                if (email != null) 'email': email.trim(),
                if (photoBase64 != null) 'photo': photoBase64,
              },
            )
            as Map,
      );

  Future<Json> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async =>
      Map<String, dynamic>.from(
        await request(
              'Employee/change-password',
              body: {
                'oldPassword': oldPassword,
                'newPassword': newPassword,
              },
            )
            as Map,
      );

  Future<List<dynamic>> getHolidays({int? year}) async {
    try {
      final q = year != null ? '?year=$year' : '';
      final res = await request('Holidays$q');
      if (res is List) return res;
      if (res is Map && res['data'] is Map && res['data']['rows'] is List) {
        return res['data']['rows'] as List;
      }
      if (res is Map && res['rows'] is List) {
        return res['rows'] as List;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Json> checkAppVersion(
    String version, {
    String? userId,
    String? deviceModel,
  }) async {
    try {
      final clean = version.startsWith('v') || version.startsWith('V')
          ? version.substring(1)
          : version;
      final params = <String, String>{
        'version': clean,
        if (userId != null && userId.isNotEmpty) 'userId': userId,
        if (deviceModel != null && deviceModel.isNotEmpty)
          'deviceModel': deviceModel,
      };
      final uri = Uri(path: 'AppVersions/check', queryParameters: params);
      final res = await dio.get(uri.toString());
      if (res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
      return {'success': false, 'isAllowed': true};
    } catch (_) {
      return {'success': false, 'isAllowed': true};
    }
  }
}

Json decodeSession(String raw) =>
    Map<String, dynamic>.from(jsonDecode(raw) as Map);
