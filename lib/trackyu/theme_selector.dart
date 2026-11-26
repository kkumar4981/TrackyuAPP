import 'package:flutter/material.dart';
import 'controller.dart';

/// Shows an ultra-modern multi-theme selection modal bottom sheet
void showThemeSelectorModal(BuildContext context, TrackyuController controller) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      final isDark = controller.isDarkMode;
      final currentMode = controller.activeTheme;

      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.82,
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xff161b22) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: isDark ? const Color(0xff30363d) : const Color(0xffe2e8f0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 28,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xff484f58) : const Color(0xffcbd5e1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: controller.themePrimaryColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.palette_rounded, color: controller.themePrimaryColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Choose Workspace Theme',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xff0f172a),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'Personalize the colors, cards and gradient styling of your app',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                ),
              ),
              const SizedBox(height: 14),

              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildSectionHeader('LUXURY PASTEL GRADIENTS (LIGHT)', isDark),
                    const SizedBox(height: 8),

                    // Option 1: ✨ Lavender Luxury (Beta) - Daylight Glass & Pastel
                    _buildThemeOptionTile(
                      ctx,
                      controller,
                      modeKey: 'beta',
                      isSelected: currentMode == 'beta',
                      title: 'Lavender Luxury (Beta)',
                      badgeText: 'Recommended',
                      badgeColor: const Color(0xff6366f1),
                      subtitle: 'Soft lavender, violet pastel & daylight glass cards',
                      icon: Icons.auto_awesome_rounded,
                      iconColor: const Color(0xff6366f1),
                      bgColors: isDark
                          ? [const Color(0xff2d2250), const Color(0xff1e1b4b)]
                          : [const Color(0xfff5f3ff), const Color(0xffeff6ff)],
                    ),
                    const SizedBox(height: 9),

                    // Option 2: 🌸 Rose Blossom Luxury
                    _buildThemeOptionTile(
                      ctx,
                      controller,
                      modeKey: 'blossom',
                      isSelected: currentMode == 'blossom',
                      title: 'Rose Blossom Luxury',
                      badgeText: 'Pastel',
                      badgeColor: const Color(0xffe11d48),
                      subtitle: 'Delicate rose pink, peach glow & warm pastel card tint',
                      icon: Icons.favorite_rounded,
                      iconColor: const Color(0xffe11d48),
                      bgColors: isDark
                          ? [const Color(0xff3f121d), const Color(0xff270a13)]
                          : [const Color(0xfffff1f2), const Color(0xfffdf2f8)],
                    ),
                    const SizedBox(height: 9),

                    // Option 3: 🌿 Emerald Mint Luxury
                    _buildThemeOptionTile(
                      ctx,
                      controller,
                      modeKey: 'emerald',
                      isSelected: currentMode == 'emerald',
                      title: 'Emerald Mint Luxury',
                      badgeText: 'Fresh',
                      badgeColor: const Color(0xff059669),
                      subtitle: 'Fresh mint, seafoam gradient & clean organic pastel',
                      icon: Icons.eco_rounded,
                      iconColor: const Color(0xff059669),
                      bgColors: isDark
                          ? [const Color(0xff062d1f), const Color(0xff041e15)]
                          : [const Color(0xffecfdf5), const Color(0xfff0fdf4)],
                    ),
                    const SizedBox(height: 9),

                    // Option 4: 🌊 Coastal Ocean Luxury
                    _buildThemeOptionTile(
                      ctx,
                      controller,
                      modeKey: 'ocean',
                      isSelected: currentMode == 'ocean',
                      title: 'Coastal Ocean Luxury',
                      badgeText: 'Calm',
                      badgeColor: const Color(0xff0284c7),
                      subtitle: 'Azure sky, cool cyan water & airy coastal pastel',
                      icon: Icons.water_rounded,
                      iconColor: const Color(0xff0284c7),
                      bgColors: isDark
                          ? [const Color(0xff082f49), const Color(0xff0c2135)]
                          : [const Color(0xfff0f9ff), const Color(0xffe0f2fe)],
                    ),
                    const SizedBox(height: 16),

                    _buildSectionHeader('EXECUTIVE & DARK CANVAS', isDark),
                    const SizedBox(height: 8),

                    // Option 5: 🏢 Classic Enterprise
                    _buildThemeOptionTile(
                      ctx,
                      controller,
                      modeKey: 'classic',
                      isSelected: currentMode == 'classic',
                      title: 'Classic Enterprise',
                      badgeText: null,
                      badgeColor: null,
                      subtitle: 'Crisp corporate clean background, navy accents, standard HRMS',
                      icon: Icons.business_rounded,
                      iconColor: const Color(0xff1c6799),
                      bgColors: isDark
                          ? [const Color(0xff1e293b), const Color(0xff0f172a)]
                          : [const Color(0xfff8fafc), const Color(0xffffffff)],
                    ),
                    const SizedBox(height: 9),

                    // Option 6: 🌙 Midnight Slate
                    _buildThemeOptionTile(
                      ctx,
                      controller,
                      modeKey: 'dark',
                      isSelected: currentMode == 'dark',
                      title: 'Midnight Dark',
                      badgeText: 'Eye-Care',
                      badgeColor: const Color(0xffa78bfa),
                      subtitle: 'Deep slate space canvas with high contrast, low glare',
                      icon: Icons.nightlight_round,
                      iconColor: const Color(0xffa78bfa),
                      bgColors: isDark
                          ? [const Color(0xff1e293b), const Color(0xff0f172a)]
                          : [const Color(0xfff1f5f9), const Color(0xffe2e8f0)],
                    ),
                    const SizedBox(height: 9),

                    // Option 7: 🌌 AMOLED Pitch Black
                    _buildThemeOptionTile(
                      ctx,
                      controller,
                      modeKey: 'amoled',
                      isSelected: currentMode == 'amoled',
                      title: 'AMOLED Pitch Black',
                      badgeText: 'Battery Saver',
                      badgeColor: const Color(0xff10b981),
                      subtitle: 'True pure #000000 black canvas for OLED battery efficiency',
                      icon: Icons.dark_mode_rounded,
                      iconColor: const Color(0xff38bdf8),
                      bgColors: isDark
                          ? [const Color(0xff111111), const Color(0xff000000)]
                          : [const Color(0xffe2e8f0), const Color(0xffcbd5e1)],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _buildSectionHeader(String title, bool isDark) {
  return Text(
    title,
    style: TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: isDark ? const Color(0xff64748b) : const Color(0xff94a3b8),
    ),
  );
}

Widget _buildThemeOptionTile(
  BuildContext ctx,
  TrackyuController controller, {
  required String modeKey,
  required bool isSelected,
  required String title,
  required String? badgeText,
  required Color? badgeColor,
  required String subtitle,
  required IconData icon,
  required Color iconColor,
  required List<Color> bgColors,
}) {
  final isDark = controller.isDarkMode;

  return InkWell(
    onTap: () async {
      await controller.setTheme(modeKey);
      Navigator.pop(ctx);
    },
    borderRadius: BorderRadius.circular(16),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: bgColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? (badgeColor ?? const Color(0xff6366f1))
              : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06)),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: (badgeColor ?? const Color(0xff6366f1)).withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: iconColor.withOpacity(0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xff0f172a),
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (badgeText != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: (badgeColor ?? const Color(0xff6366f1)).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: badgeColor ?? const Color(0xff6366f1),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (isSelected)
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: badgeColor ?? const Color(0xff6366f1),
              ),
              child: const Icon(Icons.check, size: 14, color: Colors.white),
            ),
        ],
      ),
    ),
  );
}
