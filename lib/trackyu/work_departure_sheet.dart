import 'dart:math';
import 'package:flutter/material.dart';
import 'controller.dart';

Future<String?> showWorkOutDepartureSheet({
  required BuildContext context,
  required TrackyuController controller,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => WorkOutDepartureSheet(controller: controller),
  );
}

class WorkOutDepartureSheet extends StatelessWidget {
  final TrackyuController controller;

  const WorkOutDepartureSheet({
    super.key,
    required this.controller,
  });

  String _formatTime(dynamic raw) {
    if (raw == null) return '--:--';
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return '--:--';
    final local = dt.toLocal();
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$h12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final duration = controller.workingDuration ?? Duration.zero;
    final hours = duration.inHours;
    final mins = duration.inMinutes.remainder(60);
    final totalSecs = duration.inSeconds;
    const targetSecs = 9 * 3600; // 9 hours
    final progress = (totalSecs / targetSecs).clamp(0.0, 1.0);
    final isEarly = duration < const Duration(hours: 9);

    final remMinsTotal = max(0, (9 * 60) - duration.inMinutes);
    final remHours = remMinsTotal ~/ 60;
    final remMins = remMinsTotal % 60;
    final remStr = remHours > 0 ? '${remHours}h ${remMins}m' : '${remMins}m';

    final punchInRaw = controller.attendance?['punchInUtc'] ?? controller.attendance?['PunchInUtc'];
    final punchInStr = _formatTime(punchInRaw);

    final goals = controller.monthlyGoals;
    final completedVisits = (goals?['completedVisits'] as num?)?.toInt() ?? 0;

    final activeVisit = controller.activeVisit;
    final shopName = activeVisit != null
        ? (activeVisit['shopName'] ?? activeVisit['clientName'] ?? 'Ongoing Shop')
        : null;

    final bgColor = isDark ? const Color(0xff0f172a) : Colors.white;
    final cardBg = isDark ? const Color(0xff1e293b) : const Color(0xfff8fafc);
    final borderCol = isDark ? const Color(0xff334155) : const Color(0xffe2e8f0);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
            blurRadius: 30,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xff475569) : const Color(0xffcbd5e1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Hero Header Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isEarly
                        ? (isDark
                            ? [const Color(0xff451a03), const Color(0xff291002)]
                            : [const Color(0xfffff7ed), const Color(0xffffedd5)])
                        : (isDark
                            ? [const Color(0xff064e3b), const Color(0xff022c22)]
                            : [const Color(0xffecfdf5), const Color(0xffd1fae5)]),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isEarly
                        ? (isDark ? const Color(0xfff97316).withValues(alpha: 0.4) : const Color(0xfffed7aa))
                        : (isDark ? const Color(0xff10b981).withValues(alpha: 0.4) : const Color(0xffa7f3d0)),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: isEarly
                            ? const Color(0xffea580c)
                            : const Color(0xff059669),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: (isEarly ? const Color(0xffea580c) : const Color(0xff059669)).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        isEarly ? Icons.timer_outlined : Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                isEarly ? 'Early Work Departure' : 'Complete Work Shift',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: isDark ? Colors.white : const Color(0xff0f172a),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: isEarly
                                      ? (isDark ? const Color(0xff9a3412) : const Color(0xffea580c))
                                      : const Color(0xff059669),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isEarly ? 'EARLY' : 'FULL SHIFT',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isEarly
                                ? 'Standard workday requirement is 9h 00m'
                                : 'Standard 9h workday completed successfully',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Shift Progress & Time Indicator
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderCol),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Work Progress Today',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xff0f172a),
                          ),
                        ),
                        Text(
                          '${(progress * 100).toInt()}% completed',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: isEarly
                                ? const Color(0xffea580c)
                                : const Color(0xff059669),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isEarly ? const Color(0xffea580c) : const Color(0xff10b981),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _metricPill(
                          isDark: isDark,
                          label: 'LOGGED WORK',
                          value: '${hours}h ${mins}m',
                          color: isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7),
                        ),
                        _metricPill(
                          isDark: isDark,
                          label: 'STANDARD GOAL',
                          value: '9h 00m',
                          color: isDark ? const Color(0xffa78bfa) : const Color(0xff7c3aed),
                        ),
                        _metricPill(
                          isDark: isDark,
                          label: isEarly ? 'REMAINING' : 'OVERTIME',
                          value: isEarly ? remStr : '+${hours - 9}h ${mins}m',
                          color: isEarly ? const Color(0xfff43f5e) : const Color(0xff10b981),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Workday Accomplishments Row (3 Stats)
              Row(
                children: [
                  Expanded(
                    child: _statCard(
                      isDark: isDark,
                      cardBg: cardBg,
                      borderCol: borderCol,
                      icon: Icons.login_rounded,
                      iconColor: const Color(0xff10b981),
                      title: 'Work In Time',
                      value: punchInStr,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statCard(
                      isDark: isDark,
                      cardBg: cardBg,
                      borderCol: borderCol,
                      icon: Icons.storefront_outlined,
                      iconColor: const Color(0xff0284c7),
                      title: 'Client Visits',
                      value: '$completedVisits Done',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statCard(
                      isDark: isDark,
                      cardBg: cardBg,
                      borderCol: borderCol,
                      icon: Icons.alt_route_rounded,
                      iconColor: const Color(0xfff59e0b),
                      title: 'Route GPS',
                      value: 'Recorded',
                    ),
                  ),
                ],
              ),

              // Active Shop Visit Warning Card (if visit is open)
              if (activeVisit != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xfffffbeb),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xfffde68a), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Color(0xffd97706), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Active Shop Visit: $shopName',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Color(0xff92400e),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'You are currently checked into this shop. If you only want to depart this shop, check out below to keep your work session active.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xff78350f),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff0284c7),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          minimumSize: const Size(double.infinity, 38),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(context, 'checkout_visit'),
                        icon: const Icon(Icons.storefront_rounded, size: 16),
                        label: const Text(
                          'Check Out of Shop First (Keep Working)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Early Departure Warning Text
              if (isEarly && activeVisit == null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xff2a1b1b) : const Color(0xfffff1f2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? const Color(0xff881337) : const Color(0xfffecdd3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xffe11d48)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Working Out now logs an Early Departure ($remStr short of 9 hours).',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xfffda4af) : const Color(0xff9f1239),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),

              // Action Buttons
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff0284c7),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text(
                  'Continue Working',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xffdc2626),
                  side: const BorderSide(color: Color(0xfffca5a5), width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                onPressed: () => Navigator.pop(context, 'confirm_work_out'),
                child: Text(
                  isEarly ? 'Confirm Early Work Out' : 'Confirm Work Out & End Shift',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricPill({
    required bool isDark,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required bool isDark,
    required Color cardBg,
    required Color borderCol,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xff0f172a),
            ),
          ),
        ],
      ),
    );
  }
}
