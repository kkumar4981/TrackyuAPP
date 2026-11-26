const fs = require('fs');

// --- 1. Update app.dart ---
let appContent = fs.readFileSync('C:/Development/Oyu/fieldforce_hrms/lib/trackyu/app.dart', 'utf8');

// Add import for work_departure_sheet.dart
if (!appContent.includes("import 'work_departure_sheet.dart';")) {
  appContent = "import 'work_departure_sheet.dart';\r\n" + appContent;
  console.log('Added work_departure_sheet.dart import to app.dart');
}

// Replace the punch() onDuty dialogs with showWorkOutDepartureSheet
const punchLines = appContent.split('\r\n');
let punchStart = -1, punchEnd = -1;
for (let i = 2280; i < 2350; i++) {
  if (punchLines[i] && punchLines[i].includes('if (c.onDuty) {')) {
    punchStart = i;
    break;
  }
}

for (let j = punchStart; j < punchStart + 200; j++) {
  if (punchLines[j] && punchLines[j].includes('final photo = await c.takeSelfie();')) {
    punchEnd = j;
    break;
  }
}

console.log('punchStart:', punchStart, 'punchEnd:', punchEnd);

if (punchStart !== -1 && punchEnd !== -1) {
  const replacementPunch = [
    '      if (c.onDuty) {',
    '        final duration = c.workingDuration;',
    '        if (duration != null && duration < const Duration(minutes: 5)) {',
    '          final secs = duration.inSeconds % 60;',
    '          final mins = duration.inMinutes;',
    "          final timeStr = mins > 0 ? '$mins min $secs sec' : '$secs seconds';",
    '          await showDialog<void>(',
    '            context: context,',
    '            builder: (ctx) => AlertDialog(',
    '              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),',
    "              title: const Text('Work Cooldown Active'),",
    '              content: Text(',
    "                'You started work just $timeStr ago.\\n\\nTo prevent accidental check-outs and protect your shift data, a minimum 5-minute work duration is required before working out.',",
    '              ),',
    '              actions: [',
    '                FilledButton(',
    '                  onPressed: () => Navigator.pop(ctx),',
    "                  child: const Text('Understood'),",
    '                ),',
    '              ],',
    '            ),',
    '          );',
    '          return;',
    '        }',
    '',
    '        // Show comprehensive Workday Departure Sheet',
    '        final choice = await showWorkOutDepartureSheet(context: context, controller: c);',
    "        if (choice == 'checkout_visit') {",
    '          final data = VisitsData(c);',
    '          await data.load();',
    '          if (mounted && c.activeVisit != null) {',
    '            await Navigator.of(context).push<bool>(',
    '              MaterialPageRoute(',
    '                builder: (_) => VisitForm(data: data, visit: c.activeVisit!),',
    '              ),',
    '            );',
    '          }',
    '          return;',
    '        }',
    "        if (choice != 'confirm_work_out') {",
    '          return;',
    '        }',
    '      }'
  ];
  punchLines.splice(punchStart, punchEnd - punchStart, ...replacementPunch);
  appContent = punchLines.join('\r\n');
  console.log('Successfully updated punch() onDuty flow in app.dart');
}

// Replace SlidePunch with sleek Work Session Bar when c.onDuty
let sliderStart = -1, sliderEnd = -1;
const lines2 = appContent.split('\r\n');
for (let i = 0; i < lines2.length; i++) {
  if (lines2[i].includes('if (!c.completed)') && lines2[i+2] && lines2[i+2].includes('padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),')) {
    sliderStart = i;
    for (let j = i; j < i + 35; j++) {
      if (lines2[j].includes('onSubmit: punch,')) {
        // find the closing of Padding
        for (let k = j; k < j + 10; k++) {
          if (lines2[k].trim() === '),') {
            sliderEnd = k;
            break;
          }
        }
        break;
      }
    }
    break;
  }
}

console.log('sliderStart:', sliderStart, 'sliderEnd:', sliderEnd);

