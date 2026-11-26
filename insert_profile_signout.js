const fs = require('fs');

let content = fs.readFileSync('C:/Development/Oyu/fieldforce_hrms/lib/trackyu/profile_page.dart', 'utf8');
const lines = content.split('\r\n');

let targetIdx = -1;
for (let i = 1960; i < 2000; i++) {
  if (lines[i] && lines[i].includes("child: const Text('Change', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),")) {
    // Find the enclosing card's end
    for (let j = i; j < i + 20; j++) {
      if (lines[j] && lines[j].includes('const SizedBox(height: 30),')) {
        targetIdx = j;
        break;
      }
    }
    break;
  }
}

console.log('targetIdx in profile_page.dart:', targetIdx);

if (targetIdx !== -1) {
  const insertLines = [
    '                      const SizedBox(height: 20),',
    '                      // Dedicated Account Session & Sign Out Section',
    '                      Container(',
    '                        padding: const EdgeInsets.all(18),',
    '                        decoration: BoxDecoration(',
    '                          color: cardBg,',
    '                          borderRadius: BorderRadius.circular(18),',
    '                          border: Border.all(color: borderColor),',
    '                        ),',
    '                        child: Column(',
    '                          crossAxisAlignment: CrossAxisAlignment.start,',
    '                          children: [',
    '                            Row(',
    '                              children: [',
    '                                Container(',
    '                                  padding: const EdgeInsets.all(8),',
    '                                  decoration: BoxDecoration(',
    '                                    color: const Color(0xffdc2626).withValues(alpha: 0.1),',
    '                                    borderRadius: BorderRadius.circular(10),',
    '                                  ),',
    '                                  child: const Icon(Icons.account_circle_outlined, size: 20, color: Color(0xffdc2626)),',
    '                                ),',
    '                                const SizedBox(width: 12),',
    '                                Expanded(',
    '                                  child: Column(',
    '                                    crossAxisAlignment: CrossAxisAlignment.start,',
    '                                    children: [',
    '                                      Text(',
    "                                        'Account Session',",
    '                                        style: TextStyle(',
    '                                          fontSize: 14,',
    '                                          fontWeight: FontWeight.w700,',
    '                                          color: textPrimary,',
    '                                        ),',
    '                                      ),',
    '                                      Text(',
    "                                        'Signed in on this device as \${widget.controller.employeeId}',",
    '                                        style: TextStyle(',
    '                                          fontSize: 11,',
    '                                          color: textSecondary,',
    '                                        ),',
    '                                      ),',
    '                                    ],',
    '                                  ),',
    '                                ),',
    '                              ],',
    '                            ),',
    '                            const SizedBox(height: 14),',
    '                            SizedBox(',
    '                              width: double.infinity,',
    '                              child: OutlinedButton.icon(',
    '                                style: OutlinedButton.styleFrom(',
    '                                  foregroundColor: const Color(0xffdc2626),',
    '                                  side: const BorderSide(color: Color(0xfffca5a5), width: 1.2),',
    '                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),',
    '                                  padding: const EdgeInsets.symmetric(vertical: 12),',
    '                                ),',
    '                                onPressed: () async {',
    '                                  final confirm = await showDialog<bool>(',
    '                                    context: context,',
    '                                    builder: (ctx) => AlertDialog(',
    '                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),',
    '                                      title: const Row(',
    '                                        children: [',
    '                                          Icon(Icons.logout_rounded, color: Color(0xffdc2626)),',
    '                                          SizedBox(width: 8),',
    '                                          Expanded(child: Text(\"Sign Out of Account?\")),',
    '                                        ],',
    '                                      ),',
    '                                      content: Text(',
    '                                        widget.controller.onDuty',
    '                                            ? \"Your work session is currently ACTIVE. Signing out will automatically record Work Out and complete your shift.\\n\\nAre you sure you want to sign out?\"',
    '                                            : \"Are you sure you want to sign out of this account on this device?\",',
    '                                      ),',
    '                                      actions: [',
    '                                        TextButton(',
    '                                          onPressed: () => Navigator.pop(ctx, false),',
    '                                          child: const Text(\"Cancel\"),',
    '                                        ),',
    '                                        FilledButton(',
    '                                          style: FilledButton.styleFrom(backgroundColor: const Color(0xffdc2626)),',
    '                                          onPressed: () => Navigator.pop(ctx, true),',
    '                                          child: const Text(\"Confirm Sign Out\"),',
    '                                        ),',
    '                                      ],',
    '                                    ),',
    '                                  );',
    '                                  if (confirm == true) {',
    '                                    await widget.controller.signOut(autoPunchOut: true);',
    '                                    if (context.mounted) {',
    '                                      Navigator.of(context).popUntil((route) => route.isFirst);',
    '                                    }',
    '                                  }',
    '                                },',
    '                                icon: const Icon(Icons.logout_rounded, size: 17),',
    '                                label: const Text(',
    "                                  'Sign Out of Account',",
    '                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),',
    '                                ),',
    '                              ),',
    '                            ),',
    '                          ],',
    '                        ),',
    '                      ),',
  ];
  lines.splice(targetIdx, 0, ...insertLines);
  fs.writeFileSync('C:/Development/Oyu/fieldforce_hrms/lib/trackyu/profile_page.dart', lines.join('\r\n'), 'utf8');
  console.log('Successfully inserted into profile_page.dart');
}
