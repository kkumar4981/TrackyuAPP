import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LocalInboxStorage {
  static final List<Map<String, dynamic>> _cache = [];
  static bool _loaded = false;

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/trackyu_local_inbox.json');
  }

  static Future<List<Map<String, dynamic>>> getNotifications() async {
    if (_loaded) return List.from(_cache);
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          _cache.clear();
          _cache.addAll(decoded
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m)));
        }
      }
    } catch (_) {}
    _loaded = true;
    return List.from(_cache);
  }

  static Future<void> addNotification({
    required String title,
    required String message,
    String kind = 'ALERT',
    String? userId,
  }) async {
    try {
      await getNotifications();
      final now = DateTime.now().toUtc();
      
      final existingIndex = _cache.indexWhere((n) =>
          n['title'] == title &&
          n['message'] == message &&
          DateTime.tryParse(n['createdAtUtc']?.toString() ?? '') != null &&
          now.difference(DateTime.parse(n['createdAtUtc'])).inMinutes < 5);
      
      if (existingIndex >= 0) return;

      final newNotice = {
        'id': DateTime.now().millisecondsSinceEpoch,
        'userId': userId ?? 'SELF',
        'kind': kind,
        'title': title,
        'message': message,
        'isRead': false,
        'createdAtUtc': now.toIso8601String(),
      };

      _cache.insert(0, newNotice);
      if (_cache.length > 100) {
        _cache.removeRange(100, _cache.length);
      }
      final file = await _getFile();
      await file.writeAsString(jsonEncode(_cache), flush: true);
    } catch (_) {}
  }

  static Future<void> markRead(dynamic id) async {
    try {
      await getNotifications();
      for (final n in _cache) {
        if (n['id']?.toString() == id?.toString()) {
          n['isRead'] = true;
          n['readAtUtc'] = DateTime.now().toUtc().toIso8601String();
        }
      }
      final file = await _getFile();
      await file.writeAsString(jsonEncode(_cache), flush: true);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      _cache.clear();
      final file = await _getFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
