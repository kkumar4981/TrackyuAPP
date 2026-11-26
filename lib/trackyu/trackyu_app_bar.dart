import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'controller.dart';
import 'network_speed.dart';
import 'theme_selector.dart';
import 'workspace.dart' show WorkspacePage, WorkFeature;

/// Universal reusable header actions matching the Trackyu Home screen:
/// 1. Sync & Network Quality Pill
/// 2. Notification Bell (Opens Workspace Inbox)
/// 3. Theme Selector (Opens Modern Theme Picker)
class TrackyuAppBarActions extends StatelessWidget {
  final TrackyuController controller;
  final List<Widget>? leadingActions;
  final List<Widget>? trailingActions;
  final bool showNetwork;
  final bool showNotifications;
  final bool showThemeSelector;
  final VoidCallback? onSync;

  const TrackyuAppBarActions({
    super.key,
    required this.controller,
    this.leadingActions,
    this.trailingActions,
    this.showNetwork = true,
    this.showNotifications = true,
    this.showThemeSelector = true,
    this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = controller;
    final network = NetworkQualityMonitor.instance(c.api);

    return ListenableBuilder(
      listenable: Listenable.merge([c, network]),
      builder: (context, _) {
        final actions = <Widget>[];

        if (leadingActions != null) {
          actions.addAll(leadingActions!);
        }

        if (showNetwork) {
          actions.add(
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Center(
                child: SyncNetworkAppBarPill(
                  controller: c,
                  network: network,
                  busy: c.isSyncing,
                  onSync: () {
                    if (onSync != null) {
                      onSync!();
                    } else {
                      c.syncData();
                    }
                  },
                ),
              ),
            ),
          );
        }

        if (showNotifications) {
          actions.add(
            Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => WorkspacePage(controller: c, feature: WorkFeature.inbox),
                      ),
                    );
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xff0284c7).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : const Color(0xff0284c7).withValues(alpha: 0.28),
                        width: 1.2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.notifications_active_outlined,
                      size: 19,
                      color: isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7),
                    ),
                  ),
                ),
              ),
            ),
          );
          actions.add(const SizedBox(width: 6));
        }

        if (showThemeSelector) {
          actions.add(
            Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => showThemeSelectorModal(context, c),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : c.themePrimaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : c.themePrimaryColor.withValues(alpha: 0.28),
                        width: 1.2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.palette_rounded,
                      size: 19,
                      color: isDark ? const Color(0xffa78bfa) : c.themePrimaryColor,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        if (trailingActions != null) {
          actions.addAll(trailingActions!);
        }

        actions.add(const SizedBox(width: 8));

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: actions,
        );
      },
    );
  }
}

/// Helper to build a unified modern AppBar with Trackyu theme support
AppBar buildTrackyuAppBar({
  required BuildContext context,
  required TrackyuController controller,
  required String title,
  Widget? leading,
  List<Widget>? leadingActions,
  List<Widget>? trailingActions,
  PreferredSizeWidget? bottom,
  bool centerTitle = false,
  VoidCallback? onSync,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final isLux = controller.isBetaMode;
  final isBgDark = isDark || (isLux && controller.themeBackgroundColor.computeLuminance() < 0.45);
  final headerBg = isDark
      ? const Color(0xff0f172a)
      : (isLux ? controller.themeBackgroundColor : Colors.white);

  return AppBar(
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isBgDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isBgDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isDark
          ? const Color(0xff0b0f19)
          : (isLux ? controller.themeBackgroundColor : Colors.white),
      systemNavigationBarIconBrightness: isBgDark ? Brightness.light : Brightness.dark,
    ),
    titleSpacing: leading != null ? 0 : 16,
    leading: leading,
    centerTitle: centerTitle,
    backgroundColor: headerBg,
    elevation: 0,
    title: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        maxLines: 1,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 17,
          letterSpacing: -0.3,
          color: isDark ? Colors.white : const Color(0xff0f172a),
        ),
      ),
    ),
    actions: [
      TrackyuAppBarActions(
        controller: controller,
        leadingActions: leadingActions,
        trailingActions: trailingActions,
        onSync: onSync,
      ),
    ],
    bottom: bottom,
  );
}

AppBar trackyuAppBar({
  required BuildContext context,
  required TrackyuController controller,
  required String title,
  Widget? leading,
  List<Widget>? leadingActions,
  List<Widget>? trailingActions,
  PreferredSizeWidget? bottom,
  bool centerTitle = false,
  VoidCallback? onSync,
}) => buildTrackyuAppBar(
  context: context,
  controller: controller,
  title: title,
  leading: leading,
  leadingActions: leadingActions,
  trailingActions: trailingActions,
  bottom: bottom,
  centerTitle: centerTitle,
  onSync: onSync,
);
