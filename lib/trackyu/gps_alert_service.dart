import 'local_inbox.dart';
import 'dart:async';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'controller.dart';
import 'visit_overstay_sheet.dart';

class GpsAlertService {
  GpsAlertService._();
  static final GpsAlertService instance = GpsAlertService._();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _isGpsOff = false;
  bool _dialogShowing = false;
  DateTime? _lastAlertTime;

  TrackyuController? _controller;
  BuildContext? Function()? _contextProvider;
  StreamSubscription<ServiceStatus>? _statusSub;
  Timer? _periodicCheck;

  static const int gpsAlertNotificationId = 9001;
  static const String channelId = 'trackyu_gps_alert';
  static const String channelName = 'GPS & Location Alerts';

  static const int overstayAlertNotificationId = 9002;
  static const String overstayChannelId = 'trackyu_visit_overstay';
  static const String overstayChannelName = 'Visit Duration & Overstay Alerts';
  DateTime? _lastOverstayAlertTime;

  Future<void> _initNotifications() async {
    if (_initialized) return;
    try {
      const androidSettings = AndroidInitializationSettings('ic_stat_notification');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);

      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          // When notification is clicked, bring up reason dialog or overstay sheet
          final ctx = _contextProvider?.call();
          if (ctx != null && _controller != null) {
            if (response.id == overstayAlertNotificationId) {
              _triggerOverstaySheet(ctx);
            } else {
              showReasonDialog(ctx);
            }
          }
        },
      );

      // Create Android Notification Channel with high importance
      if (!kIsWeb && Platform.isAndroid) {
        final androidPlugin = _notifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          await androidPlugin.createNotificationChannel(
            const AndroidNotificationChannel(
              channelId,
              channelName,
              description: 'Urgent alerts when GPS is disabled during work shifts',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          );
          await androidPlugin.createNotificationChannel(
            const AndroidNotificationChannel(
              overstayChannelId,
              overstayChannelName,
              description: 'Urgent alerts when a customer or store visit exceeds expected duration',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          );
          await androidPlugin.requestNotificationsPermission();
        }
      }
      _initialized = true;
    } catch (e) {
      debugPrint('[GpsAlertService] init error: $e');
    }
  }

  void start({
    required TrackyuController controller,
    required BuildContext? Function() contextProvider,
  }) {
    _controller?.removeListener(_onVisitChanged);
    _controller = controller;
    controller.addListener(_onVisitChanged);
    _contextProvider = contextProvider;
    unawaited(_initNotifications());

    _statusSub?.cancel();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      _statusSub = Geolocator.getServiceStatusStream().listen((status) {
        if (status == ServiceStatus.disabled) {
          _handleGpsDisabled();
        } else if (status == ServiceStatus.enabled) {
          _handleGpsEnabled();
        }
      });
    }

    _periodicCheck?.cancel();
    _periodicCheck = Timer.periodic(const Duration(seconds: 8), (_) async {
      final c = _controller;
      if (c == null || !c.loggedIn) return;
      // Only monitor when logged in and actively on duty or checked in today
      final isDutyActive = c.onDuty || (c.attendance != null && !c.completed);
      if (!isDutyActive) return;

      try {
        final enabled = await Geolocator.isLocationServiceEnabled();
        if (!enabled) {
          _handleGpsDisabled();
        } else if (_isGpsOff) {
          _handleGpsEnabled();
        }
        await _checkVisitOverstay();
      } catch (_) {}
    });
  }

  void _onVisitChanged() {
    final c = _controller;
    if (c == null || c.activeVisit == null || !c.onDuty) {
      _lastOverstayAlertTime = null;
      unawaited(_notifications.cancel(overstayAlertNotificationId).catchError((_) {}));
    }
  }

  void stop() {
    _controller?.removeListener(_onVisitChanged);
    _statusSub?.cancel();
    _statusSub = null;
    _periodicCheck?.cancel();
    _periodicCheck = null;
  }

  Future<void> _handleGpsDisabled() async {
    final c = _controller;
    if (c == null || !c.loggedIn) return;
    final isDutyActive = c.onDuty || (c.attendance != null && !c.completed);
    if (!isDutyActive) return;

    final now = DateTime.now();
    final isFirstOff = !_isGpsOff;
    _isGpsOff = true;

    // Show system notification immediately
    if (isFirstOff || _lastAlertTime == null || now.difference(_lastAlertTime!).inMinutes >= 2) {
      _lastAlertTime = now;
      await _showGpsDisabledNotification();

      // Log event to backend with OFF status
      unawaited(_reportGpsEvent(
        eventType: 'OFF',
        reason: 'GPS turned off on device during active work shift',
      ));
    }

    // Trigger in-app alert dialog if app is in foreground
    final ctx = _contextProvider?.call();
    if (ctx != null && !_dialogShowing) {
      showReasonDialog(ctx);
    }
  }

  Future<void> _handleGpsEnabled() async {
    if (!_isGpsOff) return;
    _isGpsOff = false;

    // Cancel the persistent warning notification
    try {
      await _notifications.cancel(gpsAlertNotificationId);
    } catch (_) {}

    // Report ON event to backend
    unawaited(_reportGpsEvent(
      eventType: 'ON',
      reason: 'GPS restored by user',
    ));

    // Show quick feedback in app
    final ctx = _contextProvider?.call();
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('GPS restored. Location tracking resumed.'),
            ],
          ),
          backgroundColor: Color(0xff16a34a),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _showGpsDisabledNotification() async {
    try {
      const androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Alerts when GPS is turned off during work shifts',
        importance: Importance.max,
        priority: Priority.high,
        ongoing: true,
        autoCancel: false,
        icon: 'ic_stat_notification',
        color: Color(0xffef4444),
        ticker: 'GPS Disabled Warning',
      );
      const notifDetails = NotificationDetails(android: androidDetails);

      await _notifications.show(
        gpsAlertNotificationId,
        '⚠️ GPS Disabled Alert',
        'GPS was turned off during your active shift. Tap to submit reason or re-enable GPS immediately.',
        notifDetails,
      );
      unawaited(LocalInboxStorage.addNotification(
        title: '⚠️ GPS Disabled Alert',
        message: 'GPS was turned off during your active shift. Tap to submit reason or re-enable GPS.',
        kind: 'GPS_TAMPERING',
      ));
    } catch (e) {
      debugPrint('[GpsAlertService] notification error: $e');
    }
  }

  Future<void> _reportGpsEvent({
    required String eventType, // 'OFF', 'ON', 'REASON'
    required String reason,
  }) async {
    final c = _controller;
    if (c == null || !c.loggedIn) return;

    try {
      int? battery;
      try {
        battery = await Battery().batteryLevel;
      } catch (_) {}

      String? model;
      try {
        if (!kIsWeb && Platform.isAndroid) {
          final info = await DeviceInfoPlugin().androidInfo;
          model = '${info.brand} ${info.model}';
        }
      } catch (_) {}

      final lastLoc = c.lastLocation;
      final attId = c.attendance?['id'] ?? c.attendance?['attendanceId'];
      await c.api.dio.post(
        'NotificationRules/tampering/log',
        data: {
          'UserId': c.employeeId,
          'AttendanceId': attId,
          'EventType': eventType,
          'Reason': reason,
          'BatteryLevel': battery,
          'Latitude': (lastLoc?['latitude'] as num?)?.toDouble(),
          'Longitude': (lastLoc?['longitude'] as num?)?.toDouble(),
          'DeviceModel': model ?? 'Mobile',
        },
      );
    } catch (e) {
      debugPrint('[GpsAlertService] report error: $e');
    }
  }

  Future<void> _checkVisitOverstay() async {
    final c = _controller;
    if (c == null || !c.loggedIn) return;
    final active = c.activeVisit;
    if (active == null) {
      _notifications.cancel(overstayAlertNotificationId).catchError((_) {});
      return;
    }

    final inUtcStr = active['checkInUtc']?.toString();
    if (inUtcStr == null || inUtcStr.isEmpty) return;
    final inTime = DateTime.tryParse(inUtcStr)?.toUtc();
    if (inTime == null) return;

    final elapsedMins = DateTime.now().toUtc().difference(inTime).inMinutes;
    if (elapsedMins < 120) return;

    if (VisitOverstayAlertSheet.isSnoozed) return;
    try { await c.reconcileServerWorkspace(); } catch (_) {}
    final current = c.activeVisit;
    if (current == null || c.isVisitClosedOrClosing(active) ||
        '${current['id']}' != '${active['id']}') return;

    final now = DateTime.now();
    if (_lastOverstayAlertTime == null || now.difference(_lastOverstayAlertTime!).inMinutes >= 30) {
      _lastOverstayAlertTime = now;
      unawaited(_showOverstayNotification(active, elapsedMins));

      final ctx = _contextProvider?.call();
      if (ctx != null && ctx.mounted) {
        VisitOverstayAlertSheet.show(
          context: ctx,
          controller: c,
          visit: active,
          elapsedMinutes: elapsedMins,
        );
      }
    }
  }

  void _triggerOverstaySheet(BuildContext ctx) {
    final c = _controller;
    if (c == null) return;
    final active = c.activeVisit;
    if (active == null) return;
    final inUtcStr = active['checkInUtc']?.toString();
    final inTime = inUtcStr != null ? DateTime.tryParse(inUtcStr)?.toUtc() : null;
    final elapsedMins = inTime != null ? DateTime.now().toUtc().difference(inTime).inMinutes : 120;
    VisitOverstayAlertSheet.show(
      context: ctx,
      controller: c,
      visit: active,
      elapsedMinutes: elapsedMins,
    );
  }

  Future<void> _showOverstayNotification(Map<String, dynamic> visit, int elapsedMinutes) async {
    try {
      final shopName = visit['shopName'] ?? visit['clientName'] ?? 'Customer Visit';
      final hrs = elapsedMinutes ~/ 60;
      final mins = elapsedMinutes % 60;
      final durStr = '$hrs hr${hrs > 1 ? 's' : ''} ${mins > 0 ? '$mins m' : ''}'.trim();

      const androidDetails = AndroidNotificationDetails(
        overstayChannelId,
        overstayChannelName,
        channelDescription: 'Alerts when a visit duration exceeds 2 hours',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        color: Color(0xfff43f5e),
      );

      const notifDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _notifications.show(
        overstayAlertNotificationId,
        '⏰ Overstay Alert • $shopName',
        'Active visit has been in progress for $durStr (Threshold: 2 Hours). Tap to punch out or snooze.',
        notifDetails,
      );
      unawaited(LocalInboxStorage.addNotification(
        title: '⏰ Visit Overstay Alert • $shopName',
        message: 'Active visit in progress for $durStr exceeding 2-hour threshold limit.',
        kind: 'OVERSTAY',
      ));
    } catch (e) {
      debugPrint('[GpsAlertService] overstay notif error: $e');
    }
  }

  void showReasonDialog(BuildContext context) {
    if (_dialogShowing) return;
    _dialogShowing = true;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GpsDisabledReasonSheet(
        onSubmitReason: (reason) async {
          await _reportGpsEvent(eventType: 'REASON', reason: reason);
        },
        onTurnOnGps: () async {
          await Geolocator.openLocationSettings();
        },
      ),
    ).then((_) {
      _dialogShowing = false;
    });
  }
}

