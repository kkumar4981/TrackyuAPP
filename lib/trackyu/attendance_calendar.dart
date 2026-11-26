import 'package:flutter/material.dart';
import 'api.dart';

class HolidayInfo {
  final int day;
  final String name;
  final bool isOptional;
  const HolidayInfo(this.day, this.name, {this.isOptional = false});
}

/// Known official holidays in India for field workforce
Map<int, List<HolidayInfo>> getHolidaysForYear(int year) {
  return {
    1: [
      const HolidayInfo(1, "New Year's Day"),
      const HolidayInfo(14, 'Makar Sankranti'),
      const HolidayInfo(26, 'Republic Day'),
    ],
    3: [
      const HolidayInfo(25, 'Holi'),
    ],
    4: [
      const HolidayInfo(14, 'Ambedkar Jayanti'),
    ],
    8: [
      const HolidayInfo(15, 'Independence Day'),
      const HolidayInfo(19, 'Raksha Bandhan'),
    ],
    10: [
      const HolidayInfo(2, 'Gandhi Jayanti'),
      const HolidayInfo(20, 'Dussehra'),
    ],
    11: [
      const HolidayInfo(8, 'Diwali'),
      const HolidayInfo(9, 'Govardhan Puja'),
      const HolidayInfo(10, 'Bhai Dooj'),
      const HolidayInfo(24, 'Guru Nanak Jayanti'),
    ],
    12: [
      const HolidayInfo(25, 'Christmas Day'),
    ],
  };
}

/// In-memory cache for dynamic holidays loaded from /api/Holidays (Holiday Master)
class HolidayRepository {
  static final Map<int, Map<int, List<HolidayInfo>>> _dynamicCache = {};
  static final Set<int> _loadingYears = {};
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<HolidayInfo> getHolidays(int year, int month) {
    if (_dynamicCache.containsKey(year) && _dynamicCache[year]!.containsKey(month)) {
      return _dynamicCache[year]![month]!;
    }
    return getHolidaysForYear(year)[month] ?? [];
  }

  static Future<void> syncHolidays(TrackyuApi? api, int year) async {
    if (api == null || _loadingYears.contains(year)) return;
    _loadingYears.add(year);
    try {
      final rows = await api.getHolidays(year: year);
      if (rows.isNotEmpty) {
        final Map<int, List<HolidayInfo>> byMonth = {};
        for (final item in rows) {
          if (item is! Map) continue;
          final dStr = item['holidayDate']?.toString() ?? '';
          final title = item['title']?.toString() ?? '';
          final isOpt = item['isOptional'] == true;
          final dt = DateTime.tryParse(dStr);
          if (dt != null && title.isNotEmpty) {
            byMonth.putIfAbsent(dt.month, () => []).add(HolidayInfo(dt.day, title, isOptional: isOpt));
          }
        }
        _dynamicCache[year] = byMonth;
        revision.value++;
      }
    } catch (_) {
      // offline fallback retained
    } finally {
      _loadingYears.remove(year);
    }
  }
}

class AttendanceCalendarCard extends StatelessWidget {
  final List<Json> rows;
  final DateTime currentMonth;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime?> onDaySelected;
  final String? employeeName;
  final bool isDark;
  final TrackyuApi? api;

  const AttendanceCalendarCard({
    super.key,
    required this.rows,
    required this.currentMonth,
    required this.selectedDay,
    required this.onMonthChanged,
    required this.onDaySelected,
    this.employeeName,
    required this.isDark,
    this.api,
  });

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  static const List<String> _weekdays = [
    'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'
  ];

