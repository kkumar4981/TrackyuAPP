

import 'visit_media.dart';

import 'local_workspace.dart';

import 'timeline_reconciliation.dart';

import 'address_cache.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import 'package:flutter_map/flutter_map.dart';

import 'package:latlong2/latlong.dart';

import 'api.dart';

import 'controller.dart';

import 'duty_tracking.dart';

import 'legacy_map.dart';

import 'route_presentation.dart';

import 'error_logger.dart';



class _DistanceStep {

  final int index;

  final DateTime fromTime;

  final DateTime toTime;

  final LatLng fromCoord;

  final LatLng toCoord;

  final String? fromAddress;

  final String? toAddress;

  final double distanceMeters;

  final double speedKmh;



  _DistanceStep({

    required this.index,

    required this.fromTime,

    required this.toTime,

    required this.fromCoord,

    required this.toCoord,

    this.fromAddress,

    this.toAddress,

    required this.distanceMeters,

    required this.speedKmh,

  });

}





class TrackingStatusCard extends StatefulWidget {

  final TrackyuController controller;

  const TrackingStatusCard({super.key, required this.controller});

  @override

  State<TrackingStatusCard> createState() => _TrackingStatusCardState();

}



class _TrackingStatusCardState extends State<TrackingStatusCard> {

  Timer? timer;

  Json state = {};

  



  @override

  void initState() {

    super.initState();

    TrackyuAddressCache.init();

    load();

    timer = Timer.periodic(const Duration(seconds: 5), (_) => load());

  }



  Future<void> load() async {

    try {

      final next = await DutyTracker.status();
      widget.controller.dutyTrackerStatus = next;

      final own =

          next['userId'] == widget.controller.employeeId &&

          next['baseUrl'] == widget.controller.api.baseUrl;

      final target = own

          ? next

          : {

              'status': 'Tracking starts at your punch-in',

              'pendingCount': 0,

            };

      if (mounted && (state['status'] != target['status'] || state['pendingCount'] != target['pendingCount'])) {

        setState(() => state = target);

      }

    } catch (_) {

      if (mounted) {

        setState(

          () =>

              state = {'status': 'Open app settings to check tracking access'},

        );

      }

    }

  }



  @override

  void dispose() {

    timer?.cancel();

    super.dispose();

  }



  @override

  Widget build(BuildContext context) {

    if (!DutyTracker.supported) return const SizedBox.shrink();

    final isDark = widget.controller.isDarkMode;





    return Column(

      mainAxisSize: MainAxisSize.min,

      crossAxisAlignment: CrossAxisAlignment.stretch,

      children: [

        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => DutyRoutePage(controller: widget.controller),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                gradient: isDark
                    ? const LinearGradient(
                        colors: [Color(0xff131b2e), Color(0xff0d1322)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : (widget.controller.isLuxuryMode
                        ? LinearGradient(
                            colors: widget.controller.themeCardGradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null),
                color: (isDark || widget.controller.isLuxuryMode) ? null : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? const Color(0xff1e293b)
                      : (widget.controller.isLuxuryMode
                          ? Colors.white.withValues(alpha: 0.95)
                          : const Color(0xffe2e8f0)),
                  width: widget.controller.isLuxuryMode ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.3)
                        : (widget.controller.isLuxuryMode
                            ? widget.controller.themePrimaryColor.withValues(alpha: 0.08)
                            : const Color(0xff0284c7).withValues(alpha: 0.06)),
                    blurRadius: 18,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),

              child: Row(

                children: [

                  Container(

                    padding: const EdgeInsets.all(11),

                    decoration: BoxDecoration(

                      gradient: const LinearGradient(

                        colors: [Color(0xff0284c7), Color(0xff0ea5e9)],

                        begin: Alignment.topLeft,

                        end: Alignment.bottomRight,

                      ),

                      borderRadius: BorderRadius.circular(14),

                      boxShadow: [

                        BoxShadow(

                          color: const Color(0xff0284c7).withValues(alpha: 0.28),

                          blurRadius: 10,

                          offset: const Offset(0, 3),

                        ),

                      ],

                    ),

                    child: const Icon(

                      Icons.route_rounded,

                      color: Colors.white,

                      size: 22,

                    ),

                  ),

                  const SizedBox(width: 14),

                  Expanded(

                    child: Column(

                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [

                        Text(

                          'My route & timeline',

                          style: TextStyle(

                            fontSize: 15.5,

                            fontWeight: FontWeight.w700,

                            letterSpacing: -0.2,

                            color: isDark

                                ? Colors.white

                                : const Color(0xff0f172a),

                          ),

                        ),

                        const SizedBox(height: 3),

                        Row(

                          children: [

                            if (widget.controller.onDuty) ...[

                              Container(

                                width: 6,

                                height: 6,

                                decoration: const BoxDecoration(

                                  shape: BoxShape.circle,

                                  color: Color(0xff10b981),

                                  boxShadow: [

                                    BoxShadow(

                                      color: Color(0xff10b981),

                                      blurRadius: 3,

                                      spreadRadius: 1,

                                    ),

                                  ],

                                ),

                              ),

                              const SizedBox(width: 5),

                            ],

                            Expanded(

                              child: Text(

                                widget.controller.onDuty

                                    ? ((widget.controller.isMockGpsDetected || state['hasMockLocation'] == true || (state['status']?.toString().toLowerCase().contains('mock') ?? false))

                                        ? '⚠️ Mock GPS detected • Route blocked'

                                        : 'Recording route & distance • View timeline')

                                    : (state['status'] as String? ??

                                          'Tracking starts at your punch-in'),

                                maxLines: 1,

                                overflow: TextOverflow.ellipsis,

                                style: TextStyle(

                                  fontSize: 12,

                                  fontWeight: FontWeight.w500,

                                  color: isDark

                                      ? (widget.controller.onDuty ? const Color(0xff38bdf8) : const Color(0xff94a3b8))

                                      : (widget.controller.onDuty ? const Color(0xff0284c7) : const Color(0xff64748b)),

                                ),

                              ),

                            ),

                          ],

                        ),

                      ],

                    ),

                  ),

                  Container(

                    width: 32,

                    height: 32,

                    decoration: BoxDecoration(

                      color: isDark ? const Color(0xff1e293b) : const Color(0xfff1f5f9),

                      shape: BoxShape.circle,

                    ),

                    child: Icon(

                      Icons.chevron_right_rounded,

                      size: 20,

                      color: isDark

                          ? const Color(0xff94a3b8)

                          : const Color(0xff64748b),

                    ),

                  ),

                ],

              ),

            ),

          ),

        ),

        if (state['batteryUnrestricted'] == false) ...[

          const SizedBox(height: 8),

          Container(

            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),

            decoration: BoxDecoration(

              color: isDark ? const Color(0xff451a03) : const Color(0xfffffbeb),

              borderRadius: BorderRadius.circular(12),

              border: Border.all(

                color: isDark ? const Color(0xffb45309) : const Color(0xfffde68a),

              ),

            ),

            child: Row(

              children: [

                Icon(

                  Icons.battery_alert_rounded,

                  color: isDark ? const Color(0xfffbbf24) : const Color(0xffd97706),

                  size: 22,

                ),

                const SizedBox(width: 10),

                Expanded(

                  child: Column(

                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [

                      Text(

                        'Battery is Restricted by Phone OS',

                        style: TextStyle(

                          fontSize: 13,

                          fontWeight: FontWeight.w600,

                          color: isDark ? const Color(0xfffef3c7) : const Color(0xff92400e),

                        ),

                      ),

                      const SizedBox(height: 2),

                      Text(

                        'Set battery to "Unrestricted" so Android never stops your GPS in background.',

                        style: TextStyle(

                          fontSize: 11,

                          color: isDark ? const Color(0xfffde68a) : const Color(0xffb45309),

                        ),

                      ),

                    ],

                  ),

                ),

                const SizedBox(width: 8),

                FilledButton.tonal(

                  onPressed: DutyTracker.batterySettings,

                  style: FilledButton.styleFrom(

                    visualDensity: VisualDensity.compact,

                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),

                  ),

                  child: const Text('Allow'),

                ),

              ],

            ),

          ),

        ],

      ],

    );

  }

}



class DutyRoutePage extends StatefulWidget {

  final TrackyuController controller;

  const DutyRoutePage({super.key, required this.controller});

  @override

  State<DutyRoutePage> createState() => _DutyRoutePageState();

}



class _DutyRoutePageState extends State<DutyRoutePage> {

    void _changeDate(DateTime nextDate) {
    if (date.year == nextDate.year &&
        date.month == nextDate.month &&
        date.day == nextDate.day) {
      return;
    }
    setState(() {
      date = nextDate;
      loading = true;
      segments = [];
      data = {};
      _position = null;
      _nativePoints = [];
      _nativeDay = null;
      _loadedDate = null;
      error = null;
    });
    load();
  }

DateTime date = DateTime.parse(businessDay(DateTime.now()));

  int _activeLoadSeq = 0;

  DateTime? _loadedDate;

  bool loading = true,

      _readingRoute = false,

      _followPosition = true,

      _requestingFix = false,

      _trackingActive = false;

  int _selectedTab = 0;

  int _selectedInsight = 0;

  String? error;

  String? _nativeDay;

  List<Json> _nativePoints = [];

  String? selectedNodeId;

  Json data = {};

  Json? _position;

  List<List<Json>> segments = [];

  final mapController = MapController();

  final Map<String, String> _addressCache = {};

  bool _fullscreenMap = false;

  bool _isLiveMode = false;

  DateTime _snapshotTime = DateTime.now();

  Timer? timer;

  late String _owner;

  bool get _sameSession =>

      _owner ==

      '${widget.controller.api.baseUrl}|${widget.controller.employeeId}';

  bool get _today => LocalWorkspace.day(date) == widget.controller.localDay;

  bool get _darkMode => widget.controller.isDarkMode;

  bool get _current =>

      _today &&

      widget.controller.onDuty &&

      isCurrentFix(_position, DateTime.now(), tracking: _trackingActive);

  String get _positionLabel =>

      _current ? 'You are here' : 'Last known location';

  @override

  void initState() {

    super.initState();

    TrackyuAddressCache.init();

    _owner = '${widget.controller.api.baseUrl}|${widget.controller.employeeId}';

    widget.controller.addListener(_sessionChanged);

    load();

    _snapshotTime = DateTime.now();

    timer = Timer.periodic(const Duration(seconds: 15), (_) {

      if (_today && _isLiveMode) load(silent: true);

    });

  }



  void _sessionChanged() {

    if (!mounted) return;

    if (!_sameSession) {

      segments = [];

      data = {};

      _position = null;

      setState(() {});

      return;

    }

    // In View mode, do not trigger auto-rebuild on background GPS fixes to prevent screen jitter
    if (_isLiveMode) {

      setState(() {});

    }

  }



  @override

  void dispose() {

    timer?.cancel();

    widget.controller.removeListener(_sessionChanged);

    mapController.dispose();

    super.dispose();

  }



  Future<void> _resolveMissingAddresses([List<Json>? currentStops]) async {

    final selected = date;

    if (!mounted || !_sameSession || widget.controller.offline) return;

    bool updated = false;

    // 1. Prioritize Halts/Stops first
    final rawStops = currentStops ?? ((data['route'] as Map?)?['stops'] as List? ?? []);

    for (final s in rawStops) {

      if (!mounted || date != selected || !_sameSession || widget.controller.offline) return;

      final pt = safeLatLng(s['latitude'], s['longitude']);

      if (pt == null) continue;

      if (TrackyuAddressCache.get(pt.latitude, pt.longitude) != null) continue;

      try {

        final addr = await TrackyuAddressCache.reverseGeocode(pt.latitude, pt.longitude);

        if (addr != null) updated = true;

      } catch (_) {}

    }

    // 2. Recent position
    if (_position != null) {

      final pt = routeCoordinate(_position);

      if (pt != null && TrackyuAddressCache.get(pt.latitude, pt.longitude) == null) {

        try {

          final addr = await TrackyuAddressCache.reverseGeocode(pt.latitude, pt.longitude);

          if (addr != null) updated = true;

        } catch (_) {}

      }

    }

    // 3. Events (Punch-in / Punch-out)
    final rawEvents = (data['events'] as List? ?? []);

    for (final e in rawEvents) {

      if (!mounted || date != selected || !_sameSession || widget.controller.offline) return;

      final pt = safeLatLng(e['latitude'], e['longitude']);

      if (pt == null) continue;

      if (TrackyuAddressCache.get(pt.latitude, pt.longitude) != null) continue;

      try {

        final addr = await TrackyuAddressCache.reverseGeocode(pt.latitude, pt.longitude);

        if (addr != null) updated = true;

      } catch (_) {}

    }

    // 4. Movement segment start and end points
    for (final seg in segments) {

      if (!mounted || date != selected || !_sameSession || widget.controller.offline) return;

      if (seg.isEmpty) continue;

      final ptStart = routeCoordinate(seg.first);

      if (ptStart != null && TrackyuAddressCache.get(ptStart.latitude, ptStart.longitude) == null) {

        try {

          final addr = await TrackyuAddressCache.reverseGeocode(ptStart.latitude, ptStart.longitude);

          if (addr != null) updated = true;

        } catch (_) {}

      }

      final ptEnd = routeCoordinate(seg.last);

      if (ptEnd != null && TrackyuAddressCache.get(ptEnd.latitude, ptEnd.longitude) == null) {

        try {

          final addr = await TrackyuAddressCache.reverseGeocode(ptEnd.latitude, ptEnd.longitude);

          if (addr != null) updated = true;

        } catch (_) {}

      }

    }

    if (updated && mounted && date == selected) {

      setState(() {});

    }

  }

      Future<void> load({bool silent = false}) async {

    if (!mounted || !_sameSession || _readingRoute) return;

    final currentSeq = ++_activeLoadSeq;

    _readingRoute = true;

    final selected = date;

    if (!silent) {

      _snapshotTime = DateTime.now();

      setState(() => loading = true);

    }

    try {

      final day =

          '${selected.year}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';

      String? warning;



      // Phase 1: Instant cache-first render from local storage (0ms UI lag)

      try {

        final cachedRecord = await widget.controller.localDayData(day);

        final cachedVisits = await widget.controller.scopedVisitCache();

        final cachedNative = await DutyTracker.status();

        if (mounted && _sameSession && date == selected && currentSeq == _activeLoadSeq) {

          if (cachedRecord.isNotEmpty || cachedVisits.isNotEmpty || (_nativeDay == day && _nativePoints.isNotEmpty)) {

            _applyRoute(selected, day, cachedNative, cachedRecord, _nativeDay == day ? _nativePoints : [], cachedVisits);

            loading = false;

            setState(() {});

          }

        }

      } catch (_) {}



      // Phase 2: Decoupled independent background fetches with deduplication & stale-response guard

      Map<String, dynamic> record = {};

      Map<String, dynamic> native = {};

      dynamic visitCache = <Json>[];



      try {

        if (_today) {
        native = await DutyTracker.status().timeout(const Duration(seconds: 4));
      } else {
        native = {};
      }

      } catch (_) {}



      try {

        visitCache = await widget.controller.scopedVisitCache().timeout(const Duration(seconds: 4));

      } catch (_) {}



      try {

        record = await widget.controller.fetchRouteDayData(day).timeout(const Duration(seconds: 25));

      } catch (exception, stack) {

        warning = 'Some phone history is still unavailable. Showing saved details; tap refresh to retry.';

        if (exception is! TimeoutException) {

          unawaited(ErrorLogger.record(exception, stack, context: 'DutyRoutePage.summary', notifyUser: false));

        }

      }



      if (!mounted || !_sameSession || date != selected || currentSeq != _activeLoadSeq) return;



      void publish(List<Json> local) {

        if (!mounted || !_sameSession || date != selected || currentSeq != _activeLoadSeq) return;

        _applyRoute(selected, day, native.isNotEmpty ? native : data, record.isNotEmpty ? record : data, local, visitCache);

        error = warning ?? error;

        setState(() => loading = false);

      }



      publish(_nativeDay == day ? _nativePoints : []);



      // Phase 3: Paginated GPS route samples with lifecycle cancellation

      try {

        final local = await DutyTracker.route(

          widget.controller.employeeId,

          selected,

          baseUrl: widget.controller.api.baseUrl,

          fullResolution: true,

          pageSize: 1000,

          onPage: (points) {

            if (!mounted || !_sameSession || date != selected || currentSeq != _activeLoadSeq) return;

            final prior = _nativeDay == day ? _nativePoints : <Json>[];

            _nativeDay = day;

            _nativePoints = mergePoints(

              [...prior, ...points],

              day,

              widget.controller.employeeId,

              widget.controller.api.baseUrl,

            );

            publish(_nativePoints);

          },

          isCancelled: () => !mounted || !_sameSession || date != selected || currentSeq != _activeLoadSeq,

        );



        if (mounted && _sameSession && date == selected && currentSeq == _activeLoadSeq) {

          _nativeDay = day;

          _nativePoints = local;

          publish(local);

        }

      } catch (exception, stack) {

        unawaited(ErrorLogger.record(exception, stack, context: 'DutyRoutePage.gps', notifyUser: false));

      }



      if (mounted && _sameSession && date == selected && currentSeq == _activeLoadSeq && warning != null) {

        setState(() => error = warning);

      }

    } catch (exception, stack) {

      if (mounted && _sameSession && date == selected && currentSeq == _activeLoadSeq) {

        error = 'Unable to read phone data. Retry after checking storage.';

        ErrorLogger.record(exception, stack, context: 'DutyRoutePage.load');

      }

    } finally {

      _readingRoute = false;

      if (mounted && currentSeq == _activeLoadSeq) {

        setState(() => loading = false);

        if (date != selected) unawaited(load());

      }

    }

  }



  void _applyRoute(

    DateTime selected,

    String day,

    Json native,

    Json record,

    List<Json> local,

    dynamic visitCache,

  ) {

    final report = record['report'] is Map

        ? Map<String, dynamic>.from(record['report'] as Map)

        : (record.containsKey('route') ||

                record.containsKey('Route') ||

                record.containsKey('events') ||

                record.containsKey('Events') ||

                record.containsKey('recordedPoints') ||

                record.containsKey('RecordedPoints') ||

                record.containsKey('attendance') ||

                record.containsKey('Attendance'))

            ? Map<String, dynamic>.from(record)

            : <String, dynamic>{};

    final owner = widget.controller.employeeId,

        baseUrl = widget.controller.api.baseUrl;

    if (!rowBelongs(report, owner, baseUrl)) {

      throw const FormatException('Cached report owner mismatch');

    }

    // No network dependency: server history arrives only through explicit restore and durable sync.

    // Full, media-free projection + raw paged native samples feed calculations, never the map preview.

    final savedPoints = rowsOf(report['recordedPoints'] ?? report['RecordedPoints']);

    final serverRoute = report['route'] ?? report['Route'];

    final serverSegments =

        (serverRoute is Map && (serverRoute['segments'] ?? serverRoute['Segments']) is List)

        ? ((serverRoute['segments'] ?? serverRoute['Segments']) as List).whereType<List>().toList()

        : <List>[];

    final normalizedSegments = <Json>[];

    for (final segment in serverSegments) {

      final points = rowsOf(segment);

      for (var i = 0; i < points.length; i++) {

        normalizedSegments.add({...points[i], if (i == 0) 'breakBefore': true});

      }

    }

    final rawMergedPoints = mergePoints(

      [

        ...savedPoints,

        ...normalizedSegments,

        ...local.map((p) => <String, dynamic>{...p, 'displaySampled': false}),

      ],

      day,

      owner,

      baseUrl,

    );

    final attendances = <Json>[

      ...rowsOf(report['attendance'] ?? report['Attendance']),

    ];

    if (record['attendance'] is Map) {

      attendances.add(Map<String, dynamic>.from(record['attendance'] as Map));

    }

    if (record['Attendance'] is Map) {

      attendances.add(Map<String, dynamic>.from(record['Attendance'] as Map));

    }

    if (day == widget.controller.localDay &&

        widget.controller.attendance != null) {

      attendances.add(widget.controller.attendance!);

    }

    // Determine active duty bounds to exclude pre-punch-in and post-punch-out points

    DateTime? shiftIn;

    DateTime? shiftOut;

    for (final e in rowsOf(report['events'] ?? report['Events'])) {

      final t = '${e['type'] ?? e['Type']}';

      final raw = DateTime.tryParse('${e['atUtc'] ?? e['AtUtc']}');

      if (raw != null) {

        if (t == 'PunchIn') {

          if (shiftIn == null || raw.isBefore(shiftIn)) shiftIn = raw;

        } else if (t == 'PunchOut') {

          if (shiftOut == null || raw.isAfter(shiftOut)) shiftOut = raw;

        }

      }

    }

    for (final a in attendances) {

      final inRaw = a['punchInUtc'] != null

          ? DateTime.tryParse('${a['punchInUtc']}')

          : a['PunchInUtc'] != null

              ? DateTime.tryParse('${a['PunchInUtc']}')

              : null;

      final outRaw = a['punchOutUtc'] != null

          ? DateTime.tryParse('${a['punchOutUtc']}')

          : a['PunchOutUtc'] != null

              ? DateTime.tryParse('${a['PunchOutUtc']}')

              : null;

      if (inRaw != null && (shiftIn == null || inRaw.isBefore(shiftIn))) shiftIn = inRaw;

      if (outRaw != null && (shiftOut == null || outRaw.isAfter(shiftOut))) shiftOut = outRaw;

    }

    final points = (shiftIn != null)

        ? rawMergedPoints.where((p) {

            final raw = DateTime.tryParse('${p['capturedAtUtc'] ?? p['atUtc'] ?? p['time']}');

            if (raw == null) return false;

            if (raw.isBefore(shiftIn!.subtract(const Duration(seconds: 30)))) return false;

            if (shiftOut != null && raw.isAfter(shiftOut.add(const Duration(seconds: 30)))) return false;

            return true;

          }).toList()

        : rawMergedPoints;

    segments = recordedSegments(points);

    final visits = reconcileVisits(

      [

        ...rowsOf(visitCache),

        ...rowsOf(report['visits'] ?? report['Visits']),

        ...rowsOf(record['visits'] ?? record['Visits']),

      ],

      widget.controller.pendingVisits,

      day,

      owner,

      baseUrl,

    );

    final events = dayEvents([

      ...rowsOf(report['events'] ?? report['Events']),

      ...attendanceEvents(attendances, day),

    ], day);

    final routeObj = serverRoute is Map ? serverRoute : null;

    final stopsList = routeObj != null ? (routeObj['stops'] ?? routeObj['Stops'] ?? <Json>[]) : <Json>[];

    data = {

      ...report,

      'events': events,

      'visits': visits,

      'route': {

        'segments': segments,

        'stops': stopsList,

        'distanceMeters': recordedDistance(segments),

        'gaps': recordingGaps(segments),

      },

    };

    final own =

        native['userId'] == widget.controller.employeeId &&

        native['baseUrl'] == widget.controller.api.baseUrl;

    _trackingActive =

        own &&

        native['active'] == true &&

        native['gpsEnabled'] == true &&

        native['precisePermission'] == true;

    _position = null;

    final candidates = <Json>[...points];

    if (_today && own && native['lastPoint'] is Map) {

      candidates.add(Map<String, dynamic>.from(native['lastPoint']));

    }

    if (_today && widget.controller.lastLocation != null) {

      candidates.add(widget.controller.lastLocation!);

    }

    candidates.removeWhere(

      (p) =>

          routeCoordinate(p) == null ||

          instant(p['capturedAtUtc']) == null ||

          businessDay(instant(p['capturedAtUtc'])!) != day,

    );

    candidates.sort(

      (a, b) =>

          (DateTime.tryParse('${a['capturedAtUtc']}') ??

                  DateTime.fromMillisecondsSinceEpoch(0))

              .compareTo(

                DateTime.tryParse('${b['capturedAtUtc']}') ??

                    DateTime.fromMillisecondsSinceEpoch(0),

              ),

    );

    if (candidates.isNotEmpty) {

      _position = candidates.lastOrNull;

    }

    // Seed persistent address cache

    if (_position != null) {

      final coord = routeCoordinate(_position);

      final addr = _position?['address']?.toString() ??

          _position?['telemetry']?['address']?.toString();

      if (coord != null && addr != null && addr.isNotEmpty) {

        TrackyuAddressCache.put(coord.latitude, coord.longitude, addr);

      }

    }

    for (final v in visits) {

      final pt = safeLatLng(

        v['inLatitude'] ?? v['latitude'] ?? v['xretailer'] ?? v['in_latitude'],

        v['inLongitude'] ?? v['longitude'] ?? v['yretailer'] ?? v['in_longitude'],

      );

      final addr = v['address']?.toString() ?? v['clientAddress']?.toString() ?? v['in_address']?.toString() ?? v['retailerAddress']?.toString();

      if (pt != null && addr != null && addr.isNotEmpty) {

        TrackyuAddressCache.put(pt.latitude, pt.longitude, addr, placeName: v['clientName']?.toString() ?? v['retailerName']?.toString());

      }

    }

    for (final a in attendances) {

      final inPt = safeLatLng(a['punchInLat'], a['punchInLng']);

      final inAddr = a['punchInAddress']?.toString();

      if (inPt != null && inAddr != null && inAddr.isNotEmpty) {

        TrackyuAddressCache.put(inPt.latitude, inPt.longitude, inAddr);

      }

      final outPt = safeLatLng(a['punchOutLat'], a['punchOutLng']);

      final outAddr = a['punchOutAddress']?.toString();

      if (outPt != null && outAddr != null && outAddr.isNotEmpty) {

        TrackyuAddressCache.put(outPt.latitude, outPt.longitude, outAddr);

      }

    }

    final changedDay = _loadedDate != selected;

    _loadedDate = selected;

    if (changedDay) _followPosition = _today;

    if (data['route'] is! Map) {

      data['route'] = {'segments': segments, 'stops': []};

    }

    for (final key in ['events', 'visits']) {

      if (data[key] is! List) data[key] = [];

    }

    if (changedDay || (_followPosition && _today && _position != null)) {

      WidgetsBinding.instance.addPostFrameCallback((_) {

        if (!mounted || date != selected || !_sameSession) return;

        final latest = routeCoordinate(_position);

        if (_today && _followPosition && latest != null) {

          _focusLocation(latest, follow: true);

        } else if (changedDay) {

          _fitBounds(

            segments

                .expand((s) => s)

                .map(routeCoordinate)

                .whereType<LatLng>()

                .toList(),

          );

        }

      });

    }

    error = record['metadataUnavailable'] == true

        ? 'Some saved timeline details could not be loaded safely. Original records are retained; retry explicit restore.'

        : null;

    if (!widget.controller.offline) {

      unawaited(_resolveMissingAddresses());

    }

  }



