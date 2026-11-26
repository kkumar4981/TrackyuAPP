import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'user_feedback.dart';
import 'api.dart' show ApiFailure;

/// Single error log record.
class ErrorLogEntry {
  final int? id;
  final DateTime timestamp;
  final String error;
  final String stackTrace;
  final String context;
  final String? userId;

  ErrorLogEntry({
    this.id,
    required this.timestamp,
    required this.error,
    required this.stackTrace,
    required this.context,
    this.userId,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'timestamp': timestamp.toIso8601String(),
    'error': error,
    'stack_trace': stackTrace,
    'context': context,
    'user_id': userId ?? '',
  };

  factory ErrorLogEntry.fromMap(Map<String, dynamic> map) => ErrorLogEntry(
    id: map['id'] as int?,
    timestamp:
        DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
    error: map['error']?.toString() ?? 'Unknown error',
    stackTrace: map['stack_trace']?.toString() ?? '',
    context: map['context']?.toString() ?? 'General',
    userId: map['user_id']?.toString(),
  );

  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.writeln('Time: ${timestamp.toLocal()}');
    buffer.writeln('Context: $context');
    if (userId != null && userId!.isNotEmpty) {
      buffer.writeln('User: $userId');
    }
    buffer.writeln('Error: $error');
    if (stackTrace.isNotEmpty) {
      buffer.writeln('Stack Trace:\n$stackTrace');
    }
    return buffer.toString();
  }
}

