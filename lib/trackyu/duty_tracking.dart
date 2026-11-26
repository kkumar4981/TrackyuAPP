import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'api.dart';

/// Native foreground service owns encrypted persistence and uploads without Dart.
class DutyTracker {
  static const channel = MethodChannel('trackyu/duty_tracking');
  @visibleForTesting
  static bool? platformOverride;
  static bool get supported =>
      platformOverride ?? (!kIsWeb && Platform.isAndroid);
  static Future<Json> status() async => supported
      ? Map<String, dynamic>.from(
          await channel.invokeMapMethod<String, dynamic>('status') ?? {},
        )
      : {};
  static Future<void> resume({String? userId, String? baseUrl}) async {
    if (!supported) return;
    final saved = await status();
    if ((userId == null || saved['userId'] == userId) &&
        (baseUrl == null || saved['baseUrl'] == baseUrl)) {
      await channel.invokeMethod<void>('resume');
    }
  }

  static Future<void> prepareUser(String userId, String baseUrl) async {
    if (!supported) return;
    final saved = await status();
    if (saved['active'] == true &&
        (saved['userId'] != userId || saved['baseUrl'] != baseUrl)) {
      await stop();
    }
  }

  static int _reconcileGeneration = 0;
  @visibleForTesting
  static int get reconcileGeneration => _reconcileGeneration;
  @visibleForTesting
  static set testReconcileGeneration(int val) => _reconcileGeneration = val;