  Future<void> _refreshPosition() async {

    _followPosition = true;

    final point = routeCoordinate(_position);

    if (point != null) _focusLocation(point, follow: true);

    if (!_sameSession ||

        !_today ||

        !widget.controller.onDuty ||

        _requestingFix) {

      return;

    }

    setState(() => _requestingFix = true);

    try {

      await DutyTracker.requestFreshFix(

        userId: widget.controller.employeeId,

        baseUrl: widget.controller.api.baseUrl,

      );

      await Future<void>.delayed(const Duration(seconds: 2));

      if (mounted) await load();

    } catch (_) {

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(

          const SnackBar(

            content: Text(

              'Unable to refresh GPS. Your saved route is available.',

            ),

          ),

        );

      }

    } finally {

      if (mounted) setState(() => _requestingFix = false);

    }

  }



  LatLng coord(Json p) =>

      safeLatLng(p['latitude'], p['longitude']) ?? const LatLng(0, 0);



  List<Json> _extractStops(List<Json> rawStops, List<Json> allPoints, [List<Json> visits = const []]) {

    final segments = recordedSegments(allPoints);

    final denseStops = detectedStops(segments);

    final gaps = recordingGaps(segments);



    final candidates = <Json>[];

    for (final s in denseStops) {

      candidates.add({

        'startUtc': s['startUtc'],

        'endUtc': s['endUtc'],

        'latitude': s['latitude'],

        'longitude': s['longitude'],

        'attendanceId': s['attendanceId'],

        'mode': s['mode'],

        'sampleCount': s['sampleCount'] ?? 1,

        'isGap': false,

        if (s['address'] != null) 'address': s['address'],

        if (s['placeName'] != null) 'placeName': s['placeName'],

      });

    }



    for (final g in gaps) {

      if (g['isStationary'] == true) {

        final sUtc = instant(g['startUtc']);

        final eUtc = instant(g['endUtc']);

        if (sUtc != null && eUtc != null) {

          final durMin = eUtc.difference(sUtc).inMinutes;

          if (durMin >= 5) {

            candidates.add({

              'startUtc': g['startUtc'],

              'endUtc': g['endUtc'],

              'latitude': g['latitude'],

              'longitude': g['longitude'],

              'attendanceId': g['fromPoint']?['attendanceId'],

              'mode': g['fromPoint']?['mode'],

              'sampleCount': 2,

              'isGap': true,

              if (g['address'] != null) 'address': g['address'],

            });

          }

        }

      }

    }



    candidates.sort((a, b) => instant(a['startUtc'])!.compareTo(instant(b['startUtc'])!));



    const distCalc = Distance();

    final stops = <Json>[];

    for (final c in candidates) {

      if (stops.isEmpty) {

        stops.add(Map<String, dynamic>.from(c));

        continue;

      }

      final prev = stops.last;

      final prevCoord = routeCoordinate(prev);

      final cCoord = routeCoordinate(c);

      if (prevCoord == null || cCoord == null) continue;

      final dist = distCalc(prevCoord, cCoord);



      final prevEnd = instant(prev['endUtc'])!;

      final cStart = instant(c['startUtc'])!;

      final cEnd = instant(c['endUtc'])!;



      final timeGapMin = cStart.difference(prevEnd).inMinutes;

      if (dist <= 100.0 && timeGapMin <= 15) {

        if (cEnd.isAfter(prevEnd)) {

          prev['endUtc'] = c['endUtc'];

        }

        prev['sampleCount'] = (prev['sampleCount'] as int? ?? 1) + (c['sampleCount'] as int? ?? 1);

        prev['address'] ??= c['address'];

      } else {

        stops.add(Map<String, dynamic>.from(c));

      }

    }

    for (final stop in stops) {

      final at = instant(stop['startUtc'])!;

      final metadata = rawStops.where((s) {

        final start = instant(s['startUtc']), end = instant(s['endUtc']);

        final p = routeCoordinate(s), q = routeCoordinate(stop);

        return start != null &&

            end != null &&

            p != null &&

            q != null &&

            !at.isBefore(start) &&

            !at.isAfter(end) &&

            const Distance()(p, q) <= 50;

      }).firstOrNull;

      if (metadata != null) {

        for (final key in ['address', 'placeName', 'locationName']) {

          if (metadata[key] != null) stop[key] = metadata[key];

        }

      }

    }

    if (visits.isEmpty) return stops;

    // Only exclude stops that are completely subsumed by a customer visit of similar duration

    return stops.where((stop) {

      final stopCoord = routeCoordinate(stop);

      final stopStart = instant(stop['startUtc']);

      final stopEnd = instant(stop['endUtc']) ?? stopStart;

      if (stopCoord == null || stopStart == null || stopEnd == null) return true;

      final stopDurSec = stopEnd.difference(stopStart).inSeconds;



      for (final v in visits) {

        final vIn = instant(v['checkInUtc']);

        final vOut = instant(v['checkOutUtc']);

        final vCoord = routeCoordinate(v);

        if (vIn == null || vCoord == null) continue;

        final vEnd = vOut ?? vIn.add(const Duration(minutes: 15));

        final vDurSec = vEnd.difference(vIn).inSeconds;



        final dist = const Distance()(stopCoord, vCoord);

        if (dist <= 100) {

          final overlaps = !stopStart.isAfter(vEnd) && !stopEnd.isBefore(vIn);

          if (overlaps) {

            // Preserve long office stays (> 25 min) even if a brief visit occurred there

            if (stopDurSec > 1500 && vDurSec < (stopDurSec * 0.7)) {

              return true;

            }

            return false;

          }

        }

      }

      return true;

    }).toList();

  }



  int _compareTimelineEntries(_TimelineEntry a, _TimelineEntry b) {

    // 1. PunchIn priority:

    // Work started (PunchIn) is the starting point of the shift. Any stop, trip, or visit within

    // 5 minutes of PunchIn MUST appear after PunchIn.

    if (a.type == _TimelineType.punchIn && b.type != _TimelineType.punchIn) {

      final diff = b.at.difference(a.at).inMinutes;

      if (diff >= -5 && diff <= 5) return -1;

    }

    if (b.type == _TimelineType.punchIn && a.type != _TimelineType.punchIn) {

      final diff = a.at.difference(b.at).inMinutes;

      if (diff >= -5 && diff <= 5) return 1;

    }



    // 2. PunchOut priority:

    // Work completed (PunchOut) is the closing event of the shift. Any stop or trip within

    // 5 minutes of PunchOut MUST appear before PunchOut.

    if (a.type == _TimelineType.punchOut && b.type != _TimelineType.punchOut) {

      final diff = b.at.difference(a.at).inMinutes;

      if (diff >= -5 && diff <= 5) return 1;

    }

    if (b.type == _TimelineType.punchOut && a.type != _TimelineType.punchOut) {

      final diff = a.at.difference(b.at).inMinutes;

      if (diff >= -5 && diff <= 5) return -1;

    }



    // 3. Chronological natural order:

    final cmp = a.at.compareTo(b.at);

    if (cmp != 0) return cmp;



    // 4. Tie-breaker for identical timestamps:

    int typeRank(_TimelineType t) {

      switch (t) {

        case _TimelineType.punchIn:

          return 0;

        case _TimelineType.visit:

          return 1;

        case _TimelineType.stop:

          return 2;

        case _TimelineType.travel:

          return 3;

        case _TimelineType.gap:

          return 4;

        case _TimelineType.login:

          return 5;

        case _TimelineType.punchOut:

          return 6;

      }

    }



    return typeRank(a.type).compareTo(typeRank(b.type));

  }



  List<_TimelineEntry> _buildTimeline({

    required List<Json> events,

    required List<Json> stops,

    required List<Json> visits,

    required List<Json> allPoints,

  }) {

    final list = <_TimelineEntry>[];

    const distCalc = Distance();



    // Identify shift punch-in and punch-out to strictly bound timeline within active duty

    DateTime? firstPunchInAt;

    DateTime? lastPunchOutAt;

    for (final e in events) {

      final type = '${e['type']}';

      final raw = DateTime.tryParse('${e['atUtc']}');

      if (raw != null) {

        final ist = toIST(raw);

        if (type == 'PunchIn') {

          if (firstPunchInAt == null || ist.isBefore(firstPunchInAt)) {

            firstPunchInAt = ist;

          }

        } else if (type == 'PunchOut') {

          if (lastPunchOutAt == null || ist.isAfter(lastPunchOutAt)) {

            lastPunchOutAt = ist;

          }

        }

      }

    }



    // 1. Attendance Events

    for (final e in events) {

      final type = '${e['type']}';

      final rawAt = DateTime.tryParse('${e['atUtc']}');

      final at = rawAt != null ? toIST(rawAt) : null;

      if (at == null) continue;

      final pt = safeLatLng(e['latitude'], e['longitude']);



      if (type == 'PunchIn') {

        final cached = pt != null ? TrackyuAddressCache.get(pt.latitude, pt.longitude) : null;

        final punchAddr = (e['address']?.toString().isNotEmpty == true && e['address'] != '-')

            ? e['address'].toString()

            : (cached ?? 'Punch-in recorded');



        list.add(_TimelineEntry(

          id: '${e['id'] ?? 'in-$at'}',

          type: _TimelineType.punchIn,

          title: 'Work started',

          subtitle: punchAddr,

          badge: 'Punch-in',

          at: at,

          coord: pt,

          color: const Color(0xff10b981),

          icon: Icons.login_rounded,

          raw: e,

          address: punchAddr,

        ));

      } else if (type == 'PunchOut') {

        final cached = pt != null ? TrackyuAddressCache.get(pt.latitude, pt.longitude) : null;

        final punchAddr = (e['address']?.toString().isNotEmpty == true && e['address'] != '-')

            ? e['address'].toString()

            : (cached ?? 'Punch-out recorded');



        list.add(_TimelineEntry(

          id: '${e['id'] ?? 'out-$at'}',

          type: _TimelineType.punchOut,

          title: 'Work completed',

          subtitle: punchAddr,

          badge: 'Punch-out',

          at: at,

          coord: pt,

          color: const Color(0xffef4444),

          icon: Icons.logout_rounded,

          raw: e,

          address: punchAddr,

        ));

      } else if (type == 'Login') {

        // Suppress routine mobile login cards if PunchIn is already present

        final hasPunchIn = events.any((ev) => '${ev['type']}' == 'PunchIn');

        if (!hasPunchIn) {

          list.add(_TimelineEntry(

            id: '${e['id'] ?? 'login-$at'}',

            type: _TimelineType.login,

            title: 'App Opened',

            subtitle: 'Device active',

            at: at,

            coord: pt,

            color: const Color(0xff3b82f6),

            icon: Icons.phonelink_ring_rounded,

            raw: e,

            address: e['address']?.toString() ?? '',

          ));

        }

      }

    }



    // 2. Visits

    for (final v in visits) {

      final rawStart = DateTime.tryParse(

        '${v['checkInUtc'] ?? v['in_time'] ?? v['atUtc']}',

      );

      final start = rawStart != null ? toIST(rawStart) : null;

      final rawEnd = v['checkOutUtc'] ?? v['out_time'];

      final rawEndDt = rawEnd != null ? DateTime.tryParse('$rawEnd') : null;

      final att = widget.controller.attendance;

      final attOut = att?['punchOutUtc'] != null ? DateTime.tryParse('${att!['punchOutUtc']}') : null;

      final dayPunchOut = events.firstWhere(

        (ev) => '${ev['type']}' == 'PunchOut',

        orElse: () => <String, dynamic>{},

      );

      final dayOutRaw = dayPunchOut['atUtc'] != null ? DateTime.tryParse('${dayPunchOut['atUtc']}') : null;

      final dayOut = dayOutRaw != null ? toIST(dayOutRaw) : null;

      final isDone = rawEnd != null || attOut != null || dayOut != null || !_today;

      final end = rawEndDt != null

          ? toIST(rawEndDt)

          : (dayOut != null && (start == null || dayOut.isAfter(start))

              ? dayOut

              : (attOut != null && (start == null || attOut.isAfter(start))

                  ? toIST(attOut)

                  : (isDone ? start : null)));

      if (start == null) continue;

      if (firstPunchInAt != null && start.isBefore(firstPunchInAt.subtract(const Duration(minutes: 5)))) {

        continue;

      }

      if (lastPunchOutAt != null && start.isAfter(lastPunchOutAt.add(const Duration(minutes: 5)))) {

        continue;

      }



      final pt = safeLatLng(

        v['inLatitude'] ??

            v['latitude'] ??

            v['xretailer'] ??

            v['in_latitude'],

        v['inLongitude'] ??

            v['longitude'] ??

            v['yretailer'] ??

            v['in_longitude'],

      );

      final cacheKey = pt != null

          ? '${pt.latitude.toStringAsFixed(4)},${pt.longitude.toStringAsFixed(4)}'

          : '';

      final cached = pt != null ? TrackyuAddressCache.get(pt.latitude, pt.longitude) : _addressCache[cacheKey];

      final addr =

          v['address']?.toString() ??

          v['placeName']?.toString() ??

          cached ??

          '';

      final shopOrClient = v['shopName']?.toString().trim() ?? v['clientName']?.toString().trim();

      final hasSpecificName = shopOrClient != null && shopOrClient.isNotEmpty && shopOrClient != 'Customer';

      final vTitle = hasSpecificName

          ? shopOrClient

          : (isDone ? 'Open visit completed' : 'Open visit in progress');

      final badge = isDone ? 'Completed' : 'In progress';

      final badgeColor = isDone ? const Color(0xffa855f7) : const Color(0xfff97316);



      list.add(

        _TimelineEntry(

          id: 'visit-${v['id'] ?? start}',

          type: _TimelineType.visit,

          title: vTitle,

          subtitle: addr.isNotEmpty ? addr : (v['clientAddress']?.toString() ?? 'Customer location'),

          badge: badge,

          at: start,

          end: end ?? start,

          coord: pt,

          color: badgeColor,

          icon: Icons.storefront_rounded,

          raw: v,

          address: addr,

          departureText: (isDone && end != null && end != start) ? 'Left at ${_formatTime(end)}' : null,

        ),

      );

    }



    // 3. Stops (Halts)

    for (int i = 0; i < stops.length; i++) {

      final s = stops[i];

      final rawStart = DateTime.tryParse('${s['startUtc']}');

      final rawEnd = DateTime.tryParse('${s['endUtc']}');

      var start = rawStart != null ? toIST(rawStart) : null;

      var end = rawEnd != null ? toIST(rawEnd) : null;

      if (start == null) continue;



      // Off-duty stop filtering: drop pre-punch-in and post-punch-out stops

      if (firstPunchInAt == null) continue;

      if (end != null && !end.isAfter(firstPunchInAt)) continue;

      if (end == null && start.isBefore(firstPunchInAt.subtract(const Duration(minutes: 5)))) continue;



      if (start.isBefore(firstPunchInAt)) {

        start = firstPunchInAt;

      }

      if (lastPunchOutAt != null && start.isAfter(lastPunchOutAt)) continue;

      if (lastPunchOutAt != null && end != null && end.isAfter(lastPunchOutAt)) {

        end = lastPunchOutAt;

      }

      final pt = safeLatLng(s['latitude'], s['longitude']);



      final duration = end != null ? end.difference(start) : Duration.zero;

      final durMin =

          (toNum(s['stoppedSeconds'])?.toInt() ?? duration.inSeconds) ~/ 60;



      // Check if this stop overlaps with an already-recorded visit

      bool hasVisitAtStop = false;

      for (final v in visits) {

        final vPt = safeLatLng(

          v['inLatitude'] ??

              v['latitude'] ??

              v['xretailer'] ??

              v['in_latitude'],

          v['inLongitude'] ??

              v['longitude'] ??

              v['yretailer'] ??

              v['in_longitude'],

        );

        final rawVStart = DateTime.tryParse(

          '${v['checkInUtc'] ?? v['in_time'] ?? v['atUtc']}',

        );

        final vStart = rawVStart != null ? toIST(rawVStart) : null;

        final rawVEnd = DateTime.tryParse(

          '${v['checkOutUtc'] ?? v['out_time']}',

        );

        final vEnd = rawVEnd != null ? toIST(rawVEnd) : vStart;

        if (vStart == null) continue;



        final timeOverlaps =

            !vStart.isAfter(end ?? start) && !(vEnd ?? vStart).isBefore(start);

        final distMeters = (vPt != null && pt != null)

            ? distCalc(vPt, pt)

            : 999999.0;

        if (timeOverlaps && distMeters <= 80) {

          final stopDur = durMin;

          final visitDur = (vEnd != null) ? vEnd.difference(vStart).inMinutes : 0;

          if (stopDur > 25 && visitDur < (stopDur * 0.7)) {

            // Keep long office stay even if brief visit occurred there

            continue;

          }

          hasVisitAtStop = true;

          break;

        }

      }



      if (hasVisitAtStop) {

        continue; // Already shown as a visit

      }



      final cacheKey = pt != null

          ? '${pt.latitude.toStringAsFixed(4)},${pt.longitude.toStringAsFixed(4)}'

          : '';

      final cached = pt != null ? TrackyuAddressCache.get(pt.latitude, pt.longitude) : _addressCache[cacheKey];

      final serverAddr =

          s['address']?.toString() ??

          s['placeName']?.toString() ??

          s['locationName']?.toString();

      final resolvedAddr = (serverAddr != null && serverAddr.trim().isNotEmpty && serverAddr != 'Stop location')

          ? serverAddr.trim()

          : (cached != null && cached != 'Resolving address...'

                ? cached

                : null);

      final hasAddress = resolvedAddr != null && resolvedAddr.trim().isNotEmpty;

      final timeStr = end != null

          ? '${_formatTime(start)} – ${_formatTime(end)}'

          : _formatTime(start);

      final coordText = pt != null ? '(${pt.latitude.toStringAsFixed(4)}, ${pt.longitude.toStringAsFixed(4)})' : '';



      String stopPlace = '';

      if (hasAddress) {

        final parts = resolvedAddr.split(',');

        stopPlace = parts.first.trim();

        if (stopPlace.length < 3 && parts.length > 1) stopPlace = parts[1].trim();

      }

      final stopTitle = stopPlace.isNotEmpty ? 'Stopped near $stopPlace' : (durMin > 0 ? 'Stopped for $durMin min' : 'Stopped');

      final stopSub = hasAddress ? 'Address: $resolvedAddr' : '$timeStr • Stay duration: ${durMin > 0 ? '$durMin min' : 'Stationary'}';



      list.add(

        _TimelineEntry(

          id: 'stop-$i-${s['startUtc']}',

          type: _TimelineType.stop,

          title: stopTitle,

          subtitle: stopSub,

          badge: durMin > 0 ? '$durMin min' : 'Stop',

          at: start,

          end: end,

          coord: pt,

          color: const Color(

            0xff475569,

          ), // Slate gray for confirmed stationary stop

          icon: Icons.pause_circle_filled_rounded,

          stopNumber: i + 1,

          raw: s,

          isMissingVisit: false,

          address: resolvedAddr ?? coordText,

          departureText: end != null ? 'Left at ${_formatTime(end)}' : null,

        ),

      );

    }



    list.sort(_compareTimelineEntries);



    // Strictly filter points to active shift duty window (drop pre-login and off-duty points)

    final shiftPoints = (firstPunchInAt != null)

        ? allPoints.where((p) {

            final raw = DateTime.tryParse('${p['capturedAtUtc'] ?? p['atUtc'] ?? p['time']}');

            if (raw == null) return false;

            final ist = toIST(raw);

            if (ist.isBefore(firstPunchInAt!.subtract(const Duration(seconds: 30)))) return false;

            if (lastPunchOutAt != null && ist.isAfter(lastPunchOutAt.add(const Duration(seconds: 30)))) return false;

            return true;

          }).toList()

        : <Json>[];



    // Every movement interval is backed by consecutive moving fixes in recording segments.

    final evidence = recordedSegments(shiftPoints);

    for (final segment in evidence) {

      if (segment.length < 2) continue;

      var movingLegs = extractMovingLegs(segment);

      if (movingLegs.isEmpty) {

        final fallbackLeg = evaluateMovingLeg(segment);

        if (fallbackLeg != null) movingLegs = [fallbackLeg];

      }

      for (final leg in movingLegs) {

        final start = businessDisplay(leg.startUtc);

        final end = businessDisplay(leg.endUtc);

        final distance = leg.distanceMeters;

        final durationMinutes = end.difference(start).inMinutes.abs();



        final meters = distance >= 1000

            ? '${(distance / 1000).toStringAsFixed(1)} km'

            : '${distance.round()} m';

        final pt = routeCoordinate(leg.points.first);

        final endPt = routeCoordinate(leg.points.last);

        final startAddr = pt != null ? TrackyuAddressCache.get(pt.latitude, pt.longitude) : null;

        final endAddr = endPt != null ? TrackyuAddressCache.get(endPt.latitude, endPt.longitude) : null;

        String addr;

        if (startAddr != null && endAddr != null) {

          final sParts = startAddr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

          final eParts = endAddr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

          final sName = sParts.isNotEmpty ? sParts.first : startAddr;

          final eName = eParts.isNotEmpty ? eParts.first : endAddr;

          addr = sName == eName ? 'Around $sName' : 'From $sName to $eName';

        } else if (startAddr != null || endAddr != null) {

          final known = startAddr ?? endAddr!;

          final parts = known.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

          addr = 'Near ${parts.isNotEmpty ? parts.first : known}';

        } else {

          addr = 'In transit • Route recorded';

        }

        final movingMin = durationMinutes > 0 ? durationMinutes : 1;

        final avgSpeedKmh = leg.avgSpeedKmh;

        final isWalk = avgSpeedKmh < 6.5;

        final activityTitle = isWalk ? 'Walking' : 'Motorcycling';

        final activityIcon = isWalk ? Icons.directions_walk_rounded : Icons.two_wheeler_rounded;

        final activityColor = isWalk ? const Color(0xff10b981) : const Color(0xff3b82f6);

        list.add(

          _TimelineEntry(

            id: 'movement:${leg.points.first['capturedAtUtc']}',

            type: _TimelineType.travel,

            title: activityTitle,

            subtitle: '$meters • $movingMin min',

            badge: activityTitle,

            at: start,

            end: end,

            coord: pt,

            address: addr,

            color: activityColor,

            icon: activityIcon,

            distanceMeters: distance,

          ),

        );

      }

    }

    for (final gap in recordingGaps(evidence)) {

      final isStationary = gap['isStationary'] == true;

      final distM = toNum(gap['distanceMeters']);

      final startUtc = instant(gap['startUtc']);

      final endUtc = instant(gap['endUtc']);

      if (startUtc != null && endUtc != null) {

        final sec = endUtc.difference(startUtc).inSeconds;

        if (sec < 120 && (distM == null || distM < 25)) continue;

      }

      final lat = toNum(gap['latitude']);

      final lng = toNum(gap['longitude']);

      final endLat = toNum(gap['endLatitude']);

      final endLng = toNum(gap['endLongitude']);




      if (firstPunchInAt != null && startUtc != null && toIST(startUtc).isBefore(firstPunchInAt)) continue;

      if (lastPunchOutAt != null && startUtc != null && toIST(startUtc).isAfter(lastPunchOutAt)) continue;



      final cacheKey = (lat != null && lng != null)

          ? '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}'

          : '';

      final cachedAddress = (lat != null && lng != null

              ? TrackyuAddressCache.get(lat.toDouble(), lng.toDouble())

              : null) ??

          _addressCache[cacheKey] ??

          gap['address']?.toString();

      final hasAddr = cachedAddress != null &&

          cachedAddress.trim().isNotEmpty &&

          cachedAddress != '-' &&

          cachedAddress != 'Stop location' &&

          cachedAddress != 'Halt location' &&

          !cachedAddress.contains('Address not loaded');



      // If stationary and an existing stop or visit is near, don't duplicate

      if (isStationary) {

        final gPt = (lat != null && lng != null) ? LatLng(lat.toDouble(), lng.toDouble()) : null;

        if (gPt != null) {

          final dup = stops.any((s) {

            final sPt = safeLatLng(s['latitude'], s['longitude']);

            if (sPt == null || distCalc(gPt, sPt) > 100) return false;

            final sStart = instant(s['startUtc']);

            final sEnd = instant(s['endUtc']) ?? sStart;

            if (sStart == null || sEnd == null || startUtc == null || endUtc == null) return true;

            return !startUtc.isAfter(sEnd) && !endUtc.isBefore(sStart);

          });

          if (dup) continue;

        }

      }



      final durMin = (startUtc != null && endUtc != null) ? endUtc.difference(startUtc).inMinutes : 0;

      String title;

      String subtitle;

      if (isStationary) {

        if (hasAddr) {

          final cleanAddr = cachedAddress.trim();

          final parts = cleanAddr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

          final placeName = TrackyuAddressCache.getPlaceName(lat?.toDouble(), lng?.toDouble()) ??

              (parts.length > 1 ? parts.sublist(0, 2).join(', ') : parts.first);

          title = 'Halt near $placeName';

          subtitle = durMin > 0 ? '$durMin min stay • $cleanAddr' : cleanAddr;

        } else {

          final resolved = (lat != null && lng != null)

              ? TrackyuAddressCache.get(lat.toDouble(), lng.toDouble())

              : null;

          if (resolved != null && resolved.isNotEmpty) {

            title = 'Halt near ${resolved.split(',').first.trim()}';

            subtitle = durMin > 0 ? '$durMin min stay • $resolved' : resolved;

          } else {

            title = durMin > 0 ? 'Halt ($durMin min stay)' : 'Halt';

            subtitle = durMin > 0 ? '$durMin min stay recorded' : 'Location recorded';

          }

        }

      } else {

        final fromName = (lat != null && lng != null)
            ? TrackyuAddressCache.get(lat.toDouble(), lng.toDouble())
            : null;
        final toName = (endLat != null && endLng != null)
            ? TrackyuAddressCache.get(endLat.toDouble(), endLng.toDouble())
            : null;
        if (fromName != null && toName != null) {
          final sParts = fromName.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          final eParts = toName.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          final sName = sParts.isNotEmpty ? sParts.first : fromName;
          final eName = eParts.isNotEmpty ? eParts.first : toName;
          title = sName == eName ? 'Movement around $sName' : 'Travel from $sName to $eName';
        } else if (fromName != null || toName != null) {
          final known = fromName ?? toName!;
          final parts = known.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          title = 'Travel near ${parts.isNotEmpty ? parts.first : known}';
        } else {
          title = 'Travel between locations';
        }

        subtitle = (distM != null && distM > 50)

            ? '${(distM / 1000).toStringAsFixed(1)} km traveled'

            : 'Moving between GPS fixes';

      }



      list.add(

        _TimelineEntry(

          id: 'gap:${gap['startUtc']}',

          type: isStationary ? _TimelineType.stop : _TimelineType.gap,

          title: title,

          subtitle: subtitle,

          badge: isStationary ? 'Halt' : 'Interval',

          at: businessDisplay(instant(gap['startUtc'])!),

          end: businessDisplay(instant(gap['endUtc'])!),

          coord: (lat != null && lng != null) ? LatLng(lat.toDouble(), lng.toDouble()) : null,

          color: isStationary ? const Color(0xff0288d1) : const Color(0xff64748b),

          icon: isStationary ? Icons.location_on_rounded : Icons.explore_rounded,

          address: hasAddr ? cachedAddress : (TrackyuAddressCache.get(lat?.toDouble(), lng?.toDouble()) ?? 'Location recorded'),

          distanceMeters: distM?.toDouble(),

          raw: gap,

        ),

      );

    }

    final capture = instant(_position?['capturedAtUtc']);

    if (_today && capture != null && routeCoordinate(_position) != null) {

      final key = coordinateKey(_position);

      final coord = routeCoordinate(_position)!;

      final cached = TrackyuAddressCache.get(coord.latitude, coord.longitude);

      final address =

          cached ??

          _position?['address']?.toString() ??

          _position?['telemetry']?['address']?.toString() ??

          _addressCache[key] ??

          'Location recorded';

      if (address.isNotEmpty && !address.startsWith('(')) {

        TrackyuAddressCache.put(coord.latitude, coord.longitude, address);

      }

      list.add(

        _TimelineEntry(

          id: 'last-fix:${capture.toIso8601String()}',

          type: _TimelineType.stop,

          title: _current ? 'You are here' : 'Last known location',

          subtitle: '$address · ${_formatTime(businessDisplay(capture))}',

          badge: _current ? 'Recent GPS' : 'Recorded',

          at: businessDisplay(capture),

          coord: routeCoordinate(_position),

          color: const Color(0xff0288d1),

          icon: Icons.my_location_rounded,

          raw: _position,

          address: address,

        ),

      );

    }

    list.sort(_compareTimelineEntries);

    return list;

  }



  void _focusLocation(LatLng point, {bool follow = false}) {

    _followPosition = follow;

    try {

      mapController.move(point, 18);

    } catch (_) {}

  }



  void _fitBounds(List<LatLng> points) {

    if (points.isEmpty) return;

    try {

      if (points.length == 1 || points.every((p) => p == points.first)) {

        mapController.move(points.first, 17.5);

      } else {

        mapController.fitCamera(

          CameraFit.bounds(

            bounds: LatLngBounds.fromPoints(points),

            padding: const EdgeInsets.all(36),

            maxZoom: 18.5,

          ),

        );

      }

    } catch (_) {}

  }



  void _showVisitDetailsModal(BuildContext context, Json visit) {

    final rawStart = DateTime.tryParse('${visit['checkInUtc']}');

    final rawEnd = DateTime.tryParse('${visit['checkOutUtc']}');

    final start = rawStart != null ? toIST(rawStart) : null;

    final end = rawEnd != null ? toIST(rawEnd) : null;

    final durMin = (start != null && end != null)

        ? end.difference(start).inMinutes

        : null;

    final shop = visit['shopName']?.toString().trim().isNotEmpty == true

        ? visit['shopName'].toString().trim()

        : (visit['clientName']?.toString().trim().isNotEmpty == true

              ? visit['clientName'].toString().trim()

              : 'Client visit');

    final addr = visit['address']?.toString().trim().isNotEmpty == true

        ? visit['address'].toString().trim()

        : (visit['placeName']?.toString().trim().isNotEmpty == true

              ? visit['placeName'].toString().trim()

              : 'Address not recorded');

    final remarks = visit['remarks']?.toString().trim().isNotEmpty == true

        ? visit['remarks'].toString().trim()

        : (visit['remark']?.toString().trim().isNotEmpty == true

              ? visit['remark'].toString().trim()

              : 'No remarks added');



    final inPt = safeLatLng(

      visit['inLatitude'] ?? visit['latitude'],

      visit['inLongitude'] ?? visit['longitude'],

    );

    final outPt = safeLatLng(visit['outLatitude'], visit['outLongitude']);

    final String? latLngText = inPt != null

        ? '${inPt.latitude.toStringAsFixed(6)}, ${inPt.longitude.toStringAsFixed(6)}'

        : null;

    final String? outLatLngText = outPt != null

        ? '${outPt.latitude.toStringAsFixed(6)}, ${outPt.longitude.toStringAsFixed(6)}'

        : null;



    showModalBottomSheet(

      context: context,

      isScrollControlled: true,

      backgroundColor: _darkMode ? const Color(0xff1e1e1e) : Colors.white,

      shape: const RoundedRectangleBorder(

        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),

      ),

      builder: (ctx) {

        return ConstrainedBox(

          constraints: BoxConstraints(

            maxHeight: MediaQuery.of(ctx).size.height * 0.88,

          ),

          child: Padding(

            padding: EdgeInsets.fromLTRB(

              20,

              16,

              20,

              MediaQuery.of(ctx).viewInsets.bottom + 20,

            ),

            child: SingleChildScrollView(

              physics: const BouncingScrollPhysics(),

              child: Column(

                mainAxisSize: MainAxisSize.min,

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  Row(

                    mainAxisAlignment: MainAxisAlignment.spaceBetween,

                    children: [

                      const Text(

                        'OPEN VISIT DETAILS',

                        style: TextStyle(

                          fontSize: 13,

                          fontWeight: FontWeight.w700,

                          letterSpacing: 1.1,

                          color: Color(0xffab47bc),

                        ),

                      ),

                      IconButton(

                        icon: Icon(

                          Icons.close_rounded,

                          color: _darkMode ? Colors.white : Colors.black87,

                        ),

                        onPressed: () => Navigator.pop(ctx),

                      ),

                    ],

                  ),

                  const SizedBox(height: 6),

                  Text(

                    shop,

                    style: TextStyle(

                      fontSize: 20,

                      fontWeight: FontWeight.w700,

                      color: _darkMode ? Colors.white : const Color(0xff102c4a),

                    ),

                  ),

                  const SizedBox(height: 4),

                  Text(

                    visit['placeName']?.toString().trim().isNotEmpty == true

                        ? visit['placeName'].toString().trim()

                        : '${visit['kind'] ?? 'Open Visit'} • Check-in',

                    style: const TextStyle(

                      fontSize: 13,

                      color: Color(0xff94a3b8),

                    ),

                  ),

                  const SizedBox(height: 16),

                  Container(

                    padding: const EdgeInsets.all(12),

                    decoration: BoxDecoration(

                      color: _darkMode

                          ? const Color(0xff25282c)

                          : const Color(0xfff8fafd),

                      borderRadius: BorderRadius.circular(12),

                      border: Border.all(

                        color: _darkMode

                            ? const Color(0xff374151)

                            : const Color(0xffe2e8f0),

                      ),

                    ),

                    child: Row(

                      mainAxisAlignment: MainAxisAlignment.spaceAround,

                      children: [

                        Column(

                          children: [

                            const Text(

                              'CHECK IN',

                              style: TextStyle(

                                fontSize: 10,

                                fontWeight: FontWeight.w600,

                                color: Color(0xff94a3b8),

                              ),

                            ),

                            const SizedBox(height: 4),

                            Text(

                              start != null ? _formatTime(start) : '--',

                              style: TextStyle(

                                fontSize: 14,

                                fontWeight: FontWeight.w700,

                                color: _darkMode

                                    ? Colors.white

                                    : Colors.black87,

                              ),

                            ),

                          ],

                        ),

                        Column(

                          children: [

                            const Text(

                              'CHECK OUT',

                              style: TextStyle(

                                fontSize: 10,

                                fontWeight: FontWeight.w600,

                                color: Color(0xff94a3b8),

                              ),

                            ),

                            const SizedBox(height: 4),

                            Text(

                              end != null ? _formatTime(end) : 'In progress',

                              style: TextStyle(

                                fontSize: 14,

                                fontWeight: FontWeight.w700,

                                color: _darkMode

                                    ? Colors.white

                                    : Colors.black87,

                              ),

                            ),

                          ],

                        ),

                        Column(

                          children: [

                            const Text(

                              'DURATION',

                              style: TextStyle(

                                fontSize: 10,

                                fontWeight: FontWeight.w600,

                                color: Color(0xff94a3b8),

                              ),

                            ),

                            const SizedBox(height: 4),

                            Text(

                              durMin != null ? '$durMin min' : '--',

                              style: const TextStyle(

                                fontSize: 14,

                                fontWeight: FontWeight.w700,

                                color: Color(0xff26c6da),

                              ),

                            ),

                          ],

                        ),

                      ],

                    ),

                  ),

                  const SizedBox(height: 14),

                  // Location, Current Address & Coordinates card

                  Container(

                    width: double.infinity,

                    padding: const EdgeInsets.all(12),

                    decoration: BoxDecoration(

                      color: _darkMode

                          ? const Color(0xff25282c)

                          : const Color(0xfff8fafd),

                      borderRadius: BorderRadius.circular(12),

                      border: Border.all(

                        color: _darkMode

                            ? const Color(0xff374151)

                            : const Color(0xffe2e8f0),

                      ),

                    ),

                    child: Column(

                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [

                        Row(

                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [

                            const Icon(

                              Icons.location_on_rounded,

                              color: Color(0xff26c6da),

                              size: 18,

                            ),

                            const SizedBox(width: 8),

                            Expanded(

                              child: Column(

                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [

                                  const Text(

                                    'SHOP ADDRESS',

                                    style: TextStyle(

                                      fontSize: 10,

                                      fontWeight: FontWeight.w700,

                                      letterSpacing: 0.6,

                                      color: Color(0xff94a3b8),

                                    ),

                                  ),

                                  const SizedBox(height: 3),

                                  Text(

                                    addr,

                                    style: TextStyle(

                                      fontSize: 13,

                                      fontWeight: FontWeight.w600,

                                      color: _darkMode

                                          ? Colors.white

                                          : const Color(0xff1f2937),

                                    ),

                                  ),

                                ],

                              ),

                            ),

                          ],

                        ),

                        if (latLngText != null) ...[

                          const SizedBox(height: 10),

                          Divider(

                            height: 1,

                            color: _darkMode

                                ? const Color(0xff374151)

                                : const Color(0xffe2e8f0),

                          ),

                          const SizedBox(height: 10),

                          Row(

                            children: [

                              const Icon(

                                Icons.explore_outlined,

                                color: Color(0xffab47bc),

                                size: 18,

                              ),

                              const SizedBox(width: 8),

                              Expanded(

                                child: Column(

                                  crossAxisAlignment: CrossAxisAlignment.start,

                                  children: [

                                    const Text(

                                      'GPS COORDINATES (LAT, LONG)',

                                      style: TextStyle(

                                        fontSize: 10,

                                        fontWeight: FontWeight.w700,

                                        letterSpacing: 0.6,

                                        color: Color(0xff94a3b8),

                                      ),

                                    ),

                                    const SizedBox(height: 3),

                                    Text(

                                      latLngText,

                                      style: TextStyle(

                                        fontSize: 13,

                                        fontWeight: FontWeight.w600,

                                        fontFamily: 'monospace',

                                        color: _darkMode

                                            ? const Color(0xff80cbc4)

                                            : const Color(0xff00695c),

                                      ),

                                    ),

                                    if (outLatLngText != null) ...[

                                      const SizedBox(height: 2),

                                      Text(

                                        'Check-out GPS: $outLatLngText',

                                        style: TextStyle(

                                          fontSize: 11,

                                          fontFamily: 'monospace',

                                          color: _darkMode

                                              ? Colors.white54

                                              : Colors.black54,

                                        ),

                                      ),

                                    ],

                                  ],

                                ),

                              ),

                              IconButton(

                                icon: const Icon(Icons.copy_rounded, size: 16),

                                tooltip: 'Copy coordinates',

                                color: _darkMode

                                    ? Colors.white70

                                    : Colors.black54,

                                onPressed: () {

                                  Clipboard.setData(

                                    ClipboardData(text: latLngText),

                                  );

                                  ScaffoldMessenger.of(context).showSnackBar(

                                    const SnackBar(

                                      content: Text(

                                        'Coordinates copied to clipboard',

                                      ),

                                      duration: Duration(seconds: 1),

                                    ),

                                  );

                                },

                              ),

                            ],

                          ),

                        ],

                        if (inPt != null) ...[

                          const SizedBox(height: 12),

                          Container(

                            height: 160,

                            width: double.infinity,

                            clipBehavior: Clip.antiAlias,

                            decoration: BoxDecoration(

                              borderRadius: BorderRadius.circular(10),

                              border: Border.all(

                                color: _darkMode

                                    ? const Color(0xff374151)

                                    : const Color(0xffe2e8f0),

                              ),

                            ),

                            child: Stack(

                              children: [

                                FlutterMap(

                                  key: ValueKey(

                                    'visit-modal-map-${inPt.latitude}-${inPt.longitude}',

                                  ),

                                  options: MapOptions(

                                    initialCenter: inPt,

                                    initialZoom: 17.5,

                                    interactionOptions:

                                        const InteractionOptions(

                                          flags:

                                              InteractiveFlag.all &

                                              ~InteractiveFlag.rotate,

                                        ),

                                  ),

                                  children: [

                                    legacyMapTiles(

                                      offline: () => widget.controller.offline,

                                      darkMode: _darkMode,

                                    ),

                                    legacyMapAttribution,

                                    MarkerLayer(

                                      markers: [

                                        Marker(

                                          point: inPt,

                                          width: 38,

                                          height: 38,

                                          child: Container(

                                            decoration: const BoxDecoration(

                                              color: Color(0xffab47bc),

                                              shape: BoxShape.circle,

                                              boxShadow: [

                                                BoxShadow(

                                                  color: Colors.black26,

                                                  blurRadius: 4,

                                                  offset: Offset(0, 2),

                                                ),

                                              ],

                                            ),

                                            child: const Icon(

                                              Icons.storefront_rounded,

                                              color: Colors.white,

                                              size: 19,

                                            ),

                                          ),

                                        ),

                                        if (outPt != null)

                                          Marker(

                                            point: outPt,

                                            width: 34,

                                            height: 34,

                                            child: Container(

                                              decoration: const BoxDecoration(

                                                color: Color(0xff26c6da),

                                                shape: BoxShape.circle,

                                                boxShadow: [

                                                  BoxShadow(

                                                    color: Colors.black26,

                                                    blurRadius: 4,

                                                    offset: Offset(0, 2),

                                                  ),

                                                ],

                                              ),

                                              child: const Icon(

                                                Icons.flag_rounded,

                                                color: Colors.white,

                                                size: 17,

                                              ),

                                            ),

                                          ),

                                      ],

                                    ),

                                  ],

                                ),

                                Positioned(

                                  top: 8,

                                  right: 8,

                                  child: Container(

                                    padding: const EdgeInsets.symmetric(

                                      horizontal: 8,

                                      vertical: 3,

                                    ),

                                    decoration: BoxDecoration(

                                      color: Colors.black.withValues(

                                        alpha: 0.65,

                                      ),

                                      borderRadius: BorderRadius.circular(6),

                                    ),

                                    child: const Row(

                                      mainAxisSize: MainAxisSize.min,

                                      children: [

                                        Icon(

                                          Icons.location_on_rounded,

                                          size: 11,

                                          color: Color(0xff26c6da),

                                        ),

                                        SizedBox(width: 3),

                                        Text(

                                          'Visit Map',

                                          style: TextStyle(

                                            fontSize: 10,

                                            fontWeight: FontWeight.w600,

                                            color: Colors.white,

                                          ),

                                        ),

                                      ],

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

                  const SizedBox(height: 14),

                  // Selfie / Photo section

                  Row(

                    children: [

                      const Icon(

                        Icons.photo_camera_rounded,

                        size: 16,

                        color: Color(0xffab47bc),

                      ),

                      const SizedBox(width: 6),

                      Text(

                        'VISIT SELFIE / PHOTO',

                        style: TextStyle(

                          fontSize: 11,

                          fontWeight: FontWeight.w700,

                          letterSpacing: 0.8,

                          color: _darkMode

                              ? Colors.white70

                              : const Color(0xff1f2937),

                        ),

                      ),

                    ],

                  ),

                  const SizedBox(height: 8),

                  _VisitSelfiePreview(

                    controller: widget.controller,

                    visit: visit,

                    darkMode: _darkMode,

                  ),

                  const SizedBox(height: 14),

                  Text(

                    'Remarks / Notes',

                    style: TextStyle(

                      fontSize: 13,

                      fontWeight: FontWeight.w700,

                      color: _darkMode ? Colors.white : const Color(0xff1f2937),

                    ),

                  ),

                  const SizedBox(height: 6),

                  Container(

                    width: double.infinity,

                    padding: const EdgeInsets.all(12),

                    decoration: BoxDecoration(

                      color: _darkMode

                          ? const Color(0xff25282c)

                          : const Color(0xfff8fafd),

                      borderRadius: BorderRadius.circular(10),

                    ),

                    child: Text(

                      remarks,

                      style: TextStyle(

                        fontSize: 13,

                        color: _darkMode

                            ? const Color(0xffcbd5e1)

                            : const Color(0xff334155),

                      ),

                    ),

                  ),

                  const SizedBox(height: 20),

                  SizedBox(

                    width: double.infinity,

                    child: FilledButton.icon(

                      style: FilledButton.styleFrom(

                        backgroundColor: const Color(0xff26c6da),

                        foregroundColor: const Color(0xff00363a),

                        padding: const EdgeInsets.symmetric(vertical: 14),

                        shape: RoundedRectangleBorder(

                          borderRadius: BorderRadius.circular(12),

                        ),

                      ),

                      onPressed: () {

                        Navigator.pop(ctx);

                        final pt = safeLatLng(

                          visit['inLatitude'] ?? visit['latitude'],

                          visit['inLongitude'] ?? visit['longitude'],

                        );

                        if (pt != null) {

                          _focusLocation(pt);

                        }

                      },

                      icon: const Icon(Icons.map_rounded),

                      label: const Text(

                        'Show this visit on map',

                        style: TextStyle(fontWeight: FontWeight.w700),

                      ),

                    ),

                  ),

                ],

              ),

            ),

          ),

        );

      },

    );

  }



  @override

  Widget build(BuildContext context) {

    if (!_sameSession) {

      return Scaffold(

        appBar: AppBar(title: const Text('Timeline')),

        body: const Center(

          child: Padding(

            padding: EdgeInsets.all(24),

            child: Text('Session changed.', textAlign: TextAlign.center),

          ),

        ),

      );

    }

    final events = uniqueRouteEvents(

      (data['events'] as List? ?? [])

          .whereType<Map>()

          .map((e) => Map<String, dynamic>.from(e))

          .toList(),

      'id',

      'atUtc',

    );

    final rawStops = (data['route'] as Map?)?['stops'] as List? ?? [];

    final visits = uniqueRouteEvents(

      (data['visits'] as List? ?? [])

          .whereType<Map>()

          .map((v) => Map<String, dynamic>.from(v))

          .toList(),

      'id',

      'checkInUtc',

    );



    final allRawPoints = segments.expand((s) => s).toList();

    final stops = _extractStops(

      rawStops

          .whereType<Map>()

          .map((s) => Map<String, dynamic>.from(s))

          .toList(),

      allRawPoints,

      visits,

    );

    if (!widget.controller.offline && stops.isNotEmpty) {

      unawaited(_resolveMissingAddresses(stops));

    }



    final preview = routePreview(segments);

    const distCalc = Distance();
    final cleanPolylines = preview
        .map((s) {
          var pts = s.map(routeCoordinate).whereType<LatLng>().toList();
          if (pts.length <= 2) return pts;

          // 1. Remove acute rebound spikes (A -> B -> C where B shoots away and returns immediately)
          final deSpiked = <LatLng>[pts.first];
          for (var i = 1; i < pts.length - 1; i++) {
            final prev = deSpiked.last;
            final curr = pts[i];
            final next = pts[i + 1];
            final d1 = distCalc(prev, curr);
            final d2 = distCalc(curr, next);
            final dDirect = distCalc(prev, next);
            // If current point detours out > 60m and bounces straight back (direct distance < 45% of detour)
            final isSpike = (d1 > 60.0 && d2 > 60.0 && dDirect < 0.45 * (d1 + d2));
            if (!isSpike) {
              deSpiked.add(curr);
            }
          }
          deSpiked.add(pts.last);

          // 2. Decimate points closer than 20m to keep lines smooth
          final filtered = <LatLng>[deSpiked.first];
          for (var i = 1; i < deSpiked.length - 1; i++) {
            if (distCalc(filtered.last, deSpiked[i]) >= 20.0) {
              filtered.add(deSpiked[i]);
            }
          }
          filtered.add(deSpiked.last);
          return filtered;
        })
        .where((s) => s.isNotEmpty)
        .toList();

    final allCleanPoints = <LatLng>[

      ...cleanPolylines.expand((p) => p),

      for (final v in visits)

        if (routeCoordinate(v) != null) routeCoordinate(v)!,

      if (_today && routeCoordinate(_position) != null)

        routeCoordinate(_position)!,

    ];

        final filteredFallback = <LatLng>[];
    if (cleanPolylines.every((s) => s.length <= 1) && allCleanPoints.length >= 2) {
      filteredFallback.add(allCleanPoints.first);
      for (var i = 1; i < allCleanPoints.length; i++) {
        final dist = distCalc(filteredFallback.last, allCleanPoints[i]);
        if (dist >= 15.0 && dist <= 250.0) {
          filteredFallback.add(allCleanPoints[i]);
        }
      }
    }

    final continuousRoute = <LatLng>[
      for (final seg in cleanPolylines) ...seg,
    ];
    if (_today) {
      final livePos = routeCoordinate(_position);
      if (livePos != null &&
          (continuousRoute.isEmpty ||
              distCalc(continuousRoute.last, livePos) > 2.0)) {
        continuousRoute.add(livePos);
      }
    }
    if (continuousRoute.length < 2 && filteredFallback.length >= 2) {
      continuousRoute
        ..clear()
        ..addAll(filteredFallback);
    }

    final mapPolylines = <Polyline>[
      if (continuousRoute.length >= 2)
        Polyline(
          points: continuousRoute,
          strokeWidth: 4.8,
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xff00e5ff)
              : const Color(0xff2563eb),
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
    ];

    final rawTimelineItems = _buildTimeline(

      events: events,

      stops: stops,

      visits: visits,

      allPoints: allRawPoints,

    );

    final timelineItems = (!_isLiveMode && _today)

        ? rawTimelineItems

            .where((item) => !item.at.isAfter(_snapshotTime.add(const Duration(seconds: 15))))

            .toList()

        : rawTimelineItems;



    final travelLegsDist = timelineItems
        .where((i) => i.type == _TimelineType.travel)
        .fold<double>(0.0, (acc, item) => acc + (item.distanceMeters ?? 0.0));

    final serverDist = toNum(data['telemetry']?['distanceMeters'] ?? data['route']?['distanceMeters'])?.toDouble();
    final fallbackDist = recordedDistance(segments);
    double totalDistanceMeters = (serverDist != null && serverDist > 0)
        ? (travelLegsDist > serverDist ? travelLegsDist : serverDist)
        : (travelLegsDist > 0 ? travelLegsDist : fallbackDist);

    final String distanceDisplay = totalDistanceMeters >= 1000

        ? '${(totalDistanceMeters / 1000).toStringAsFixed(1)} km'

        : '${totalDistanceMeters.round()} meters';



    int totalStopMinutes = 0;

    for (final s in stops) {

      final st = DateTime.tryParse('${s['startUtc']}');

      final en = DateTime.tryParse('${s['endUtc']}');

      if (st != null && en != null) {

        totalStopMinutes +=

            (toNum(s['stoppedSeconds'])?.toInt() ??

                en.difference(st).inSeconds) ~/

            60;

      }

    }



    int transitMinutes = 0;

    for (final t in timelineItems.where(

      (i) => i.type == _TimelineType.travel,

    )) {

      if (t.end != null) {

        transitMinutes += t.end!.difference(t.at).inMinutes;

      }

    }



    final LatLng? initialCenter = allCleanPoints.isNotEmpty

        ? allCleanPoints.first

        : (allRawPoints.isNotEmpty

              ? routeCoordinate(allRawPoints.first)

              : null);



    final bgColor = _darkMode

        ? const Color(0xff121212)

        : const Color(0xfff8fafd);

    final cardColor = _darkMode ? const Color(0xff1e1e1e) : Colors.white;

    final textPrimary = _darkMode ? Colors.white : const Color(0xff102c4a);

    final textSecondary = _darkMode

        ? const Color(0xff94a3b8)

        : const Color(0xff64748b);

    final borderColor = _darkMode

        ? const Color(0xff2d3135)

        : const Color(0xffe2e8f0);



    if (error != null && data.isEmpty) {

      return Scaffold(

        backgroundColor: bgColor,

        appBar: AppBar(
          leading: BackButton(color: textPrimary),
          backgroundColor: bgColor,
          foregroundColor: textPrimary,
          iconTheme: IconThemeData(color: textPrimary),

          elevation: 0,

          title: Text(

            'Timeline',

            style: TextStyle(

              fontWeight: FontWeight.w700,

              fontSize: 20,

              color: textPrimary,

            ),

          ),

        ),

        body: Center(

          child: Padding(

            padding: const EdgeInsets.all(24),

            child: Column(

              mainAxisSize: MainAxisSize.min,

              children: [

                Icon(Icons.lock_person_rounded, size: 48, color: textSecondary),

                const SizedBox(height: 16),

                Text(

                  error!,

                  textAlign: TextAlign.center,

                  style: TextStyle(

                    color: textPrimary,

                    fontSize: 16,

                    fontWeight: FontWeight.w600,

                  ),

                ),

                const SizedBox(height: 16),

                FilledButton.tonal(onPressed: load, child: const Text('Retry')),

              ],

            ),

          ),

        ),

      );

    }



    Widget buildMapStack({required bool isFullscreen}) {

      return Stack(

        children: [

          FlutterMap(

            mapController: mapController,

            key: ValueKey('route-map-$_fullscreenMap'),

            options: MapOptions(

              onPositionChanged: (_, gesture) {

                if (gesture) _followPosition = false;

              },

              initialCenter:

                  (_today ? routeCoordinate(_position) : null) ??

                  initialCenter ??

                  const LatLng(23.18, 77.42),

              initialZoom: 17.5,



              initialCameraFit: () {

                if (_today || allCleanPoints.length <= 1) {

                  return null;

                }

                try {

                  final b = LatLngBounds.fromPoints(allCleanPoints);

                  if (b.southWest.latitude == b.northEast.latitude &&

                      b.southWest.longitude == b.northEast.longitude) {

                    return null;

                  }

                  return CameraFit.bounds(

                    bounds: b,

                    padding: const EdgeInsets.all(40),

                    maxZoom: 18.5,

                  );

                } catch (_) {

                  return null;

                }

              }(),

            ),

            children: [

              legacyMapTiles(

                offline: () => widget.controller.offline,

                darkMode: _darkMode,

              ),

              legacyMapAttribution,

              PolylineLayer(polylines: mapPolylines),

              if (routeCoordinate(_position) != null &&

                  toNum(_position!['accuracyMeters'])?.isFinite == true)

                CircleLayer(

                  circles: [

                    CircleMarker(

                      point: routeCoordinate(_position)!,

                      radius: (toNum(

                        _position!['accuracyMeters'],

                      )!.toDouble()).clamp(0, 10000),

                      useRadiusInMeter: true,

                      color: const Color(0x2026c6da),

                      borderColor: const Color(0x8026c6da),

                      borderStrokeWidth: 1.5,

                    ),

                  ],

                ),

              MarkerLayer(

                markers: _buildMapMarkers(

                  cleanPoints: allCleanPoints,

                  stops: stops,

                  visits: visits,

                  events: events,

                ),

              ),

            ],

          ),

          if (isFullscreen)

            Positioned(

              top: 12,

              left: 12,

              right: 12,

              child: Material(

                color: _darkMode

                    ? const Color(0xdd1e1e1e)

                    : Colors.white.withValues(alpha: 0.94),

                borderRadius: BorderRadius.circular(20),

                elevation: 4,

                child: Padding(

                  padding: const EdgeInsets.symmetric(

                    horizontal: 14,

                    vertical: 8,

                  ),

                  child: Row(

                    children: [

                      const Icon(

                        Icons.map_rounded,

                        size: 16,

                        color: Color(0xff26c6da),

                      ),

                      const SizedBox(width: 8),

                      Expanded(

                        child: Text(

                          'Full Map View • ${_today ? 'Today' : '${date.day}/${date.month}/${date.year}'}',

                          style: TextStyle(

                            fontSize: 12,

                            fontWeight: FontWeight.w700,

                            color: textPrimary,

                          ),

                        ),

                      ),

                      InkWell(

                        onTap: () => setState(() => _fullscreenMap = false),

                        borderRadius: BorderRadius.circular(12),

                        child: Container(

                          padding: const EdgeInsets.symmetric(

                            horizontal: 8,

                            vertical: 4,

                          ),

                          decoration: BoxDecoration(

                            color: const Color(

                              0xff26c6da,

                            ).withValues(alpha: 0.15),

                            borderRadius: BorderRadius.circular(8),

                          ),

                          child: const Row(

                            mainAxisSize: MainAxisSize.min,

                            children: [

                              Icon(

                                Icons.close_fullscreen_rounded,

                                size: 13,

                                color: Color(0xff26c6da),

                              ),

                              SizedBox(width: 4),

                              Text(

                                'Collapse',

                                style: TextStyle(

                                  fontSize: 11,

                                  fontWeight: FontWeight.w700,

                                  color: Color(0xff26c6da),

                                ),

                              ),

                            ],

                          ),

                        ),

                      ),

                    ],

                  ),

                ),

              ),

            ),

          // Map Floating Controls

          Positioned(

            left: 12,

            bottom: 12,

            child: Row(

              mainAxisSize: MainAxisSize.min,

              children: [

                Material(

                  color: _darkMode ? const Color(0xcc1e1e1e) : Colors.white,

                  borderRadius: BorderRadius.circular(20),

                  elevation: 3,

                  child: InkWell(

                    borderRadius: BorderRadius.circular(20),

                    onTap: () {

                      _followPosition = false;

                      _fitBounds(allCleanPoints);

                    },

                    child: Padding(

                      padding: const EdgeInsets.symmetric(

                        horizontal: 10,

                        vertical: 6,

                      ),

                      child: Row(

                        mainAxisSize: MainAxisSize.min,

                        children: [

                          Icon(

                            Icons.fit_screen_rounded,

                            size: 15,

                            color: textPrimary,

                          ),

                          const SizedBox(width: 4),

                          Text(

                            'Fit route',

                            style: TextStyle(

                              fontSize: 11,

                              fontWeight: FontWeight.w600,

                              color: textPrimary,

                            ),

                          ),

                        ],

                      ),

                    ),

                  ),

                ),

                const SizedBox(width: 8),

                Material(

                  color: _darkMode ? const Color(0xcc1e1e1e) : Colors.white,

                  borderRadius: BorderRadius.circular(20),

                  elevation: 3,

                  child: InkWell(

                    borderRadius: BorderRadius.circular(20),

                    onTap: () {

                      setState(() {

                        _fullscreenMap = !_fullscreenMap;

                      });

                    },

                    child: Padding(

                      padding: const EdgeInsets.symmetric(

                        horizontal: 10,

                        vertical: 6,

                      ),

                      child: Row(

                        mainAxisSize: MainAxisSize.min,

                        children: [

                          Icon(

                            isFullscreen

                                ? Icons.close_fullscreen_rounded

                                : Icons.open_in_full_rounded,

                            size: 15,

                            color: textPrimary,

                          ),

                          const SizedBox(width: 4),

                          Text(

                            isFullscreen ? 'Show timeline' : 'Extend map',

                            style: TextStyle(

                              fontSize: 11,

                              fontWeight: FontWeight.w600,

                              color: textPrimary,

                            ),

                          ),

                        ],

                      ),

                    ),

                  ),

                ),

              ],

            ),

          ),

          Positioned(

            right: 12,

            bottom: 12,

            child: Material(

              color: _darkMode ? const Color(0xcc1e1e1e) : Colors.white,

              shape: const CircleBorder(),

              elevation: 3,

              child: IconButton(

                icon: const Icon(

                  Icons.my_location_rounded,

                  color: Color(0xff26c6da),

                  size: 20,

                ),

                tooltip: 'Show my location',

                onPressed: _requestingFix ? null : _refreshPosition,

              ),

            ),

          ),

        ],

      );

    }



    return PopScope(

      canPop: !_fullscreenMap,

      onPopInvokedWithResult: (didPop, _) {

        if (!didPop && _fullscreenMap) {

          setState(() => _fullscreenMap = false);

        }

      },

      child: Scaffold(

        backgroundColor: bgColor,

        appBar: AppBar(
          leading: BackButton(color: (_darkMode || bgColor.computeLuminance() < 0.45) ? Colors.white : const Color(0xff102c4a)),
          backgroundColor: bgColor,
          foregroundColor: (_darkMode || bgColor.computeLuminance() < 0.45) ? Colors.white : const Color(0xff102c4a),
          iconTheme: IconThemeData(color: (_darkMode || bgColor.computeLuminance() < 0.45) ? Colors.white : const Color(0xff102c4a)),
          actionsIconTheme: IconThemeData(color: (_darkMode || bgColor.computeLuminance() < 0.45) ? Colors.white : const Color(0xff102c4a)),

          elevation: 0,

          scrolledUnderElevation: 0,

          title: Text(

            _fullscreenMap ? 'Map View' : 'Timeline',

            style: TextStyle(

              fontWeight: FontWeight.w700,

              fontSize: 20,

              color: (_darkMode || bgColor.computeLuminance() < 0.45) ? Colors.white : const Color(0xff102c4a),

            ),

          ),

          actions: [

            IconButton(

              tooltip: _fullscreenMap ? 'Show timeline' : 'Extend map',

              icon: Icon(

                _fullscreenMap

                    ? Icons.view_timeline_rounded

                    : Icons.open_in_full_rounded,

                color: textSecondary,

              ),

              onPressed: () => setState(() => _fullscreenMap = !_fullscreenMap),

            ),

            IconButton(

              tooltip: _darkMode ? 'Switch to Light (Beta)' : 'Switch to Midnight Dark',

              icon: Icon(

                _darkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,

                color: textSecondary,

              ),

              onPressed: () async {

                await widget.controller.toggleDarkMode();

                if (mounted) setState(() {});

              },

            ),

            if (_today)

              IconButton(

                tooltip: _isLiveMode

                    ? 'Live mode active (continuous GPS updates)'

                    : 'View mode active (snapshot paused)',

                icon: Icon(

                  _isLiveMode ? Icons.sensors_rounded : Icons.pause_circle_outline_rounded,

                  color: _isLiveMode ? const Color(0xff10b981) : textSecondary,

                ),

                onPressed: () {

                  setState(() {

                    _isLiveMode = !_isLiveMode;

                    if (_isLiveMode) {

                      load(silent: true);

                    } else {

                      _snapshotTime = DateTime.now();

                    }

                  });

                },

              ),

            IconButton(

              tooltip: 'Refresh route',

              onPressed: loading ? null : load,

              icon: Icon(Icons.refresh_rounded, color: textSecondary),

            ),

          ],

          bottom: _fullscreenMap

              ? null

              : PreferredSize(

                  preferredSize: const Size.fromHeight(48),

                  child: Container(

                    decoration: BoxDecoration(

                      border: Border(

                        bottom: BorderSide(color: borderColor, width: 1),

                      ),

                    ),

                    child: Row(

                      children: [

                        _buildTopTabItem(

                          0,

                          'Day',

                          Icons.calendar_today_rounded,

                          textPrimary,

                          textSecondary,

                        ),

                        _buildTopTabItem(

                          1,

                          'Places',

                          Icons.place_rounded,

                          textPrimary,

                          textSecondary,

                        ),

                        _buildTopTabItem(

                          2,

                          'Insights',

                          Icons.insights_rounded,

                          textPrimary,

                          textSecondary,

                        ),

                      ],

                    ),

                  ),

                ),

        ),

        body: _fullscreenMap

            ? buildMapStack(isFullscreen: true)

            : (_selectedTab == 0

                  ? ListView(

                      scrollCacheExtent: const ScrollCacheExtent.pixels(300),

                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),

                      children: [

                        // Google Maps Timeline Interactive Map Box

                        Container(

                          clipBehavior: Clip.antiAlias,

                          decoration: BoxDecoration(

                            color: cardColor,

                            borderRadius: BorderRadius.circular(20),

                            border: Border.all(color: borderColor),

                            boxShadow: [

                              BoxShadow(

                                color: Colors.black.withValues(

                                  alpha: _darkMode ? 0.3 : 0.05,

                                ),

                                blurRadius: 14,

                                offset: const Offset(0, 4),

                              ),

                            ],

                          ),

                          child: Column(

                            children: [

                              if (allCleanPoints.isNotEmpty ||

                                  allRawPoints.isNotEmpty ||

                                  _position != null)

                                SizedBox(

                                  height: 260,

                                  child: buildMapStack(isFullscreen: false),

                                )

                              else if (!loading)

                                Padding(

                                  padding: const EdgeInsets.all(28),

                                  child: Center(

                                    child: Column(

                                      mainAxisSize: MainAxisSize.min,

                                      children: [

                                        Icon(

                                          _today && !widget.controller.onDuty

                                              ? Icons.alarm_rounded

                                              : Icons.location_off_rounded,

                                          size: 38,

                                          color: _today && !widget.controller.onDuty

                                              ? const Color(0xfff59e0b)

                                              : textSecondary,

                                        ),

                                        const SizedBox(height: 8),

                                        Text(

                                          _today && (!widget.controller.onDuty || !events.any((ev) => '${ev['type']}' == 'PunchIn'))

                                              ? 'Work Not Started Today'

                                              : 'No location points recorded for this date.',

                                          textAlign: TextAlign.center,

                                          style: TextStyle(

                                            color: textPrimary,

                                            fontWeight: FontWeight.w700,

                                            fontSize: 14,

                                          ),

                                        ),

                                        if (_today && !widget.controller.onDuty) ...[

                                          const SizedBox(height: 4),

                                          Text(

                                            'Please punch in from the Home screen to start recording your live route and GPS timeline.',

                                            textAlign: TextAlign.center,

                                            style: TextStyle(color: textSecondary, fontSize: 12),

                                          ),

                                          const SizedBox(height: 12),

                                          FilledButton.icon(

                                            onPressed: () => Navigator.pop(context),

                                            icon: const Icon(Icons.login_rounded, size: 16),

                                            label: const Text('Go to Home & Punch In'),

                                            style: FilledButton.styleFrom(

                                              backgroundColor: const Color(0xfff97316),

                                              foregroundColor: Colors.white,

                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),

                                            ),

                                          ),

                                        ],

                                      ],

                                    ),

                                  ),

                                ),

                            ],

                          ),

                        ),



                        const SizedBox(height: 12),



                        // Date Navigator Bar (< Today ▾ >)

                        Container(

                          padding: const EdgeInsets.symmetric(

                            horizontal: 8,

                            vertical: 4,

                          ),

                          decoration: BoxDecoration(

                            color: cardColor,

                            borderRadius: BorderRadius.circular(16),

                            border: Border.all(color: borderColor),

                          ),

                          child: Row(

                            mainAxisAlignment: MainAxisAlignment.spaceBetween,

                            children: [

                              IconButton(

                                icon: Icon(

                                  Icons.chevron_left_rounded,

                                  color: textPrimary,

                                ),

                                tooltip: 'Previous day',

                                onPressed: loading

                                    ? null

                                    : () {

                                        _changeDate(

                                          DateTime(date.year, date.month, date.day - 1),

                                        );

                                      },

                              ),

                              InkWell(

                                onTap: loading

                                    ? null

                                    : () async {

                                        final picked = await showDatePicker(

                                          context: context,

                                          initialDate: date,

                                          firstDate: DateTime(2024),

                                          lastDate: DateTime.parse(

                                            widget.controller.localDay,

                                          ),

                                        );

                                        if (picked != null && mounted) {

                                          _changeDate(picked);

                                        }

                                      },

                                borderRadius: BorderRadius.circular(10),

                                child: Padding(

                                  padding: const EdgeInsets.symmetric(

                                    horizontal: 12,

                                    vertical: 8,

                                  ),

                                  child: Row(

                                    mainAxisSize: MainAxisSize.min,

                                    children: [

                                      Text(

                                        _today

                                            ? 'Today'

                                            : MaterialLocalizations.of(

                                                context,

                                              ).formatMediumDate(date),

                                        style: TextStyle(

                                          fontSize: 16,

                                          fontWeight: FontWeight.w700,

                                          color: textPrimary,

                                        ),

                                      ),

                                      const SizedBox(width: 4),

                                      Icon(

                                        Icons.arrow_drop_down_rounded,

                                        color: const Color(0xff26c6da),

                                        size: 22,

                                      ),

                                    ],

                                  ),

                                ),

                              ),

                              IconButton(

                                icon: Icon(

                                  Icons.chevron_right_rounded,

                                  color: _today

                                      ? textSecondary.withValues(alpha: 0.3)

                                      : textPrimary,

                                ),

                                tooltip: 'Next day',

                                onPressed: (loading || _today)

                                    ? null

                                    : () {

                                        _changeDate(

                                          DateTime(date.year, date.month, date.day + 1),

                                        );

                                      },

                              ),

                            ],

                          ),

                        ),



                        const SizedBox(height: 12),



                        // Google Maps style sleek horizontal summary bar (no bulky boxes)

                        Builder(

                          builder: (context) {

                            final completedVisits = visits.where((v) => v['checkOutUtc'] != null || v['out_time'] != null).length;

                            final openVisits = visits.length - completedVisits;

                            final hasOpenVisit = openVisits > 0;



                            return Container(

                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),

                              decoration: BoxDecoration(

                                color: cardColor,

                                borderRadius: BorderRadius.circular(16),

                                border: Border.all(color: borderColor),

                                boxShadow: [

                                  BoxShadow(

                                    color: Colors.black.withValues(alpha: _darkMode ? 0.2 : 0.03),

                                    blurRadius: 6,

                                    offset: const Offset(0, 2),

                                  ),

                                ],

                              ),

                              child: Row(

                                children: [

                                  // 1. Total Distance

                                  Expanded(

                                    child: Row(

                                      children: [

                                        Container(

                                          padding: const EdgeInsets.all(7),

                                          decoration: BoxDecoration(

                                            color: const Color(0xff0288d1).withValues(alpha: _darkMode ? 0.25 : 0.1),

                                            borderRadius: BorderRadius.circular(10),

                                          ),

                                          child: const Icon(

                                            Icons.two_wheeler_rounded,

                                            size: 18,

                                            color: Color(0xff0288d1),

                                          ),

                                        ),

                                        const SizedBox(width: 8),

                                        Expanded(

                                          child: Column(

                                            crossAxisAlignment: CrossAxisAlignment.start,

                                            mainAxisSize: MainAxisSize.min,

                                            children: [

                                              Text(

                                                distanceDisplay,

                                                style: TextStyle(

                                                  fontSize: 14,

                                                  fontWeight: FontWeight.w800,

                                                  color: textPrimary,

                                                ),

                                                maxLines: 1,

                                                overflow: TextOverflow.ellipsis,

                                              ),

                                              Text(

                                                'Distance',

                                                style: TextStyle(

                                                  fontSize: 10.5,

                                                  fontWeight: FontWeight.w500,

                                                  color: textSecondary,

                                                ),

                                              ),

                                            ],

                                          ),

                                        ),

                                      ],

                                    ),

                                  ),

                                  Container(width: 1, height: 26, color: borderColor, margin: const EdgeInsets.symmetric(horizontal: 4)),

                                  // 2. Visits (Completed / In Progress)

                                  Expanded(

                                    child: Row(

                                      children: [

                                        Container(

                                          padding: const EdgeInsets.all(7),

                                          decoration: BoxDecoration(

                                            color: (hasOpenVisit ? const Color(0xfff97316) : const Color(0xff10b981))

                                                .withValues(alpha: _darkMode ? 0.25 : 0.1),

                                            borderRadius: BorderRadius.circular(10),

                                          ),

                                          child: Icon(

                                            Icons.storefront_rounded,

                                            size: 18,

                                            color: hasOpenVisit ? const Color(0xfff97316) : const Color(0xff10b981),

                                          ),

                                        ),

                                        const SizedBox(width: 8),

                                        Expanded(

                                          child: Column(

                                            crossAxisAlignment: CrossAxisAlignment.start,

                                            mainAxisSize: MainAxisSize.min,

                                            children: [

                                              Text(

                                                hasOpenVisit

                                                    ? (completedVisits > 0 ? '$completedVisits + 1 open' : '1 Active')

                                                    : '$completedVisits',

                                                style: TextStyle(

                                                  fontSize: 14,

                                                  fontWeight: FontWeight.w800,

                                                  color: hasOpenVisit ? const Color(0xfff97316) : textPrimary,

                                                ),

                                                maxLines: 1,

                                                overflow: TextOverflow.ellipsis,

                                              ),

                                              Text(

                                                hasOpenVisit ? 'In progress' : 'Visits done',

                                                style: TextStyle(

                                                  fontSize: 10.5,

                                                  fontWeight: FontWeight.w500,

                                                  color: textSecondary,

                                                ),

                                              ),

                                            ],

                                          ),

                                        ),

                                      ],

                                    ),

                                  ),

                                  Container(width: 1, height: 26, color: borderColor, margin: const EdgeInsets.symmetric(horizontal: 4)),

                                  // 3. Stops

                                  Expanded(

                                    child: Row(

                                      children: [

                                        Container(

                                          padding: const EdgeInsets.all(7),

                                          decoration: BoxDecoration(

                                            color: const Color(0xff64748b).withValues(alpha: _darkMode ? 0.25 : 0.1),

                                            borderRadius: BorderRadius.circular(10),

                                          ),

                                          child: const Icon(

                                            Icons.place_outlined,

                                            size: 18,

                                            color: Color(0xff64748b),

                                          ),

                                        ),

                                        const SizedBox(width: 8),

                                        Expanded(

                                          child: Column(

                                            crossAxisAlignment: CrossAxisAlignment.start,

                                            mainAxisSize: MainAxisSize.min,

                                            children: [

                                              Text(

                                                '${stops.length}',

                                                style: TextStyle(

                                                  fontSize: 14,

                                                  fontWeight: FontWeight.w800,

                                                  color: textPrimary,

                                                ),

                                              ),

                                              Text(

                                                'Stops',

                                                style: TextStyle(

                                                  fontSize: 10.5,

                                                  fontWeight: FontWeight.w500,

                                                  color: textSecondary,

                                                ),

                                              ),

                                            ],

                                          ),

                                        ),

                                      ],

                                    ),

                                  ),

                                ],

                              ),

                            );

                          },

                        ),



                        const SizedBox(height: 12),



                        // Status Bar (You are here / Last known location)

                        Container(

                          key: const ValueKey('location-status'),

                          padding: const EdgeInsets.symmetric(

                            horizontal: 14,

                            vertical: 10,

                          ),

                          decoration: BoxDecoration(

                            color: _current

                                ? (_darkMode

                                      ? const Color(0xff122b3a)

                                      : const Color(0xffe8f0fe))

                                : (_darkMode

                                      ? const Color(0xff2a2517)

                                      : const Color(0xfffff8e1)),

                            borderRadius: BorderRadius.circular(12),

                            border: Border.all(

                              color: _current

                                  ? const Color(

                                      0xff26c6da,

                                    ).withValues(alpha: 0.4)

                                  : const Color(

                                      0xfff59e0b,

                                    ).withValues(alpha: 0.4),

                            ),

                          ),

                          child: Row(

                            children: [

                              Icon(

                                _position != null

                                    ? Icons.person_pin_circle_rounded

                                    : (_today && (!widget.controller.onDuty || !events.any((ev) => '${ev['type']}' == 'PunchIn'))

                                        ? Icons.alarm_off_rounded

                                        : Icons.person_pin_circle_rounded),

                                color: _current

                                    ? const Color(0xff26c6da)

                                    : const Color(0xfff59e0b),

                                size: 22,

                              ),

                              const SizedBox(width: 10),

                              Expanded(

                                child: Column(

                                  crossAxisAlignment: CrossAxisAlignment.start,

                                  children: [

                                    Text(

                                      _position == null

                                          ? (_today

                                              ? (widget.controller.onDuty && events.any((ev) => '${ev['type']}' == 'PunchIn')

                                                  ? 'Acquiring GPS location...'

                                                  : 'Work Not Started (Punch In Required)')

                                              : 'Summary for this date')

                                          : _positionLabel,

                                      style: TextStyle(

                                        fontWeight: FontWeight.w700,

                                        fontSize: 14,

                                        color: textPrimary,

                                      ),

                                    ),

                                    if (_position != null)

                                      Text(

                                        '${DateTime.tryParse("${_position!['capturedAtUtc']}")?.add(businessOffset).toString().split('.').first ?? "Unknown time"} | +/-${toNum(_position!['accuracyMeters'])?.round() ?? "?"} m',

                                        style: TextStyle(

                                          fontSize: 11,

                                          color: textSecondary,

                                        ),

                                      )

                                    else if (_today && !widget.controller.onDuty)

                                      Text(

                                        'Please punch in from Home screen to start tracking',

                                        style: TextStyle(

                                          fontSize: 11,

                                          color: textSecondary,

                                        ),

                                      ),

                                  ],

                                ),

                              ),

                              if (_today && widget.controller.onDuty)

                                IconButton(

                                  tooltip: 'Refresh GPS',

                                  onPressed: _requestingFix

                                      ? null

                                      : _refreshPosition,

                                  icon: Icon(

                                    Icons.refresh,

                                    color: textSecondary,

                                    size: 20,

                                  ),

                                )

                              else if (_today && !widget.controller.onDuty)

                                TextButton(

                                  onPressed: () => Navigator.pop(context),

                                  child: const Text(

                                    'Punch In',

                                    style: TextStyle(

                                      fontWeight: FontWeight.bold,

                                      color: Color(0xfff97316),

                                    ),

                                  ),

                                ),

                            ],

                          ),

                        ),



                        const SizedBox(height: 20),



                        // Connected Timeline Stream Header

                        Row(

                          children: [

                            Text(

                              'Timeline',

                              style: TextStyle(

                                fontSize: 18,

                                fontWeight: FontWeight.w700,

                                color: textPrimary,

                              ),

                            ),

                            const SizedBox(width: 8),

                            Container(

                              padding: const EdgeInsets.symmetric(

                                horizontal: 8,

                                vertical: 3,

                              ),

                              decoration: BoxDecoration(

                                color: const Color(

                                  0xff26c6da,

                                ).withValues(alpha: 0.15),

                                borderRadius: BorderRadius.circular(10),

                              ),

                              child: Text(

                                '${timelineItems.where((t) => t.type != _TimelineType.travel && t.type != _TimelineType.gap).length} steps',

                                style: const TextStyle(

                                  color: Color(0xff26c6da),

                                  fontSize: 11.5,

                                  fontWeight: FontWeight.w700,

                                ),

                              ),

                            ),

                            const Spacer(),

                            // 2-Mode Segmented Selector: [ View Mode ] [ Live Mode ]
                            if (_today)

                              Container(

                                decoration: BoxDecoration(

                                  color: _darkMode ? const Color(0xff181a1b) : const Color(0xffe2e8f0),

                                  borderRadius: BorderRadius.circular(20),

                                  border: Border.all(

                                    color: _darkMode ? const Color(0xff2d3135) : const Color(0xffcbd5e1),

                                    width: 1,

                                  ),

                                ),

                                padding: const EdgeInsets.all(2),

                                child: Row(

                                  mainAxisSize: MainAxisSize.min,

                                  children: [

                                    InkWell(

                                      onTap: () {

                                        if (_isLiveMode) {

                                          setState(() {

                                            _isLiveMode = false;

                                            _snapshotTime = DateTime.now();

                                          });

                                        }

                                      },

                                      borderRadius: BorderRadius.circular(18),

                                      child: Container(

                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),

                                        decoration: BoxDecoration(

                                          color: !_isLiveMode

                                              ? (_darkMode ? const Color(0xff334155) : Colors.white)

                                              : Colors.transparent,

                                          borderRadius: BorderRadius.circular(18),

                                          boxShadow: !_isLiveMode

                                              ? [

                                                  BoxShadow(

                                                    color: Colors.black.withValues(alpha: 0.1),

                                                    blurRadius: 4,

                                                    offset: const Offset(0, 1),

                                                  )

                                                ]

                                              : null,

                                        ),

                                        child: Row(

                                          mainAxisSize: MainAxisSize.min,

                                          children: [

                                            Icon(

                                              Icons.visibility_outlined,

                                              size: 13,

                                              color: !_isLiveMode ? const Color(0xff0284c7) : textSecondary,

                                            ),

                                            const SizedBox(width: 4),

                                            Text(

                                              'View',

                                              style: TextStyle(

                                                fontSize: 11.5,

                                                fontWeight: FontWeight.w700,

                                                color: !_isLiveMode

                                                    ? (_darkMode ? Colors.white : const Color(0xff0f172a))

                                                    : textSecondary,

                                              ),

                                            ),

                                          ],

                                        ),

                                      ),

                                    ),

                                    InkWell(

                                      onTap: () {

                                        if (!_isLiveMode) {

                                          setState(() {

                                            _isLiveMode = true;

                                          });

                                          load(silent: true);

                                        }

                                      },

                                      borderRadius: BorderRadius.circular(18),

                                      child: Container(

                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),

                                        decoration: BoxDecoration(

                                          color: _isLiveMode

                                              ? const Color(0xff10b981).withValues(alpha: 0.2)

                                              : Colors.transparent,

                                          borderRadius: BorderRadius.circular(18),

                                          border: _isLiveMode

                                              ? Border.all(color: const Color(0xff10b981), width: 1)

                                              : null,

                                        ),

                                        child: Row(

                                          mainAxisSize: MainAxisSize.min,

                                          children: [

                                            Container(

                                              width: 6,

                                              height: 6,

                                              decoration: const BoxDecoration(

                                                shape: BoxShape.circle,

                                                color: Color(0xff10b981),

                                              ),

                                            ),

                                            const SizedBox(width: 4),

                                            Text(

                                              'Live',

                                              style: TextStyle(

                                                fontSize: 11.5,

                                                fontWeight: FontWeight.w700,

                                                color: _isLiveMode ? const Color(0xff10b981) : textSecondary,

                                              ),

                                            ),

                                          ],

                                        ),

                                      ),

                                    ),

                                  ],

                                ),

                              ),

                          ],

                        ),

                        const SizedBox(height: 14),



                        if (error != null)

                          Padding(

                            padding: const EdgeInsets.only(bottom: 12),

                            child: Text(

                              error!,

                              style: const TextStyle(color: Color(0xff9a6700)),

                            ),

                          ),

                        if (timelineItems.isEmpty && loading)

                          Container(

                            padding: const EdgeInsets.symmetric(

                              horizontal: 12,

                              vertical: 18,

                            ),

                            decoration: BoxDecoration(

                              color: cardColor,

                              borderRadius: BorderRadius.circular(16),

                              border: Border.all(color: borderColor),

                            ),

                            child: Center(

                              child: Row(

                                mainAxisSize: MainAxisSize.min,

                                children: [

                                  const SizedBox(

                                    width: 14,

                                    height: 14,

                                    child: CircularProgressIndicator(

                                      strokeWidth: 2,

                                      color: Color(0xff26c6da),

                                    ),

                                  ),

                                  const SizedBox(width: 8),

                                  Flexible(

                                    child: Text(

                                      'Loading timeline...',

                                      maxLines: 1,

                                      overflow: TextOverflow.ellipsis,

                                      style: TextStyle(

                                        color: textSecondary,

                                        fontSize: 13,

                                      ),

                                    ),

                                  ),

                                ],

                              ),

                            ),

                          ),



                        if (timelineItems.isEmpty && !loading)

                          Container(

                            padding: const EdgeInsets.all(24),

                            decoration: BoxDecoration(

                              color: cardColor,

                              borderRadius: BorderRadius.circular(16),

                              border: Border.all(color: borderColor),

                            ),

                            child: Center(

                              child: Text(

                                'No activity recorded for this date.',

                                style: TextStyle(color: textSecondary),

                              ),

                            ),

                          ),



                        // Connected Timeline Items

                        for (int i = 0; i < timelineItems.length; i++)

                          _buildConnectedTimelineItem(

                            item: timelineItems[i],

                            isFirst: i == 0,

                            isLast: i == timelineItems.length - 1,

                          ),

                      ],

                    )

                  : _selectedTab == 1

                  ? _buildPlacesTab(

                      visits,

                      stops,

                      textPrimary,

                      textSecondary,

                      cardColor,

                      borderColor,

                    )

                  : _buildInsightsTab(

                      totalMeters: totalDistanceMeters,

                      segments: segments,

                      transitMin: transitMinutes,

                      stopMin: totalStopMinutes,

                      visits: visits,

                      stops: stops,

                      timelineItems: timelineItems,

                      allCleanPoints: allCleanPoints,

                      allRawPoints: allRawPoints,

                      textPrimary: textPrimary,

                      textSecondary: textSecondary,

                      cardColor: cardColor,

                      borderColor: borderColor,

                    )),

      ),

    );

  }



  Widget _buildTopTabItem(

    int index,

    String title,

    IconData icon,

    Color textPrimary,

    Color textSecondary,

  ) {

    final isSelected = _selectedTab == index;

    return Expanded(

      child: InkWell(

        onTap: () => setState(() => _selectedTab = index),

        child: Container(

          padding: const EdgeInsets.symmetric(vertical: 12),

          decoration: BoxDecoration(

            border: Border(

              bottom: BorderSide(

                color: isSelected

                    ? const Color(0xff26c6da)

                    : Colors.transparent,

                width: 3,

              ),

            ),

          ),

          child: Row(

            mainAxisAlignment: MainAxisAlignment.center,

            mainAxisSize: MainAxisSize.min,

            children: [

              Icon(

                icon,

                size: 16,

                color: isSelected ? const Color(0xff26c6da) : textSecondary,

              ),

              const SizedBox(width: 6),

              Flexible(

                child: Text(

                  title,

                  maxLines: 1,

                  overflow: TextOverflow.ellipsis,

                  style: TextStyle(

                    fontSize: 14,

                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,

                    color: isSelected ? const Color(0xff26c6da) : textSecondary,

                  ),

                ),

              ),

            ],

          ),

        ),

      ),

    );

  }



  Widget _buildPlacesTab(

    List<Json> visits,

    List<Json> stops,

    Color textPrimary,

    Color textSecondary,

    Color cardColor,

    Color borderColor,

  ) {

    return ListView(

      padding: const EdgeInsets.all(16),

      children: [

        Builder(

          builder: (context) {

            final completedCount = visits.where((v) => v['checkOutUtc'] != null || v['out_time'] != null).length;

            final openCount = visits.length - completedCount;

            return Text(

              openCount > 0 ? '$completedCount visited • $openCount in progress' : '$completedCount places visited',

              style: TextStyle(

                fontSize: 18,

                fontWeight: FontWeight.w700,

                color: textPrimary,

              ),

            );

          },

        ),

        const SizedBox(height: 14),

        if (visits.isEmpty && stops.isEmpty)

          Container(

            padding: const EdgeInsets.all(24),

            decoration: BoxDecoration(

              color: cardColor,

              borderRadius: BorderRadius.circular(16),

              border: Border.all(color: borderColor),

            ),

            child: Center(

              child: Text(

                'No visits or halts recorded on this date.',

                style: TextStyle(color: textSecondary),

              ),

            ),

          ),

        for (final v in visits) ...[

          Container(

            margin: const EdgeInsets.only(bottom: 12),

            padding: const EdgeInsets.all(16),

            decoration: BoxDecoration(

              color: cardColor,

              borderRadius: BorderRadius.circular(16),

              border: Border.all(color: borderColor),

            ),

            child: Row(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Container(

                  width: 44,

                  height: 44,

                  decoration: BoxDecoration(

                    color: const Color(0xffab47bc).withValues(alpha: 0.15),

                    shape: BoxShape.circle,

                  ),

                  child: const Icon(

                    Icons.storefront_rounded,

                    color: Color(0xffab47bc),

                    size: 22,

                  ),

                ),

                const SizedBox(width: 14),

                Expanded(

                  child: Column(

                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [

                      Text(

                        '${v['shopName'] ?? v['clientName'] ?? 'Open visit'}',

                        style: TextStyle(

                          fontSize: 16,

                          fontWeight: FontWeight.w700,

                          color: textPrimary,

                        ),

                      ),

                      const SizedBox(height: 4),

                      Text(

                        '${v['address'] ?? v['placeName'] ?? 'Address recorded via GPS'}',

                        style: TextStyle(fontSize: 13, color: textSecondary),

                      ),

                      const SizedBox(height: 8),

                      Row(

                        children: [

                          Text(

                            '${routeEventTime(v['checkInUtc'] ?? v['in_time'])} – ${v['checkOutUtc'] != null ? routeEventTime(v['checkOutUtc']) : (v['out_time'] != null ? routeEventTime(v['out_time']) : 'In progress')}',

                            style: const TextStyle(

                              fontSize: 12,

                              fontWeight: FontWeight.w600,

                              color: Color(0xff26c6da),

                            ),

                          ),

                        ],

                      ),

                    ],

                  ),

                ),

                IconButton(

                  icon: Icon(Icons.chevron_right_rounded, color: textSecondary),

                  onPressed: () => _showVisitDetailsModal(context, v),

                ),

              ],

            ),

          ),

        ],

        if (stops.isNotEmpty) ...[

          const SizedBox(height: 12),

          Text(

            '${stops.length} stationary halts',

            style: TextStyle(

              fontSize: 16,

              fontWeight: FontWeight.w700,

              color: textPrimary,

            ),

          ),

          const SizedBox(height: 10),

          for (int i = 0; i < stops.length; i++) ...[

            Builder(

              builder: (context) {

                final s = stops[i];

                final pt = safeLatLng(s['latitude'], s['longitude']);

                final cached = pt != null ? TrackyuAddressCache.get(pt.latitude, pt.longitude) : null;

                final serverAddr =

                    s['address']?.toString() ??

                    s['placeName']?.toString() ??

                    s['locationName']?.toString();

                final resolvedAddr =

                    (serverAddr != null && serverAddr.trim().isNotEmpty && serverAddr != 'Stop location')

                    ? serverAddr.trim()

                    : (cached != null && cached != 'Resolving address...'

                          ? cached

                          : null);

                // If no address yet, trigger background reverse-geocode and refresh

                final hasAddress = resolvedAddr != null && resolvedAddr.trim().isNotEmpty;

                if (!hasAddress && pt != null && !widget.controller.offline) {

                  TrackyuAddressCache.reverseGeocode(pt.latitude, pt.longitude).then((addr) {

                    if (mounted && addr != null) setState(() {});

                  });

                }

                final rawStart = DateTime.tryParse('${s['startUtc']}');

                final rawEnd = DateTime.tryParse('${s['endUtc']}');

                final start = rawStart != null ? toIST(rawStart) : null;

                final end = rawEnd != null ? toIST(rawEnd) : null;

                final duration = (start != null && end != null)

                    ? end.difference(start)

                    : Duration.zero;

                final durMin =

                    (toNum(s['stoppedSeconds'])?.toInt() ??

                        duration.inSeconds) ~/

                    60;

                final timeStr = (start != null && end != null)

                    ? '${_formatTime(start)} – ${_formatTime(end)}'

                    : (start != null ? _formatTime(start) : '');

                return Container(

                  margin: const EdgeInsets.only(bottom: 12),

                  padding: const EdgeInsets.all(16),

                  decoration: BoxDecoration(

                    color: cardColor,

                    borderRadius: BorderRadius.circular(16),

                    border: Border.all(color: borderColor),

                  ),

                  child: Row(

                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [

                      Container(

                        width: 44,

                        height: 44,

                        decoration: BoxDecoration(

                          color: const Color(

                            0xff475569,

                          ).withValues(alpha: 0.12),

                          shape: BoxShape.circle,

                        ),

                        child: const Icon(

                          Icons.pause_circle_filled_rounded,

                          color: Color(0xff475569),

                          size: 22,

                        ),

                      ),

                      const SizedBox(width: 14),

                      Expanded(

                        child: Column(

                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [

                            Text(

                              resolvedAddr ?? 'Halt ${i + 1}',

                              style: TextStyle(

                                fontSize: 15,

                                fontWeight: FontWeight.w700,

                                color: textPrimary,

                              ),

                            ),

                            const SizedBox(height: 4),

                            Text(

                              (resolvedAddr != null && resolvedAddr.trim().isNotEmpty) ? 'Halt ${i + 1} • $timeStr | $durMin min stay' : '$timeStr • Stay duration: $durMin min',

                              style: TextStyle(

                                fontSize: 13,

                                color: textSecondary,

                              ),

                            ),

                          ],

                        ),

                      ),

                    ],

                  ),

                );

              },

            ),

          ],

        ],

      ],

    );

  }



  Widget _buildInsightsTab({

    required double totalMeters,

    required List<List<Json>> segments,

    required int transitMin,

    required int stopMin,

    required List<Json> visits,

    required List<Json> stops,

    required List<_TimelineEntry> timelineItems,

    required List<LatLng> allCleanPoints,

    required List<Json> allRawPoints,

    required Color textPrimary,

    required Color textSecondary,

    required Color cardColor,

    required Color borderColor,

  }) {

    final distStr = totalMeters >= 1000

        ? '${(totalMeters / 1000).toStringAsFixed(1)} km'

        : '${totalMeters.round()} m';

    final completedCount = visits

        .where((v) => v['checkOutUtc'] != null || v['out_time'] != null)

        .length;

    final openCount = visits.length - completedCount;



    return ListView(

      padding: const EdgeInsets.all(16),

      children: [

        Row(

          mainAxisAlignment: MainAxisAlignment.spaceBetween,

          children: [

            Text(

              'Day Insights',

              style: TextStyle(

                fontSize: 18,

                fontWeight: FontWeight.w700,

                color: textPrimary,

              ),

            ),

            Container(

              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),

              decoration: BoxDecoration(

                color: textSecondary.withValues(alpha: 0.12),

                borderRadius: BorderRadius.circular(12),

              ),

              child: Row(

                mainAxisSize: MainAxisSize.min,

                children: [

                  Icon(Icons.touch_app_rounded, size: 13, color: textSecondary),

                  const SizedBox(width: 4),

                  Text(

                    'Tap tile for details',

                    style: TextStyle(

                      fontSize: 11,

                      fontWeight: FontWeight.w600,

                      color: textSecondary,

                    ),

                  ),

                ],

              ),

            ),

          ],

        ),

        const SizedBox(height: 16),

        Row(

          children: [

            Expanded(

              child: _insightCard(

                title: 'Distance',

                value: distStr,

                icon: Icons.straighten_rounded,

                color: const Color(0xff26c6da),

                cardColor: cardColor,

                borderColor: borderColor,

                textPrimary: textPrimary,

                textSecondary: textSecondary,

                isSelected: _selectedInsight == 0,

                onTap: () => setState(() => _selectedInsight = 0),

              ),

            ),

            const SizedBox(width: 12),

            Expanded(

              child: _insightCard(

                title: 'In Transit',

                value: '$transitMin min',

                icon: Icons.two_wheeler_rounded,

                color: const Color(0xff42a5f5),

                cardColor: cardColor,

                borderColor: borderColor,

                textPrimary: textPrimary,

                textSecondary: textSecondary,

                isSelected: _selectedInsight == 1,

                onTap: () => setState(() => _selectedInsight = 1),

              ),

            ),

          ],

        ),

        const SizedBox(height: 12),

        Row(

          children: [

            Expanded(

              child: _insightCard(

                title: 'Stay Duration',

                value: '$stopMin min',

                icon: Icons.pause_circle_outline_rounded,

                color: const Color(0xffff8a65),

                cardColor: cardColor,

                borderColor: borderColor,

                textPrimary: textPrimary,

                textSecondary: textSecondary,

                isSelected: _selectedInsight == 2,

                onTap: () => setState(() => _selectedInsight = 2),

              ),

            ),

            const SizedBox(width: 12),

            Expanded(

              child: _insightCard(

                title: 'Completed Visits',

                value: openCount > 0

                    ? '$completedCount (+$openCount open)'

                    : '$completedCount',

                icon: Icons.check_circle_outline_rounded,

                color: const Color(0xffab47bc),

                cardColor: cardColor,

                borderColor: borderColor,

                textPrimary: textPrimary,

                textSecondary: textSecondary,

                isSelected: _selectedInsight == 3,

                onTap: () => setState(() => _selectedInsight = 3),

              ),

            ),

          ],

        ),

        const SizedBox(height: 22),

        _buildInsightDetailsSection(

          selectedInsight: _selectedInsight,

          totalMeters: totalMeters,

          segments: segments,

          distStr: distStr,

          transitMin: transitMin,

          stopMin: stopMin,

          visits: visits,

          stops: stops,

          timelineItems: timelineItems,

          allCleanPoints: allCleanPoints,

          allRawPoints: allRawPoints,

          textPrimary: textPrimary,

          textSecondary: textSecondary,

          cardColor: cardColor,

          borderColor: borderColor,

        ),

      ],

    );

  }



  Widget _insightCard({

    required String title,

    required String value,

    required IconData icon,

    required Color color,

    required Color cardColor,

    required Color borderColor,

    required Color textPrimary,

    required Color textSecondary,

    required bool isSelected,

    required VoidCallback onTap,

  }) {

    return Material(

      color: Colors.transparent,

      child: InkWell(

        onTap: onTap,

        borderRadius: BorderRadius.circular(16),

        child: Container(

          padding: const EdgeInsets.all(14),

          decoration: BoxDecoration(

            color: isSelected ? color.withValues(alpha: 0.12) : cardColor,

            borderRadius: BorderRadius.circular(16),

            border: Border.all(

              color: isSelected ? color : borderColor,

              width: isSelected ? 2.0 : 1.0,

            ),

          ),

          child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              Row(

                mainAxisAlignment: MainAxisAlignment.spaceBetween,

                children: [

                  Icon(icon, color: color, size: 24),

                  if (isSelected)

                    Container(

                      padding: const EdgeInsets.symmetric(

                        horizontal: 6,

                        vertical: 2,

                      ),

                      decoration: BoxDecoration(

                        color: color,

                        borderRadius: BorderRadius.circular(8),

                      ),

                      child: const Text(

                        'Details ▼',

                        style: TextStyle(

                          color: Colors.white,

                          fontSize: 9.5,

                          fontWeight: FontWeight.w700,

                        ),

                      ),

                    ),

                ],

              ),

              const SizedBox(height: 10),

              Text(

                value,

                maxLines: 1,

                overflow: TextOverflow.ellipsis,

                style: TextStyle(

                  fontSize: 17,

                  fontWeight: FontWeight.w700,

                  color: isSelected ? color : textPrimary,

                ),

              ),

              const SizedBox(height: 4),

              Row(

                children: [

                  Expanded(

                    child: Text(

                      title,

                      maxLines: 1,

                      overflow: TextOverflow.ellipsis,

                      style: TextStyle(

                        fontSize: 12,

                        color: isSelected ? textPrimary : textSecondary,

                        fontWeight:

                            isSelected ? FontWeight.w600 : FontWeight.normal,

                      ),

                    ),

                  ),

                  Icon(

                    Icons.arrow_drop_down,

                    size: 16,

                    color: isSelected

                        ? color

                        : textSecondary.withValues(alpha: 0.5),

                  ),

                ],

              ),

            ],

          ),

        ),

      ),

    );

  }



  Widget _buildInsightDetailsSection({

    required int selectedInsight,

    required double totalMeters,

    required List<List<Json>> segments,

    required String distStr,

    required int transitMin,

    required int stopMin,

    required List<Json> visits,

    required List<Json> stops,

    required List<_TimelineEntry> timelineItems,

    required List<LatLng> allCleanPoints,

    required List<Json> allRawPoints,

    required Color textPrimary,

    required Color textSecondary,

    required Color cardColor,

    required Color borderColor,

  }) {

    switch (selectedInsight) {

      case 0:

        return _buildDistanceDetails(

          totalMeters: totalMeters,

          segments: segments,

          distStr: distStr,

          allCleanPoints: allCleanPoints,

          allRawPoints: allRawPoints,

          timelineItems: timelineItems,

          textPrimary: textPrimary,

          textSecondary: textSecondary,

          cardColor: cardColor,

          borderColor: borderColor,

        );

      case 1:

        return _buildTransitDetails(

          transitMin: transitMin,

          timelineItems: timelineItems,

          textPrimary: textPrimary,

          textSecondary: textSecondary,

          cardColor: cardColor,

          borderColor: borderColor,

        );

      case 2:

        return _buildStayDetails(

          stopMin: stopMin,

          stops: stops,

          textPrimary: textPrimary,

          textSecondary: textSecondary,

          cardColor: cardColor,

          borderColor: borderColor,

        );

      case 3:

      default:

        return _buildVisitsDetails(

          visits: visits,

          textPrimary: textPrimary,

          textSecondary: textSecondary,

          cardColor: cardColor,

          borderColor: borderColor,

        );

    }

  }



  Widget _buildSectionHeader({

    required IconData icon,

    required Color color,

    required String title,

    required String subtitle,

    required Color textPrimary,

    required Color textSecondary,

  }) {

    return Container(

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(

        color: color.withValues(alpha: 0.12),

        borderRadius: BorderRadius.circular(14),

        border: Border.all(color: color.withValues(alpha: 0.3)),

      ),

      child: Row(

        children: [

          Container(

            padding: const EdgeInsets.all(8),

            decoration: BoxDecoration(

              color: color.withValues(alpha: 0.2),

              shape: BoxShape.circle,

            ),

            child: Icon(icon, color: color, size: 20),

          ),

          const SizedBox(width: 12),

          Expanded(

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Text(

                  title,

                  style: TextStyle(

                    fontSize: 15,

                    fontWeight: FontWeight.w700,

                    color: textPrimary,

                  ),

                ),

                const SizedBox(height: 2),

                Text(

                  subtitle,

                  style: TextStyle(fontSize: 12, color: textSecondary),

                ),

              ],

            ),

          ),

        ],

      ),

    );

  }



  Widget _metricBox({

    required String label,

    required String value,

    required String sub,

    required Color color,

    required Color cardColor,

    required Color borderColor,

    required Color textPrimary,

    required Color textSecondary,

  }) {

    return Container(

      padding: const EdgeInsets.all(12),

      decoration: BoxDecoration(

        color: cardColor,

        borderRadius: BorderRadius.circular(12),

        border: Border.all(color: borderColor),

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Text(label, style: TextStyle(fontSize: 11, color: textSecondary)),

          const SizedBox(height: 4),

          Text(

            value,

            style: TextStyle(

              fontSize: 16,

              fontWeight: FontWeight.w700,

              color: color,

            ),

          ),

          const SizedBox(height: 2),

          Text(

            sub,

            style: TextStyle(

              fontSize: 10,

              color: textSecondary.withValues(alpha: 0.8),

            ),

          ),

        ],

      ),

    );

  }



  List<_DistanceStep> _extractDistanceSteps(

    List<List<Json>> segments,

    List<Json> fallbackPoints,

  ) {

    const distCalc = Distance();

    final steps = <_DistanceStep>[];

    final segList = segments.isNotEmpty ? segments : [fallbackPoints];



    for (final segment in segList) {

      if (segment.length < 2) continue;



      LatLng? anchor = routeCoordinate(segment.first);

      DateTime? anchorTime = instant(segment.first['capturedAtUtc']);



      for (var i = 1; i < segment.length; i++) {

        final prev = segment[i - 1];

        final curr = segment[i];

        final currCoord = routeCoordinate(curr);

        final currTime = instant(curr['capturedAtUtc']);



        if (currCoord == null) continue;



        if (!connectedFixes(prev, curr)) {

          anchor = currCoord;

          anchorTime = currTime;

          continue;

        }



        anchor ??= routeCoordinate(prev);

        if (anchor == null) {

          anchor = currCoord;

          anchorTime = currTime;

          continue;

        }



        final moved = distCalc(anchor, currCoord);

        final acc = toNum(curr['accuracyMeters']) ?? 20.0;

        final threshold = (acc > 25.0 ? acc : 25.0).clamp(20.0, 45.0);



        if (moved >= threshold) {

          if (anchorTime != null && currTime != null) {

            final dtSec = currTime.difference(anchorTime).inSeconds.abs();

            if (dtSec > 0 && (moved / dtSec) > 42.0) {

              anchor = currCoord;

              anchorTime = currTime;

              continue;

            }

            final speed = dtSec > 0 ? (moved / dtSec) * 3.6 : 0.0;

            final fromAddr =

                TrackyuAddressCache.get(anchor.latitude, anchor.longitude);

            final toAddr =

                TrackyuAddressCache.get(currCoord.latitude, currCoord.longitude);



            steps.add(_DistanceStep(

              index: steps.length + 1,

              fromTime: anchorTime,

              toTime: currTime,

              fromCoord: anchor,

              toCoord: currCoord,

              fromAddress: fromAddr,

              toAddress: toAddr,

              distanceMeters: moved,

              speedKmh: speed,

            ));

          }

          anchor = currCoord;

          anchorTime = currTime;

        }

      }

    }



    if (steps.isEmpty && fallbackPoints.length >= 2) {

      for (var i = 1; i < fallbackPoints.length; i++) {

        final p1 = fallbackPoints[i - 1];

        final p2 = fallbackPoints[i];

        final c1 = routeCoordinate(p1);

        final c2 = routeCoordinate(p2);

        final t1 = instant(p1['capturedAtUtc']);

        final t2 = instant(p2['capturedAtUtc']);

        if (c1 != null && c2 != null && t1 != null && t2 != null) {

          final m = distCalc(c1, c2);

          if (m >= 10.0) {

            final dtSec = t2.difference(t1).inSeconds.abs();

            final speed = dtSec > 0 ? (m / dtSec) * 3.6 : 0.0;

            steps.add(_DistanceStep(

              index: steps.length + 1,

              fromTime: t1,

              toTime: t2,

              fromCoord: c1,

              toCoord: c2,

              fromAddress: TrackyuAddressCache.get(c1.latitude, c1.longitude),

              toAddress: TrackyuAddressCache.get(c2.latitude, c2.longitude),

              distanceMeters: m,

              speedKmh: speed,

            ));

          }

        }

      }

    }



    return steps;

  }



  Widget _buildStepCard({

    required int index,

    required _DistanceStep step,

    required Color cardColor,

    required Color borderColor,

    required Color textPrimary,

    required Color textSecondary,

    required Color accent,

  }) {

    final distStr = step.distanceMeters >= 1000

        ? '${(step.distanceMeters / 1000).toStringAsFixed(2)} km'

        : '${step.distanceMeters.round()} m';

    final durSec = step.toTime.difference(step.fromTime).inSeconds.abs();

    final durStr =

        durSec >= 60 ? '${durSec ~/ 60}m ${durSec % 60}s' : '${durSec}s';

    final speedStr =

        step.speedKmh > 0 ? '${step.speedKmh.toStringAsFixed(1)} km/h' : null;



    final fromTimeStr = _formatTime(step.fromTime);

    final toTimeStr = _formatTime(step.toTime);



    final fromAddr = step.fromAddress ??

        '${step.fromCoord.latitude.toStringAsFixed(5)}, ${step.fromCoord.longitude.toStringAsFixed(5)}';

    final toAddr = step.toAddress ??

        '${step.toCoord.latitude.toStringAsFixed(5)}, ${step.toCoord.longitude.toStringAsFixed(5)}';



    return Container(

      margin: const EdgeInsets.only(bottom: 10),

      padding: const EdgeInsets.all(12),

      decoration: BoxDecoration(

        color: cardColor,

        borderRadius: BorderRadius.circular(14),

        border: Border.all(color: borderColor),

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Row(

            mainAxisAlignment: MainAxisAlignment.spaceBetween,

            children: [

              Row(

                children: [

                  Container(

                    padding:

                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),

                    decoration: BoxDecoration(

                      color: accent.withValues(alpha: 0.15),

                      borderRadius: BorderRadius.circular(8),

                    ),

                    child: Text(

                      'Point #$index',

                      style: TextStyle(

                        fontSize: 11,

                        fontWeight: FontWeight.w700,

                        color: accent,

                      ),

                    ),

                  ),

                  const SizedBox(width: 8),

                  Text(

                    '$fromTimeStr -> $toTimeStr',

                    style: TextStyle(

                      fontSize: 12,

                      fontWeight: FontWeight.w600,

                      color: textPrimary,

                    ),

                  ),

                ],

              ),

              Container(

                padding:

                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),

                decoration: BoxDecoration(

                  color: accent.withValues(alpha: 0.12),

                  borderRadius: BorderRadius.circular(10),

                  border: Border.all(color: accent.withValues(alpha: 0.3)),

                ),

                child: Text(

                  '+$distStr',

                  style: TextStyle(

                    fontSize: 12.5,

                    fontWeight: FontWeight.w800,

                    color: accent,

                  ),

                ),

              ),

            ],

          ),

          const SizedBox(height: 10),

          Row(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              const Padding(

                padding: EdgeInsets.only(top: 2),

                child: Icon(Icons.circle, size: 8, color: Color(0xff10b981)),

              ),

              const SizedBox(width: 8),

              Expanded(

                child: Text(

                  'From: $fromAddr',

                  style: TextStyle(fontSize: 11.5, color: textSecondary),

                  maxLines: 2,

                  overflow: TextOverflow.ellipsis,

                ),

              ),

            ],

          ),

          const SizedBox(height: 5),

          Row(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              const Padding(

                padding: EdgeInsets.only(top: 2),

                child: Icon(Icons.location_on_rounded,

                    size: 10, color: Color(0xff06b6d4)),

              ),

              const SizedBox(width: 8),

              Expanded(

                child: Text(

                  'To: $toAddr',

                  style: TextStyle(fontSize: 11.5, color: textPrimary),

                  maxLines: 2,

                  overflow: TextOverflow.ellipsis,

                ),

              ),

            ],

          ),

          if (speedStr != null || durSec > 0) ...[

            const SizedBox(height: 6),

            Text(

              'Duration: $durStr${speedStr != null ? '  -  Avg Speed: $speedStr' : ''}',

              style: TextStyle(

                  fontSize: 10.5,

                  color: textSecondary.withValues(alpha: 0.7)),

            ),

          ],

        ],

      ),

    );

  }



  Widget _buildDistanceDetails({

    required double totalMeters,

    required List<List<Json>> segments,

    required String distStr,

    required List<LatLng> allCleanPoints,

    required List<Json> allRawPoints,

    required List<_TimelineEntry> timelineItems,

    required Color textPrimary,

    required Color textSecondary,

    required Color cardColor,

    required Color borderColor,

  }) {

    final steps = _extractDistanceSteps(segments, allRawPoints);

    const accent = Color(0xff26c6da);



    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        _buildSectionHeader(

          icon: Icons.straighten_rounded,

          color: accent,

          title: 'Distance Breakdown ($distStr)',

          subtitle: 'Point-to-point GPS movement steps logged today',

          textPrimary: textPrimary,

          textSecondary: textSecondary,

        ),

        const SizedBox(height: 12),

        Row(

          children: [

            Expanded(

              child: _metricBox(

                label: 'Raw GPS Fixes',

                value: '${allRawPoints.length}',

                sub: 'Continuous logs',

                color: accent,

                cardColor: cardColor,

                borderColor: borderColor,

                textPrimary: textPrimary,

                textSecondary: textSecondary,

              ),

            ),

            const SizedBox(width: 8),

            Expanded(

              child: _metricBox(

                label: 'Movement Steps',

                value: '${steps.length}',

                sub: 'Logged steps',

                color: accent,

                cardColor: cardColor,

                borderColor: borderColor,

                textPrimary: textPrimary,

                textSecondary: textSecondary,

              ),

            ),

            const SizedBox(width: 8),

            Expanded(

              child: _metricBox(

                label: 'Total Distance',

                value: distStr,

                sub: 'Cumulative path',

                color: accent,

                cardColor: cardColor,

                borderColor: borderColor,

                textPrimary: textPrimary,

                textSecondary: textSecondary,

              ),

            ),

          ],

        ),

        const SizedBox(height: 16),

        Text(

          steps.isNotEmpty

              ? 'Movement Steps (${steps.length})'

              : 'Movement Legs Breakdown',

          style: TextStyle(

            fontSize: 14,

            fontWeight: FontWeight.w700,

            color: textPrimary,

          ),

        ),

        const SizedBox(height: 8),

        if (steps.isNotEmpty)

          for (int i = 0; i < steps.length; i++)

            _buildStepCard(

              index: i + 1,

              step: steps[i],

              cardColor: cardColor,

              borderColor: borderColor,

              textPrimary: textPrimary,

              textSecondary: textSecondary,

              accent: accent,

            )

        else

          Container(

            padding: const EdgeInsets.all(16),

            decoration: BoxDecoration(

              color: cardColor,

              borderRadius: BorderRadius.circular(14),

              border: Border.all(color: borderColor),

            ),

            child: Row(

              children: [

                Icon(

                  Icons.info_outline_rounded,

                  color: textSecondary,

                  size: 20,

                ),

                const SizedBox(width: 12),

                Expanded(

                  child: Text(

                    allRawPoints.isNotEmpty

                        ? 'Continuous GPS fixes logged ~$distStr movement around current work location.'

                        : 'No GPS movement recorded for this date yet.',

                    style: TextStyle(fontSize: 13, color: textSecondary),

                  ),

                ),

              ],

            ),

          ),

        const SizedBox(height: 12),

        Container(

          padding: const EdgeInsets.all(12),

          decoration: BoxDecoration(

            color: accent.withValues(alpha: 0.08),

            borderRadius: BorderRadius.circular(12),

            border: Border.all(color: accent.withValues(alpha: 0.3)),

          ),

          child: Row(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              const Icon(Icons.calculate_outlined, color: accent, size: 18),

              const SizedBox(width: 10),

              Expanded(

                child: Text(

                  'Distance is computed using geodesic Haversine formula across successive high-accuracy GPS fixes. Stationary noise (<5m) is automatically filtered out.',

                  style: TextStyle(

                    fontSize: 11.5,

                    color: textSecondary,

                    height: 1.4,

                  ),

                ),

              ),

            ],

          ),

        ),

      ],

    );

  }



  Widget _buildTransitDetails({

    required int transitMin,

    required List<_TimelineEntry> timelineItems,

    required Color textPrimary,

    required Color textSecondary,

    required Color cardColor,

    required Color borderColor,

  }) {

    final travelLegs = timelineItems

        .where((i) => i.type == _TimelineType.travel)

        .toList();

    const accent = Color(0xff42a5f5);



    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        _buildSectionHeader(

          icon: Icons.two_wheeler_rounded,

          color: accent,

          title: 'In Transit Details',

          subtitle: '$transitMin min total travel time on the road',

          textPrimary: textPrimary,

          textSecondary: textSecondary,

        ),

        const SizedBox(height: 14),

        if (travelLegs.isNotEmpty)

          for (int i = 0; i < travelLegs.length; i++)

            _buildLegCard(

              index: i + 1,

              leg: travelLegs[i],

              cardColor: cardColor,

              borderColor: borderColor,

              textPrimary: textPrimary,

              textSecondary: textSecondary,

              accent: accent,

            )

        else

          Container(

            padding: const EdgeInsets.all(18),

            decoration: BoxDecoration(

              color: cardColor,

              borderRadius: BorderRadius.circular(14),

              border: Border.all(color: borderColor),

            ),

            child: Row(

              children: [

                Icon(Icons.two_wheeler_rounded, color: textSecondary, size: 22),

                const SizedBox(width: 12),

                Expanded(

                  child: Text(

                    'No travel trips detected ($transitMin min). When vehicle or walking movement between stops exceeds 5 km/h, transit segments appear here.',

                    style: TextStyle(fontSize: 13, color: textSecondary),

                  ),

                ),

              ],

            ),

          ),

      ],

    );

  }



  Widget _buildLegCard({

    required int index,

    required _TimelineEntry leg,

    required Color cardColor,

    required Color borderColor,

    required Color textPrimary,

    required Color textSecondary,

    required Color accent,

  }) {

    final dist = leg.distanceMeters != null

        ? (leg.distanceMeters! >= 1000

            ? '${(leg.distanceMeters! / 1000).toStringAsFixed(1)} km'

            : '${leg.distanceMeters!.round()} m')

        : 'Moving';

    final dur = leg.end != null

        ? '${leg.end!.difference(leg.at).inMinutes} min'

        : 'In progress';

    final timeStr = leg.end != null

        ? '${_formatTime(leg.at)} - ${_formatTime(leg.end!)}'

        : _formatTime(leg.at);



    return Container(

      margin: const EdgeInsets.only(bottom: 8),

      padding: const EdgeInsets.all(12),

      decoration: BoxDecoration(

        color: cardColor,

        borderRadius: BorderRadius.circular(12),

        border: Border.all(color: borderColor),

      ),

      child: Row(

        children: [

          Container(

            width: 28,

            height: 28,

            decoration: BoxDecoration(

              color: accent.withValues(alpha: 0.15),

              shape: BoxShape.circle,

            ),

            child: Center(

              child: Text(

                '$index',

                style: TextStyle(

                  fontSize: 12,

                  fontWeight: FontWeight.w700,

                  color: accent,

                ),

              ),

            ),

          ),

          const SizedBox(width: 10),

          Expanded(

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Text(

                  leg.title,

                  style: TextStyle(

                    fontSize: 13,

                    fontWeight: FontWeight.w600,

                    color: textPrimary,

                  ),

                ),

                const SizedBox(height: 2),

                Text(

                  '$timeStr  -  $dur',

                  style: TextStyle(fontSize: 11, color: textSecondary),

                ),

              ],

            ),

          ),

          Container(

            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),

            decoration: BoxDecoration(

              color: accent.withValues(alpha: 0.1),

              borderRadius: BorderRadius.circular(8),

            ),

            child: Text(

              dist,

              style: TextStyle(

                fontSize: 12,

                fontWeight: FontWeight.w700,

                color: accent,

              ),

            ),

          ),

        ],

      ),

    );

  }



  Widget _buildStayDetails({

    required int stopMin,

    required List<Json> stops,

    required Color textPrimary,

    required Color textSecondary,

    required Color cardColor,

    required Color borderColor,

  }) {

    const accent = Color(0xffff8a65);



    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        _buildSectionHeader(

          icon: Icons.pause_circle_outline_rounded,

          color: accent,

          title: 'Stay Duration Details',

          subtitle: '$stopMin min stationary on route (excluding client visits)',

          textPrimary: textPrimary,

          textSecondary: textSecondary,

        ),

        const SizedBox(height: 14),

        if (stops.isNotEmpty) ...[

          Text(

            'Stationary Halts (${stops.length})',

            style: TextStyle(

              fontSize: 14,

              fontWeight: FontWeight.w700,

              color: textPrimary,

            ),

          ),

          const SizedBox(height: 8),

          for (int i = 0; i < stops.length; i++)

            _buildStopCard(

              index: i + 1,

              stop: stops[i],

              cardColor: cardColor,

              borderColor: borderColor,

              textPrimary: textPrimary,

              textSecondary: textSecondary,

              accent: accent,

            ),

        ] else

          Container(

            padding: const EdgeInsets.all(18),

            decoration: BoxDecoration(

              color: cardColor,

              borderRadius: BorderRadius.circular(14),

              border: Border.all(color: borderColor),

            ),

            child: Row(

              children: [

                Icon(

                  Icons.pause_circle_outline_rounded,

                  color: textSecondary,

                  size: 22,

                ),

                const SizedBox(width: 12),

                Expanded(

                  child: Text(

                    'No stationary halts on route recorded yet today.',

                    style: TextStyle(fontSize: 13, color: textSecondary),

                  ),

                ),

              ],

            ),

          ),

      ],

    );

  }



  Widget _buildStopCard({

    required int index,

    required Json stop,

    required Color cardColor,

    required Color borderColor,

    required Color textPrimary,

    required Color textSecondary,

    required Color accent,

  }) {

    final start = DateTime.tryParse('${stop['startUtc']}');

    final end = DateTime.tryParse('${stop['endUtc']}');

    final durMin = (toNum(stop['stoppedSeconds'])?.toInt() ??

            (start != null && end != null

                ? end.difference(start).inSeconds

                : 0)) ~/

        60;

    final timeStr = (start != null && end != null)

        ? '${_formatTime(start)} - ${_formatTime(end)}'

        : (start != null ? _formatTime(start) : '');

    final lat = toNum(stop['latitude'])?.toDouble();

    final lng = toNum(stop['longitude'])?.toDouble();

    final addr =

        (lat != null && lng != null) ? TrackyuAddressCache.get(lat, lng) : null;



    return Container(

      margin: const EdgeInsets.only(bottom: 8),

      padding: const EdgeInsets.all(12),

      decoration: BoxDecoration(

        color: cardColor,

        borderRadius: BorderRadius.circular(12),

        border: Border.all(color: borderColor),

      ),

      child: Row(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Container(

            width: 28,

            height: 28,

            decoration: BoxDecoration(

              color: accent.withValues(alpha: 0.15),

              shape: BoxShape.circle,

            ),

            child: Center(

              child: Text(

                '$index',

                style: TextStyle(

                  fontSize: 12,

                  fontWeight: FontWeight.w700,

                  color: accent,

                ),

              ),

            ),

          ),

          const SizedBox(width: 10),

          Expanded(

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Text(

                  addr ??

                      (lat != null && lng != null

                          ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'

                          : 'Halt $index'),

                  style: TextStyle(

                    fontSize: 13,

                    fontWeight: FontWeight.w600,

                    color: textPrimary,

                  ),

                ),

                const SizedBox(height: 2),

                Text(timeStr,

                    style: TextStyle(fontSize: 11, color: textSecondary)),

              ],

            ),

          ),

          Container(

            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),

            decoration: BoxDecoration(

              color: accent.withValues(alpha: 0.1),

              borderRadius: BorderRadius.circular(8),

            ),

            child: Text(

              '$durMin min',

              style: TextStyle(

                fontSize: 12,

                fontWeight: FontWeight.w700,

                color: accent,

              ),

            ),

          ),

        ],

      ),

    );

  }



  Widget _buildVisitsDetails({

    required List<Json> visits,

    required Color textPrimary,

    required Color textSecondary,

    required Color cardColor,

    required Color borderColor,

  }) {

    const accent = Color(0xffab47bc);

    final completed = visits

        .where((v) => v['checkOutUtc'] != null || v['out_time'] != null)

        .toList();



    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        _buildSectionHeader(

          icon: Icons.check_circle_outline_rounded,

          color: accent,

          title: 'Completed Visits Details',

          subtitle:

              '${completed.length} completed of ${visits.length} total visits today',

          textPrimary: textPrimary,

          textSecondary: textSecondary,

        ),

        const SizedBox(height: 14),

        if (visits.isNotEmpty)

          for (final v in visits)

            _buildDetailedVisitCard(

              visit: v,

              cardColor: cardColor,

              borderColor: borderColor,

              textPrimary: textPrimary,

              textSecondary: textSecondary,

            )

        else

          Container(

            padding: const EdgeInsets.all(18),

            decoration: BoxDecoration(

              color: cardColor,

              borderRadius: BorderRadius.circular(14),

              border: Border.all(color: borderColor),

            ),

            child: Row(

              children: [

                Icon(Icons.storefront_outlined,

                    color: textSecondary, size: 22),

                const SizedBox(width: 12),

                Expanded(

                  child: Text(

                    'No client visits logged today. Use "Start Open Visit" on the home screen to record visits with GPS & client photos.',

                    style: TextStyle(fontSize: 13, color: textSecondary),

                  ),

                ),

              ],

            ),

          ),

      ],

    );

  }

  Widget _buildDetailedVisitCard({

    required Json visit,

    required Color cardColor,

    required Color borderColor,

    required Color textPrimary,

    required Color textSecondary,

  }) {

    final isDone = visit['checkOutUtc'] != null || visit['out_time'] != null;

    final inTime =

        DateTime.tryParse('${visit['checkInUtc'] ?? visit['in_time']}');

    final outTime =

        DateTime.tryParse('${visit['checkOutUtc'] ?? visit['out_time']}');

    final shopName =

        '${visit['shopName'] ?? visit['client_name'] ?? 'Open visit'}';

    final note = '${visit['note'] ?? visit['notes'] ?? ''}'.trim();

    final phone = '${visit['clientPhone'] ?? visit['mobile'] ?? ''}'.trim();

    final address = '${visit['inAddress'] ?? visit['address'] ?? ''}'.trim();

    final lat = toNum(visit['inLatitude'] ?? visit['latitude'])?.toDouble();

    final lng = toNum(visit['inLongitude'] ?? visit['longitude'])?.toDouble();

    final stayMin = (inTime != null && outTime != null)

        ? outTime.difference(inTime).inMinutes

        : 0;

    final timeStr = inTime != null

        ? (outTime != null

            ? '${_formatTime(inTime)} – ${_formatTime(outTime)} • ${stayMin > 0 ? '$stayMin min stay' : '< 1 min stay'}'

            : 'In: ${_formatTime(inTime)}')

        : '';



    return Container(

      margin: const EdgeInsets.only(bottom: 10),

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(

        color: cardColor,

        borderRadius: BorderRadius.circular(14),

        border: Border.all(

          color: isDone

              ? const Color(0xff10b981).withValues(alpha: 0.4)

              : const Color(0xfff59e0b).withValues(alpha: 0.4),

        ),

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Row(

            children: [

              Container(

                padding: const EdgeInsets.all(7),

                decoration: BoxDecoration(

                  color: isDone

                      ? const Color(0xff10b981).withValues(alpha: 0.15)

                      : const Color(0xfff59e0b).withValues(alpha: 0.15),

                  shape: BoxShape.circle,

                ),

                child: Icon(

                  Icons.storefront_rounded,

                  size: 18,

                  color: isDone

                      ? const Color(0xff10b981)

                      : const Color(0xfff59e0b),

                ),

              ),

              const SizedBox(width: 10),

              Expanded(

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    Text(

                      shopName,

                      style: TextStyle(

                        fontSize: 15,

                        fontWeight: FontWeight.w700,

                        color: textPrimary,

                      ),

                    ),

                    const SizedBox(height: 2),

                    Text(

                      'Open visit',

                      style: TextStyle(fontSize: 11, color: textSecondary),

                    ),

                  ],

                ),

              ),

              Container(

                padding:

                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),

                decoration: BoxDecoration(

                  color: isDone

                      ? const Color(0xff10b981).withValues(alpha: 0.15)

                      : const Color(0xfff59e0b).withValues(alpha: 0.15),

                  borderRadius: BorderRadius.circular(10),

                ),

                child: Row(

                  mainAxisSize: MainAxisSize.min,

                  children: [

                    Icon(

                      isDone

                          ? Icons.check_circle_rounded

                          : Icons.access_time_rounded,

                      size: 12,

                      color: isDone

                          ? const Color(0xff10b981)

                          : const Color(0xfff59e0b),

                    ),

                    const SizedBox(width: 4),

                    Text(

                      isDone ? 'Completed' : 'In Progress',

                      style: TextStyle(

                        fontSize: 11,

                        fontWeight: FontWeight.w700,

                        color: isDone

                            ? const Color(0xff10b981)

                            : const Color(0xfff59e0b),

                      ),

                    ),

                  ],

                ),

              ),

            ],

          ),

          if (timeStr.isNotEmpty) ...[

            const SizedBox(height: 10),

            Row(

              children: [

                Icon(Icons.access_time_rounded, size: 14, color: textSecondary),

                const SizedBox(width: 6),

                Text(timeStr,

                    style: TextStyle(fontSize: 12, color: textSecondary)),

              ],

            ),

          ],

          if (address.isNotEmpty || (lat != null && lng != null)) ...[

            const SizedBox(height: 6),

            Row(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                const Icon(Icons.location_on_rounded,

                    size: 14, color: Color(0xff38bdf8)),

                const SizedBox(width: 6),

                Expanded(

                  child: Text(

                    address.isNotEmpty

                        ? address

                        : '${lat?.toStringAsFixed(4)}, ${lng?.toStringAsFixed(4)}',

                    style: TextStyle(fontSize: 11.5, color: textSecondary),

                  ),

                ),

              ],

            ),

          ],

          if (phone.isNotEmpty) ...[

            const SizedBox(height: 6),

            Row(

              children: [

                Icon(Icons.phone_outlined, size: 14, color: textSecondary),

                const SizedBox(width: 6),

                Text(phone,

                    style: TextStyle(fontSize: 12, color: textSecondary)),

              ],

            ),

          ],

          if (note.isNotEmpty) ...[

            const SizedBox(height: 6),

            Container(

              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),

              decoration: BoxDecoration(

                color: textSecondary.withValues(alpha: 0.08),

                borderRadius: BorderRadius.circular(8),

              ),

              child: Row(

                children: [

                  Icon(Icons.notes_rounded, size: 13, color: textSecondary),

                  const SizedBox(width: 6),

                  Expanded(

                    child: Text(

                      'Note: $note',

                      style: TextStyle(fontSize: 11.5, color: textPrimary),

                    ),

                  ),

                ],

              ),

            ),

          ],

        ],

      ),

    );

  }



  List<Marker> _buildMapMarkers({

    required List<LatLng> cleanPoints,

    required List<Json> stops,

    required List<Json> visits,

    required List<Json> events,

  }) {

    final markers = <Marker>[];



    if (cleanPoints.isNotEmpty) {

      markers.add(

        Marker(

          point: cleanPoints.first,

          width: 50,

          height: 50,

          child: GestureDetector(

            onTap: () {

              setState(() => selectedNodeId = 'start');

              _focusLocation(cleanPoints.first);

            },

            child: Container(

              padding: const EdgeInsets.all(8),

              decoration: const BoxDecoration(

                color: Color(0xff607d8b),

                shape: BoxShape.circle,

                boxShadow: [

                  BoxShadow(

                    color: Colors.black45,

                    blurRadius: 4,

                    offset: Offset(0, 2),

                  ),

                ],

              ),

              child: const Icon(

                Icons.radio_button_checked_rounded,

                color: Colors.white,

                size: 20,

              ),

            ),

          ),

        ),

      );

    }



    final groupedStops = groupMapLocations([

      for (var i = 0; i < stops.length; i++) {...stops[i], 'mapNumber': i + 1},

    ]);

    for (final group in groupedStops) {

      final s = group.first;

      final i = (toNum(s['mapNumber'])?.toInt() ?? 1) - 1;

      final pt = safeLatLng(s['latitude'], s['longitude']);

      if (pt == null) continue;



      markers.add(

        Marker(

          point: pt,

          width: 50,

          height: 50,

          child: GestureDetector(

            onTap: () {

              setState(() => selectedNodeId = 'stop-$i-${s['startUtc']}');

              _followPosition = false;

              _focusLocation(pt);

            },

            child: Container(

              padding: const EdgeInsets.all(8),

              decoration: const BoxDecoration(

                color: Color(0xff475569), // Slate gray for stationary stop

                shape: BoxShape.circle,

                boxShadow: [

                  BoxShadow(

                    color: Colors.black45,

                    blurRadius: 4,

                    offset: Offset(0, 2),

                  ),

                ],

              ),

              child: const Icon(

                Icons.pause_circle_filled_rounded,

                color: Colors.white,

                size: 20,

              ),

            ),

          ),

        ),

      );

    }



    final groupedVisits = groupMapLocations(visits);

    for (final group in groupedVisits) {

      final v = group.first;

      final pt = safeLatLng(

        v['inLatitude'] ?? v['latitude'],

        v['inLongitude'] ?? v['longitude'],

      );

      if (pt == null) continue;

      final shop = v['shopName']?.toString().trim() ?? 'Visit';



      markers.add(

        Marker(

          point: pt,

          width: 76,

          height: 60,

          child: GestureDetector(

            onTap: () {

              setState(() => selectedNodeId = 'visit-${v['id']}');

              _followPosition = false;

              _focusLocation(pt);

              if (group.length == 1) {

                _showVisitDetailsModal(context, v);

              }

            },

            child: Column(

              children: [

                Container(

                  padding: const EdgeInsets.all(6),

                  decoration: const BoxDecoration(

                    color: Color(0xffab47bc),

                    shape: BoxShape.circle,

                    boxShadow: [

                      BoxShadow(

                        color: Colors.black45,

                        blurRadius: 4,

                        offset: Offset(0, 2),

                      ),

                    ],

                  ),

                  child: const Icon(

                    Icons.storefront_rounded,

                    color: Colors.white,

                    size: 16,

                  ),

                ),

                Container(

                  margin: const EdgeInsets.only(top: 2),

                  padding: const EdgeInsets.symmetric(

                    horizontal: 4,

                    vertical: 1,

                  ),

                  decoration: BoxDecoration(

                    color: _darkMode ? const Color(0xff1e1e1e) : Colors.white,

                    borderRadius: BorderRadius.circular(4),

                    border: Border.all(

                      color: const Color(0xffab47bc),

                      width: 1,

                    ),

                  ),

                  child: Text(

                    shop,

                    maxLines: 1,

                    overflow: TextOverflow.ellipsis,

                    style: const TextStyle(

                      fontSize: 8.5,

                      fontWeight: FontWeight.w700,

                      color: Color(0xffab47bc),

                    ),

                  ),

                ),

              ],

            ),

          ),

        ),

      );

    }



    final lastPt = routeCoordinate(_position);

    if (lastPt != null) {

      final hasPunchOut = events.any((e) => e['type'] == 'PunchOut');

      markers.add(

        Marker(

          key: const ValueKey('user-location-marker'),

          alignment: const Alignment(0, 13 / 24),

          point: lastPt,

          rotate: true,

          width: 180,

          height: 96,

          child: GestureDetector(

            onTap: () {

              setState(() => selectedNodeId = 'end');

              _focusLocation(lastPt);

            },

            child: Column(

              children: [

                Container(

                  padding: const EdgeInsets.all(7),

                  decoration: BoxDecoration(

                    color: hasPunchOut

                        ? const Color(0xffef5350)

                        : (_current

                              ? const Color(0xff0284c7)

                              : const Color(0xfff59e0b)),

                    shape: BoxShape.circle,

                    border: Border.all(color: Colors.white, width: 2.5),

                    boxShadow: const [

                      BoxShadow(

                        color: Colors.black45,

                        blurRadius: 5,

                        offset: Offset(0, 2),

                      ),

                    ],

                  ),

                  child: const Icon(

                    Icons.person_rounded,

                    color: Colors.white,

                    size: 22,

                  ),

                ),

                Container(

                  margin: const EdgeInsets.only(top: 2),

                  padding: const EdgeInsets.symmetric(

                    horizontal: 6,

                    vertical: 2,

                  ),

                  decoration: BoxDecoration(

                    color: _darkMode

                        ? const Color(0xdd1e1e1e)

                        : const Color(0xeeffffff),

                    borderRadius: BorderRadius.circular(8),

                    boxShadow: const [

                      BoxShadow(

                        color: Colors.black26,

                        blurRadius: 3,

                        offset: Offset(0, 1),

                      ),

                    ],

                  ),

                  child: Text(

                    _positionLabel,

                    maxLines: 1,

                    overflow: TextOverflow.ellipsis,

                    style: TextStyle(

                      fontSize: 11,

                      fontWeight: FontWeight.w600,

                      color: _darkMode

                          ? Colors.white70

                          : const Color(0xff334155),

                    ),

                  ),

                ),

              ],

            ),

          ),

        ),

      );

    }



    return markers;

  }



  Widget _buildConnectedTimelineItem({

    required _TimelineEntry item,

    required bool isFirst,

    required bool isLast,

  }) {

    final textPrimary = _darkMode ? Colors.white : const Color(0xff102c4a);

    final textSecondary = _darkMode

        ? const Color(0xff94a3b8)

        : const Color(0xff64748b);

    final cardColor = _darkMode ? const Color(0xff1e1e1e) : Colors.white;

    final borderColor = _darkMode

        ? const Color(0xff2d3135)

        : const Color(0xffe2e8f0);



    // In-Transit / Travel Node

    if (item.type == _TimelineType.travel || item.type == _TimelineType.gap) {

      final distStr = item.distanceMeters != null

          ? (item.distanceMeters! >= 1000

                ? '${(item.distanceMeters! / 1000).toStringAsFixed(1)} km'

                : '${item.distanceMeters!.round()} meters')

          : (item.badge ?? '');

      final durMin = item.end != null

          ? item.end!.difference(item.at).inMinutes

          : 0;

      final timeStr = item.end != null

          ? '${_formatTime(item.at)} – ${_formatTime(item.end!)}'

          : _formatTime(item.at);



      return IntrinsicHeight(

        child: Row(

          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [

            SizedBox(

              width: 48,

              child: Column(

                children: [

                  Expanded(

                    child: Container(

                      width: 2.5,

                      color: _darkMode

                          ? const Color(0xff3e4246)

                          : const Color(0xffcbd5e1),

                    ),

                  ),

                  Container(

                    width: 24,

                    height: 24,

                    decoration: BoxDecoration(

                      color: _darkMode ? const Color(0xff181a1b) : Colors.white,

                      shape: BoxShape.circle,

                      border: Border.all(color: item.color, width: 1.5),

                    ),

                    child: Icon(item.icon, size: 13, color: item.color),

                  ),

                  Expanded(

                    child: Container(

                      width: 2.5,

                      color: _darkMode

                          ? const Color(0xff3e4246)

                          : const Color(0xffcbd5e1),

                    ),

                  ),

                ],

              ),

            ),

            const SizedBox(width: 8),

            Expanded(

              child: Padding(

                padding: const EdgeInsets.symmetric(vertical: 8),

                child: InkWell(

                  borderRadius: BorderRadius.circular(10),

                  onTap: item.coord != null

                      ? () {

                          setState(() => selectedNodeId = item.id);

                          _focusLocation(item.coord!);

                        }

                      : null,

                  child: Container(

                    padding: const EdgeInsets.symmetric(

                      horizontal: 12,

                      vertical: 8,

                    ),

                    decoration: BoxDecoration(

                      color: _darkMode

                          ? const Color(0xff1c1f22)

                          : const Color(0xfff1f5f9),

                      borderRadius: BorderRadius.circular(10),

                      border: Border.all(

                        color: _darkMode

                            ? const Color(0xff2d3135)

                            : const Color(0xffe2e8f0),

                      ),

                    ),

                    child: Column(

                      crossAxisAlignment: CrossAxisAlignment.start,

                      mainAxisSize: MainAxisSize.min,

                      children: [

                        Row(

                          children: [

                            Icon(item.icon, size: 14, color: item.color),

                            const SizedBox(width: 6),

                            Expanded(

                              child: Text(

                                item.type == _TimelineType.travel

                                    ? (distStr.isNotEmpty && durMin > 0

                                          ? 'Travel • $distStr ($durMin min)'

                                          : (distStr.isNotEmpty

                                                ? 'Travel • $distStr'

                                                : (durMin > 0 ? 'Travel • $durMin min' : 'Travel • In Transit')))

                                    : ((item.title.isNotEmpty && item.title != '-' && !item.title.startsWith('•'))

                                          ? item.title

                                          : (durMin > 0 ? 'Movement • $durMin min' : 'GPS Movement')),

                                maxLines: 2,

                                overflow: TextOverflow.ellipsis,

                                style: TextStyle(

                                  fontSize: 12.5,

                                  fontWeight: FontWeight.w700,

                                  color: item.color,

                                ),

                              ),

                            ),

                          ],

                        ),

                        const SizedBox(height: 3),

                        Text(

                          (timeStr.isNotEmpty && timeStr != ' – ' && timeStr != '-')

                              ? (item.subtitle.isNotEmpty && item.subtitle != '-' && !item.subtitle.contains('unknown')

                                  ? '$timeStr • ${item.subtitle}'

                                  : timeStr)

                              : (item.subtitle.isNotEmpty && item.subtitle != '-' ? item.subtitle : 'Recorded route interval'),

                          style: TextStyle(

                            fontSize: 11.5,

                            fontWeight: FontWeight.w600,

                            color: textSecondary,

                          ),

                        ),

                        if (item.coord != null) ...[

                          const SizedBox(height: 4),

                          Row(

                            children: [

                              const Icon(

                                Icons.explore_outlined,

                                size: 12,

                                color: Color(0xff0288d1),

                              ),

                              const SizedBox(width: 4),

                              Expanded(

                                child: Text(

                                  (item.address != null &&

                                          item.address!.isNotEmpty &&

                                          item.address != 'Stop location' &&

                                          item.address != '-' &&

                                          !item.address!.startsWith('('))

                                      ? item.address!

                                      : (item.coord != null

                                          ? (TrackyuAddressCache.get(item.coord!.latitude, item.coord!.longitude) ?? 'In transit • Route recorded')

                                          : 'In transit • Route recorded'),

                                  maxLines: 1,

                                  overflow: TextOverflow.ellipsis,

                                  style: const TextStyle(

                                    fontSize: 11,

                                    fontFamily: 'monospace',

                                    color: Color(0xff0288d1),

                                    fontWeight: FontWeight.w600,

                                  ),

                                ),

                              ),

                            ],

                          ),

                        ],

                      ],

                    ),

                  ),

                ),

              ),

            ),

          ],

        ),

      );

    }



    final isSelected = selectedNodeId == item.id;



    // Place / Stop / Event Nodes

    return IntrinsicHeight(

      child: Row(

        crossAxisAlignment: CrossAxisAlignment.stretch,

        children: [

          // Vertical connected line & circular icon badge

          SizedBox(

            width: 48,

            child: Column(

              children: [

                if (!isFirst)

                  Container(

                    width: 2.5,

                    height: 14,

                    color: _darkMode

                        ? const Color(0xff3e4246)

                        : const Color(0xffcbd5e1),

                  )

                else

                  const SizedBox(height: 14),

                Container(

                  width: 36,

                  height: 36,

                  decoration: BoxDecoration(

                    color: item.color,

                    shape: BoxShape.circle,

                    boxShadow: [

                      BoxShadow(

                        color: item.color.withValues(alpha: 0.35),

                        blurRadius: 6,

                        offset: const Offset(0, 2),

                      ),

                    ],

                  ),

                  child: Icon(item.icon, color: Colors.white, size: 20),

                ),

                Expanded(

                  child: Container(

                    width: isLast ? 0 : 2.5,

                    color: _darkMode

                        ? const Color(0xff3e4246)

                        : const Color(0xffcbd5e1),

                  ),

                ),

              ],

            ),

          ),

          const SizedBox(width: 8),



          // Content Card

          Expanded(

            child: Padding(

              padding: const EdgeInsets.only(bottom: 12),

              child: Material(

                color: isSelected

                    ? (_darkMode

                          ? const Color(0xff1a3344)

                          : const Color(0xffe8f0fe))

                    : cardColor,

                borderRadius: BorderRadius.circular(16),

                child: InkWell(

                  borderRadius: BorderRadius.circular(16),

                  onTap: () {

                    setState(() => selectedNodeId = item.id);

                    if (item.coord != null) {

                      _focusLocation(item.coord!);

                    }

                  },

                  child: Container(

                    padding: const EdgeInsets.all(14),

                    decoration: BoxDecoration(

                      borderRadius: BorderRadius.circular(16),

                      border: Border.all(

                        color: isSelected

                            ? const Color(0xff26c6da)

                            : borderColor,

                        width: isSelected ? 1.5 : 1,

                      ),

                      boxShadow: [

                        BoxShadow(

                          color: Colors.black.withValues(

                            alpha: _darkMode ? 0.2 : 0.03,

                          ),

                          blurRadius: 6,

                          offset: const Offset(0, 2),

                        ),

                      ],

                    ),

                    child: Column(

                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [

                        Text(

                          (item.type == _TimelineType.travel && item.end != null && item.end != item.at)

                              ? '${_formatTime(item.at)} – ${_formatTime(item.end!)}'

                              : _formatTime(item.at),

                          style: TextStyle(

                            fontSize: 12,

                            fontWeight: FontWeight.w700,

                            color: textSecondary,

                          ),

                        ),

                        const SizedBox(height: 2),

                        Row(

                          children: [

                            Expanded(

                              child: Text(

                                item.title,

                                style: TextStyle(

                                  fontSize: 16,

                                  fontWeight: FontWeight.w700,

                                  color: textPrimary,

                                ),

                              ),

                            ),

                            if (item.badge != null)

                              Container(

                                padding: const EdgeInsets.symmetric(

                                  horizontal: 8,

                                  vertical: 3,

                                ),

                                decoration: BoxDecoration(

                                  color: item.color.withValues(alpha: 0.15),

                                  borderRadius: BorderRadius.circular(8),

                                ),

                                child: Text(

                                  item.badge!,

                                  style: TextStyle(

                                    fontSize: 11,

                                    fontWeight: FontWeight.w700,

                                    color: item.color,

                                  ),

                                ),

                              ),

                          ],

                        ),

                        const SizedBox(height: 4),

                        Text(

                          item.subtitle.isNotEmpty &&

                                  item.subtitle != '-' &&

                                  !item.subtitle.startsWith('(') &&

                                  !item.subtitle.startsWith('GPS:')

                              ? item.subtitle

                              : (item.address != null &&

                                      item.address!.isNotEmpty &&

                                      item.address != '-' &&

                                      !item.address!.startsWith('(')

                                  ? item.address!

                                  : (item.coord != null

                                      ? (TrackyuAddressCache.get(item.coord!.latitude, item.coord!.longitude) ?? 'Location recorded')

                                      : 'Activity recorded')),

                          style: TextStyle(fontSize: 13, color: textSecondary),

                        ),

// Clean Google Maps style: no raw coordinate spam or duplicate address

                        if (item.departureText != null) ...[

                          const SizedBox(height: 4),

                          Text(

                            item.departureText!,

                            style: const TextStyle(

                              fontSize: 12,

                              fontWeight: FontWeight.w600,

                              color: Color(0xff26c6da),

                            ),

                          ),

                        ],

                        if (isSelected && item.coord != null) ...[

                          const SizedBox(height: 6),

                          Container(

                            padding: const EdgeInsets.symmetric(

                              horizontal: 8,

                              vertical: 3,

                            ),

                            decoration: BoxDecoration(

                              color: const Color(

                                0xff26c6da,

                              ).withValues(alpha: 0.18),

                              borderRadius: BorderRadius.circular(6),

                            ),

                            child: const Text(

                              'Focused on map',

                              style: TextStyle(

                                fontSize: 11,

                                fontWeight: FontWeight.w600,

                                color: Color(0xff26c6da),

                              ),

                            ),

                          ),

                        ],

                        if (item.type == _TimelineType.visit &&

                            item.raw != null) ...[

                          if (item.raw!['remarks'] != null ||

                              item.raw!['remark'] != null) ...[

                            const SizedBox(height: 6),

                            Text(

                              '${item.raw!['remarks'] ?? item.raw!['remark']}',

                              style: TextStyle(

                                fontSize: 13,

                                color: textSecondary,

                              ),

                              maxLines: 2,

                              overflow: TextOverflow.ellipsis,

                            ),

                          ],

                          const SizedBox(height: 8),

                          InkWell(

                            onTap: () =>

                                _showVisitDetailsModal(context, item.raw!),

                            child: const Text(

                              'Tap for full visit details',

                              style: TextStyle(

                                fontSize: 12,

                                fontWeight: FontWeight.w600,

                                color: Color(0xffab47bc),

                                decoration: TextDecoration.underline,

                              ),

                            ),

                          ),

                        ],

                      ],

                    ),

                  ),

                ),

              ),

            ),

          ),

        ],

      ),

    );

  }

}



