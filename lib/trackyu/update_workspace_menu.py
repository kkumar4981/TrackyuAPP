with open(r'C:\Development\Oyu\fieldforce_hrms\lib\trackyu\workspace.dart', 'r', encoding='utf-8') as f:
    text = f.read()

target = """          ListTile(
            leading: const Icon(Icons.lock_reset_rounded, color: Color(0xffd97706)),
            title: const Text('Change Password'),
            subtitle: const Text('Update your login password', style: TextStyle(fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ChangePasswordPage(controller: controller),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Attendance'),
            selected: true,
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.add_location_alt_outlined, color: Color(0xff0284c7)),
            title: const Text('Geo Tag Location', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Save GPS coordinates for store or office', style: TextStyle(fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => OfficeLocationRequestPage(controller: controller),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.radar_rounded, color: Color(0xff10b981)),
            title: const Text('Live Team Map', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Live GPS tracking & day route for field staff', style: TextStyle(fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ManagerTeamMapPage(controller: controller),
                ),
              );
            },
          ),"""

replacement = """          if (controller.menuEnabled('change_password'))
            ListTile(
              leading: const Icon(Icons.lock_reset_rounded, color: Color(0xffd97706)),
              title: const Text('Change Password'),
              subtitle: const Text('Update your login password', style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ChangePasswordPage(controller: controller),
                  ),
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Attendance'),
            selected: true,
            onTap: () => Navigator.pop(context),
          ),
          if (controller.menuEnabled('geotag'))
            ListTile(
              leading: const Icon(Icons.add_location_alt_outlined, color: Color(0xff0284c7)),
              title: const Text('Geo Tag Location', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Save GPS coordinates for warehouse or residence', style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => OfficeLocationRequestPage(controller: controller),
                  ),
                );
              },
            ),
          if (controller.menuEnabled('manager_team_map'))
            ListTile(
              leading: const Icon(Icons.radar_rounded, color: Color(0xff10b981)),
              title: const Text('Live Team Map', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Live GPS tracking & day route for field staff', style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ManagerTeamMapPage(controller: controller),
                  ),
                );
              },
            ),"""

# Normalize CRLF
if target in text:
    text = text.replace(target, replacement)
elif target.replace('\n', '\r\n') in text:
    text = text.replace(target.replace('\n', '\r\n'), replacement.replace('\n', '\r\n'))
else:
    print("Target not found directly in workspace.dart")

with open(r'C:\Development\Oyu\fieldforce_hrms\lib\trackyu\workspace.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print("Updated workspace.dart drawer!")