/// Centralized crash catcher & SQLite error logger.
/// Prevents unhandled exceptions from tearing down the application,
/// writes error records to local SQLite database, and exposes an on-screen
/// notification and inspection UI.
class ErrorLogger {
  static Database? _db;
  static bool _initialized = false;
  static bool _handlersInstalled = false;
  static void installHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;
    _setupGlobalHandlers();
  }

  static final List<ErrorLogEntry> recentLogs = [];
  static final ValueNotifier<ErrorLogEntry?> latestError =
      ValueNotifier<ErrorLogEntry?>(null);
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Global current user context for logs
  static String? currentUserId;

  static bool get isTestEnvironment =>
      Platform.environment.containsKey('FLUTTER_TEST');

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Setup global Flutter error handlers
    installHandlers();

    // 2. Open SQLite database safely
    try {
      if (!kIsWeb && !isTestEnvironment) {
        final dir = await getApplicationDocumentsDirectory();
        final dbPath = p.join(dir.path, 'trackyu_errors.db');
        _db = await openDatabase(
          dbPath,
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS error_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                error TEXT NOT NULL,
                stack_trace TEXT,
                context TEXT,
                user_id TEXT
              )
            ''');
          },
        );
        await _loadRecentFromDb();
      }
    } catch (e) {
      debugPrint('[ErrorLogger] SQLite init skipped or failed: $e');
    }
  }

  static void _setupGlobalHandlers() {
    if (isTestEnvironment) return;
    // Intercept all Flutter widget framework errors
    final originalFlutterOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      record(
        details.exception,
        details.stack ?? StackTrace.current,
        context:
            'Flutter: ${details.library ?? details.context?.toString() ?? "UI"}',
      );
      originalFlutterOnError?.call(details);
    };

    // Intercept all unhandled platform/async Dart errors
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      record(error, stack, context: 'Async / PlatformDispatcher');
      return true; // Mark as handled so process doesn't terminate
    };

    // Replace the red/grey screen of death with a graceful recoverable card
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        color: const Color(0xfffff1f2),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xffe11d48),
                    size: 36,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Widget rendering error',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xff9f1239),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    details.exception.toString(),
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xff475569),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xffe11d48),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(
                              text: '${details.exception}\n${details.stack}',
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy error details'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    };
  }

  static Future<void> _loadRecentFromDb() async {
    if (_db == null) return;
    try {
      final rows = await _db!.query(
        'error_logs',
        orderBy: 'id DESC',
        limit: 50,
      );
      recentLogs.clear();
      for (final r in rows) {
        recentLogs.add(ErrorLogEntry.fromMap(r));
      }
    } catch (_) {}
  }

  /// Records an error in SQLite database and in memory, and triggers on-screen alert.
  static Future<void> record(
    dynamic error,
    dynamic stackTrace, {
    String? context,
    String? userId,
    bool notifyUser = false,
  }) async {
    // User input/auth/permission conflicts are not app crashes.
    if(error is ApiFailure && [400,401,403,409,422].contains(error.status)) return;
    final diagnosticStack = error is ApiFailure
      ? '${error.diagnosticMetadata.entries.map((e)=>'${e.key}=${e.value}').join(' ')}\n${stackTrace ?? ''}'
      : stackTrace?.toString() ?? '';
    final strErr = error?.toString() ?? '';
    final strCtx = context ?? '';
    final lowerErr = strErr.toLowerCase();
    final lowerCtx = strCtx.toLowerCase();
    if (lowerCtx.contains('image resource service') ||
        lowerCtx.contains('image') ||
        lowerErr.contains('tourimages') ||
        (lowerErr.contains('statuscode: 503') && lowerErr.contains('http')) ||
        (lowerErr.contains('statuscode: 502') && lowerErr.contains('http')) ||
        (lowerErr.contains('statuscode: 504') && lowerErr.contains('http')) ||
        (lowerErr.contains('statuscode: 404') && lowerErr.contains('http'))) {
      // Suppress routine transient image load failures during backend deploy/restart
      return;
    }
    if (!kIsWeb &&
        !isTestEnvironment &&
        defaultTargetPlatform == TargetPlatform.android) {
      // Native journal persists even before the Dart SQLite logger is ready.
      // Never forward exception messages: codec errors can contain entire GPS payloads.
      unawaited(
        const MethodChannel('trackyu/duty_tracking')
            .invokeMethod<void>('diagnostic', {
              'errorType': error is ApiFailure ? 'API_${error.diagnosticMetadata['code']?.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}' : error.runtimeType.toString(),
              'stack': diagnosticStack,
              'context': context ?? 'Flutter',
            })
            .catchError((Object _) {}),
      );
    }
    final entry = ErrorLogEntry(
      timestamp: DateTime.now(),
      error: error?.toString() ?? 'Unknown error',
      stackTrace: stackTrace?.toString() ?? '',
      context: context ?? 'General',
      userId: userId ?? currentUserId,
    );

    debugPrint('[ErrorLogger] ${entry.context}: ${entry.error}');

    // 1. In-memory storage (always works even without DB)
    recentLogs.insert(0, entry);
    if (recentLogs.length > 100) {
      recentLogs.removeLast();
    }

    // 2. Persistent SQLite storage
    if (_db != null && _db!.isOpen) {
      try {
        await _db!.insert('error_logs', entry.toMap());

        // Rolling trim: keep last 200 logs
        await _db!.rawDelete('''
          DELETE FROM error_logs WHERE id NOT IN (
            SELECT id FROM error_logs ORDER BY id DESC LIMIT 200
          )
        ''');
      } catch (e) {
        debugPrint('[ErrorLogger] Failed to write error to DB: $e');
      }
    }

    // 3. Show non-intrusive on-screen notice if messenger is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      latestError.value = entry;
      if (notifyUser) _showOnScreenNotice(entry);
    });
  }

  static void _showOnScreenNotice(ErrorLogEntry entry) {
    // Avoid double alerts if showFailure is already displaying an AlertDialog
    if (entry.context == 'showFailure') return;
    // Suppress minor pixel layout overflows and auth expiration from showing disturbing red on-screen banner
    final lowerErr = entry.error.toLowerCase();
    final lowerCtx = entry.context.toLowerCase();
    if (lowerErr.contains('overflowed') ||
        lowerCtx.contains('renderflex') ||
        lowerErr.contains('renderflex') ||
        lowerCtx.contains('image resource service') ||
        lowerCtx.contains('image') ||
        lowerErr.contains('http request failed') ||
        lowerErr.contains('statuscode: 503') ||
        lowerErr.contains('statuscode: 502') ||
        lowerErr.contains('statuscode: 504') ||
        lowerErr.contains('statuscode: 500') ||
        lowerErr.contains('statuscode: 404') ||
        lowerErr.contains('imagecodecexception') ||
        lowerErr.contains('failed to decode image') ||
        lowerErr.contains('login token') ||
        lowerErr.contains('unauthorized') ||
        lowerErr.contains('login expired') ||
        lowerErr.contains('socketexception') ||
        lowerErr.contains('failed host lookup') ||
        lowerErr.contains('handshakeexception') ||
        lowerErr.contains('timeoutexception') ||
        lowerErr.contains('clientexception') ||
        lowerErr.contains('network is unreachable') ||
        lowerErr.contains('connection refused') ||
        lowerErr.contains('connection timed out')) {
      return;
    }
    try {
      final messenger = messengerKey.currentState;
      if (messenger != null) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xff1e293b),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 4),
            content: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xff38bdf8),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    userFriendlyErrorMessage(entry.error),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (_) {}
  }

  static Future<List<ErrorLogEntry>> getAll() async {
    if (_db != null && _db!.isOpen) {
      try {
        final rows = await _db!.query('error_logs', orderBy: 'id DESC');
        return rows.map((r) => ErrorLogEntry.fromMap(r)).toList();
      } catch (_) {}
    }
    return List<ErrorLogEntry>.from(recentLogs);
  }

  static Future<void> delete(int? id) async {
    if (id != null) {
      recentLogs.removeWhere((l) => l.id == id);
      if (_db != null && _db!.isOpen) {
        try {
          await _db!.delete('error_logs', where: 'id = ?', whereArgs: [id]);
        } catch (_) {}
      }
    }
  }

  static Future<void> clear() async {
    recentLogs.clear();
    latestError.value = null;
    if (_db != null && _db!.isOpen) {
      try {
        await _db!.delete('error_logs');
      } catch (_) {}
    }
  }
}

/// Dialog presenting comprehensive error details with copy action.
class ErrorDetailsDialog extends StatelessWidget {
  final ErrorLogEntry entry;
  const ErrorDetailsDialog({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? const Color(0xff0f172a) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xff450a0a) : const Color(0xfffee2e2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.bug_report_rounded,
              color: isDark ? const Color(0xfff87171) : const Color(0xffb91c1c),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Error Details',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xff0f172a),
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xff1e293b) : const Color(0xfff8fafc),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Time: ',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Context: ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xfff1f5f9) : const Color(0xff0f172a),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Message:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xffe2e8f0) : const Color(0xff0f172a),
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                userFriendlyErrorMessage(entry.error),
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xfff87171) : const Color(0xffb91c1c),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (entry.stackTrace.isNotEmpty) ...[
                const SizedBox(height: 12),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text(
                      'Technical Details (For IT / Admin)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                      ),
                    ),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xff020617) : const Color(0xff0f172a),
                          borderRadius: BorderRadius.circular(8),
                          border: isDark ? Border.all(color: const Color(0xff334155)) : null,
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            entry.stackTrace,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: Color(0xfff8fafc),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy Details'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: entry.toFormattedString()));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error details copied to clipboard!'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Full screen log inspector page.
class ErrorLogsPage extends StatefulWidget {
  const ErrorLogsPage({super.key});

  @override
  State<ErrorLogsPage> createState() => _ErrorLogsPageState();
}

class _ErrorLogsPageState extends State<ErrorLogsPage> {
  List<ErrorLogEntry> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final logs = await ErrorLogger.getAll();
    if (mounted) {
      setState(() {
        _logs = logs;
        _loading = false;
      });
    }
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${local.day} ${months[local.month - 1]}, $hour:$minute:$second $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Error Logs'),
        actions: [
          IconButton(
            tooltip: 'Copy all logs',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: _logs.isEmpty
                ? null
                : () {
                    final allText = _logs
                        .map((l) => l.toFormattedString())
                        .join('\n---\n');
                    Clipboard.setData(ClipboardData(text: allText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${_logs.length} error logs copied!'),
                      ),
                    );
                  },
          ),
          IconButton(
            tooltip: 'Clear logs',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _logs.isEmpty
                ? null
                : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear All Error Logs?'),
                        content: const Text(
                          'Are you sure you want to delete all recorded error logs?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Clear All'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ErrorLogger.clear();
                      await _load();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('All error logs cleared!')),
                        );
                      }
                    }
                  },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 48,
                    color: Colors.green.shade400,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No errors recorded!',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'All operations running smoothly.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _logs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = _logs[index];
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Card(
                  elevation: 0,
                  color: isDark ? const Color(0xff1e293b) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => ErrorDetailsDialog(entry: item),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xff450a0a) : const Color(0xfffee2e2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.context,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? const Color(0xfff87171) : const Color(0xffb91c1c),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _formatDateTime(item.timestamp),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () async {
                                  await ErrorLogger.delete(item.id);
                                  await _load();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.error,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xfff1f5f9) : const Color(0xff0f172a),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                'Tap to view stack trace & copy',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? const Color(0xff60a5fa) : const Color(0xff2563eb),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 14,
                                color: isDark ? const Color(0xff60a5fa) : const Color(0xff2563eb),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