String _formatTime(DateTime dt) {

  final local = toIST(dt);

  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;

  final minute = local.minute.toString().padLeft(2, '0');

  final ampm = local.hour < 12 ? 'AM' : 'PM';

  return '$hour:$minute $ampm';

}



String routeEventTitle(Json event) {

  switch (event['type']) {

    case 'PunchIn':

      return 'Punch-in';

    case 'PunchOut':

      return 'Punch-out';

    case 'Login':

      return 'Signed in';

    default:

      return '${event['title'] ?? 'Activity'}'.replaceAll(

        RegExp(r'\bduty\b', caseSensitive: false),

        'Attendance',

      );

  }

}



String routeEventTime(dynamic value) {

  if (value == null) return 'Time unavailable';

  final date = DateTime.tryParse('$value');

  if (date == null) return 'Time unavailable';

  return _formatTime(date);

}



enum _TimelineType { punchIn, punchOut, login, visit, stop, travel, gap }



class _TimelineEntry {

  final String id, title, subtitle;

  final _TimelineType type;

  final DateTime at;

  final DateTime? end;

  final LatLng? coord;

  final Color color;

  final IconData icon;

  final Json? raw;

  final String? badge, departureText, address;

  final double? distanceMeters;

  final int? stopNumber;

  final bool isMissingVisit;

