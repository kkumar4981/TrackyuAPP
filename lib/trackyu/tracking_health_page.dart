import 'dart:async';

import 'package:flutter/material.dart';

import 'package:geolocator/geolocator.dart';

import 'package:permission_handler/permission_handler.dart';

import 'controller.dart';

import 'duty_tracking.dart';

/// Real-time Tracking Health diagnostics screen.

/// Gives employees and managers 100% transparency into foreground service status,

/// GPS accuracy, battery exemptions, offline pending queues, and OEM background restrictions.

class TrackingHealthPage extends StatefulWidget {

  final TrackyuController controller;

  const TrackingHealthPage({super.key, required this.controller});

  @override

  State<TrackingHealthPage> createState() => _TrackingHealthPageState();

}

class _TrackingHealthPageState extends State<TrackingHealthPage> {

  Timer? _timer;

  bool _loading = true;

  Map<String, dynamic> _health = {};

    bool _syncing = false;

  @override

  void initState() {

    super.initState();

    _fullRefresh();

    // Lightweight polling every 8s: reads in-memory native service state only (no IPC/SQLite overhead)

    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _lightweightPoll());

  }

  @override

  void dispose() {

    _timer?.cancel();

    super.dispose();

  }

  /// Full diagnostics refresh with OS permission & accuracy check (on page open & manual refresh)

  Future<void> _fullRefresh() async {

    try {

      final data = await DutyTracker.health();

      final dev = await DutyTracker.deviceInfo();

      final gpsService = await Geolocator.isLocationServiceEnabled();

      final perm = await Geolocator.checkPermission();

      final hasAcc = await Geolocator.getLocationAccuracy();

      if (mounted) {

        setState(() {

          _health = {

            ...dev,

            ...data,

            'gpsServiceEnabled': gpsService,

            'permissionLevel': perm.name,

            'isPrecise': hasAcc == LocationAccuracyStatus.precise,

          };

          _loading = false;

        });

      }

    } catch (e) {

      if (mounted) setState(() => _loading = false);

    }

  }

  /// Lightweight periodic poll: only updates in-memory tracking health state

  Future<void> _lightweightPoll() async {

    try {

      final data = await DutyTracker.health();

      if (mounted && data.isNotEmpty) {

        setState(() {

          _health = {

            ..._health,

            ...data,

          };

        });

      }

    } catch (_) {}

  }

  Future<void> _refresh() => _fullRefresh();

  Future<void> _fixBattery() async {

    await DutyTracker.batterySettings();

    await _refresh();

  }

  Future<void> _fixAutostart() async {

    await DutyTracker.autostartSettings();

    await _refresh();

  }

  Future<void> _fixBackgroundPerm() async {

    await openAppSettings();

    await _refresh();

  }

  Future<void> _syncNow() async {

    setState(() => _syncing = true);

    try {

      await DutyTracker.sync();

      await widget.controller.syncData();

    } finally {

      if (mounted) {

        setState(() => _syncing = false);

        await _refresh();

      }

    }

  }

  Future<void> _clearStaleOutbox() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Stuck Outbox?'),
        content: const Text(
          'Do you want to reset the offline outbox?\n\nThis clears stuck sync items and restarts fresh server synchronization.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xffdc2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear & Resync'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _syncing = true);
    try {
      await widget.controller.clearStalePendingQueues();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Outbox queue cleared. Fresh sync complete.'),
            backgroundColor: Color(0xff16a34a),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _freshFix() async {

    setState(() => _syncing = true);

    try {

      await DutyTracker.requestFreshFix(

        userId: widget.controller.employeeId,

        baseUrl: widget.controller.api.baseUrl,

      );

    } finally {

      if (mounted) {

        setState(() => _syncing = false);

        await _refresh();

      }

    }

  }

  @override

  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;

    final brand = (_health['deviceBrand'] ?? _health['brand'] ?? 'Android').toString().toUpperCase();

    final model = (_health['deviceModel'] ?? _health['model'] ?? '').toString();

    final sdk = _health['androidSdk'] ?? _health['sdk'] ?? '';

    final isRunning = _health['foregroundServiceRunning'] == true;

    final serviceStatus = (_health['serviceStatus'] ?? 'Idle').toString();

    final batteryExempt = _health['batteryExempt'] == true;

    final gpsOn = _health['gpsServiceEnabled'] == true || _health['gpsEnabled'] == true;

    final permLevel = (_health['permissionLevel'] ?? '').toString();

    final isAlways = permLevel == 'always';

    final isWhileInUse = permLevel == 'whileInUse';

    final hasLocation = isAlways || isWhileInUse;

    final isPrecise = _health['isPrecise'] == true;

    final pendingCount = (_health['pendingCount'] as num?)?.toInt() ?? 0;
    final pendingPunches = widget.controller.pendingPunchesCount;
    final pendingVisits = widget.controller.pendingVisitsCount;
    final syncError = widget.controller.lastSyncError;
    final totalPending = pendingCount + pendingPunches + pendingVisits;

    final rejectedCount = (_health['rejectedCount'] as num?)?.toInt() ?? 0;

    final lastFixUtc = (_health['lastFixAtUtc'] ?? '').toString();

    final lastSyncUtc = (_health['lastSyncAtUtc'] ?? '').toString();

    final lastAcc = (_health['lastAccuracyMeters'] as num?)?.toDouble();

    final lastLat = (_health['lastLatitude'] as num?)?.toDouble();

    final lastLng = (_health['lastLongitude'] as num?)?.toDouble();

    final lastBat = (_health['lastBatteryPercent'] as num?)?.toInt();

    final requiresAutostart = _health['requiresAutostart'] == true;
    final autostartSettingsOpened = _health['autostartSettingsOpened'] == true;

    // Health score: autostart status cannot be verified by public Android OS APIs.

    // Unverified autostart is marked as a manual check tile, not a blocking red/yellow warning.

    final hasWarning = !batteryExempt || !isAlways || !gpsOn;

    final isCritical = !hasLocation || !gpsOn;

    return Scaffold(

      appBar: AppBar(

        title: const Text('Tracking Health Diagnostics', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),

        actions: [

          IconButton(

            icon: _syncing

                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))

                : const Icon(Icons.refresh_rounded),

            onPressed: _syncing ? null : _refresh,

            tooltip: 'Refresh',

          ),

        ],

      ),

      body: _loading

          ? const Center(child: CircularProgressIndicator())

          : ListView(

              padding: const EdgeInsets.all(16),

              children: [

                // Top Status Overview Card

                _buildOverviewCard(

                  isDark: isDark,

                  brand: brand,

                  model: model,

                  sdk: sdk,

                  isCritical: isCritical,

                  hasWarning: hasWarning,

                  isRunning: isRunning,

                ),

                const SizedBox(height: 16),

                // Action Required Warning if not optimal

                if (hasWarning)

                  _buildActionRequiredBanner(

                    isDark: isDark,

                    batteryExempt: batteryExempt,

                    isAlways: isAlways,

                    gpsOn: gpsOn,

                    requiresAutostart: requiresAutostart,

                    autostartSettingsOpened: autostartSettingsOpened,

                    brand: brand,

                  ),

                const SizedBox(height: 16),

                // 4 Pillars of Health

                Text(

                  'CORE HEALTH CHECKS',

                  style: TextStyle(

                    fontSize: 12,

                    fontWeight: FontWeight.w700,

                    letterSpacing: 1.1,

                    color: isDark ? Colors.grey[400] : Colors.grey[600],

                  ),

                ),

                const SizedBox(height: 8),

                // 1. GPS Permission

                _buildDiagnosticTile(

                  icon: Icons.location_on_rounded,

                  title: 'GPS & Location Permission',

                  subtitle: !hasLocation

                      ? 'Denied — Tracking cannot function'

                      : isAlways

                          ? 'Allow all the time (Continuous background)'

                          : 'Only while using app — May sleep when screen locks',

                  status: isAlways ? 'Granted' : (hasLocation ? 'Needs review' : 'Denied'),

                  statusColor: isAlways ? Colors.green : (hasLocation ? Colors.orange : Colors.red),

                  actionText: isAlways ? null : 'Fix Permission',

                  onAction: _fixBackgroundPerm,

                  isDark: isDark,

                ),

                // 2. Battery Optimization

                _buildDiagnosticTile(

                  icon: Icons.battery_charging_full_rounded,

                  title: 'Battery Optimization',

                  subtitle: batteryExempt

                      ? 'Unrestricted — Android will not kill service'

                      : 'Optimized / Restricted — $brand may kill background GPS',

                  status: batteryExempt ? 'Unrestricted' : 'Needs review',

                  statusColor: batteryExempt ? Colors.green : Colors.orange,

                  actionText: batteryExempt ? null : 'Set Unrestricted',

                  onAction: _fixBattery,

                  isDark: isDark,

                ),

                // 3. Auto-start (if OEM requires it)

                // NOTE: Android OS provides no public API for 3rd-party apps to verify OEM autostart switch.

                // We transparently report "User Action Required" rather than falsely claiming "Configured".

                if (requiresAutostart)

                  _buildDiagnosticTile(

                    icon: Icons.power_settings_new_rounded,

                    title: 'OEM Auto-start ($brand)',

                    subtitle: _health['autostartSettingsOpened'] == true

                        ? 'Settings page was opened. Android cannot verify toggle status — ensure Trackyu is ON in $brand.'

                        : 'Required so $brand does not terminate GPS when phone is locked.',

                    status: 'Manual check',

                    statusColor: Colors.orange,

                    actionText: 'Open $brand Settings',

                    onAction: _fixAutostart,

                    isDark: isDark,

                  ),

                // 4. Foreground Tracking Service

                _buildDiagnosticTile(

                  icon: Icons.alt_route_rounded,

                  title: 'Tracking Service',

                  subtitle: isRunning

                      ? 'Running: $serviceStatus'

                      : 'Idle (Will start automatically when Punched In)',

                  status: isRunning ? 'Running' : 'Idle',

                  statusColor: isRunning ? Colors.green : Colors.blueGrey,

                  actionText: isRunning ? 'Fresh GPS Fix' : null,

                  onAction: isRunning ? _freshFix : null,

                  isDark: isDark,

                ),

                // 5. Offline Storage & Cloud Sync Queue
                _buildDiagnosticTile(
                  icon: Icons.cloud_sync_rounded,
                  title: 'Cloud Sync & Outbox',
                  subtitle: (totalPending == 0 && syncError == null)
                      ? 'All attendance punches, visits & GPS points synced'
                      : '${pendingPunches > 0 ? '$pendingPunches punch(es) pending, ' : ''}'
                        '${pendingVisits > 0 ? '$pendingVisits visit(s) pending, ' : ''}'
                        '${pendingCount > 0 ? '$pendingCount GPS points' : ''}'
                        '${syncError != null ? '\nIssue: $syncError' : ' waiting to upload'}',
                  status: syncError != null
                      ? 'Sync Issue'
                      : (totalPending == 0 ? 'Healthy' : '$totalPending pending'),
                  statusColor: syncError != null
                      ? Colors.red
                      : (totalPending > 0 ? Colors.orange : Colors.green),
                  actionText: (syncError != null || totalPending > 0) ? 'Sync Now' : 'Check Sync',
                  onAction: _syncNow,
                  isDark: isDark,
                ),

                if (syncError != null || pendingPunches > 0 || pendingVisits > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xff451a1a) : const Color(0xfffef2f2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xffef4444).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xffdc2626), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Outbox Sync Alert',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: isDark ? Colors.white : const Color(0xff991b1b),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          syncError != null
                              ? 'Server synchronization issue:\n$syncError\n\nIf stuck punches or visits are conflicting, tap "Clear Stuck Outbox" below.'
                              : '$totalPending items in outbox waiting to sync with server.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : const Color(0xff7f1d1d),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xffdc2626),
                                  side: const BorderSide(color: Color(0xffdc2626)),
                                ),
                                onPressed: _syncing ? null : _clearStaleOutbox,
                                icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                                label: const Text('Clear Stuck Outbox', style: TextStyle(fontSize: 11.5)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xff16a34a),
                                ),
                                onPressed: _syncing ? null : _syncNow,
                                icon: const Icon(Icons.sync_rounded, size: 16),
                                label: const Text('Sync Now', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Telemetry Details Section

                Text(

                  'LIVE TELEMETRY DETAILS',

                  style: TextStyle(

                    fontSize: 12,

                    fontWeight: FontWeight.w700,

                    letterSpacing: 1.1,

                    color: isDark ? Colors.grey[400] : Colors.grey[600],

                  ),

                ),

                const SizedBox(height: 8),

                Container(

                  padding: const EdgeInsets.all(16),

                  decoration: BoxDecoration(

                    color: isDark ? const Color(0xff1e293b) : Colors.white,

                    borderRadius: BorderRadius.circular(16),

                    border: Border.all(color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0)),

                  ),

                  child: Column(

                    children: [

                      _buildTelemetryRow('Last Fix (Phone UTC)', lastFixUtc.isEmpty ? 'Waiting...' : lastFixUtc),

                      const Divider(height: 16),

                      _buildTelemetryRow('Last Upload', lastSyncUtc.isEmpty ? 'None' : lastSyncUtc),
                      const Divider(height: 16),
                      _buildTelemetryRow('Pending Punches', '$pendingPunches waiting'),
                      const Divider(height: 16),
                      _buildTelemetryRow('Pending Visits', '$pendingVisits waiting'),
                      const Divider(height: 16),
                      _buildTelemetryRow('Sync Health', syncError == null ? 'Healthy (No issues)' : 'Issue: $syncError'),

                      const Divider(height: 16),

                      _buildTelemetryRow(

                        'Location Accuracy',

                        lastAcc != null ? '±${lastAcc.toStringAsFixed(1)} m ${isPrecise ? '🎯 (Precise)' : '⚠️ (Approx)'}' : 'Unknown',

                      ),

                      const Divider(height: 16),

                      _buildTelemetryRow('Coordinates', lastLat != null && lastLng != null ? '${lastLat.toStringAsFixed(5)}, ${lastLng.toStringAsFixed(5)}' : 'No fix yet'),

                      const Divider(height: 16),

                      _buildTelemetryRow('Battery Level', lastBat != null && lastBat >= 0 ? '$lastBat%' : 'Unknown'),

                      const Divider(height: 16),

                      _buildTelemetryRow('Rejected Samples', '$rejectedCount (Drift / Inaccurate / Mock)'),

                    ],

                  ),

                ),

                const SizedBox(height: 24),

                // Bottom Action Buttons

                Row(

                  children: [

                    Expanded(

                      child: OutlinedButton.icon(

                        onPressed: _syncNow,

                        icon: const Icon(Icons.sync_rounded),

                        label: const Text('Sync All Data'),

                        style: OutlinedButton.styleFrom(

                          minimumSize: const Size.fromHeight(48),

                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

                        ),

                      ),

                    ),

                    const SizedBox(width: 12),

                    Expanded(

                      child: FilledButton.icon(

                        onPressed: _fixBattery,

                        icon: const Icon(Icons.battery_saver_rounded),

                        label: const Text('Battery Settings'),

                        style: FilledButton.styleFrom(

                          minimumSize: const Size.fromHeight(48),

                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

                        ),

                      ),

                    ),

                  ],

                ),

                const SizedBox(height: 16),

              ],

            ),

    );

  }

  Widget _buildOverviewCard({

    required bool isDark,

    required String brand,

    required String model,

    required dynamic sdk,

    required bool isCritical,

    required bool hasWarning,

    required bool isRunning,

  }) {

    final statusColor = isCritical ? Colors.red : (hasWarning ? Colors.orange : Colors.green);

    final statusTitle = isCritical ? 'Attention Required' : (hasWarning ? 'Review Recommended' : 'Optimal Tracking Health');

    return Container(

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(

        color: isDark ? const Color(0xff1e293b) : Colors.white,

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: statusColor.withValues(alpha: 0.5), width: 1.5),

        boxShadow: [

          BoxShadow(

            color: statusColor.withValues(alpha: 0.08),

            blurRadius: 12,

            offset: const Offset(0, 4),

          ),

        ],

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Row(

            children: [

              Container(

                padding: const EdgeInsets.all(8),

                decoration: BoxDecoration(

                  color: statusColor.withValues(alpha: 0.15),

                  shape: BoxShape.circle,

                ),

                child: Icon(

                  isCritical ? Icons.error_outline_rounded : (hasWarning ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded),

                  color: statusColor,

                  size: 24,

                ),

              ),

              const SizedBox(width: 12),

              Expanded(

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    Text(

                      statusTitle,

                      style: TextStyle(

                        fontSize: 16,

                        fontWeight: FontWeight.w700,

                        color: statusColor,

                      ),

                    ),

                    const SizedBox(height: 2),

                    Text(

                      '$brand $model • Android SDK $sdk',

                      style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[400] : Colors.grey[600]),

                    ),

                  ],

                ),

              ),

            ],

          ),

        ],

      ),

    );

  }

  Widget _buildActionRequiredBanner({

    required bool isDark,

    required bool batteryExempt,

    required bool isAlways,

    required bool gpsOn,

    required bool requiresAutostart,

    required bool autostartSettingsOpened,

    required String brand,

  }) {

    return Container(

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(

        color: isDark ? const Color(0xff451a03) : const Color(0xfffff7ed),

        borderRadius: BorderRadius.circular(14),

        border: Border.all(color: isDark ? const Color(0xff7c2d12) : const Color(0xfffed7aa)),

      ),

      child: Row(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          const Icon(Icons.info_outline_rounded, color: Color(0xffea580c), size: 20),

          const SizedBox(width: 10),

          Expanded(

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                const Text(

                  'Action required to avoid tracking gaps:',

                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xffea580c)),

                ),

                const SizedBox(height: 4),

                if (!gpsOn)

                  const Text('• Device GPS is turned off. Turn on GPS in quick settings.', style: TextStyle(fontSize: 12)),

                if (!isAlways)

                  const Text('• Location is set to "While using app". Change to "Allow all the time" so tracking continues when screen locks.', style: TextStyle(fontSize: 12)),

                if (!batteryExempt)

                  Text('• $brand battery optimization is active. Set battery to "Unrestricted" / "No restrictions".', style: const TextStyle(fontSize: 12)),

                if (requiresAutostart && !autostartSettingsOpened)

                  Text('• Enable Auto-start in $brand Security Manager to prevent process kills.', style: const TextStyle(fontSize: 12)),

              ],

            ),

          ),

        ],

      ),

    );

  }

  Widget _buildDiagnosticTile({

    required IconData icon,

    required String title,

    required String subtitle,

    required String status,

    required Color statusColor,

    String? actionText,

    VoidCallback? onAction,

    required bool isDark,

  }) {

    return Container(

      margin: const EdgeInsets.only(bottom: 10),

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(

        color: isDark ? const Color(0xff1e293b) : Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0)),

      ),

      child: Row(

        children: [

          Container(

            padding: const EdgeInsets.all(8),

            decoration: BoxDecoration(

              color: statusColor.withValues(alpha: 0.12),

              shape: BoxShape.circle,

            ),

            child: Icon(icon, color: statusColor, size: 20),

          ),

          const SizedBox(width: 12),

          Expanded(

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Row(

                  mainAxisAlignment: MainAxisAlignment.spaceBetween,

                  children: [

                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),

                    Container(

                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),

                      decoration: BoxDecoration(

                        color: statusColor.withValues(alpha: 0.15),

                        borderRadius: BorderRadius.circular(8),

                      ),

                      child: Text(

                        status,

                        style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700),

                      ),

                    ),

                  ],

                ),

                const SizedBox(height: 3),

                Text(

                  subtitle,

                  style: TextStyle(

                    fontSize: 12,

                    color: isDark ? Colors.grey[400] : Colors.grey[600],

                    height: 1.3,

                  ),

                ),

                if (actionText != null && onAction != null) ...[

                  const SizedBox(height: 8),

                  InkWell(

                    onTap: onAction,

                    child: Text(

                      '$actionText →',

                      style: TextStyle(

                        fontSize: 12,

                        fontWeight: FontWeight.w700,

                        color: Theme.of(context).primaryColor,

                      ),

                    ),

                  ),

                ],

              ],

            ),

          ),

        ],

      ),

    );

  }

  Widget _buildTelemetryRow(String label, String value) {

    return Row(

      mainAxisAlignment: MainAxisAlignment.spaceBetween,

      children: [

        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),

        Flexible(

          child: Text(

            value,

            textAlign: TextAlign.end,

            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),

          ),

        ),

      ],

    );

  }

}

