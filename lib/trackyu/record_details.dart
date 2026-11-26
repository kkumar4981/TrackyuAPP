import 'package:flutter/material.dart';

String leavePortionLabel(String value) => switch (value.trim().toLowerCase()) {
  'firsthalf' || 'h1' => 'First half',
  'secondhalf' || 'h2' => 'Second half',
  'halfday' || 'half day' || 'h' => 'Half day',
  'fullday' || 'full day' || '0' || '2' => 'Full day',
  _ => value,
};
String recordStatus(String value) => switch (value.trim().toLowerCase()) {
  '0' => 'Pending',
  '1' || 'approve' => 'Approved',
  '2' || 'reject' => 'Rejected',
  'inprogress' => 'In progress',
  _ => value.trim(),
};
String recordDate(dynamic value) {
  if (value == null) return '-';
  final s = value.toString().trim();
  if (s.isEmpty) return '-';
  final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (match != null) {
    final d = match.group(3)!.padLeft(2, '0');
    final m = match.group(2)!.padLeft(2, '0');
    final y = match.group(1)!;
    return '$d/$m/$y';
  }
  final parsed = DateTime.tryParse(s);
  return parsed == null
      ? s
      : '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
}

class RecordStatusBadge extends StatelessWidget {
  final String status;
  const RecordStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final trimmed = status.trim();
    if (trimmed.isEmpty || trimmed == '—' || trimmed == '-') {
      return const SizedBox.shrink();
    }
    final label = recordStatus(trimmed);
    final lower = label.toLowerCase();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final good = [
      'approved',
      'completed',
      'enabled',
      'read',
      'punched in',
      'active',
      'present',
      'on time',
    ].any(lower.contains);
    final bad = [
      'rejected',
      'cancelled',
      'disabled',
      'late',
      'early exit',
    ].any(lower.contains);
    final warn = ['pending', 'in progress', 'unread', 'active / pending'].any(lower.contains);

    final Color fgColor;
    final Color bgColor;

    if (good) {
      fgColor = isDark ? const Color(0xff4ade80) : const Color(0xff15803d);
      bgColor = isDark ? const Color(0x244ade80) : const Color(0xffdcfce7);
    } else if (bad) {
      fgColor = isDark ? const Color(0xfff87171) : const Color(0xffb91c1c);
      bgColor = isDark ? const Color(0x24f87171) : const Color(0xfffee2e2);
    } else if (warn) {
      fgColor = isDark ? const Color(0xfffbbf24) : const Color(0xffb45309);
      bgColor = isDark ? const Color(0x24fbbf24) : const Color(0xfffef3c7);
    } else {
      fgColor = isDark ? const Color(0xff38bdf8) : const Color(0xff0369a1);
      bgColor = isDark ? const Color(0x2438bdf8) : const Color(0xffe0f2fe);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fgColor.withValues(alpha: 0.35), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fgColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class RecordDetails extends StatelessWidget {
  final Map<String, String> fields;
  const RecordDetails({super.key, required this.fields});

  Widget _fieldIcon(String key, bool isDark) {
    final lower = key.toLowerCase();
    final IconData iconData;
    final Color iconColor;

    if (lower.contains('punch in')) {
      iconData = Icons.login_rounded;
      iconColor = isDark ? const Color(0xff4ade80) : const Color(0xff16a34a);
    } else if (lower.contains('punch out')) {
      iconData = Icons.logout_rounded;
      iconColor = isDark ? const Color(0xfffb923c) : const Color(0xffea580c);
    } else if (lower.contains('late') || lower.contains('early') || lower.contains('timing') || lower.contains('time')) {
      iconData = Icons.schedule_rounded;
      iconColor = isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7);
    } else if (lower.contains('employee') || lower.contains('user')) {
      iconData = Icons.person_outline_rounded;
      iconColor = isDark ? const Color(0xffa78bfa) : const Color(0xff7c3aed);
    } else if (lower.contains('date') || lower.contains('from') || lower.contains('to')) {
      iconData = Icons.calendar_today_rounded;
      iconColor = isDark ? const Color(0xff94a3b8) : const Color(0xff64748b);
    } else {
      iconData = Icons.info_outline_rounded;
      iconColor = isDark ? const Color(0xff64748b) : const Color(0xff94a3b8);
    }

    return Icon(iconData, size: 15, color: iconColor);
  }

  Widget _formatValue(String key, String val, Color defaultColor, bool isDark) {
    final lowerKey = key.toLowerCase();
    final lowerVal = val.toLowerCase();

    if (lowerKey.contains('timing') || lowerKey.contains('late') || lowerKey.contains('early')) {
      if (lowerVal.contains('on time') || val == 'No') {
        return Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? const Color(0x224ade80) : const Color(0xffdcfce7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                val,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xff4ade80) : const Color(0xff16a34a),
                ),
              ),
            ),
          ],
        );
      } else if (lowerVal.contains('late') || val == 'Yes') {
        return Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? const Color(0x22f87171) : const Color(0xfffee2e2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                val,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xfff87171) : const Color(0xffdc2626),
                ),
              ),
            ),
          ],
        );
      }
    }

    if (lowerVal.contains('pending') || lowerVal.contains('active')) {
      return Text(
        val,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.italic,
          color: isDark ? const Color(0xfffbbf24) : const Color(0xffd97706),
        ),
      );
    }

    return SelectableText(
      val,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: defaultColor,
        height: 1.4,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final entries = fields.entries
          .where((e) => e.value.trim().isNotEmpty)
          .toList();
      final stacked =
          size.maxWidth < 280 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.35;
      final tableBg = isDark ? const Color(0xff14171c) : const Color(0xfff8fafc);
      final borderColor = isDark ? const Color(0xff2d333b) : const Color(0xffe2e8f0);
      final labelColor = isDark ? const Color(0xff94a3b8) : const Color(0xff64748b);
      final valColor = isDark ? const Color(0xfff1f5f9) : const Color(0xff0f172a);

      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: tableBg,
          border: Border.all(color: borderColor, width: 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            for (var i = 0; i < entries.length; i++)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: i == entries.length - 1
                      ? null
                      : Border(
                          bottom: BorderSide(color: borderColor, width: 0.8),
                        ),
                ),
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _fieldIcon(entries[i].key, isDark),
                              const SizedBox(width: 6),
                              Text(
                                entries[i].key,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: labelColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          _formatValue(entries[i].key, entries[i].value, valColor, isDark),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 4,
                            child: Row(
                              children: [
                                _fieldIcon(entries[i].key, isDark),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    entries[i].key,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: labelColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 6,
                            child: _formatValue(entries[i].key, entries[i].value, valColor, isDark),
                          ),
                        ],
                      ),
              ),
          ],
        ),
      );
    },
  );
}
