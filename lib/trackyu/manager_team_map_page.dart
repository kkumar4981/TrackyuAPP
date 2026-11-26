import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'controller.dart';
import 'api.dart' show ApiFailure;
import 'legacy_map.dart';
import 'workspace.dart' show jsonRows;

/// Live Team Radar and Interactive Employee Map for Field Managers.
/// Shows all field employees live with Uber/cab-style markers, active/inactive
/// color coding, real-time stats, and full interactive day route & timeline overlays.
class ManagerTeamMapPage extends StatefulWidget {
  final TrackyuController controller;
  const ManagerTeamMapPage({super.key, required this.controller});

  @override
  State<ManagerTeamMapPage> createState() => _ManagerTeamMapPageState();
}

class _ManagerTeamMapPageState extends State<ManagerTeamMapPage>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  Map<String, dynamic>? _selectedEmployee;

  // Selected date (defaults to today)
  DateTime _selectedDate = DateTime.now();

  bool _loading = false;
  bool _autoRefresh = true;
  Timer? _autoRefreshTimer;
  String? _errorMessage;

  // Status Filter: 'ALL', 'ACTIVE', 'CLIENT', 'OFFLINE'
  String _activeFilter = 'ALL';

  // Level Filter: 'ALL', '1', '2', '3', '4', '5'
  String _selectedLevel = 'ALL';

  // Day Route polyline data for currently inspected employee
  bool _loadingRoute = false;
  Map<String, dynamic>? _routeData;
  List<LatLng> _routePoints = [];
  List<Map<String, dynamic>> _routeVisits = [];
  List<Map<String, dynamic>> _routeEvents = [];
  bool _showingRoute = false;

  // Animation controller for pulsing active pins
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _searchController.addListener(_applyFilter);
    _loadTeamLocations();

    // Set up auto-refresh every 20 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && _autoRefresh && !_showingRoute && !_loading) {
        _loadTeamLocations(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _pulseController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String get _dateStr =>
      '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  Future<void> _loadTeamLocations({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final res = await widget.controller.api.request(
        'DutyTracking/employees',
        body: {'date': _dateStr},
      );

      final List<Map<String, dynamic>> rows = [];
      if (res is Map && res['rows'] is List) {
        for (final item in res['rows']) {
          if (item is Map) rows.add(Map<String, dynamic>.from(item));
        }
      } else if (res is List) {
        for (final item in res) {
          if (item is Map) rows.add(Map<String, dynamic>.from(item));
        }
      } else {
        final extracted = jsonRows(res);
        rows.addAll(extracted);
      }

      if (mounted) {
        // Sort hierarchy-wise & level-wise: Level DESC (5->1), then Hierarchy Depth ASC (direct reportees first), then Name
        rows.sort((a, b) {
          final levelA = int.tryParse((a['level'] ?? a['Level'] ?? '1').toString()) ?? 1;
          final levelB = int.tryParse((b['level'] ?? b['Level'] ?? '1').toString()) ?? 1;
          if (levelB != levelA) return levelB.compareTo(levelA);

          final depthA = int.tryParse((a['hierarchyDepth'] ?? a['HierarchyDepth'] ?? '99').toString()) ?? 99;
          final depthB = int.tryParse((b['hierarchyDepth'] ?? b['HierarchyDepth'] ?? '99').toString()) ?? 99;
          if (depthA != depthB) return depthA.compareTo(depthB);

          final nameA = (a['name'] ?? a['Name'] ?? '').toString();
          final nameB = (b['name'] ?? b['Name'] ?? '').toString();
          return nameA.compareTo(nameB);
        });

        setState(() {
          _employees = rows;
          _loading = false;
        });
        _applyFilter();

        // Fit bounds on first load if we have valid coordinates
        if (!silent && _employees.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitAllMarkers());
        }
      }
    } catch (e) {
      if(e is ApiFailure && [401,403].contains(e.status)) {
        _autoRefreshTimer?.cancel();
        _autoRefresh=false;
      }

      if (mounted) {
        setState(() {
          _loading = false;
          if (!silent || e is ApiFailure && [401,403].contains(e.status)) {
            _errorMessage = 'Could not load team locations: $e';
          }
        });
      }
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredEmployees = _employees.where((emp) {
        final name = (emp['name'] ?? emp['Name'] ?? '').toString().toLowerCase();
        final id = (emp['userId'] ?? emp['UserId'] ?? '').toString().toLowerCase();
        final matchesQuery = query.isEmpty || name.contains(query) || id.contains(query);
        if (!matchesQuery) return false;

        if (_selectedLevel != 'ALL') {
          final lvl = (emp['level'] ?? emp['Level'] ?? '1').toString().trim();
          if (lvl != _selectedLevel) return false;
        }

        final status = _determineStatus(emp);
        if (_activeFilter == 'ACTIVE') {
          return status == _EmployeeMapStatus.active;
        } else if (_activeFilter == 'CLIENT') {
          return status == _EmployeeMapStatus.atClient;
        } else if (_activeFilter == 'OFFLINE') {
          return status == _EmployeeMapStatus.offline ||
              status == _EmployeeMapStatus.punchedOut;
        }
        return true;
      }).toList();
    });
  }

  _EmployeeMapStatus _determineStatus(Map<String, dynamic> emp) {
    final gpsEnabled = emp['gpsEnabled'] ?? emp['GpsEnabled'];
    if (gpsEnabled == false) {
      return _EmployeeMapStatus.gpsDisabled;
    }

    final punchOut = emp['punchOutUtc'] ?? emp['PunchOutUtc'];
    if (punchOut != null && punchOut.toString().isNotEmpty) {
      return _EmployeeMapStatus.punchedOut;
    }

    final punchIn = emp['punchInUtc'] ?? emp['PunchInUtc'];
    if (punchIn == null || punchIn.toString().isEmpty) {
      return _EmployeeMapStatus.offline;
    }

    final activeVisit = emp['activeVisitName'] ?? emp['ActiveVisitName'];
    final trackingStatus = (emp['trackingStatus'] ?? emp['TrackingStatus'] ?? '').toString();
    if ((activeVisit != null && activeVisit.toString().isNotEmpty) ||
        trackingStatus.toLowerCase().contains('stationary') ||
        trackingStatus.toLowerCase().contains('client')) {
      return _EmployeeMapStatus.atClient;
    }

    final capturedAt = emp['capturedAtUtc'] ?? emp['CapturedAtUtc'];
    if (capturedAt != null) {
      final dt = DateTime.tryParse(capturedAt.toString());
      if (dt != null) {
        final diffMins = DateTime.now().toUtc().difference(dt).inMinutes;
        if (diffMins > 45) {
          return _EmployeeMapStatus.idle;
        }
      }
    }

    return _EmployeeMapStatus.active;
  }

  void _focusLatestLocationOrFit({bool userTriggered = false}) {
    final withCoords = _filteredEmployees.where((emp) {
      final lat = _parseDouble(emp['latitude'] ?? emp['Latitude']);
      final lng = _parseDouble(emp['longitude'] ?? emp['Longitude']);
      return lat != null && lng != null && (lat != 0 || lng != 0);
    }).toList();

    if (withCoords.isEmpty) {
      // Default to Bhopal center if no points
      _mapController.move(const LatLng(23.2599, 77.4126), 12.0);
      return;
    }

    // Sort to prioritize the employee with the most recent valid GPS location ping
    withCoords.sort((a, b) {
      final capA = a['capturedAtUtc'] ?? a['CapturedAtUtc'];
      final capB = b['capturedAtUtc'] ?? b['CapturedAtUtc'];
      final dtA = capA != null ? DateTime.tryParse(capA.toString()) : null;
      final dtB = capB != null ? DateTime.tryParse(capB.toString()) : null;

      if (dtA != null && dtB != null) {
        final cmp = dtB.compareTo(dtA);
        if (cmp != 0) return cmp;
      } else if (dtA != null) {
        return -1;
      } else if (dtB != null) {
        return 1;
      }

      final stA = _determineStatus(a);
      final stB = _determineStatus(b);
      final rankA = (stA == _EmployeeMapStatus.active || stA == _EmployeeMapStatus.atClient) ? 0 : 1;
      final rankB = (stB == _EmployeeMapStatus.active || stB == _EmployeeMapStatus.atClient) ? 0 : 1;
      return rankA.compareTo(rankB);
    });

    final target = withCoords.first;
    final lat = _parseDouble(target['latitude'] ?? target['Latitude'])!;
    final lng = _parseDouble(target['longitude'] ?? target['Longitude'])!;

    setState(() {
      _selectedEmployee = target;
    });

    _mapController.move(LatLng(lat, lng), 15.0);
  }

  void _fitAllMarkers() {
    _focusLatestLocationOrFit(userTriggered: true);
  }

  double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Future<void> _loadEmployeeDayRoute(Map<String, dynamic> emp) async {
    final userId = (emp['userId'] ?? emp['UserId'] ?? '').toString();
    if (userId.isEmpty) return;

    setState(() {
      _loadingRoute = true;
      _showingRoute = true;
      _routePoints = [];
      _routeVisits = [];
      _routeEvents = [];
      _routeData = null;
    });

    try {
      final res = await widget.controller.api.request(
        'DutyTracking/day',
        body: {
          'userId': userId,
          'date': _dateStr,
          'includeRaw': true,
        },
      );

      final pts = <LatLng>[];
      final visits = <Map<String, dynamic>>[];
      final events = <Map<String, dynamic>>[];

      if (res is Map) {
        // Parse polyline route segments
        final routeObj = res['route'] ?? res['Route'];
        if (routeObj is Map && routeObj['segments'] is List) {
          for (final seg in routeObj['segments']) {
            if (seg is List) {
              for (final p in seg) {
                if (p is Map) {
                  final lat = _parseDouble(p['latitude'] ?? p['Latitude']);
                  final lng = _parseDouble(p['longitude'] ?? p['Longitude']);
                  if (lat != null && lng != null && (lat != 0 || lng != 0)) {
                    pts.add(LatLng(lat, lng));
                  }
                }
              }
            }
          }
        }

        // If segments were empty, check recordedPoints
        if (pts.isEmpty && res['recordedPoints'] is List) {
          for (final p in res['recordedPoints']) {
            if (p is Map) {
              final lat = _parseDouble(p['latitude'] ?? p['Latitude']);
              final lng = _parseDouble(p['longitude'] ?? p['Longitude']);
              if (lat != null && lng != null && (lat != 0 || lng != 0)) {
                pts.add(LatLng(lat, lng));
              }
            }
          }
        }

        // Parse visits
        final vList = res['visits'] ?? res['Visits'];
        if (vList is List) {
          for (final v in vList) {
            if (v is Map) visits.add(Map<String, dynamic>.from(v));
          }
        }

        // Parse events
        final eList = res['events'] ?? res['Events'];
        if (eList is List) {
          for (final e in eList) {
            if (e is Map) events.add(Map<String, dynamic>.from(e));
          }
        }
      }

      if (mounted) {
        setState(() {
          _loadingRoute = false;
          _routePoints = pts;
          _routeVisits = visits;
          _routeEvents = events;
          _routeData = res is Map ? Map<String, dynamic>.from(res) : null;
        });

        // Fit map bounds to polyline
        if (pts.isNotEmpty) {
          _fitRouteBounds(pts);
        } else {
          // Fallback to employee's last known location
          final lat = _parseDouble(emp['latitude'] ?? emp['Latitude']);
          final lng = _parseDouble(emp['longitude'] ?? emp['Longitude']);
          if (lat != null && lng != null) {
            _mapController.move(LatLng(lat, lng), 15.0);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingRoute = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load day route: $e')),
        );
      }
    }
  }

  void _fitRouteBounds(List<LatLng> points) {
    if (points.isEmpty) return;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final pt in points) {
      minLat = math.min(minLat, pt.latitude);
      maxLat = math.max(maxLat, pt.latitude);
      minLng = math.min(minLng, pt.longitude);
      maxLng = math.max(maxLng, pt.longitude);
    }

    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    _mapController.move(center, 14.0);
  }

  void _clearRouteView() {
    setState(() {
      _showingRoute = false;
      _routePoints = [];
      _routeVisits = [];
      _routeEvents = [];
      _routeData = null;
    });
    _fitAllMarkers();
  }

  Future<void> _makeCall(String? mobile) async {
    if (mobile == null || mobile.trim().isEmpty) return;
    final clean = mobile.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: clean);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot launch phone dialer for $clean')),
          );
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Build map markers
    final markers = <Marker>[];

    // 1. If showing route, draw start, visit stops, and end markers
    if (_showingRoute && _routePoints.isNotEmpty) {
      // Start Marker (Punch In)
      final startPt = _routePoints.first;
      markers.add(
        Marker(
          point: startPt,
          width: 70,
          height: 60,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xff10b981),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'START',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.flag_rounded, color: Color(0xff10b981), size: 28),
            ],
          ),
        ),
      );

      // Visit Stops along route
      for (int i = 0; i < _routeVisits.length; i++) {
        final v = _routeVisits[i];
        final vLat = _parseDouble(v['inLatitude'] ?? v['InLatitude'] ?? v['latitude']);
        final vLng = _parseDouble(v['inLongitude'] ?? v['InLongitude'] ?? v['longitude']);
        if (vLat != null && vLng != null && (vLat != 0 || vLng != 0)) {
          final shopName = (v['shopName'] ?? v['ShopName'] ?? 'Stop ${i + 1}').toString();
          markers.add(
            Marker(
              point: LatLng(vLat, vLng),
              width: 80,
              height: 65,
              child: GestureDetector(
                onTap: () => _showVisitDetailsSheet(v, i + 1),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xff3b82f6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#${i + 1} ${shopName.length > 7 ? '${shopName.substring(0, 7)}…' : shopName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(Icons.storefront_rounded, color: Color(0xff2563eb), size: 26),
                  ],
                ),
              ),
            ),
          );
        }
      }

      // End / Current Marker
      final endPt = _routePoints.last;
      markers.add(
        Marker(
          point: endPt,
          width: 80,
          height: 65,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xffef4444),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'CURRENT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.location_on_rounded, color: Color(0xffef4444), size: 30),
            ],
          ),
        ),
      );
    } else {
      // 2. Team Radar markers (All employees with cab / vehicle styling)
      for (final emp in _filteredEmployees) {
        final lat = _parseDouble(emp['latitude'] ?? emp['Latitude']);
        final lng = _parseDouble(emp['longitude'] ?? emp['Longitude']);
        if (lat == null || lng == null || (lat == 0 && lng == 0)) continue;

        final status = _determineStatus(emp);
        final name = (emp['name'] ?? emp['Name'] ?? 'Staff').toString();
        final firstName = name.split(' ').first;
        final isSelected = _selectedEmployee != null &&
            (_selectedEmployee!['userId'] == emp['userId'] ||
                _selectedEmployee!['UserId'] == emp['UserId']);

        Color statusColor;
        IconData statusIcon;
        switch (status) {
          case _EmployeeMapStatus.active:
            statusColor = const Color(0xff10b981); // Emerald Green
            statusIcon = Icons.local_taxi_rounded; // Uber/Cab style moving vehicle
            break;
          case _EmployeeMapStatus.atClient:
            statusColor = const Color(0xfff59e0b); // Amber
            statusIcon = Icons.storefront_rounded; // Stationary at client
            break;
          case _EmployeeMapStatus.idle:
            statusColor = const Color(0xff3b82f6); // Slate blue
            statusIcon = Icons.navigation_rounded;
            break;
          case _EmployeeMapStatus.gpsDisabled:
            statusColor = const Color(0xffef4444); // Red
            statusIcon = Icons.gps_off_rounded;
            break;
          case _EmployeeMapStatus.offline:
          case _EmployeeMapStatus.punchedOut:
            statusColor = const Color(0xff94a3b8); // Gray
            statusIcon = Icons.person_pin_circle_rounded;
            break;
        }

        markers.add(
          Marker(
            point: LatLng(lat, lng),
            width: 80,
            height: 70,
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedEmployee = emp);
                _mapController.move(LatLng(lat, lng), 15.0);
                _showEmployeeDetailSheet(emp);
              },
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  final scale = status == _EmployeeMapStatus.active ? _pulseAnimation.value : 1.0;
                  return Transform.scale(
                    scale: isSelected ? 1.25 : scale,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Name Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xff1e293b) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: statusColor, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: statusColor.withValues(alpha: 0.35),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            firstName,
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xff0f172a),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Cab / Vehicle Pin Badge
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: statusColor,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: statusColor.withValues(alpha: 0.5),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(statusIcon, color: Colors.white, size: 18),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      }
    }

    // Polyline layer
    final polylines = <Polyline>[];
    if (_showingRoute && _routePoints.length >= 2) {
      polylines.add(
        Polyline(
          points: _routePoints,
          strokeWidth: 4.5,
          color: const Color(0xff2563eb),
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      );
    }

    // Counts
    int activeCount = 0;
    int atClientCount = 0;
    int offlineCount = 0;
    for (final emp in _employees) {
      final s = _determineStatus(emp);
      if (s == _EmployeeMapStatus.active) {
        activeCount++;
      } else if (s == _EmployeeMapStatus.atClient) {
        atClientCount++;
      } else {
        offlineCount++;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_showingRoute ? 'Employee Day Route' : 'Live Team Map'),
        actions: [
          if (_showingRoute)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Exit Route View',
              onPressed: _clearRouteView,
            )
          else ...[
            IconButton(
              icon: Icon(
                _autoRefresh ? Icons.sync_rounded : Icons.sync_disabled_rounded,
                color: _autoRefresh ? const Color(0xff10b981) : Colors.white60,
              ),
              tooltip: _autoRefresh ? 'Auto-refresh Active' : 'Auto-refresh Paused',
              onPressed: () {
                setState(() => _autoRefresh = !_autoRefresh);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _autoRefresh
                          ? 'Auto-refresh enabled (updates every 20s)'
                          : 'Auto-refresh paused',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh Locations',
              onPressed: () => _loadTeamLocations(),
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          // FlutterMap
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(23.2599, 77.4126), // Default Bhopal
              initialZoom: 12.0,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              legacyMapTiles(darkMode: isDark),
              if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
              MarkerLayer(markers: markers),
              legacyMapAttribution,
            ],
          ),

          // Top Floating Control Card
          if (!_showingRoute)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: isDark ? const Color(0xff1e293b).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.96),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Builder(
                    builder: (context) {
                      final searchQuery = _searchController.text.trim();
                      final searchMatches = searchQuery.isEmpty
                          ? <Map<String, dynamic>>[]
                          : _employees.where((emp) {
                              final q = searchQuery.toLowerCase();
                              final name = (emp['name'] ?? emp['Name'] ?? '').toString().toLowerCase();
                              final id = (emp['userId'] ?? emp['UserId'] ?? '').toString().toLowerCase();
                              return name.contains(q) || id.contains(q);
                            }).take(6).toList();

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Search & Date Picker Row
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 38,
                                  child: TextField(
                                    controller: _searchController,
                                    decoration: InputDecoration(
                                      hintText: 'Search employee by name or ID...',
                                      hintStyle: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                                      ),
                                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                                      suffixIcon: searchQuery.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.clear_rounded, size: 16),
                                              onPressed: () {
                                                _searchController.clear();
                                                setState(() {});
                                              },
                                            )
                                          : null,
                                      filled: true,
                                      fillColor: isDark ? const Color(0xff0f172a) : const Color(0xfff1f5f9),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Date Button
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _selectedDate,
                                    firstDate: DateTime.now().subtract(const Duration(days: 90)),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null && picked != _selectedDate) {
                                    setState(() => _selectedDate = picked);
                                    _loadTeamLocations();
                                  }
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  height: 38,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xff0f172a) : const Color(0xfff1f5f9),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.calendar_today_rounded, size: 15, color: Color(0xff3b82f6)),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${_selectedDate.day}/${_selectedDate.month}',
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Live Autocomplete Suggestions List
                          if (searchQuery.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Divider(height: 1, thickness: 0.5),
                            if (searchMatches.isNotEmpty)
                              Container(
                                constraints: const BoxConstraints(maxHeight: 220),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  itemCount: searchMatches.length,
                                  separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
                                  itemBuilder: (context, idx) {
                                    final emp = searchMatches[idx];
                                    final name = (emp['name'] ?? emp['Name'] ?? 'Staff').toString();
                                    final userId = (emp['userId'] ?? emp['UserId'] ?? '').toString();
                                    final status = _determineStatus(emp);
                                    final statusColor = status == _EmployeeMapStatus.active
                                        ? const Color(0xff10b981)
                                        : status == _EmployeeMapStatus.atClient
                                            ? const Color(0xfff59e0b)
                                            : const Color(0xff94a3b8);
                                    final empLevel = (emp['level'] ?? emp['Level'] ?? '1').toString().trim();
                                    final designation = (emp['designation'] ?? emp['Designation'] ?? '').toString().trim();
                                    final activeVisit = (emp['activeVisitName'] ?? emp['ActiveVisitName'] ?? '').toString();
                                    final visitsDone = emp['visitCount'] ?? emp['VisitCount'] ?? 0;
                                    final lat = _parseDouble(emp['latitude'] ?? emp['Latitude']);
                                    final lng = _parseDouble(emp['longitude'] ?? emp['Longitude']);
                                    final hasCoords = lat != null && lng != null && (lat != 0 || lng != 0);

                                    return InkWell(
                                      onTap: () {
                                        FocusScope.of(context).unfocus();
                                        setState(() {
                                          _selectedEmployee = emp;
                                        });
                                        if (hasCoords) {
                                          _mapController.move(LatLng(lat, lng), 16.0);
                                          _showEmployeeDetailSheet(emp);
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('No live GPS coordinates available for $name today.'),
                                              duration: const Duration(seconds: 2),
                                            ),
                                          );
                                          _showEmployeeDetailSheet(emp);
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                        child: Row(
                                          children: [
                                            Stack(
                                              children: [
                                                CircleAvatar(
                                                  radius: 16,
                                                  backgroundColor: statusColor.withValues(alpha: 0.15),
                                                  child: Text(
                                                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: statusColor),
                                                  ),
                                                ),
                                                Positioned(
                                                  right: 0,
                                                  bottom: 0,
                                                  child: Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                      color: statusColor,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: Colors.white, width: 1.5),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          name,
                                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                        decoration: BoxDecoration(
                                                          color: isDark ? Colors.white12 : const Color(0xffe2e8f0),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          userId,
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w600,
                                                            color: isDark ? Colors.white70 : const Color(0xff475569),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                        decoration: BoxDecoration(
                                                          color: _levelColor(empLevel).withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: _levelColor(empLevel).withValues(alpha: 0.35)),
                                                        ),
                                                        child: Text(
                                                          'L$empLevel',
                                                          style: TextStyle(
                                                            fontSize: 9.5,
                                                            fontWeight: FontWeight.w700,
                                                            color: _levelColor(empLevel),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    activeVisit.isNotEmpty
                                                        ? 'At $activeVisit'
                                                        : status == _EmployeeMapStatus.active
                                                            ? 'Active at work • $visitsDone visits'
                                                            : status == _EmployeeMapStatus.atClient
                                                                ? 'Visiting client'
                                                                : 'Offline / Punched out',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              hasCoords ? Icons.near_me_rounded : Icons.location_off_rounded,
                                              size: 16,
                                              color: hasCoords ? const Color(0xff2563eb) : const Color(0xff94a3b8),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              )
                            else
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  'No employee matches this search',
                                  style: TextStyle(fontSize: 11.5, color: Color(0xff94a3b8), fontStyle: FontStyle.italic),
                                ),
                              ),
                          ],
                      const SizedBox(height: 8),
                      // Filter Badges Row
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('ALL', 'All (${_employees.length})', const Color(0xff64748b)),
                            const SizedBox(width: 6),
                            _buildFilterChip('ACTIVE', 'Active ($activeCount)', const Color(0xff10b981)),
                            const SizedBox(width: 6),
                            _buildFilterChip('CLIENT', 'At Client ($atClientCount)', const Color(0xfff59e0b)),
                            const SizedBox(width: 6),
                            _buildFilterChip('OFFLINE', 'Offline ($offlineCount)', const Color(0xff94a3b8)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Level-wise Hierarchy Filter Row
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildLevelChip('ALL', 'All Levels (${_employees.length})'),
                            const SizedBox(width: 6),
                            for (final lvl in ['5', '4', '3', '2', '1'])
                              if (_employees.any((e) => (e['level'] ?? e['Level'] ?? '1').toString().trim() == lvl)) ...[
                                _buildLevelChip(lvl, 'L$lvl (${_employees.where((e) => (e['level'] ?? e['Level'] ?? '1').toString().trim() == lvl).length})'),
                                const SizedBox(width: 6),
                              ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),

          // Route Top Floating Banner
          if (_showingRoute)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                color: isDark ? const Color(0xff1e293b) : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xff2563eb).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.route_rounded, color: Color(0xff2563eb), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedEmployee?['name'] ?? _selectedEmployee?['Name'] ?? 'Field Staff',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                            Text(
                              'Date: $_dateStr • Points: ${_routePoints.length} • Visits: ${_routeVisits.length}',
                              style: const TextStyle(fontSize: 11, color: Color(0xff64748b)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.list_alt_rounded, color: Color(0xff2563eb)),
                        tooltip: 'View Step-by-Step Timeline',
                        onPressed: _showDayTimelineSheet,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Floating Action Buttons (Fit Bounds & My Location)
          Positioned(
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'fit_all',
                  backgroundColor: isDark ? const Color(0xff1e293b) : Colors.white,
                  foregroundColor: const Color(0xff2563eb),
                  tooltip: 'Fit All Markers',
                  onPressed: () {
                    if (_showingRoute && _routePoints.isNotEmpty) {
                      _fitRouteBounds(_routePoints);
                    } else {
                      _fitAllMarkers();
                    }
                  },
                  child: const Icon(Icons.zoom_out_map_rounded),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'my_loc',
                  backgroundColor: isDark ? const Color(0xff1e293b) : Colors.white,
                  foregroundColor: const Color(0xff10b981),
                  tooltip: 'Center on My GPS',
                  onPressed: () async {
                    try {
                      final pos = await widget.controller.locate();
                      final lat = _parseDouble(pos['latitude']);
                      final lng = _parseDouble(pos['longitude']);
                      if (lat != null && lng != null) {
                        _mapController.move(LatLng(lat, lng), 15.0);
                      }
                    } catch (_) {}
                  },
                  child: const Icon(Icons.my_location_rounded),
                ),
              ],
            ),
          ),

          // Loading Indicator
          if (_loading || _loadingRoute)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Updating live positions...',
                        style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Error notification banner
          if (_errorMessage != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 70,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xfffee2e2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xfffca5a5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xffdc2626), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Color(0xffb91c1c), fontSize: 11.5),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _levelColor(String level) {
    switch (level.trim()) {
      case '5':
        return const Color(0xff7c3aed);
      case '4':
        return const Color(0xff2563eb);
      case '3':
        return const Color(0xff0891b2);
      case '2':
        return const Color(0xff059669);
      case '1':
      default:
        return const Color(0xffd97706);
    }
  }

  String _levelTitle(String level) {
    switch (level.trim()) {
      case '5':
        return 'L5 - Director';
      case '4':
        return 'L4 - State Head';
      case '3':
        return 'L3 - Territory Manager';
      case '2':
        return 'L2 - Area Manager';
      case '1':
      default:
        return 'L1 - Sales Staff';
    }
  }

  Widget _buildLevelChip(String key, String label) {
    final isSelected = _selectedLevel == key;
    final color = key == 'ALL' ? const Color(0xff64748b) : _levelColor(key);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedLevel = key;
        });
        _applyFilter();
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.18)
              : (isDark ? const Color(0xff0f172a) : const Color(0xfff1f5f9)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : (isDark ? Colors.white12 : const Color(0xffe2e8f0)),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : (isDark ? const Color(0xffcbd5e1) : const Color(0xff475569)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, Color color) {
    final isSelected = _activeFilter == key;
    return InkWell(
      onTap: () {
        setState(() => _activeFilter = key);
        _applyFilter();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? color : color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEmployeeDetailSheet(Map<String, dynamic> emp) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = (emp['name'] ?? emp['Name'] ?? 'Field Staff').toString();
    final userId = (emp['userId'] ?? emp['UserId'] ?? '').toString();
    final mobile = (emp['mobile'] ?? emp['Mobile'] ?? emp['sm_mobile'] ?? '').toString();
    final company = (emp['company'] ?? emp['Company'] ?? '').toString();
    final empLevel = (emp['level'] ?? emp['Level'] ?? '1').toString().trim();
    final designation = (emp['designation'] ?? emp['Designation'] ?? '').toString().trim();
    final managerId = (emp['managerId'] ?? emp['ManagerId'] ?? '').toString().trim();
    final hierarchyDepth = int.tryParse((emp['hierarchyDepth'] ?? emp['HierarchyDepth'] ?? '99').toString()) ?? 99;
    final status = _determineStatus(emp);
    final runningKm = emp['runningKm'] ?? emp['RunningKm'] ?? 0.0;
    final visitCount = emp['visitCount'] ?? emp['VisitCount'] ?? 0;
    final punchIn = emp['punchInUtc'] ?? emp['PunchInUtc'];
    final punchOut = emp['punchOutUtc'] ?? emp['PunchOutUtc'];
    final battery = emp['batteryPercent'] ?? emp['BatteryPercent'];
    final accuracy = emp['accuracyMeters'] ?? emp['AccuracyMeters'];
    final activeVisit = emp['activeVisitName'] ?? emp['ActiveVisitName'];

    Color statusColor;
    String statusLabel;
    switch (status) {
      case _EmployeeMapStatus.active:
        statusColor = const Color(0xff10b981);
        statusLabel = 'Active At Work';
        break;
      case _EmployeeMapStatus.atClient:
        statusColor = const Color(0xfff59e0b);
        statusLabel = 'At Client: ${activeVisit ?? 'Store Visit'}';
        break;
      case _EmployeeMapStatus.idle:
        statusColor = const Color(0xff3b82f6);
        statusLabel = 'Stationary / Idle';
        break;
      case _EmployeeMapStatus.gpsDisabled:
        statusColor = const Color(0xffef4444);
        statusLabel = 'GPS Disabled';
        break;
      case _EmployeeMapStatus.punchedOut:
        statusColor = const Color(0xff94a3b8);
        statusLabel = 'Punched Out';
        break;
      case _EmployeeMapStatus.offline:
        statusColor = const Color(0xff94a3b8);
        statusLabel = 'Offline / Not Punched In';
        break;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xff1e293b) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Profile Header
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  child: Text(
                    name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: _levelColor(empLevel).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _levelColor(empLevel).withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              _levelTitle(empLevel),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _levelColor(empLevel),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$userId ${company.isNotEmpty ? '• $company' : ''}',
                            style: const TextStyle(fontSize: 12, color: Color(0xff64748b), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      if (designation.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          designation,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: Color(0xff64748b)),
                        ),
                      ],
                      if (managerId.isNotEmpty || (hierarchyDepth >= 0 && hierarchyDepth < 99)) ...[
                        const SizedBox(height: 2),
                        Text(
                          hierarchyDepth == 1
                              ? 'Direct Reportee • Manager: $managerId'
                              : hierarchyDepth == 0
                                  ? 'Team Lead / Self'
                                  : 'Level $hierarchyDepth Reportee • Manager: $managerId',
                          style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xff94a3b8)),
                        ),
                      ],
                    ],
                  ),
                ),
                if (mobile.isNotEmpty)
                  IconButton.filled(
                    onPressed: () => _makeCall(mobile),
                    icon: const Icon(Icons.phone_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xff10b981),
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Status Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    statusLabel,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Real-Time Stats Grid
            Row(
              children: [
                _buildMetricCard(
                  Icons.route_rounded,
                  '${runningKm is num ? runningKm.toStringAsFixed(1) : runningKm} km',
                  'Distance',
                  const Color(0xff3b82f6),
                ),
                const SizedBox(width: 10),
                _buildMetricCard(
                  Icons.storefront_rounded,
                  '$visitCount',
                  'Visits Done',
                  const Color(0xff8b5cf6),
                ),
                const SizedBox(width: 10),
                _buildMetricCard(
                  Icons.login_rounded,
                  punchIn != null ? _formatTime(punchIn) : '--:--',
                  'Punch In',
                  const Color(0xff10b981),
                ),
                const SizedBox(width: 10),
                _buildMetricCard(
                  Icons.battery_charging_full_rounded,
                  battery != null ? '$battery%' : '--',
                  'Battery',
                  const Color(0xfff59e0b),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Primary Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _loadEmployeeDayRoute(emp);
                    },
                    icon: const Icon(Icons.timeline_rounded, size: 18),
                    label: const Text('View Today\'s Route Trail'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff2563eb),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(IconData icon, String val, String label, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xff0f172a) : const Color(0xfff8fafc),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              val,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDayTimelineSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = (_selectedEmployee?['name'] ?? _selectedEmployee?['Name'] ?? 'Staff').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (_, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xff1e293b) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$name • Day Timeline',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      Text(
                        'Date: $_dateStr • Visits: ${_routeVisits.length}',
                        style: const TextStyle(fontSize: 12, color: Color(0xff64748b)),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: _routeVisits.isEmpty && _routeEvents.isEmpty
                    ? const Center(
                        child: Text(
                          'No specific visit milestones recorded for this date.',
                          style: TextStyle(color: Color(0xff64748b), fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _routeVisits.length,
                        itemBuilder: (context, idx) {
                          final v = _routeVisits[idx];
                          final shopName = (v['shopName'] ?? v['ShopName'] ?? 'Store Visit').toString();
                          final address = (v['address'] ?? v['Address'] ?? 'Location recorded').toString();
                          final checkIn = v['checkInUtc'] ?? v['CheckInUtc'];
                          final checkOut = v['checkOutUtc'] ?? v['CheckOutUtc'];
                          final remark = (v['remark'] ?? v['Remark'] ?? '').toString();

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Step Circle
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xff2563eb),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${idx + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xff0f172a) : const Color(0xfff8fafc),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          shopName,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          address,
                                          style: const TextStyle(fontSize: 11, color: Color(0xff64748b)),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(Icons.access_time_rounded, size: 12, color: Color(0xff3b82f6)),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${_formatTime(checkIn)} - ${_formatTime(checkOut)}',
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                        if (remark.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xff1e293b) : Colors.white,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Note: $remark',
                                              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showVisitDetailsSheet(Map<String, dynamic> v, int stopNum) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shopName = (v['shopName'] ?? v['ShopName'] ?? 'Store Visit').toString();
    final address = (v['address'] ?? v['Address'] ?? 'Location recorded').toString();
    final checkIn = v['checkInUtc'] ?? v['CheckInUtc'];
    final checkOut = v['checkOutUtc'] ?? v['CheckOutUtc'];
    final remark = (v['remark'] ?? v['Remark'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xff1e293b) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xff2563eb),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Stop #$stopNum',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    shopName,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(address, style: const TextStyle(fontSize: 12, color: Color(0xff64748b))),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 14, color: Color(0xff3b82f6)),
                const SizedBox(width: 6),
                Text(
                  'Check-In: ${_formatTime(checkIn)} • Check-Out: ${_formatTime(checkOut)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (remark.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Remark: $remark',
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(dynamic raw) {
    if (raw == null || raw.toString().isEmpty) return '--:--';
    final dt = DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return raw.toString();
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'pm' : 'am';
    return '$hour:$min $ampm';
  }
}

enum _EmployeeMapStatus {
  active,
  atClient,
  idle,
  gpsDisabled,
  punchedOut,
  offline,
}