  _TimelineEntry({

    required this.id,

    required this.type,

    required this.title,

    required this.subtitle,

    required this.at,

    this.end,

    this.coord,

    required this.color,

    required this.icon,

    this.raw,

    this.badge,

    this.departureText,

    this.address,

    this.distanceMeters,

    this.stopNumber,

    this.isMissingVisit = false,

  });

}



class _VisitSelfiePreview extends StatefulWidget {

  final TrackyuController controller;

  final Json visit;

  final bool darkMode;



  const _VisitSelfiePreview({

    required this.controller,

    required this.visit,

    required this.darkMode,

  });



  @override

  State<_VisitSelfiePreview> createState() => _VisitSelfiePreviewState();

}



class _VisitSelfiePreviewState extends State<_VisitSelfiePreview> {

  Uint8List? _inBytes;

  Uint8List? _outBytes;

  bool _loading = true;



  @override

  void initState() {

    super.initState();

    TrackyuAddressCache.init();

    _load();

  }



  Future<void> _load() async {

    Json v;

    try {

      v = await localVisitMedia(widget.controller, widget.visit);

    } catch (_) {

      if (mounted) setState(() => _loading = false);

      return;

    }

    try {

      _inBytes = await loadVisitPhoto(widget.controller, v, 'in');

    } catch (_) {

      // Arrival photo not cached or offline

    }

    if (hasDeparturePhoto(v)) {

      try {

        _outBytes = await loadVisitPhoto(widget.controller, v, 'out');

      } catch (_) {

        // Departure photo not cached or offline

      }

    }



    if (mounted) {

      setState(() {

        _loading = false;

      });

    }

  }