  String _localTimeOnly(dynamic raw) {
    if (raw == null) return '-';
    final str = raw.toString().trim();
    if (str.isEmpty || str == '—' || str == '-') return '-';
    final date = DateTime.tryParse(str)?.toLocal();
    if (date == null) return str;
    final hourNum = date.hour;
    final period = hourNum >= 12 ? 'PM' : 'AM';
    final hour = hourNum == 0 ? 12 : (hourNum > 12 ? hourNum - 12 : hourNum);
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  Json? _findRecordForDay(DateTime day) {
    for (final row in rows) {
      final raw = row['workDate'];
      if (raw == null) continue;
      DateTime? dt;
      if (raw is DateTime) {
        dt = raw;
      } else {
        dt = DateTime.tryParse(raw.toString());
      }
      if (dt != null && dt.year == day.year && dt.month == day.month && dt.day == day.day) {
        return row;
      }
    }
    return null;
  }

  Future<void> _pickMonthYear(BuildContext context, int initialYear, int initialMonth) async {
    final now = DateTime.now();
    int tempYear = initialYear;
    int tempMonth = initialMonth;

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final isDlgDark = Theme.of(ctx).brightness == Brightness.dark;
          final dlgBg = isDlgDark ? const Color(0xff1e293b) : Colors.white;
          final dlgText = isDlgDark ? Colors.white : const Color(0xff0f172a);
          return AlertDialog(
            backgroundColor: dlgBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: const Color(0xff0284c7),
                  onPressed: () => setDlgState(() => tempYear--),
                ),
                Text(
                  '$tempYear',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: dlgText,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: const Color(0xff0284c7),
                  onPressed: tempYear >= now.year + 1 ? null : () => setDlgState(() => tempYear++),
                ),
              ],
            ),
            content: SizedBox(
              width: 300,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2.1,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: 12,
                itemBuilder: (ctx, idx) {
                  final m = idx + 1;
                  final isSelected = (m == tempMonth && tempYear == initialYear);
                  final isFuture = (tempYear > now.year || (tempYear == now.year && m > now.month));
                  return InkWell(
                    onTap: isFuture
                        ? null
                        : () {
                            Navigator.pop(ctx, DateTime(tempYear, m, 1));
                          },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xff0284c7)
                            : (isFuture
                                ? Colors.transparent
                                : (isDlgDark ? const Color(0xff334155) : const Color(0xfff1f5f9))),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _monthNames[idx].substring(0, 3),
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : (isFuture
                                  ? (isDlgDark ? Colors.white24 : Colors.black26)
                                  : dlgText),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );

    if (picked != null) {
      onMonthChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xff1e293b) : Colors.white;
    final borderColor = isDark ? const Color(0xff334155) : const Color(0xffe2e8f0);
    final textPrimary = isDark ? Colors.white : const Color(0xff0f172a);
    final textSecondary = isDark ? const Color(0xff94a3b8) : const Color(0xff64748b);

    final year = currentMonth.year;
    final month = currentMonth.month;
    final monthName = _monthNames[month - 1];

    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstDayOfMonth = DateTime(year, month, 1);
    // Sunday-first offset: Sun = 0, Mon = 1 ... Sat = 6
    final leadingOffset = firstDayOfMonth.weekday % 7;
    final totalSlots = ((leadingOffset + daysInMonth + 6) ~/ 7) * 7;

    final now = DateTime.now();

    // Calculate month stats
    int presentCount = 0;
    int pendingCount = 0;

    for (int d = 1; d <= daysInMonth; d++) {
      final dt = DateTime(year, month, d);
      final rec = _findRecordForDay(dt);
      if (rec != null) {
        final hasIn = rec['punchInUtc'] != null && rec['punchInUtc'].toString().trim().isNotEmpty;
        final hasOut = rec['punchOutUtc'] != null && rec['punchOutUtc'].toString().trim().isNotEmpty;
        if (hasIn && hasOut) {
          presentCount++;
        } else if (hasIn) {
          pendingCount++;
        }
      }
    }

    // Get holidays for this month (dynamic from Holiday Master API with offline fallback)
    if (api != null) {
      HolidayRepository.syncHolidays(api, year);
    }
    final holidays = HolidayRepository.getHolidays(year, month);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Month Header Bar with Navigation & Employee Name
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xff0284c7).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    size: 20,
                    color: Color(0xff0284c7),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _pickMonthYear(context, year, month),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$monthName $year',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.arrow_drop_down_rounded,
                                color: Color(0xff0284c7),
                                size: 24,
                              ),
                            ],
                          ),
                          if (employeeName != null && employeeName!.isNotEmpty)
                            Text(
                              employeeName!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xff0284c7),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Month Nav Arrows with tactile pill styling
                Material(
                  color: isDark ? const Color(0xff334155) : const Color(0xfff1f5f9),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 24),
                    color: const Color(0xff0284c7),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    tooltip: 'Previous month',
                    onPressed: () {
                      final prev = DateTime(year, month - 1, 1);
                      onMonthChanged(prev);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: isDark ? const Color(0xff334155) : const Color(0xfff1f5f9),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 24),
                    color: !(year > now.year || (year == now.year && month >= now.month))
                        ? const Color(0xff0284c7)
                        : (isDark ? Colors.white24 : Colors.black26),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    tooltip: 'Next month',
                    onPressed: (year > now.year || (year == now.year && month >= now.month))
                        ? null
                        : () {
                            final next = DateTime(year, month + 1, 1);
                            onMonthChanged(next);
                          },
                  ),
                ),
              ],
            ),
          ),

          // 2. Month Overview Stats Pills
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStatBadge(
                    label: 'Present',
                    count: presentCount,
                    bg: isDark ? const Color(0x3310b981) : const Color(0xffdcfce7),
                    textColor: isDark ? const Color(0xff4ade80) : const Color(0xff15803d),
                    dotColor: const Color(0xff10b981),
                  ),
                  const SizedBox(width: 8),
                  if (pendingCount > 0) ...[
                    _buildStatBadge(
                      label: 'In progress',
                      count: pendingCount,
                      bg: isDark ? const Color(0x33f59e0b) : const Color(0xfffef3c7),
                      textColor: isDark ? const Color(0xfffbbf24) : const Color(0xffb45309),
                      dotColor: const Color(0xfff59e0b),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (holidays.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _buildStatBadge(
                      label: 'Holidays',
                      count: holidays.length,
                      bg: isDark ? const Color(0x338b5cf6) : const Color(0xfff3e8ff),
                      textColor: isDark ? const Color(0xffc084fc) : const Color(0xff7e22ce),
                      dotColor: const Color(0xff8b5cf6),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // 3. Weekday Labels (SUN .. SAT)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: _weekdays.map((w) {
                final isSun = w == 'Sun';
                return Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSun
                            ? const Color(0xffef4444)
                            : (isDark ? const Color(0xff94a3b8) : const Color(0xff64748b)),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 8),

          // 4. Calendar Month Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: totalSlots,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 5,
                crossAxisSpacing: 4,
                childAspectRatio: 0.68,
              ),
              itemBuilder: (context, idx) {
                final dayNumber = idx - leadingOffset + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  // Empty slot before/after month
                  return const SizedBox.shrink();
                }

                final dayDate = DateTime(year, month, dayNumber);
                final isSunday = dayDate.weekday == DateTime.sunday;
                final isToday = dayDate.year == now.year &&
                    dayDate.month == now.month &&
                    dayDate.day == now.day;
                final isSelected = selectedDay != null &&
                    selectedDay!.year == dayDate.year &&
                    selectedDay!.month == dayDate.month &&
                    selectedDay!.day == dayDate.day;

                // Check for holiday
                final holiday = holidays.where((h) => h.day == dayNumber).firstOrNull;
                final isHoliday = holiday != null;

                // Check for attendance record
                final record = _findRecordForDay(dayDate);
                final hasPunchIn = record != null &&
                    record['punchInUtc'] != null &&
                    record['punchInUtc'].toString().trim().isNotEmpty;
                final hasPunchOut = record != null &&
                    record['punchOutUtc'] != null &&
                    record['punchOutUtc'].toString().trim().isNotEmpty;

                final punchInStr = hasPunchIn ? _localTimeOnly(record['punchInUtc']) : null;
                final punchOutStr = hasPunchOut ? _localTimeOnly(record['punchOutUtc']) : null;
                final isPending = hasPunchIn && !hasPunchOut;

                // Cell styling
                Color cellBg;
                Color cellBorder;

                if (isSelected) {
                  cellBg = const Color(0xff0284c7).withValues(alpha: isDark ? 0.25 : 0.15);
                  cellBorder = const Color(0xff0284c7);
                } else if (isToday) {
                  cellBg = const Color(0xff38bdf8).withValues(alpha: isDark ? 0.2 : 0.12);
                  cellBorder = const Color(0xff38bdf8);
                } else if (isSunday || isHoliday) {
                  cellBg = isDark
                      ? const Color(0xffef4444).withValues(alpha: 0.12)
                      : const Color(0xfffff1f2);
                  cellBorder = isDark
                      ? const Color(0xffef4444).withValues(alpha: 0.25)
                      : const Color(0xfffee2e2);
                } else {
                  cellBg = isDark ? const Color(0xff0f172a) : const Color(0xfff8fafc);
                  cellBorder = isDark ? const Color(0xff334155) : const Color(0xffe2e8f0);
                }

                // Date number color
                Color numColor;
                if (isSunday || isHoliday) {
                  numColor = const Color(0xffef4444);
                } else if (isToday) {
                  numColor = const Color(0xff0284c7);
                } else {
                  numColor = textPrimary;
                }

                return InkWell(
                  onTap: () {
                    // Tap to toggle selection
                    if (isSelected) {
                      onDaySelected(null);
                    } else {
                      onDaySelected(dayDate);
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    decoration: BoxDecoration(
                      color: cellBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: cellBorder,
                        width: isSelected || isToday ? 1.6 : 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Day Number & Today indicator
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$dayNumber',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: (isToday || isSelected || isSunday || isHoliday)
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: numColor,
                              ),
                            ),
                            if (isToday) ...[
                              const SizedBox(width: 2),
                              Container(
                                width: 4,
                                height: 4,
                                decoration: const BoxDecoration(
                                  color: Color(0xff0284c7),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),

                        // Badges for Punch In & Punch Out
                        if (hasPunchIn) ...[
                          // Punch In Badge (Green)
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 1),
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xff16a34a),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _compactTime(punchInStr!),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: const TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),

                          // Punch Out Badge (Red/Coral) or Pending (Amber)
                          if (hasPunchOut)
                            Container(
                              margin: const EdgeInsets.only(bottom: 1),
                              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xffdc2626),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _compactTime(punchOutStr!),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: const TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            )
                          else if (isPending)
                            Container(
                              margin: const EdgeInsets.only(bottom: 1),
                              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xffd97706),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Pending',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 8.0,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                        ] else if (isHoliday) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                            child: Text(
                              holiday.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xfff87171) : const Color(0xffdc2626),
                                height: 1.1,
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // 5. Selected Day Filter Banner (if a day is selected)
          if (selectedDay != null) ...[
            const SizedBox(height: 10),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xff0284c7).withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xff0284c7).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_rounded, size: 16, color: Color(0xff0284c7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Filtered: ${selectedDay!.day.toString().padLeft(2, '0')}/${selectedDay!.month.toString().padLeft(2, '0')}/${selectedDay!.year}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => onDaySelected(null),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Clear filter',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xffef4444),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 6. Holidays Section (if any this month)
          if (holidays.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xff0f172a) : const Color(0xfff8fafc),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.celebration_rounded, size: 16, color: Color(0xffef4444)),
                      const SizedBox(width: 6),
                      Text(
                        'Holidays (${holidays.length})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: holidays.map((h) {
                      final hDate = DateTime(year, month, h.day);
                      final dayOfWeek = _weekdays[hDate.weekday % 7];
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xffef4444),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${h.name}: ',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xffef4444),
                            ),
                          ),
                          Text(
                            '${h.day} $monthName, $dayOfWeek',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildStatBadge({
    required String label,
    required int count,
    required Color bg,
    required Color textColor,
    required Color dotColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count $label',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  String _compactTime(String fullTime) {
    // "10:31 AM" -> "10:31 AM" or "10:31A"
    return fullTime.trim();
  }
}
