with open(r'C:\Development\Oyu\fieldforce_hrms\lib\trackyu\app.dart', 'r', encoding='utf-8') as f:
    text = f.read()

target1 = """                        // Manager Live Team Map Card
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => ManagerTeamMapPage(controller: c),
                                ),
                              );
                            },"""

replacement1 = """                        // Manager Live Team Map Card
                        if (c.menuEnabled('manager_team_map'))
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => ManagerTeamMapPage(controller: c),
                                ),
                              );
                            },"""

target2 = """                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => OfficeLocationRequestPage(controller: c),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xff161e2e) : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isDark ? const Color(0xff2563eb).withValues(alpha: 0.3) : const Color(0xffbae6fd),
                                        width: 1.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xff0284c7).withValues(alpha: 0.06),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(7.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xff0284c7).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                            Icons.add_location_alt_outlined,
                                            size: 19,
                                            color: Color(0xff0284c7),
                                          ),
                                        ),
                                        const SizedBox(width: 9),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Geo Tag Location',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                              SizedBox(height: 1),
                                              Text(
                                                'Self-tag place',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Color(0xff64748b),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),"""

replacement2 = """                              if (c.menuEnabled('geotag'))
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => OfficeLocationRequestPage(controller: c),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xff161e2e) : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isDark ? const Color(0xff2563eb).withValues(alpha: 0.3) : const Color(0xffbae6fd),
                                        width: 1.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xff0284c7).withValues(alpha: 0.06),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(7.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xff0284c7).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                            Icons.add_location_alt_outlined,
                                            size: 19,
                                            color: Color(0xff0284c7),
                                          ),
                                        ),
                                        const SizedBox(width: 9),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Geo Tag Location',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                              SizedBox(height: 1),
                                              Text(
                                                'Self-tag place',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Color(0xff64748b),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),"""

if target1 in text:
    text = text.replace(target1, replacement1)
elif target1.replace('\n', '\r\n') in text:
    text = text.replace(target1.replace('\n', '\r\n'), replacement1.replace('\n', '\r\n'))

if target2 in text:
    text = text.replace(target2, replacement2)
elif target2.replace('\n', '\r\n') in text:
    text = text.replace(target2.replace('\n', '\r\n'), replacement2.replace('\n', '\r\n'))

with open(r'C:\Development\Oyu\fieldforce_hrms\lib\trackyu\app.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print("Updated app.dart home menu checks!")
