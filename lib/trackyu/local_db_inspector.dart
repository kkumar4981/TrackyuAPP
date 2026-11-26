import 'package:flutter/material.dart';
import 'controller.dart';
import 'duty_tracking.dart';
import 'address_cache.dart';

class LocalDatabaseInspectorPage extends StatefulWidget {
  final TrackyuController controller;
  const LocalDatabaseInspectorPage({super.key, required this.controller});

  @override
  State<LocalDatabaseInspectorPage> createState() =>
      _LocalDatabaseInspectorPageState();
}

class _LocalDatabaseInspectorPageState
    extends State<LocalDatabaseInspectorPage> {
  bool _loading = true;
  bool _syncing = false;
  Map<String, dynamic>? _dayData;
  Map<String, dynamic> _trackingStatus = {};
  List<Map<String, dynamic>> _savedGpsPoints = [];
  Map<String, dynamic> _syncState = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final day = await widget.controller.localDayData();
      final status = await DutyTracker.status();
      final points = await DutyTracker.route(
        widget.controller.employeeId,
        DateTime.now(),
        baseUrl: widget.controller.api.baseUrl,
      );
      final syncSt = widget.controller.local != null
          ? await widget.controller.local!.syncState()
          : <String, dynamic>{};

      if (mounted) {
        setState(() {
          _dayData = day;
          _trackingStatus = status;
          _savedGpsPoints = points;
          _syncState = syncSt;
          _loading = false;
        });
        // Resolve addresses for saved GPS coordinates
        for (final pt in points.reversed.take(15)) {
          final lat = (pt['latitude'] as num?)?.toDouble();
          final lng = (pt['longitude'] as num?)?.toDouble();
          if (lat != null && lng != null && TrackyuAddressCache.get(lat, lng) == null) {
            TrackyuAddressCache.reverseGeocode(lat, lng).then((addr) {
              if (mounted && addr != null) setState(() {});
            });
          }
        }
        return;
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forceSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final ok = await widget.controller.syncData();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'All local data synced with workspace!'
                  : (widget.controller.notice.isNotEmpty
                        ? widget.controller.notice
                        : 'Local data saved on phone.'),
            ),
            backgroundColor: ok ? const Color(0xff059669) : const Color(0xffd97706),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.controller.isDarkMode;
    final bg = isDark ? const Color(0xff121212) : const Color(0xfff8fafc);
    final cardBg = isDark ? const Color(0xff1e1e1e) : Colors.white;
    final textPrim = isDark ? Colors.white : const Color(0xff0f172a);
    final textSec = isDark ? const Color(0xff94a3b8) : const Color(0xff64748b);
    final borderCol = isDark ? const Color(0xff2d3135) : const Color(0xffe2e8f0);

    final dynamic attRaw = _dayData?['attendance'] ?? widget.controller.attendance;
    Map? att;
    if (attRaw is Map) {
      att = attRaw;
    } else if (attRaw is List && attRaw.isNotEmpty && attRaw.first is Map) {
      att = attRaw.first as Map;
    } else if (widget.controller.attendance is Map) {
      att = widget.controller.attendance;
    }
    final dynamic visitsRaw = _dayData?['visits'] ?? _dayData?['rows'];
    final List<Map> visits = (visitsRaw is List
            ? visitsRaw
            : (visitsRaw is Map && visitsRaw['rows'] is List)
                ? (visitsRaw['rows'] as List)
                : <dynamic>[])
        .whereType<Map>()
        .toList();
    final pendingCount = _syncState['pending'] as num? ?? 0;
    final blockedCount = _syncState['blocked'] as num? ?? 0;
    final lastError = '${_syncState['error'] ?? ''}';

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text(
          'Local DB & Sync Inspector',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Reload Database',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Sync Outbox Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderCol),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (blockedCount > 0
                                        ? Colors.red
                                        : pendingCount > 0
                                            ? Colors.amber
                                            : Colors.green)
                                    .withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                blockedCount > 0
                                    ? Icons.error_outline_rounded
                                    : pendingCount > 0
                                        ? Icons.cloud_upload_outlined
                                        : Icons.cloud_done_rounded,
                                color: blockedCount > 0
                                    ? Colors.red
                                    : pendingCount > 0
                                        ? Colors.amber.shade800
                                        : Colors.green,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sync Outbox Status',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: textPrim,
                                    ),
                                  ),
                                  Text(
                                    blockedCount > 0
                                        ? '$blockedCount items need review'
                                        : pendingCount > 0
                                            ? '$pendingCount items pending sync'
                                            : 'All phone records are synced',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: blockedCount > 0
                                          ? Colors.red
                                          : textSec,
                                      fontWeight: blockedCount > 0
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xff1c6799),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              onPressed: _syncing ? null : _forceSync,
                              icon: _syncing
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.sync_rounded, size: 16),
                              label: Text(_syncing ? 'Syncing...' : 'Sync now'),
                            ),
                          ],
                        ),
                        if (lastError.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.red.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  color: Colors.red,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    lastError,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // GPS Samples in Local DB
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderCol),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              color: Color(0xff26c6da),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'GPS Points in Phone DB',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: textPrim,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xff26c6da).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_savedGpsPoints.length} points',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xff00838f),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _infoRow('Tracking Service', _trackingStatus['active'] == true ? 'Active (Recording route)' : 'Idle', textSec, textPrim),
                        _infoRow('Pending GPS Upload', '${_trackingStatus['pendingCount'] ?? 0} samples waiting', textSec, textPrim),
                        if (_trackingStatus['lastFixAtUtc'] != null)
                          _infoRow('Last Captured GPS', '${_trackingStatus['lastFixAtUtc']}', textSec, textPrim),
                        if (_trackingStatus['status'] != null)
                          _infoRow('Service Status', '${_trackingStatus['status']}', textSec, textPrim),
                        if ((widget.controller.lastLocation?['telemetry']?['city'] ??
                                widget.controller.attendance?['punchInCity'] ??
                                widget.controller.lastLocation?['telemetry']?['address']) !=
                            null)
                          _infoRow(
                            'Area / City',
                            '${widget.controller.lastLocation?['telemetry']?['city'] ?? widget.controller.attendance?['punchInCity'] ?? widget.controller.lastLocation?['telemetry']?['address']}',
                            textSec,
                            textPrim,
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Attendance in Local DB
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderCol),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              color: Color(0xff1c6799),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Attendance in Phone DB',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: textPrim,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (att != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: (att['syncState'] == 'pending'
                                          ? Colors.amber
                                          : Colors.green)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${att['syncState'] ?? 'synced'}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: att['syncState'] == 'pending'
                                        ? Colors.amber.shade800
                                        : Colors.green.shade700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (att == null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No attendance recorded for today yet.',
                              style: TextStyle(color: textSec, fontSize: 13),
                            ),
                          )
                        else ...[
                          _infoRow('Work Date', '${att['workDate'] ?? 'Today'}', textSec, textPrim),
                          _infoRow('Punch In Time', '${att['punchInUtc'] ?? 'Pending'}', textSec, textPrim),
                          _infoRow('Punch Out Time', '${att['punchOutUtc'] ?? 'In progress'}', textSec, textPrim),
                          _infoRow('Local ID', '${att['localId'] ?? att['id'] ?? '-'}', textSec, textPrim),
                          if (att['serverId'] != null)
                            _infoRow('Server ID', '${att['serverId']}', textSec, textPrim),
                          if (att['punchInLat'] != null && att['punchInLng'] != null)
                            _infoRow(
                              'Punch In GPS',
                              '${att['punchInLat']}, ${att['punchInLng']}',
                              textSec,
                              textPrim,
                            ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Visits in Local DB
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderCol),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.storefront_rounded,
                              color: Color(0xffab47bc),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Visits in Phone DB',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: textPrim,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${visits.length} recorded',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textSec,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (visits.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No visits recorded on phone today.',
                              style: TextStyle(color: textSec, fontSize: 13),
                            ),
                          )
                        else
                          for (int i = 0; i < visits.length; i++) ...[
                            if (i > 0) const Divider(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${visits[i]['shopName'] ?? visits[i]['clientName'] ?? 'Visit ${i + 1}'}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: textPrim,
                                        ),
                                      ),
                                      Text(
                                        '${visits[i]['placeName'] ?? visits[i]['address'] ?? 'Recorded locally'} • ${visits[i]['checkInUtc'] ?? ''}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: textSec,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (visits[i]['syncState'] == 'pending'
                                            ? Colors.amber
                                            : Colors.green)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${visits[i]['syncState'] ?? 'synced'}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: visits[i]['syncState'] == 'pending'
                                          ? Colors.amber.shade800
                                          : Colors.green.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Recent GPS Points List
                  if (_savedGpsPoints.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderCol),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.route_rounded,
                                color: Color(0xff0288d1),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Recent Saved GPS Coordinates',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: textPrim,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          for (final pt in _savedGpsPoints.reversed.take(15)) ...[
                            Builder(
                              builder: (context) {
                                final lat = (pt['latitude'] as num?)?.toDouble();
                                final lng = (pt['longitude'] as num?)?.toDouble();
                                final addr = (lat != null && lng != null) ? TrackyuAddressCache.get(lat, lng) : null;
                                final timeStr = DateTime.tryParse('${pt['capturedAtUtc']}')?.toLocal().toString().split('.').first.split(' ').lastOrNull ?? '';

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 5),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Icon(
                                          Icons.place_rounded,
                                          size: 14,
                                          color: const Color(0xff0288d1),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              addr ?? 'Resolving street address...',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: textPrim,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 1),
                                            Text(
                                              '${lat?.toStringAsFixed(5)}, ${lng?.toStringAsFixed(5)} (±${(pt['accuracyMeters'] as num?)?.toStringAsFixed(0) ?? '-'}m)',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontFamily: 'monospace',
                                                color: textSec,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        timeStr,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: textSec,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _infoRow(
    String label,
    String value,
    Color labelColor,
    Color valueColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: labelColor),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