class GpsDisabledReasonSheet extends StatefulWidget {
  final Future<void> Function(String reason) onSubmitReason;
  final VoidCallback onTurnOnGps;

  const GpsDisabledReasonSheet({
    super.key,
    required this.onSubmitReason,
    required this.onTurnOnGps,
  });

  @override
  State<GpsDisabledReasonSheet> createState() => _GpsDisabledReasonSheetState();
}

class _GpsDisabledReasonSheetState extends State<GpsDisabledReasonSheet> {
  String selectedReason = 'Low battery / Battery saver mode';
  final TextEditingController detailsController = TextEditingController();
  bool submitting = false;

  final List<Map<String, dynamic>> presetReasons = [
    {'title': 'Low battery / Battery saver mode', 'icon': Icons.battery_alert_rounded},
    {'title': 'Phone heating up', 'icon': Icons.thermostat_rounded},
    {'title': 'GPS signal glitch / not fixing', 'icon': Icons.signal_cellular_connected_no_internet_4_bar_rounded},
    {'title': 'Turned off by mistake', 'icon': Icons.touch_app_rounded},
    {'title': 'Personal break / privacy', 'icon': Icons.coffee_rounded},
    {'title': 'Other reason', 'icon': Icons.edit_note_rounded},
  ];

  @override
  void dispose() {
    detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final extra = detailsController.text.trim();
    final fullReason = extra.isNotEmpty ? '$selectedReason — $extra' : selectedReason;

    setState(() => submitting = true);
    try {
      await widget.onSubmitReason(fullReason);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reason submitted to your manager. Please enable GPS as soon as possible.'),
            backgroundColor: Color(0xff2563eb),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(22, 18, 22, 24 + bottomInset),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff161b22) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Warning
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xffef4444).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.location_off_rounded, color: Color(0xffef4444), size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GPS Location Disabled',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xff0f172a),
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Active Work Location Alert',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xffef4444),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Message
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xff1f2937) : const Color(0xfffef2f2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xffef4444).withValues(alpha: 0.2)),
            ),
            child: const Text(
              'Location services are required during your active work shift. Please state the reason for turning off GPS, or turn GPS back on now.',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: Color(0xff991b1b)),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'SELECT REASON FOR TURNING OFF GPS:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Color(0xff64748b),
            ),
          ),
          const SizedBox(height: 10),

          // Reason Options
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: presetReasons.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (ctx, i) {
                final item = presetReasons[i];
                final isSelected = selectedReason == item['title'];
                return InkWell(
                  onTap: () => setState(() => selectedReason = item['title']),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xff2563eb).withValues(alpha: 0.12)
                          : (isDark ? const Color(0xff1e293b) : const Color(0xfff8fafc)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? const Color(0xff2563eb) : (isDark ? const Color(0xff334155) : const Color(0xffe2e8f0)),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          item['icon'] as IconData,
                          size: 18,
                          color: isSelected ? const Color(0xff2563eb) : const Color(0xff64748b),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item['title'] as String,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? const Color(0xff2563eb) : (isDark ? Colors.white : const Color(0xff1e293b)),
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded, color: Color(0xff2563eb), size: 18),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Additional comments textfield
          TextField(
            controller: detailsController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Additional explanation or notes (optional)',
              hintStyle: const TextStyle(fontSize: 12),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),

          // Buttons
          Row(
            children: [
              Expanded(
                flex: 5,
                child: OutlinedButton.icon(
                  onPressed: widget.onTurnOnGps,
                  icon: const Icon(Icons.settings_suggest_rounded, size: 18),
                  label: const Text('Turn On GPS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: const BorderSide(color: Color(0xff16a34a), width: 1.5),
                    foregroundColor: const Color(0xff16a34a),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 6,
                child: FilledButton.icon(
                  onPressed: submitting ? null : _submit,
                  icon: submitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(submitting ? 'Submitting...' : 'Submit Reason', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff2563eb),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