  static Future<void> stop() async {
    _reconcileGeneration++;
    try {
      if (supported) await channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  static Future<void> sync() async {
    if (supported) await channel.invokeMethod<void>('sync');
  }

  static Future<void> requestFreshFix({
    required String userId,
    required String baseUrl,
  }) async {
    if (!supported) return;
    await channel.invokeMethod<void>('refreshFix', {
      'userId': userId,
      'baseUrl': baseUrl,
    });
  }

  static Future<void> batterySettings({String? package, String? activity}) async {
    if (supported) {
      await channel.invokeMethod<void>('batterySettings', {
        if (package != null && package.isNotEmpty) 'package': package,
        if (activity != null && activity.isNotEmpty) 'activity': activity,
      });
    }
  }

  static Future<void> autostartSettings({String? package, String? activity}) async {
    if (supported) {
      await channel.invokeMethod<void>('autostartSettings', {
        if (package != null && package.isNotEmpty) 'package': package,
        if (activity != null && activity.isNotEmpty) 'activity': activity,
      });
    }
  }

  static Future<Map<String, dynamic>> deviceInfo() async {
    if (!supported) return {};
    try {
      final res = await channel.invokeMapMethod<String, dynamic>('deviceInfo');
      return res != null ? Map<String, dynamic>.from(res) : {};
    } catch (_) {
      return {};
    }
  }

  /// Live tracking health diagnostics including service state, GPS fixes,
  /// permission states, battery exemption, and offline pending queue.
  static Future<Map<String, dynamic>> health() async {
    if (!supported) return {};
    try {
      final res = await channel.invokeMapMethod<String, dynamic>('trackingHealth');
      return res != null ? Map<String, dynamic>.from(res) : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> reconcile(
    TrackyuApi api,
    String mode,
    Json? attendance, {
    String? userId,
  }) async {
    if (!supported) return;
    final gen = ++_reconcileGeneration;
    if (userId != null) await prepareUser(userId, api.baseUrl);
    if (gen != _reconcileGeneration) return;
    final native = await status();
    if (gen != _reconcileGeneration) return;
    if (attendance == null) {
      // No session is only authoritative after a successful state response.
      if (native['active'] == true &&
          native['baseUrl'] == api.baseUrl &&
          (userId == null || native['userId'] == userId)) {
        await stop();
      }
      return;
    }
    final active = attendance['punchOutUtc'] == null;
    if (!active) {
      await stop();
      return;
    }
    final expires = DateTime.tryParse('${native['expiresAtUtc']}');
    final same =
        native['baseUrl'] == api.baseUrl &&
        (userId == null || native['userId'] == userId) &&
        native['mode'] == mode &&
        native['attendanceId'] == attendance['id'];
    try {
      final lease = Map<String, dynamic>.from(
        await api.request(
              'DutyTracking/lease',
              body: {'mode': mode, 'attendanceId': attendance['id']},
            )
            as Map,
      );
      if (gen != _reconcileGeneration) return;
      final device = await api.currentDevice();
      if (gen != _reconcileGeneration) return;
      await channel.invokeMethod<void>('configure', {
        'baseUrl': api.baseUrl,
        'userId': lease['userId'],
        'trackingKey': lease['trackingKey'],
        'deviceId': device['deviceId'],
        'mode': mode,
        'attendanceId': attendance['id'],
        'active': active && attendance['punchOutUtc'] == null,
        'expiresAtUtc': lease['expiresAtUtc'],
        'dutyCutoffUtc': lease['dutyCutoffUtc'],
        'serverTimeUtc': lease['serverTimeUtc'],
        'trackingMode': lease['trackingMode'] ?? lease['TrackingMode'] ?? lease['mode'],
        'intervalSeconds': num.tryParse('${lease['intervalSeconds'] ?? lease['IntervalSeconds']}')?.toInt() ?? 300,
        'distanceFilterMeters': num.tryParse('${lease['distanceFilterMeters'] ?? lease['DistanceFilterMeters']}')?.toInt() ?? 100,
        'uploadSeconds': num.tryParse('${lease['uploadSeconds'] ?? lease['UploadSeconds']}')?.toInt() ?? 300,
        'maxAccuracyMeters': num.tryParse('${lease['maxAccuracyMeters'] ?? lease['MaxAccuracyMeters']}')?.toInt() ?? 80,
        'geocodeBreadcrumbs': lease['geocodeBreadcrumbs'] ?? lease['GeocodeBreadcrumbs'] ?? false,
      });
      await sync();
    } catch (_) {
      if (gen != _reconcileGeneration) return;
      // Offline fallback: keep existing tracking active or stop when off-duty
      if (same &&
          '${native['dutyCutoffUtc'] ?? ''}'.isNotEmpty &&
          expires != null &&
          expires.isAfter(DateTime.now().toUtc())) {
        if (active) {
          await resume();
        } else {
          await stop();
        }
        await sync();
        return;
      }
      if (active && attendance['punchOutUtc'] == null) {
        await resume(userId: userId, baseUrl: api.baseUrl);
      } else {
        await stop();
      }
    }
  }

  static Future<List<Json>> route(
    String userId,
    DateTime date, {
    String? baseUrl,
    bool fullResolution = false,
    void Function(List<Json>)? onPage,
    bool Function()? isCancelled,
    int pageSize = 250,
  }) async {
    if (!supported || userId.trim().isEmpty) return [];
    final start = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).subtract(const Duration(minutes: 330));
    final rows = <Json>[];
    var offset = 0;
    do {
      if (isCancelled?.call() == true) break;
      List<dynamic>? result;
      try {
        result = await channel
            .invokeListMethod<dynamic>('route', {
              'userId': userId,
              if (baseUrl != null) 'baseUrl': baseUrl,
              'from': start.millisecondsSinceEpoch,
              'to': start.add(const Duration(days: 1)).millisecondsSinceEpoch,
              if (fullResolution) 'timeline': true,
              if (fullResolution) 'offset': offset,
              if (fullResolution) 'pageSize': pageSize,
            })
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        break;
      }
      if (isCancelled?.call() == true) break;
      final page = (result ?? [])
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      rows.addAll(page);
      onPage?.call(List<Json>.unmodifiable(rows));
      if (!fullResolution || page.length < pageSize) break;
      offset += page.length;
    } while (true);
    return rows;
  }
}
