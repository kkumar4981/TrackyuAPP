with open(r'C:\Development\Oyu\fieldforce_hrms\lib\trackyu\profile_page.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Make Branch / Company always show
branch_old = """                              if (_profileDetails['BRANCH'] != null &&
                                  _profileDetails['BRANCH'].toString().isNotEmpty) ...[
                                const SizedBox(height: 14),
                                _ReadOnlyInfoTile(
                                  label: 'Branch / Company',
                                  value: _profileDetails['BRANCH'].toString(),
                                  icon: Icons.business_rounded,
                                  isDark: isDark,
                                ),
                              ],"""

branch_new = """                              const SizedBox(height: 14),
                              _ReadOnlyInfoTile(
                                label: 'Branch / Company',
                                value: (_profileDetails['BRANCH'] != null && _profileDetails['BRANCH'].toString().trim().isNotEmpty)
                                    ? _profileDetails['BRANCH'].toString().trim()
                                    : (c.company?.isNotEmpty == true ? c.company! : 'Oyu Infotech'),
                                icon: Icons.business_rounded,
                                isDark: isDark,
                              ),"""

if branch_old in text:
    text = text.replace(branch_old, branch_new)
else:
    print("branch_old not found directly, checking regex or normal replace")

# Labels update
text = text.replace("'Full Name *'", "'Full name'")

with open(r'C:\Development\Oyu\fieldforce_hrms\lib\trackyu\profile_page.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print("Updated profile labels and Branch / Company")