  void _showFullScreen(Uint8List bytes, String title) {

    showDialog(

      context: context,

      builder: (ctx) => Dialog(

        backgroundColor: Colors.transparent,

        insetPadding: const EdgeInsets.all(12),

        child: Stack(

          alignment: Alignment.topRight,

          children: [

            ClipRRect(

              borderRadius: BorderRadius.circular(16),

              child: Container(

                color: Colors.black,

                child: InteractiveViewer(

                  maxScale: 4.0,

                  child: Image.memory(bytes, fit: BoxFit.contain),

                ),

              ),

            ),

            Positioned(

              top: 10,

              right: 10,

              child: CircleAvatar(

                backgroundColor: Colors.black54,

                radius: 18,

                child: IconButton(

                  padding: EdgeInsets.zero,

                  icon: const Icon(Icons.close, color: Colors.white, size: 20),

                  onPressed: () => Navigator.pop(ctx),

                ),

              ),

            ),

            Positioned(

              bottom: 12,

              left: 12,

              child: Container(

                padding: const EdgeInsets.symmetric(

                  horizontal: 10,

                  vertical: 4,

                ),

                decoration: BoxDecoration(

                  color: Colors.black87,

                  borderRadius: BorderRadius.circular(6),

                ),

                child: Text(

                  title,

                  style: const TextStyle(

                    color: Colors.white,

                    fontSize: 12,

                    fontWeight: FontWeight.w600,

                  ),

                ),

              ),

            ),

          ],

        ),

      ),

    );

  }



