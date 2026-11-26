import 'dart:math';
import 'package:flutter/material.dart';
import 'controller.dart';

class MonthlyGoalsCard extends StatefulWidget {
  final TrackyuController controller;
  const MonthlyGoalsCard({super.key, required this.controller});

  @override
  State<MonthlyGoalsCard> createState() => _MonthlyGoalsCardState();
}

class _MonthlyGoalsCardState extends State<MonthlyGoalsCard> {
  @override
  void initState() {
    super.initState();
    widget.controller.refreshGoals();
  }

  void _showGoalsDetailModal(BuildContext context, Map<String, dynamic> data, bool isDark) {
    final monthLabel = data['monthLabel']?.toString() ?? 'This Month';
    final targetVisits = (data['targetVisits'] as num?)?.toInt() ?? 50;
    final completedVisits = (data['completedVisits'] as num?)?.toInt() ?? 0;
    final targetDutyDays = (data['targetDutyDays'] as num?)?.toInt() ?? 24;
    final completedDutyDays = (data['completedDutyDays'] as num?)?.toInt() ?? 0;
    final totalHoursWorked = (data['totalHoursWorked'] as num?)?.toDouble() ?? 0.0;
    final daysRemaining = (data['daysRemaining'] as num?)?.toInt() ?? 15;
    final dailyRunRate = (data['dailyVisitsRunRate'] as num?)?.toDouble() ?? 1.5;
    final headline = data['statusHeadline']?.toString() ?? 'Keep Pushing! 🚀';
    final motivation = data['motivationMessage']?.toString() ?? '';
    final badge = data['badgeName']?.toString() ?? 'Rising Star 🌟';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xff0b0f19) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).padding.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xff334155) : const Color(0xffcbd5e1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xff8b5cf6), Color(0xff6366f1)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.stars_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Performance & Monthly Goals',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : const Color(0xff0f172a),
                          ),
                        ),
                        Text(
                          monthLabel,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: const Color(0xff8b5cf6).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xff8b5cf6).withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xffc084fc),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xff1e1b4b), const Color(0xff172554)]
                        : [const Color(0xffeef2ff), const Color(0xffeff6ff)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? const Color(0xff4338ca) : const Color(0xffc7d2fe),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: isDark ? const Color(0xffe0e7ff) : const Color(0xff3730a3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      motivation,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: isDark ? const Color(0xffcbd5e1) : const Color(0xff475569),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildModalMetricRow(
                'Visits Target',
                '$completedVisits / $targetVisits visits',
                '${max(0, targetVisits - completedVisits)} remaining',
                Icons.storefront_rounded,
                const Color(0xff10b981),
                isDark,
              ),
              const SizedBox(height: 10),
              _buildModalMetricRow(
                'Work Attendance',
                '$completedDutyDays / $targetDutyDays days',
                '${max(0, targetDutyDays - completedDutyDays)} days left',
                Icons.event_available_rounded,
                const Color(0xff0ea5e9),
                isDark,
              ),
              const SizedBox(height: 10),
              _buildModalMetricRow(
                'Work Hours Logged',
                '${totalHoursWorked.toStringAsFixed(1)} hours',
                'Logged via GPS tracking',
                Icons.timer_outlined,
                const Color(0xfff59e0b),
                isDark,
              ),
              const SizedBox(height: 10),
              _buildModalMetricRow(
                'Required Run-Rate',
                '$dailyRunRate visits / day',
                'Over next $daysRemaining days',
                Icons.speed_rounded,
                const Color(0xffec4899),
                isDark,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff6366f1),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Back to Workspace', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalMetricRow(
    String label,
    String primary,
    String secondary,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff131b2e) : const Color(0xfff8fafc),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xff1e293b) : const Color(0xffe2e8f0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  primary,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xff0f172a),
                  ),
                ),
              ],
            ),
          ),
          Text(
            secondary,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final isDark = c.isDarkMode;
    final goals = c.monthlyGoals;

    // Default fallback values if still fetching
    final monthLabel = goals?['monthLabel']?.toString() ?? 'November 2026';
    final targetVisits = (goals?['targetVisits'] as num?)?.toInt() ?? 25;
    final completedVisits = (goals?['completedVisits'] as num?)?.toInt() ?? 0;
    final targetDutyDays = (goals?['targetDutyDays'] as num?)?.toInt() ?? 24;
    final completedDutyDays = (goals?['completedDutyDays'] as num?)?.toInt() ?? 0;
    final totalHours = (goals?['totalHoursWorked'] as num?)?.toDouble() ?? 0.0;
    final visitsNeeded = (goals?['visitsNeeded'] as num?)?.toInt() ?? max(0, targetVisits - completedVisits);
    final visitPct = (goals?['visitProgressPercent'] as num?)?.toDouble() ?? (targetVisits > 0 ? (completedVisits / targetVisits * 100).clamp(0, 100) : 0.0);
    final headline = goals?['statusHeadline']?.toString() ?? 'Daily Target Tracker 🎯';
    final motivation = goals?['motivationMessage']?.toString() ?? 'Complete $targetVisits client visits this month to achieve your target!';
    final badge = goals?['badgeName']?.toString() ?? 'Active Hustler 💼';

    final progressFactor = (visitPct / 100.0).clamp(0.0, 1.0);

    final isLux = c.isLuxuryMode;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _showGoalsDetailModal(context, goals ?? {}, isDark),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: isDark
                ? const LinearGradient(
                    colors: [Color(0xff131b2e), Color(0xff0d1322)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : (isLux
                    ? LinearGradient(
                        colors: c.themeCardGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null),
            color: (isDark || isLux) ? null : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark
                  ? const Color(0xff1e293b)
                  : (isLux ? Colors.white.withValues(alpha: 0.95) : const Color(0xffe2e8f0)),
              width: isLux ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.3)
                    : (isLux
                        ? c.themePrimaryColor.withValues(alpha: 0.08)
                        : const Color(0xff6366f1).withValues(alpha: 0.06)),
                blurRadius: 18,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Title & Badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [c.themePrimaryColor, c.themeSecondaryColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xff6366f1).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monthly Goals',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: isDark ? Colors.white : const Color(0xff0f172a),
                          ),
                          maxLines: 1,
                        ),
                        Text(
                          monthLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    fit: FlexFit.loose,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: c.themePrimaryColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.themePrimaryColor.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isDark ? const Color(0xffa78bfa) : c.themePrimaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Progress Bar Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Client Visits Target',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? const Color(0xffcbd5e1) : const Color(0xff334155),
                    ),
                  ),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xff0f172a),
                      ),
                      children: [
                        TextSpan(
                          text: '$completedVisits',
                          style: const TextStyle(color: Color(0xff10b981)),
                        ),
                        TextSpan(
                          text: ' / $targetVisits (${visitPct.toStringAsFixed(0)}%)',
                          style: TextStyle(
                            color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Visual Progress Bar
              Stack(
                children: [
                  Container(
                    height: 9,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xff1e293b) : const Color(0xffe2e8f0),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progressFactor,
                    child: Container(
                      height: 9,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xff06b6d4), Color(0xff10b981)],
                        ),
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xff10b981).withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    visitsNeeded > 0
                        ? '$visitsNeeded visits left to reach goal'
                        : '🎉 100% Target Crushed!',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: visitsNeeded > 0
                          ? (isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7))
                          : const Color(0xff10b981),
                    ),
                  ),
                  Text(
                    'Details →',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 3 Mini Stat Pills
              Row(
                children: [
                  Expanded(
                    child: _buildMiniStat(
                      'Visits Done',
                      '$completedVisits',
                      Icons.storefront_rounded,
                      const Color(0xff10b981),
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMiniStat(
                      'Work Days',
                      '$completedDutyDays / $targetDutyDays',
                      Icons.event_available_rounded,
                      const Color(0xff0ea5e9),
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMiniStat(
                      'Hours Logged',
                      '${totalHours.toStringAsFixed(1)}h',
                      Icons.timer_outlined,
                      const Color(0xfff59e0b),
                      isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Motivation Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xff172554).withValues(alpha: 0.6), const Color(0xff1e1b4b).withValues(alpha: 0.6)]
                        : [c.themePrimaryColor.withValues(alpha: 0.08), c.themeSecondaryColor.withValues(alpha: 0.12)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xff2563eb).withValues(alpha: 0.4) : c.themePrimaryColor.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.rocket_launch_rounded, size: 16, color: Color(0xff38bdf8)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headline,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: isDark ? const Color(0xff93c5fd) : const Color(0xff1e40af),
                            ),
                          ),
                          Text(
                            motivation,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              height: 1.3,
                              color: isDark ? const Color(0xffcbd5e1) : const Color(0xff475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xff0b0f19)
            : (widget.controller.isLuxuryMode
                ? Colors.white.withValues(alpha: 0.8)
                : const Color(0xfff8fafc)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? const Color(0xff1e293b)
              : (widget.controller.isLuxuryMode
                  ? widget.controller.themePrimaryColor.withValues(alpha: 0.15)
                  : const Color(0xffe2e8f0)),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
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
