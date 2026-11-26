import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'api.dart';

/// Native SQLite transaction commits both the visible record and its outbox item.
/// Network acknowledgement never deletes the local record.
class LocalWorkspace {
  static const channel = MethodChannel('trackyu/duty_tracking');
  static bool get available => !kIsWeb && Platform.isAndroid;
  String scope = '';
  static String day(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  Future<void> configure(TrackyuApi api, String user, String token) async {
    scope = '${api.baseUrl}|$user';
    final device = await api.currentDevice();
    await channel.invokeMethod('localAuth', {
      'scope': scope,
      'baseUrl': api.baseUrl,
      'userId': user,
      'token': token,
      'deviceId': device['deviceId'],
    });
  }

  Future<Json?> read(String key) async {
    final result = await channel.invokeMapMethod<String, dynamic>('localRead', {
      'scope': scope,
      'key': key,
    });
    return result == null ? null : Map<String, dynamic>.from(result);
  }

  Future<Json?> readSummary(String key) async {
    if (!available) return read(key);
    final result = await channel.invokeMapMethod<String, dynamic>(
      'localReadSummary',
      {'scope': scope, 'key': key},
    );
    return result == null ? null : Map<String, dynamic>.from(result);
  }

  Future<void> write(String key, Json value) => channel.invokeMethod<void>(
    'localWrite',
    {'scope': scope, 'key': key, 'value': value},
  );
  Future<void> commit(String key, Json value, Json operation) =>
      channel.invokeMethod<void>('localCommit', {
        'scope': scope,
        'key': key,
        'value': value,
        'operation': operation,
      });
  Future<Json> syncState() async => Map<String, dynamic>.from(
    await channel.invokeMapMethod<String, dynamic>('localSyncState', {
          'scope': scope,
        }) ??
        {},
  );
  Future<void> sync() => channel.invokeMethod<void>('sync');
  Future<void> unblock() =>
      channel.invokeMethod<void>('localUnblock', {'scope': scope});
  Future<void> pause() =>
      channel.invokeMethod<void>('localPause', {'scope': scope});
  Future<void> offlineTracking(Json value) =>
      channel.invokeMethod<void>('configureOffline', value);
}