  Widget _buildPhotoCard(Uint8List bytes, String label) {

    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        Row(

          mainAxisAlignment: MainAxisAlignment.spaceBetween,

          children: [

            Text(

              label,

              style: TextStyle(

                fontSize: 11,

                fontWeight: FontWeight.w700,

                letterSpacing: 0.5,

                color: widget.darkMode

                    ? Colors.white70

                    : const Color(0xff475569),

              ),

            ),

            const Text(

              'Tap to zoom',

              style: TextStyle(

                fontSize: 11,

                fontWeight: FontWeight.w600,

                color: Color(0xff26c6da),

              ),

            ),

          ],

        ),

        const SizedBox(height: 6),

        InkWell(

          onTap: () => _showFullScreen(bytes, label),

          borderRadius: BorderRadius.circular(12),

          child: ClipRRect(

            borderRadius: BorderRadius.circular(12),

            child: Container(

              height: 190,

              width: double.infinity,

              decoration: BoxDecoration(

                color: widget.darkMode

                    ? const Color(0xff25282c)

                    : const Color(0xfff1f5f9),

                border: Border.all(

                  color: widget.darkMode

                      ? const Color(0xff374151)

                      : const Color(0xffe2e8f0),

                ),

              ),

              child: Stack(

                fit: StackFit.expand,

                children: [

                  Image.memory(bytes, fit: BoxFit.cover),

                  Positioned(

                    bottom: 8,

                    right: 8,

                    child: Container(

                      padding: const EdgeInsets.symmetric(

                        horizontal: 8,

                        vertical: 4,

                      ),

                      decoration: BoxDecoration(

                        color: Colors.black.withValues(alpha: 0.65),

                        borderRadius: BorderRadius.circular(6),

                      ),

                      child: const Row(

                        mainAxisSize: MainAxisSize.min,

                        children: [

                          Icon(Icons.zoom_in, color: Colors.white, size: 14),

                          SizedBox(width: 4),

                          Text(

                            'Full photo',

                            style: TextStyle(

                              color: Colors.white,

                              fontSize: 11,

                              fontWeight: FontWeight.w600,

                            ),

                          ),

                        ],

                      ),

                    ),

                  ),

                ],

              ),

            ),

          ),

        ),

      ],

    );

  }



  @override

  Widget build(BuildContext context) {

    if (_loading) {

      return Container(

        height: 120,

        width: double.infinity,

        decoration: BoxDecoration(

          color: widget.darkMode

              ? const Color(0xff25282c)

              : const Color(0xfff8fafd),

          borderRadius: BorderRadius.circular(12),

          border: Border.all(

            color: widget.darkMode

                ? const Color(0xff374151)

                : const Color(0xffe2e8f0),

          ),

        ),

        child: const Center(

          child: Column(

            mainAxisSize: MainAxisSize.min,

            children: [

              SizedBox(

                width: 24,

                height: 24,

                child: CircularProgressIndicator(strokeWidth: 2.2),

              ),

              SizedBox(height: 10),

              Text(

                'Loading visit selfie...',

                style: TextStyle(fontSize: 12, color: Color(0xff94a3b8)),

              ),

            ],

          ),

        ),

      );

    }



    if (_inBytes == null && _outBytes == null) {

      return Container(

        width: double.infinity,

        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),

        decoration: BoxDecoration(

          color: widget.darkMode

              ? const Color(0xff25282c)

              : const Color(0xfff8fafd),

          borderRadius: BorderRadius.circular(10),

          border: Border.all(

            color: widget.darkMode

                ? const Color(0xff374151)

                : const Color(0xffe2e8f0),

          ),

        ),

        child: Row(

          children: [

            Icon(

              Icons.no_photography_outlined,

              size: 20,

              color: widget.darkMode ? Colors.white54 : Colors.black45,

            ),

            const SizedBox(width: 10),

            Expanded(

              child: Text(

                'No selfie recorded for this visit',

                style: TextStyle(

                  fontSize: 12,

                  color: widget.darkMode ? Colors.white60 : Colors.black54,

                ),

              ),

            ),

          ],

        ),

      );

    }



    return Column(

      children: [

        if (_inBytes != null) _buildPhotoCard(_inBytes!, 'Arrival Selfie'),

        if (_inBytes != null && _outBytes != null) const SizedBox(height: 12),

        if (_outBytes != null) _buildPhotoCard(_outBytes!, 'Departure Selfie'),

      ],

    );

  }

}

