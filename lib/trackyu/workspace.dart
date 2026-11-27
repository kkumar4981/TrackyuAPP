import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'attendance_calendar.dart';
import 'controller.dart';
import 'daily_route_chart_page.dart';
import 'error_logger.dart';
import 'exports.dart';
import 'local_db_inspector.dart';
import 'local_inbox.dart';
import 'locations.dart';
import 'manager_team_map_page.dart';
import 'office_location_request.dart';
import 'profile_avatar.dart';
import 'profile_page.dart';
import 'theme_selector.dart';
import 'tracking_status.dart';
import 'trackyu_app_bar.dart';
import 'visits.dart';
import 'workflow_dates.dart';

String dateOnly(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

List<Json> jsonRows(dynamic data) {
  if (data is Map) {
    if (data['rows'] is List) return jsonRows(data['rows']);
    if (data['data'] is List) return jsonRows(data['data']);
    if (data['items'] is List) return jsonRows(data['items']);
    if (data['notifications'] is List) return jsonRows(data['notifications']);
    return <Json>[];
  }
  if (data is! List) return <Json>[];
  return data
      .whereType<Map>()
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
}

String valueOf(Json row, String key, [String fallback = '—']) {
  final val = row[key];
  if (val == null) return fallback;
  final s = val.toString().trim();
  return s.isEmpty ? fallback : s;
}

String localTimeOnly(dynamic raw) {
  if (raw == null) return '—';
  final str = raw.toString().trim();
  if (str.isEmpty || str == '00:00') return '—';
  final date = DateTime.tryParse(str)?.toLocal();
  if (date == null) return str;
  final hourNum = date.hour;
  final period = hourNum >= 12 ? 'PM' : 'AM';
  final hour = hourNum == 0 ? 12 : (hourNum > 12 ? hourNum - 12 : hourNum);
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute $period';
}

String localStamp(dynamic raw) {
  if (raw == null) return '—';
  final date = DateTime.tryParse(raw.toString())?.toLocal();
  if (date == null) return raw.toString();
  final d =
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  return '$d ${localTimeOnly(raw)}';
}

String recordDate(dynamic raw) {
  if (raw == null) return '—';
  final str = raw.toString().trim();
  final dt = DateTime.tryParse(str)?.toLocal();
  if (dt != null) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
  return str.isEmpty ? '—' : str;
}

String cleanAddress(String raw) =>
    raw.replaceAll(RegExp(r'\s+'), ' ').trim();

enum WorkFeature {
  history(
    'Attendance history',
    Icons.history,
    writable: false,
    teamSupported: true,
    officeScoped: false,
  ),
  locations(
    'Duty route',
    Icons.alt_route_rounded,
    writable: false,
    teamSupported: false,
    officeScoped: false,
  ),
  leave(
    'Leave',
    Icons.event_busy_outlined,
    writable: true,
    teamSupported: true,
    officeScoped: false,
  ),
  activity(
    'Activity',
    Icons.assignment_outlined,
    writable: true,
    teamSupported: true,
    officeScoped: true,
  ),
  reminder(
    'Reminders',
    Icons.alarm_outlined,
    writable: true,
    teamSupported: false,
    officeScoped: true,
  ),
  intimation(
    'Pre-intimation',
    Icons.schedule_send_outlined,
    writable: true,
    teamSupported: true,
    officeScoped: false,
  ),
  inbox(
    'Inbox',
    Icons.notifications_outlined,
    writable: false,
    teamSupported: false,
    officeScoped: false,
  ),
  visits(
    'Open visit',
    Icons.storefront_outlined,
    writable: false,
    teamSupported: false,
    officeScoped: false,
  ),
  orders(
    'Orders',
    Icons.shopping_bag_outlined,
    writable: false,
    teamSupported: false,
    officeScoped: false,
  ),
  tasks(
    'Assigned tasks',
    Icons.task_alt,
    writable: false,
    teamSupported: false,
    officeScoped: false,
  ),
  offices(
    'My offices',
    Icons.business_outlined,
    writable: false,
    teamSupported: false,
    officeScoped: false,
  );

  final String title;
  final IconData icon;
  final bool writable;
  final bool teamSupported;
  final bool officeScoped;

  const WorkFeature(
    this.title,
    this.icon, {
    required this.writable,
    required this.teamSupported,
    required this.officeScoped,
  });
}

class WorkspaceDrawer extends StatelessWidget {
  final TrackyuController controller;
  final VoidCallback? openSetup;
  const WorkspaceDrawer({
    super.key,
    required this.controller,
    this.openSetup,
  });

  Color _featureColor(WorkFeature feature) {
    switch (feature) {
      case WorkFeature.visits:
        return const Color(0xff2563eb);
      case WorkFeature.locations:
        return const Color(0xff8b5cf6);
      case WorkFeature.inbox:
        return const Color(0xfff59e0b);
      case WorkFeature.leave:
        return const Color(0xff10b981);
      case WorkFeature.orders:
        return const Color(0xff059669);
      case WorkFeature.tasks:
        return const Color(0xffec4899);
      default:
        return const Color(0xff0284c7);
    }
  }

  String _featureSubtitle(WorkFeature feature) {
    switch (feature) {
      case WorkFeature.history:
        return 'View past duty logs & timestamps';
      case WorkFeature.locations:
        return 'Tracked day route & GPS breadcrumbs';
      case WorkFeature.inbox:
        return 'System broadcasts & geofence alerts';
      case WorkFeature.visits:
        return 'Client shop check-ins & checkouts';
      case WorkFeature.leave:
        return 'Apply for leave & check approval status';
      case WorkFeature.orders:
        return 'Order logs & summaries';
      case WorkFeature.activity:
        return 'Log daily work activities';
      case WorkFeature.reminder:
        return 'Schedule office reminders';
      case WorkFeature.intimation:
        return 'Notify team of late arrival';
      case WorkFeature.tasks:
        return 'Assigned tasks & status';
      case WorkFeature.offices:
        return 'View assigned office locations';
    }
  }

  Widget _drawerSection(
    BuildContext context,
    String title, {
    bool showDivider = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDivider)
          Divider(
            height: 16,
            thickness: 1,
            color: isDark ? const Color(0xff1e293b) : const Color(0xffe2e8f0),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
            ),
          ),
        ),
      ],
    );
  }

  Widget _drawerItem({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    String? badge,
    VoidCallback? onTap,
  }) {
    return ListTile(
      dense: true,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 19),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 11)),
      trailing: badge == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: iconColor,
                ),
              ),
            ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Drawer(
        backgroundColor: isDark ? const Color(0xff0f172a) : Colors.white,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xff1e293b)
                      : const Color(0xfff1f5f9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: !controller.menuEnabled('profile')
                      ? null
                      : () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ProfilePage(controller: controller),
                            ),
                          );
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        TrackyuAvatarWidget(
                          controller: controller,
                          size: 52,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                controller.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                controller.employeeId,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? const Color(0xff94a3b8)
                                      : const Color(0xff64748b),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xff94a3b8),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    if (controller.menuEnabled('profile'))
                      _drawerItem(
                        context: context,
                        icon: Icons.person_rounded,
                        iconColor: const Color(0xff0284c7),
                        title: 'My Profile',
                        subtitle: 'Name, photo & contact details',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ProfilePage(controller: controller),
                            ),
                          );
                        },
                      ),
                    _drawerItem(
                      context: context,
                      icon: Icons.fingerprint,
                      iconColor: const Color(0xff2563eb),
                      title: 'Attendance',
                      onTap: () => Navigator.pop(context),
                    ),
                    if (controller.menuEnabled('visits'))
                      _drawerItem(
                        context: context,
                        icon: Icons.alt_route_rounded,
                        iconColor: const Color(0xff7c3aed),
                        title: 'Daily Route Chart',
                        subtitle: 'Timeline, stops & route summary',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  DailyRouteChartPage(controller: controller),
                            ),
                          );
                        },
                      ),
                    if (controller.menuEnabled('geotag')) ...[
                      _drawerItem(
                        context: context,
                        icon: Icons.store_mall_directory_rounded,
                        iconColor: const Color(0xff0284c7),
                        title: 'Retailer Geo-Tag',
                        subtitle: 'Tag or update client shop GPS coordinates',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => OfficeLocationRequestPage(
                                controller: controller,
                                initialTab: 0,
                              ),
                            ),
                          );
                        },
                      ),
                      _drawerItem(
                        context: context,
                        icon: Icons.business_rounded,
                        iconColor: const Color(0xff0d9488),
                        title: 'Office Location Mapping',
                        subtitle:
                            'Propose or update official workplace GPS location',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => OfficeLocationRequestPage(
                                controller: controller,
                                initialTab: 1,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    if (controller.menuEnabled('manager_team_map'))
                      _drawerItem(
                        context: context,
                        icon: Icons.radar_rounded,
                        iconColor: const Color(0xff059669),
                        title: 'Live Team Map',
                        subtitle: 'Live GPS tracking & day route for field staff',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ManagerTeamMapPage(controller: controller),
                            ),
                          );
                        },
                      ),
                    if (WorkFeature.values
                        .any((f) => controller.menuEnabled(f.name)))
                      _drawerSection(
                        context,
                        'ACTIVITY & RECORDS',
                        showDivider: true,
                      ),
                    for (final feature in WorkFeature.values.where(
                      (f) =>
                          f == WorkFeature.inbox ||
                          controller.menuEnabled(f.name),
                    ))
                      _drawerItem(
                        context: context,
                        icon: feature.icon,
                        iconColor: _featureColor(feature),
                        title: feature.title,
                        subtitle: _featureSubtitle(feature),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => feature == WorkFeature.visits
                                  ? VisitsPage(controller: controller)
                                  : feature == WorkFeature.locations
                                      ? DutyRoutePage(controller: controller)
                                      : WorkspacePage(
                                          controller: controller,
                                          feature: feature,
                                        ),
                            ),
                          );
                        },
                      ),
                    if (controller.menuEnabled('app_theme') ||
                        controller.menuEnabled('change_password') ||
                        controller.menuEnabled('restore_history') ||
                        controller.menuEnabled('local_db_inspector') ||
                        controller.menuEnabled('error_logs') ||
                        (openSetup != null &&
                            controller.menuEnabled('setup_checklist')))
                      _drawerSection(
                        context,
                        'PREFERENCES & TOOLS',
                        showDivider: true,
                      ),
                    if (controller.menuEnabled('app_theme'))
                      _drawerItem(
                        context: context,
                        icon: controller.isBetaMode
                            ? Icons.nightlight_round
                            : Icons.palette_rounded,
                        iconColor: controller.isBetaMode
                            ? const Color(0xff6366f1)
                            : controller.isDarkMode
                                ? const Color(0xffa78bfa)
                                : const Color(0xff0284c7),
                        title: 'App Theme',
                        subtitle: 'Switch between Dark, Classic & Beta Luxury',
                        badge: controller.isBetaMode
                            ? 'Beta Luxury'
                            : controller.isDarkMode
                                ? 'Dark'
                                : 'Classic',
                        onTap: () {
                          Navigator.pop(context);
                          showThemeSelectorModal(context, controller);
                        },
                      ),
                    if (controller.menuEnabled('change_password'))
                      _drawerItem(
                        context: context,
                        icon: Icons.lock_reset_rounded,
                        iconColor: const Color(0xffd97706),
                        title: 'Change Password',
                        subtitle: 'Update your login password',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ChangePasswordPage(controller: controller),
                            ),
                          );
                        },
                      ),
                    if (controller.menuEnabled('restore_history'))
                      _drawerItem(
                        context: context,
                        icon: Icons.cloud_download_rounded,
                        iconColor: const Color(0xff2563eb),
                        title: 'Restore Phone History',
                        subtitle: 'Recover attendance & visits from server',
                        onTap: () async {
                          Navigator.pop(context);
                          await controller.refresh();
                        },
                      ),
                    if (controller.menuEnabled('local_db_inspector'))
                      _drawerItem(
                        context: context,
                        icon: Icons.storage_rounded,
                        iconColor: const Color(0xff0284c7),
                        title: 'Local DB & Sync Inspector',
                        subtitle: 'View pending outbox & cached records',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => LocalDatabaseInspectorPage(
                                controller: controller,
                              ),
                            ),
                          );
                        },
                      ),
                    if (controller.menuEnabled('error_logs'))
                      _drawerItem(
                        context: context,
                        icon: Icons.bug_report_outlined,
                        iconColor: const Color(0xffdc2626),
                        title: 'App Error Logs',
                        subtitle: 'Diagnostics & crash trace viewer',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const ErrorLogsPage(),
                            ),
                          );
                        },
                      ),
                    if (openSetup != null &&
                        controller.menuEnabled('setup_checklist'))
                      _drawerItem(
                        context: context,
                        icon: Icons.verified_user_outlined,
                        iconColor: const Color(0xff059669),
                        title: 'Device Setup Checklist',
                        subtitle: 'GPS, battery, clone app & permissions',
                        onTap: () {
                          Navigator.pop(context);
                          openSetup!();
                        },
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      await controller.signOut();
                    },
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Sign out'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkspaceData extends ChangeNotifier {
  final TrackyuController session;
  final WorkFeature feature;
  bool loading = false;
  bool saving = false;
  bool more = false;
  bool team = false;
  bool _disposed = false;
  int _revision = 0;
  int page = 1;
  int? officeId;
  DateTime from = DateTime.now().subtract(const Duration(days: 6));
  DateTime to = DateTime.now();
  Json? profile;
  List<Json> rows = [];
  List<Json> leaveReasons = [];
  String? error;

  WorkspaceData(this.session, this.feature);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  List<Json> get offices =>
      profile == null ? [] : jsonRows(profile!['offices']);
  List<Json> get members =>
      offices.where((o) => o['isMember'] == true).toList();
  List<Json> get managers =>
      offices.where((o) => o['canManage'] == true).toList();
  List<Json> get choices => team ? managers : members;

  bool get needsOffice =>
      feature.officeScoped || (team && feature.teamSupported);

  bool get canCreate {
    if (!feature.writable || team) return false;
    if (feature == WorkFeature.leave || feature == WorkFeature.intimation) {
      return profile != null;
    }
    return members.isNotEmpty;
  }

  Future<dynamic> request(String route, {Json? body}) async {
    try {
      return await session.api.request(route, body: body);
    } on ApiFailure catch (e) {
      if (e.status == 401) {
        session.setOffline(true);
      }
      rethrow;
    }
  }

  Future<void> load({bool append = false}) async {
    final revision = ++_revision;
    if (!append) {
      page = 1;
      error = null;
    }
    loading = true;
    notifyListeners();
    try {
      if (profile == null) {
        final p = Map<String, dynamic>.from(
          await request('Portal/profile') as Map,
        );
        if (_disposed || revision != _revision) return;
        profile = p;
      }
      if (feature == WorkFeature.leave && leaveReasons.isEmpty) {
        try {
          leaveReasons = jsonRows(await request('OfficeLeave/reasons'));
        } catch (_) {}
      }
      if (!choices.any((o) => o['id'] == officeId)) {
        officeId = choices.firstOrNull?['id'] as int?;
      }
      if (needsOffice && officeId == null) {
        rows = [];
        more = false;
        loading = false;
        notifyListeners();
        return;
      }

      final query = <String, dynamic>{
        'fromDate': dateOnly(from),
        'toDate': dateOnly(to),
        'month': from.month,
        'year': from.year,
        'page': page,
        'pageSize': 50,
        if (officeId != null) 'officeId': officeId,
      };

      dynamic data;
      switch (feature) {
        case WorkFeature.history:
          final res = await request(
            team ? 'Portal/team-attendance' : 'Portal/attendance',
            body: query,
          );
          data = res is Map ? res['rows'] : res;
        case WorkFeature.locations:
          data = await request(
            'Portal/locations',
            body: {'date': dateOnly(to)},
          );
        case WorkFeature.leave:
          data = await request(
            team ? 'OfficeLeave/team' : 'OfficeLeave/mine',
            body: query,
          );
        case WorkFeature.activity:
          data = await request(
            team ? 'OfficeActivities/team' : 'OfficeActivities/mine',
            body: query,
          );
        case WorkFeature.reminder:
          data = await request('OfficeReminders/mine');
        case WorkFeature.intimation:
          data = await request(
            team
                ? 'OfficePreIntimation/team'
                : (members.isEmpty
                    ? 'OfficePreIntimation/personal'
                    : 'OfficePreIntimation/mine'),
            body: team ? query : null,
          );
        case WorkFeature.inbox:
          data = await request('WorkforceInbox/mine');
        case WorkFeature.visits:
          final selectedDateStr = dateOnly(to);
          List<Json> modernList = [];
          try {
            modernList = jsonRows(
              await request('MobileVisits/mine?date=$selectedDateStr'),
            );
          } catch (_) {}
          List<Json> legacyList = [];
          try {
            final visits = await request(
              'Portal/visits',
              body: {'date': selectedDateStr},
            ) as Map;
            legacyList = [
              ...jsonRows(visits['modern'] ?? []),
              ...jsonRows(visits['regular'])
                  .map((r) => {...r, 'visitKind': 'Regular'}),
              ...jsonRows(visits['open'])
                  .map((r) => {...r, 'visitKind': 'Open'}),
            ];
          } catch (_) {}
          final byKey = <String, Json>{};
          for (final row in [...modernList, ...legacyList]) {
            final k = row['id']?.toString() ??
                row['requestId']?.toString() ??
                '${row['shopName']}_${row['checkInUtc']}';
            byKey.putIfAbsent(k, () => row);
          }
          data = byKey.values.toList();
        case WorkFeature.orders:
          data = await request('Portal/orders', body: {'date': dateOnly(to)});
        case WorkFeature.tasks:
          data = await request('Portal/tasks', body: query);
        case WorkFeature.offices:
          data = offices;
      }

      if (_disposed || revision != _revision) return;
      final received = jsonRows(data);
      rows = append ? [...rows, ...received] : received;
      more = received.length >= 50;
      error = null;
    } on ApiFailure catch (e) {
      if (_disposed || revision != _revision) return;
      error = e.message;
      if (!append) rows = [];
    } catch (e) {
      if (_disposed || revision != _revision) return;
      error = e.toString();
      if (!append) rows = [];
    } finally {
      if (!_disposed && revision == _revision) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> save(String route, Json body) async {
    saving = true;
    error = null;
    notifyListeners();
    try {
      await request(route, body: body);
      await load();
      return true;
    } on ApiFailure catch (e) {
      error = e.message;
      return false;
    } finally {
      saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> action(String route, Json body) => save(route, body);
}

class WorkspacePage extends StatefulWidget {
  final TrackyuController controller;
  final WorkFeature feature;
  const WorkspacePage({
    super.key,
    required this.controller,
    required this.feature,
  });

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  late final WorkspaceData data;
  DateTime? selectedCalendarDay;
  bool exporting = false;

  WorkFeature get feature => widget.feature;

  @override
  void initState() {
    super.initState();
    data = WorkspaceData(widget.controller, widget.feature);
    data.addListener(_onUpdate);
    unawaited(data.load());
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    data.removeListener(_onUpdate);
    data.dispose();
    super.dispose();
  }

  Future<void> chooseDate(bool isFrom) async {
    final initial = isFrom ? data.from : data.to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        data.from = picked;
        if (data.from.isAfter(data.to)) data.to = picked;
      } else {
        data.to = picked;
        if (data.to.isBefore(data.from)) data.from = picked;
      }
    });
    await data.load();
  }

  Future<void> edit([Json? row]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkspaceForm(data: data, row: row),
      ),
    );
    if (saved == true && mounted) {
      await data.load();
    }
  }

  Future<void> export() async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      await saveAttendanceExport(data.rows);
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Widget recordCard(Json row) {
    String title = valueOf(row, 'title', valueOf(row, 'name', feature.title));
    String badge = valueOf(row, 'status', '');
    Map<String, String> details = {};

    switch (feature) {
      case WorkFeature.history:
        final dateStr = recordDate(row['workDate']);
        title = 'Attendance · $dateStr';
        final hasIn = (row['punchInUtc'] ?? '').toString().trim().isNotEmpty;
        final hasOut = (row['punchOutUtc'] ?? '').toString().trim().isNotEmpty;
        final mode = valueOf(row, 'attendanceMode', '').trim();
        final modeLabel = (mode.isNotEmpty && mode != '—') ? mode : '';
        if (hasIn && !hasOut) {
          badge = modeLabel.isNotEmpty ? '$modeLabel · Punched in' : 'Punched in';
        } else if (hasIn && hasOut) {
          badge = modeLabel.isNotEmpty ? '$modeLabel · Completed' : 'Completed';
        } else {
          badge = modeLabel;
        }
        details = {
          'Punch in': localTimeOnly(row['punchInUtc']),
          'Punch out': localTimeOnly(row['punchOutUtc']),
        };
      case WorkFeature.leave:
        title = valueOf(row, 'reasonName', valueOf(row, 'reason', 'Leave'));
        badge = valueOf(row, 'status', 'Pending');
        details = {
          'From': recordDate(row['fromDate']),
          'To': recordDate(row['toDate']),
          'Remarks': valueOf(row, 'reason'),
        };
      case WorkFeature.activity:
        title = valueOf(row, 'title', 'Activity');
        badge = valueOf(row, 'status', 'Planned');
        details = {
          'Date': recordDate(row['activityDate']),
          'Minutes': '${valueOf(row, 'minutesSpent', '0')} min',
        };
      case WorkFeature.reminder:
        title = valueOf(row, 'title', 'Reminder');
        badge = row['isEnabled'] == false ? 'Paused' : 'Active';
        details = {'Remind at': localStamp(row['remindAtUtc'])};
      case WorkFeature.intimation:
        title = valueOf(row, 'userName', valueOf(row, 'userId', 'Late arrival'));
        badge = valueOf(row, 'status', 'Submitted');
        details = {
          'Expected': localStamp(row['expectedArrivalUtc']),
          'Reason': valueOf(row, 'reason'),
        };
      case WorkFeature.inbox:
        title = valueOf(row, 'title', 'Notification');
        badge = row['isRead'] == true ? 'Read' : 'Unread';
        details = {
          'Message': valueOf(row, 'message', valueOf(row, 'body')),
          'Received': localStamp(row['createdAtUtc']),
        };
      case WorkFeature.visits:
        title = valueOf(row, 'shopName', valueOf(row, 'clientName', 'Visit'));
        final regular = row['visitKind'] == 'Regular' || row['kind'] == 'Regular';
        badge = regular ? 'Retailer visit' : 'Open visit';
        details = {
          'Check in': localTimeOnly(row['checkInUtc'] ?? row['intime']),
          'Check out': localTimeOnly(row['checkOutUtc'] ?? row['outtime']),
        };
      case WorkFeature.offices:
        title = valueOf(row, 'name');
        badge = row['isEnabled'] == true ? 'Enabled' : 'Disabled';
        details = {
          'Shift starts': valueOf(row, 'shiftStart'),
          'Shift ends': valueOf(row, 'shiftEnd'),
          'Time zone': valueOf(row, 'timeZoneId'),
          'Office radius': '${valueOf(row, 'radiusMeters')} m',
          'Late grace': '${valueOf(row, 'lateGraceMinutes')} min',
        };
      default:
        details = {'Date': recordDate(row['workDate'] ?? row['createdAtUtc'])};
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (badge.isNotEmpty && badge != '—')
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xff0284c7).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xff0284c7),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final e in details.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${e.key}: ${e.value}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            if (feature == WorkFeature.inbox && row['isRead'] != true)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: data.saving
                      ? null
                      : () async {
                          unawaited(LocalInboxStorage.markRead(row['id']));
                          try {
                            await data.action('WorkforceInbox/read', {
                              'notificationId': row['id'],
                            });
                          } catch (_) {}
                        },
                  child: const Text('Mark read'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = feature == WorkFeature.history &&
            selectedCalendarDay != null
        ? data.rows.where((r) {
            final dt = DateTime.tryParse('${r['workDate'] ?? ''}')?.toLocal();
            return dt != null &&
                dt.year == selectedCalendarDay!.year &&
                dt.month == selectedCalendarDay!.month &&
                dt.day == selectedCalendarDay!.day;
          }).toList()
        : data.rows;

    return Scaffold(
      appBar: buildTrackyuAppBar(
        context: context,
        controller: widget.controller,
        title: feature == WorkFeature.visits ? 'Open visit history' : feature.title,
        trailingActions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: data.loading || data.saving ? null : () => data.load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: feature == WorkFeature.offices
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      OfficeLocationRequestPage(controller: widget.controller),
                ),
              ),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add office location'),
            )
          : feature == WorkFeature.visits
              ? FloatingActionButton.extended(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VisitsPage(controller: widget.controller),
                    ),
                  ),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Start / manage visits'),
                )
              : data.canCreate
                  ? FloatingActionButton.extended(
                      onPressed: data.loading || data.saving ? null : () => edit(),
                      icon: const Icon(Icons.add),
                      label: Text(
                        feature == WorkFeature.leave
                            ? 'Apply leave'
                            : feature == WorkFeature.intimation
                                ? 'Notify late arrival'
                                : 'Add',
                      ),
                    )
                  : null,
      body: RefreshIndicator(
        onRefresh: () => data.load(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            if (feature.teamSupported && data.managers.isNotEmpty)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Team view'),
                subtitle: const Text('Only offices you manage'),
                value: data.team,
                onChanged: data.loading
                    ? null
                    : (value) {
                        data.team = value;
                        data.officeId = null;
                        data.load();
                      },
              ),
            if (data.needsOffice && data.choices.isNotEmpty)
              DropdownButtonFormField<int>(
                key: ValueKey('${data.team}-${data.officeId}'),
                initialValue: data.officeId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Office'),
                items: data.choices
                    .map(
                      (o) => DropdownMenuItem(
                        value: o['id'] as int,
                        child: Text(
                          o['name'].toString(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: data.loading
                    ? null
                    : (value) {
                        data.officeId = value;
                        data.load();
                      },
              ),
            if (feature == WorkFeature.history)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AttendanceCalendarCard(
                  rows: data.rows,
                  currentMonth: data.from,
                  selectedDay: selectedCalendarDay,
                  isDark: Theme.of(context).brightness == Brightness.dark,
                  api: widget.controller.api,
                  employeeName: data.profile?['name']?.toString() ??
                      widget.controller.user?['name']?.toString() ??
                      widget.controller.user?['SM_USER_ID']?.toString(),
                  onMonthChanged: (newMonth) async {
                    setState(() {
                      selectedCalendarDay = null;
                      data.from = DateTime(newMonth.year, newMonth.month, 1);
                      final lastDay =
                          DateTime(newMonth.year, newMonth.month + 1, 0);
                      final today = DateTime.now();
                      data.to = (newMonth.year == today.year &&
                              newMonth.month == today.month)
                          ? today
                          : lastDay;
                    });
                    await data.load();
                  },
                  onDaySelected: (day) {
                    setState(() => selectedCalendarDay = day);
                  },
                ),
              ),
            if (feature != WorkFeature.history &&
                ([
                  WorkFeature.locations,
                  WorkFeature.leave,
                  WorkFeature.activity,
                  WorkFeature.intimation,
                  WorkFeature.tasks,
                  WorkFeature.visits,
                  WorkFeature.orders,
                ].contains(feature) ||
                    data.team))
              WorkflowDateFields(
                from: data.from,
                to: data.to,
                single: [
                  WorkFeature.visits,
                  WorkFeature.orders,
                  WorkFeature.locations,
                ].contains(feature),
                onFrom: data.loading ? null : () => chooseDate(true),
                onTo: data.loading ? null : () => chooseDate(false),
              ),
            if (feature == WorkFeature.history && data.rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Text(
                      selectedCalendarDay != null
                          ? '${visibleRows.length} of ${data.rows.length} records'
                          : '${data.rows.length} days recorded',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: exporting || data.loading ? null : export,
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: Text(exporting ? 'Saving...' : 'Export CSV'),
                    ),
                  ],
                ),
              ),
            if (data.error != null)
              Card(
                color: const Color(0xffffece8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data.error!),
                      TextButton(
                        onPressed: () => data.load(),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
            if (data.loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (feature == WorkFeature.locations && data.error == null)
              PunchLocationMap(rows: data.rows),
            if (data.error == null)
              for (final row in visibleRows) recordCard(row),
            if (data.more && !data.loading)
              TextButton(
                onPressed: () {
                  data.page++;
                  data.load(append: true);
                },
                child: const Text('Load more'),
              ),
          ],
        ),
      ),
    );
  }
}