if (sliderStart !== -1 && sliderEnd !== -1) {
  const replacementSlider = [
    '                if (!c.completed)',
    '                  Padding(',
    '                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),',
    '                    child: c.onDuty',
    '                        ? Container(',
    '                            height: 58,',
    '                            padding: const EdgeInsets.symmetric(horizontal: 16),',
    '                            decoration: BoxDecoration(',
    '                              color: isDark ? const Color(0xff161e2e) : Colors.white,',
    '                              borderRadius: BorderRadius.circular(18),',
    '                              border: Border.all(',
    '                                color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),',
    '                                width: 1.2,',
    '                              ),',
    '                              boxShadow: [',
    '                                BoxShadow(',
    '                                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),',
    '                                  blurRadius: 16,',
    '                                  offset: const Offset(0, 4),',
    '                                ),',
    '                              ],',
    '                            ),',
    '                            child: Row(',
    '                              children: [',
    '                                Container(',
    '                                  width: 10,',
    '                                  height: 10,',
    '                                  decoration: const BoxDecoration(',
    '                                    color: Color(0xff10b981),',
    '                                    shape: BoxShape.circle,',
    '                                  ),',
    '                                ),',
    '                                const SizedBox(width: 10),',
    '                                Expanded(',
    '                                  child: Column(',
    '                                    mainAxisAlignment: MainAxisAlignment.center;',
    '                                    crossAxisAlignment: CrossAxisAlignment.start,',
    '                                    children: [',
    '                                      Text(',
    "                                        'Work Session Active',",
    '                                        style: TextStyle(',
    '                                          fontWeight: FontWeight.w800,',
    '                                          fontSize: 13,',
    '                                          color: isDark ? Colors.white : const Color(0xff0f172a),',
    '                                        ),',
    '                                      ),',
    '                                      Text(',
    "                                        '\${(c.workingDuration ?? Duration.zero).inHours}h \${(c.workingDuration ?? Duration.zero).inMinutes.remainder(60)}m logged today (9h standard)',",
    '                                        style: TextStyle(',
    '                                          fontSize: 11,',
    '                                          fontWeight: FontWeight.w500,',
    '                                          color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),',
    '                                        ),',
    '                                      ),',
    '                                    ],',
    '                                  ),',
    '                                ),',
    '                                const SizedBox(width: 8),',
    '                                Material(',
    '                                  color: Colors.transparent,',
    '                                  child: InkWell(',
    '                                    borderRadius: BorderRadius.circular(12),',
    '                                    onTap: busy ? null : punch,',
    '                                    child: Container(',
    '                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8.5),',
    '                                      decoration: BoxDecoration(',
    '                                        gradient: const LinearGradient(',
    '                                          colors: [Color(0xffea580c), Color(0xffc2410c)],',
    '                                        ),',
    '                                        borderRadius: BorderRadius.circular(12),',
    '                                        boxShadow: [',
    '                                          BoxShadow(',
    '                                            color: const Color(0xffea580c).withValues(alpha: 0.3),',
    '                                            blurRadius: 8,',
    '                                            offset: const Offset(0, 2),',
    '                                          ),',
    '                                        ],',
    '                                      ),',
    '                                      child: const Row(',
    '                                        mainAxisSize: MainAxisSize.min,',
    '                                        children: [',
    '                                          Icon(Icons.power_settings_new_rounded, color: Colors.white, size: 16),',
    '                                          SizedBox(width: 6),',
    '                                          Text(',
    "                                            'Work Out',",
    '                                            style: TextStyle(',
    '                                              color: Colors.white,',
    '                                              fontWeight: FontWeight.w800,',
    '                                              fontSize: 12.5,',
    '                                            ),',
    '                                          ),',
    '                                        ],',
    '                                      ),',
    '                                    ),',
    '                                  ),',
    '                                ),',
    '                              ],',
    '                            ),',
    '                          )',
    '                        : SlidePunch(',
    '                            controller: c,',
    '                            enabled: canPunch,',
    "                            hint: 'Selfie & GPS required to Start Work',",
    "                            label: busy ? 'Confirming attendance...' : 'Slide to Start Work (Work In)',",
    '                            onSubmit: punch,',
    '                          ),',
    '                  )',
  ];
  lines2.splice(sliderStart, sliderEnd - sliderStart + 1, ...replacementSlider);
  appContent = lines2.join('\r\n');
  console.log('Successfully replaced SlidePunch with sleek Work Session Bar in app.dart');
}

// Replace 'Duty Not Started' with 'Work Not Started'
appContent = appContent.replace("'Duty Not Started'", "'Work Not Started'");

fs.writeFileSync('C:/Development/Oyu/fieldforce_hrms/lib/trackyu/app.dart', appContent, 'utf8');

// --- 2. Update workspace.dart ---
let ws = fs.readFileSync('C:/Development/Oyu/fieldforce_hrms/lib/trackyu/workspace.dart', 'utf8');
ws = ws.replace("return 'View past duty logs & timestamps';", "return 'View past work logs & timestamps';");
ws = ws.replace("title: Text(controller.onDuty ? 'Duty Active: Punch-out & Sign out?' : 'Sign out?'),", "title: Text(controller.onDuty ? 'Work Active: Punch-out & Sign out?' : 'Sign out?'),");
ws = ws.replace("? 'Your duty is currently ACTIVE. Signing out will automatically punch you out and end your shift. Continue?'", "? 'Your work session is currently ACTIVE. Signing out will automatically punch you out and end your shift. Continue?'");
ws = ws.replace("subtitle: 'Mark daily duty check-in & check-out',", "subtitle: 'Mark daily work check-in & check-out',");
ws = ws.replace("subtitle: 'Re-download duty data from server',", "subtitle: 'Re-download work data from server',");
ws = ws.replace("'message': 'Welcome to Trackyu. Your duty alerts, visit notifications, and company broadcasts will appear here.',", "'message': 'Welcome to Trackyu. Your work alerts, visit notifications, and company broadcasts will appear here.',");
fs.writeFileSync('C:/Development/Oyu/fieldforce_hrms/lib/trackyu/workspace.dart', ws, 'utf8');
console.log('Updated workspace.dart');

// --- 3. Update monthly_goals_card.dart ---
let mg = fs.readFileSync('C:/Development/Oyu/fieldforce_hrms/lib/trackyu/monthly_goals_card.dart', 'utf8');
mg = mg.replace("'Duty Attendance',", "'Work Attendance',");
mg = mg.replace("'Duty Hours Logged',", "'Work Hours Logged',");
mg = mg.replace("'Logged via GPS duty',", "'Logged via GPS tracking',");
mg = mg.replace("'Duty Days',", "'Work Days',");
fs.writeFileSync('C:/Development/Oyu/fieldforce_hrms/lib/trackyu/monthly_goals_card.dart', mg, 'utf8');
console.log('Updated monthly_goals_card.dart');
