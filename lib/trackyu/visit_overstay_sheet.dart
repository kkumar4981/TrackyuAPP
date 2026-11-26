import 'dart:async';
import 'package:flutter/material.dart';
import 'controller.dart';
import 'visits.dart';
import 'visit_reconciliation.dart';

class VisitOverstayAlertSheet extends StatelessWidget {
  final TrackyuController controller;
  final Map<String, dynamic> visit;
  final int elapsedMinutes;
  final VoidCallback onSnooze;

  const VisitOverstayAlertSheet({
    super.key,
    required this.controller,
    required this.visit,
    required this.elapsedMinutes,
    required this.onSnooze,
  });

  static bool _isShowing = false;
  static DateTime? _snoozeUntil;

  static bool get isSnoozed {
    if (_snoozeUntil == null) return false;
    return DateTime.now().isBefore(_snoozeUntil!);
  }

  static void snooze([int minutes = 30]) {
    _snoozeUntil = DateTime.now().add(Duration(minutes: minutes));
  }

  static void clearSnooze() {
    _snoozeUntil = null;
  }

  static Future<void> show({
    required BuildContext context,
    required TrackyuController controller,
    required Map<String, dynamic> visit,
    required int elapsedMinutes,
  }) async {
    if (_isShowing || isSnoozed || controller.isVisitClosedOrClosing(visit) ||
        controller.activeVisit == null) return;
    _isShowing = true;
    BuildContext? sheetContext;
    var dismissalQueued = false;
    void closeIfResolved() {
      final active = controller.activeVisit;
      if (active != null && sameVisit(active, visit) && !controller.isVisitClosedOrClosing(visit)) return;
      if (dismissalQueued) return;
      dismissalQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = sheetContext;
        if (ctx != null && ctx.mounted && ModalRoute.of(ctx)?.isCurrent == true) Navigator.of(ctx).pop();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    controller.addListener(closeIfResolved);

    try {
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          sheetContext = ctx;
          closeIfResolved();
          return VisitOverstayAlertSheet(
          controller: controller,
          visit: visit,
          elapsedMinutes: elapsedMinutes,
          onSnooze: () {
            snooze(30);
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.snooze_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('Overstay alert snoozed for 30 minutes.'),
                  ],
                ),
                backgroundColor: Color(0xfff97316),
                duration: Duration(seconds: 4),
              ),
            );
          },
          );
        },
      );
    } finally {
      controller.removeListener(closeIfResolved);
      _isShowing = false;
      // Auto-snooze for at least 30 minutes on ANY close / dismiss to prevent repeated popups
      if (!isSnoozed) {
        snooze(30);
      }
    }
  }

  String _formatHoursMins(int mins) {
    if (mins <= 0) return '0 mins';
    final hrs = mins ~/ 60;
    final remaining = mins % 60;
    if (hrs > 0) {
      return '$hrs hr${hrs > 1 ? 's' : ''} ${remaining > 0 ? '$remaining m' : ''}'.trim();
    }
    return '$mins mins';
  }

  String _formatCheckIn(String? utcStr) {
    if (utcStr == null || utcStr.isEmpty) return '--:--';
    try {
      final dt = DateTime.parse(utcStr).toLocal();
      final hr = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hr:$min $ampm';
    } catch (_) {
      return '--:--';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shopName = visit['shopName']?.toString().trim().isNotEmpty == true
        ? visit['shopName'].toString()
        : (visit['clientName']?.toString().trim().isNotEmpty == true
            ? visit['clientName'].toString()
            : 'Active Visit');
    final checkInStr = _formatCheckIn(visit['checkInUtc']?.toString());
    final elapsedStr = _formatHoursMins(elapsedMinutes);
    final address = (visit['address'] ?? visit['placeName'] ?? '').toString().trim();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff121826) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 30,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // HealthifyMe Top Gradient Accent Bar
            Container(
              height: 5,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                gradient: LinearGradient(
                  colors: [Color(0xfff43f5e), Color(0xfffb923c)],
                ),
              ),
            ),

            // Pull Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xff334155) : const Color(0xffcbd5e1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // HealthifyMe Header Row with Glowing Icon & Live Badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xfff43f5e), Color(0xfffb923c)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xfff43f5e).withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.access_time_filled_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xffffe4e6),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xfffecdd3)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shield_outlined, size: 12, color: Color(0xffe11d48)),
                                  SizedBox(width: 4),
                                  Text(
                                    'LIVE OVERSTAY ALERT',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                      color: Color(0xffe11d48),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Excessive Visit Duration',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: isDark ? Colors.white : const Color(0xff0f172a),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Store Details Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xff1e293b) : const Color(0xfff8fafc),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xff0f172a) : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
                                ),
                              ),
                              child: const Icon(
                                Icons.storefront_rounded,
                                color: Color(0xffea580c),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    shopName,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: isDark ? Colors.white : const Color(0xff0f172a),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Started at $checkInStr',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Elapsed duration pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xffffe4e6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xfffecdd3)),
                              ),
                              child: Text(
                                elapsedStr,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xffe11d48),
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (address.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.place_rounded,
                                size: 14,
                                color: Color(0xff94a3b8),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  address,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 12),

                        // Threshold Warning Banner
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xfffff1f2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xffffe4e6)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xffe11d48)),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Exceeded configured threshold limit of 2 Hours.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xffbe123c),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Action Buttons (Punch Out / Check Out Now)
                  FilledButton(
                    onPressed: () async {
                      snooze(60);
                      Navigator.of(context).pop();
                      final data = VisitsData(controller);
                      await data.load();
                      if (data.active == null || data.rows.any((r) => sameVisit(r, visit) && visitClosed(r))) {
                        controller.clearActiveVisit();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Visit "' + (visit['shopName'] ?? visit['clientName'] ?? 'Store') + '" is already completed and closed.'),
                              backgroundColor: const Color(0xff059669),
                            ),
                          );
                        }
                        return;
                      }
                      if (context.mounted) {
                        final saved = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => VisitForm(data: data, visit: visit),
                          ),
                        );
                        if (saved == true) {
                          controller.clearActiveVisit();
                        }
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      shadowColor: const Color(0xfff43f5e).withValues(alpha: 0.4),
                      backgroundColor: Colors.transparent,
                    ).copyWith(
                      backgroundColor: WidgetStateProperty.all(Colors.transparent),
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xfff43f5e), Color(0xfffb923c)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Check Out & Complete Visit',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Snooze / Still in meeting button
                  OutlinedButton(
                    onPressed: onSnooze,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: BorderSide(
                        color: isDark ? const Color(0xff334155) : const Color(0xffcbd5e1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.snooze_rounded,
                          size: 18,
                          color: isDark ? const Color(0xffcbd5e1) : const Color(0xff475569),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Still in Meeting (+30 min Snooze)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xffcbd5e1) : const Color(0xff475569),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