class WorkspaceForm extends StatefulWidget {
  final WorkspaceData data;
  final Json? row;
  const WorkspaceForm({super.key, required this.data, this.row});

  @override
  State<WorkspaceForm> createState() => _WorkspaceFormState();
}

class _WorkspaceFormState extends State<WorkspaceForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _reasonCtrl;
  late final TextEditingController _minutesCtrl;
  int? _reasonId;
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  DateTime _expectedArrival = DateTime.now().add(const Duration(minutes: 30));

  WorkFeature get feature => widget.data.feature;

  @override
  void initState() {
    super.initState();
    final r = widget.row ?? {};
    _titleCtrl = TextEditingController(text: '${r['title'] ?? ''}');
    _reasonCtrl = TextEditingController(text: '${r['reason'] ?? ''}');
    _minutesCtrl =
        TextEditingController(text: '${r['minutesSpent'] ?? 15}');
    _reasonId = r['reasonId'] as int? ??
        widget.data.leaveReasons.firstOrNull?['id'] as int?;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _reasonCtrl.dispose();
    _minutesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    bool ok = false;
    if (feature == WorkFeature.leave) {
      ok = await widget.data.save('OfficeLeave/apply', {
        if (widget.data.officeId != null) 'officeId': widget.data.officeId,
        if (_reasonId != null) 'reasonId': _reasonId,
        'fromDate': dateOnly(_fromDate),
        'toDate': dateOnly(_toDate),
        'reason': _reasonCtrl.text.trim(),
      });
    } else if (feature == WorkFeature.intimation) {
      ok = await widget.data.save('OfficePreIntimation/submit', {
        if (widget.data.officeId != null) 'officeId': widget.data.officeId,
        'expectedArrivalUtc': _expectedArrival.toUtc().toIso8601String(),
        'reason': _reasonCtrl.text.trim(),
      });
    } else if (feature == WorkFeature.activity) {
      ok = await widget.data.save('OfficeActivities/save', {
        if (widget.row?['id'] != null) 'id': widget.row!['id'],
        if (widget.row?['version'] != null) 'version': widget.row!['version'],
        if (widget.data.officeId != null) 'officeId': widget.data.officeId,
        'title': _titleCtrl.text.trim(),
        'activityDate': dateOnly(_fromDate),
        'minutesSpent': int.tryParse(_minutesCtrl.text.trim()) ?? 0,
        'status': widget.row?['status'] ?? 'Planned',
      });
    } else if (feature == WorkFeature.reminder) {
      ok = await widget.data.save('OfficeReminders/save', {
        if (widget.row?['id'] != null) 'id': widget.row!['id'],
        if (widget.data.officeId != null) 'officeId': widget.data.officeId,
        'title': _titleCtrl.text.trim(),
        'remindAtUtc': _expectedArrival.toUtc().toIso8601String(),
        'isEnabled': true,
      });
    }
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final saveLabel = feature == WorkFeature.intimation
        ? 'Send pre-intimation'
        : feature == WorkFeature.leave
            ? 'Apply leave'
            : 'Save';
    return Scaffold(
      appBar: AppBar(title: Text(feature.title)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (feature == WorkFeature.leave) ...[
              const Text(
                'Plan your time off',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (widget.data.leaveReasons.isNotEmpty)
                DropdownButtonFormField<int>(
                  initialValue: _reasonId,
                  decoration: const InputDecoration(labelText: 'Leave reason'),
                  items: widget.data.leaveReasons
                      .map(
                        (r) => DropdownMenuItem(
                          value: r['id'] as int,
                          child: Text('${r['name'] ?? ''}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _reasonId = v),
                ),
              const SizedBox(height: 12),
              WorkflowDateFields(
                from: _fromDate,
                to: _toDate,
                onFrom: () async {
                  final p = await showDatePicker(
                    context: context,
                    initialDate: _fromDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (p != null) setState(() => _fromDate = p);
                },
                onTo: () async {
                  final p = await showDatePicker(
                    context: context,
                    initialDate: _toDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (p != null) setState(() => _toDate = p);
                },
              ),
            ],
            if (feature == WorkFeature.activity ||
                feature == WorkFeature.reminder) ...[
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
            ],
            if (feature == WorkFeature.activity)
              TextFormField(
                controller: _minutesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minutes'),
              ),
            if (feature == WorkFeature.leave ||
                feature == WorkFeature.intimation)
              TextFormField(
                controller: _reasonCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: feature == WorkFeature.leave
                      ? 'Remarks / details'
                      : 'Reason',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            if (widget.data.error != null) ...[
              const SizedBox(height: 12),
              Text(
                widget.data.error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: widget.data.saving ? null : _submit,
              child: Text(saveLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class ChangePasswordPage extends StatefulWidget {
  final TrackyuController controller;
  const ChangePasswordPage({super.key, required this.controller});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.api.request(
        'Auth/change-password',
        body: {
          'currentPassword': _oldCtrl.text,
          'newPassword': _newCtrl.text,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated successfully.')),
        );
        Navigator.pop(context);
      }
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _oldCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _newCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
              validator: (v) => (v == null || v.length < 4)
                  ? 'Minimum 4 characters'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Confirm new password'),
              validator: (v) =>
                  v != _newCtrl.text ? 'Passwords do not match' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: Text(_saving ? 'Updating...' : 'Update Password'),
            ),
          ],
        ),
      ),
    );
  }
}
