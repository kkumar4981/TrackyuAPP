import 'package:flutter/material.dart';

String readableDate(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
bool arrivalAllowed(DateTime value, DateTime now) =>
    DateUtils.isSameDay(value, now) && value.isAfter(now);

class WorkflowPickerField extends StatelessWidget {
  final String label, value;
  final VoidCallback? onTap;
  final IconData icon;
  const WorkflowPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon = Icons.calendar_month_outlined,
  });
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xff1e293b) : Colors.white;
    final borderColor = isDark ? const Color(0xff334155) : const Color(0xffcbd5e1);
    final textColor = isDark ? Colors.white : const Color(0xff0f172a);
    final labelColor = isDark ? const Color(0xff94a3b8) : const Color(0xff64748b);
    final iconColor = isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7);

    return Semantics(
      button: true,
      label: '$label, $value',
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          color: labelColor,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WorkflowDateFields extends StatelessWidget {
  final DateTime from, to;
  final VoidCallback? onFrom, onTo;
  final bool single;
  const WorkflowDateFields({
    super.key,
    required this.from,
    required this.to,
    required this.onFrom,
    required this.onTo,
    this.single = false,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: LayoutBuilder(
      builder: (context, size) {
        final start = WorkflowPickerField(
          label: single ? 'Date' : 'From date',
          value: readableDate(single ? to : from),
          onTap: single ? onTo : onFrom,
        );
        if (single) return start;
        final end = WorkflowPickerField(
          label: 'To date',
          value: readableDate(to),
          onTap: onTo,
        );
        if (size.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.4) {
          return Column(children: [start, const SizedBox(height: 16), end]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: start),
            const SizedBox(width: 12),
            Expanded(child: end),
          ],
        );
      },
    ),
  );
}


class MonthYearBar extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;

  const MonthYearBar({
    super.key,
    required this.selectedDate,
    required this.onChanged,
    this.enabled = true,
  });

  static const List<String> monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const List<String> shortMonthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  bool get canGoNext {
    final now = DateTime.now();
    if (selectedDate.year > now.year) return false;
    if (selectedDate.year == now.year && selectedDate.month >= now.month) {
      return false;
    }
    return true;
  }

  void _previousMonth() {
    if (!enabled) return;
    int year = selectedDate.year;
    int month = selectedDate.month - 1;
    if (month < 1) {
      month = 12;
      year--;
    }
    onChanged(DateTime(year, month, 1));
  }

  void _nextMonth() {
    if (!enabled || !canGoNext) return;
    int year = selectedDate.year;
    int month = selectedDate.month + 1;
    if (month > 12) {
      month = 1;
      year++;
    }
    onChanged(DateTime(year, month, 1));
  }

  Future<void> _showPicker(BuildContext context) async {
    if (!enabled) return;
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => _MonthYearPickerDialog(initialDate: selectedDate),
    );
    if (picked != null) {
      onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xff1e293b) : Colors.white;
    final borderColor = isDark ? const Color(0xff334155) : const Color(0xffcbd5e1);
    final textColor = isDark ? Colors.white : const Color(0xff0f172a);
    final iconColor = isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7);
    final monthName = monthNames[selectedDate.month - 1];

    return Semantics(
      container: true,
      label: 'Selected month  ',
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 14),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              color: iconColor,
              tooltip: 'Previous Month',
              onPressed: enabled ? _previousMonth : null,
            ),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: enabled ? () => _showPicker(context) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_month_rounded, color: iconColor, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          ' ',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down, color: textColor.withValues(alpha: 0.7)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              color: canGoNext
                  ? iconColor
                  : (isDark ? const Color(0xff475569) : const Color(0xff94a3b8)),
              tooltip: 'Next Month',
              onPressed: enabled && canGoNext ? _nextMonth : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthYearPickerDialog extends StatefulWidget {
  final DateTime initialDate;
  const _MonthYearPickerDialog({required this.initialDate});

  @override
  State<_MonthYearPickerDialog> createState() => _MonthYearPickerDialogState();
}

class _MonthYearPickerDialogState extends State<_MonthYearPickerDialog> {
  late int _selectedYear;
  late int _selectedMonth;

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialDate.year;
    _selectedMonth = widget.initialDate.month;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xff1e293b) : Colors.white;
    final primaryColor = isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7);
    final textColor = isDark ? Colors.white : const Color(0xff0f172a);
    final subColor = isDark ? const Color(0xff94a3b8) : const Color(0xff64748b);

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _selectedYear > 2020
                      ? () => setState(() => _selectedYear--)
                      : null,
                ),
                Text(
                  '',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _selectedYear < now.year + 1
                      ? () => setState(() => _selectedYear++)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.1,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                final month = index + 1;
                final isSelected =
                    month == _selectedMonth && _selectedYear == widget.initialDate.year;
                final isFuture = _selectedYear > now.year ||
                    (_selectedYear == now.year && month > now.month);

                return Material(
                  color: isSelected
                      ? primaryColor
                      : (isDark ? const Color(0xff334155) : const Color(0xfff1f5f9)),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: isFuture
                        ? null
                        : () {
                            Navigator.of(context).pop(DateTime(_selectedYear, month, 1));
                          },
                    child: Center(
                      child: Text(
                        MonthYearBar.shortMonthNames[index],
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: isFuture
                              ? subColor.withValues(alpha: 0.4)
                              : (isSelected ? Colors.white : textColor),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(DateTime(now.year, now.month, 1));
                  },
                  child: const Text('Current Month'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
