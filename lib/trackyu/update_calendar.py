with open(r'C:\Development\Oyu\fieldforce_hrms\lib\trackyu\attendance_calendar.dart', 'r', encoding='utf-8') as f:
    content = f.read()

target = """                  _buildStatBadge(
                    label: 'Sunday Off',
                    count: sundayCount,
                    bg: isDark ? const Color(0x33ef4444) : const Color(0xfffee2e2),
                    textColor: isDark ? const Color(0xfff87171) : const Color(0xffb91c1c),
                    dotColor: const Color(0xffef4444),
                  ),"""

# Normalize newlines for matching
if target in content:
    content = content.replace(target + "\n", "")
elif target.replace("\n", "\r\n") in content:
    content = content.replace(target.replace("\n", "\r\n") + "\r\n", "")
else:
    print("Not found directly, searching regex")
    import re
    content = re.sub(r"\s*_buildStatBadge\(\s*label:\s*'Sunday Off'[\s\S]*?\),", "", content)

with open(r'C:\Development\Oyu\fieldforce_hrms\lib\trackyu\attendance_calendar.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated attendance_calendar.dart successfully")
