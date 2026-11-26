import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'controller.dart';
import 'visits.dart';
import 'workspace.dart' show jsonRows;
import 'trackyu_app_bar.dart';

class DailyRouteChartPage extends StatefulWidget {
  final TrackyuController controller;
  final String? targetUserId;
  final String? targetUserName;

  const DailyRouteChartPage({
    super.key,
    required this.controller,
    this.targetUserId,
    this.targetUserName,
  });

  @override
  State<DailyRouteChartPage> createState() => _DailyRouteChartPageState();
}

class _DailyRouteChartPageState extends State<DailyRouteChartPage> {
  bool _loading = false;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _stops = [];
  int _totalStops = 0;
  int _completedStops = 0;
  String _workDate = '';

  // All retailers for planning
  List<Map<String, dynamic>> _allRetailers = [];
  bool _loadingRetailers = false;

  String get _effectiveUserId =>
      widget.targetUserId ?? widget.controller.employeeId ?? '';

  bool get _isManagerView =>
      widget.targetUserId != null &&
      widget.targetUserId != widget.controller.employeeId;

  @override
  void initState() {
    super.initState();
    _loadTodayRoute();
  }

  Future<void> _loadTodayRoute() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final now = DateTime.now();
      final dateStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final query = 'userId=$_effectiveUserId&date=$dateStr';
      final res = await widget.controller.api.request('RoutePlan/today?$query');

      if (res is Map && res['data'] is Map) {
        final data = res['data'] as Map;
        final rawStops = (data['stops'] as List?) ?? [];
        setState(() {
          _stops = rawStops.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _totalStops = (data['totalStops'] as num?)?.toInt() ?? _stops.length;
          _completedStops = (data['completedStops'] as num?)?.toInt() ??
              _stops.where((s) => s['status'] == 'Completed').length;
          _workDate = data['workDate']?.toString() ?? dateStr;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ApiFailure ? e.message : e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRetailersForPlanner() async {
    if (_allRetailers.isNotEmpty) return;
    setState(() => _loadingRetailers = true);

    try {
      final res = await widget.controller.api.request('RetailerMappings/retailers?userId=$_effectiveUserId&assignedOnly=true');
      if (res is Map && res['data'] is List) {
        _allRetailers = (res['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {
      // Fallback to local retailers in session
      try {
        final localVisits = VisitsData(widget.controller);
        final rows = await localVisits.search('');
        _allRetailers = rows.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    } finally {
      _allRetailers = _allRetailers.where((r) {
        final lat = double.tryParse((r['xretailer'] ?? r['latitude'] ?? r['xloc'] ?? '').toString());
        final lng = double.tryParse((r['yretailer'] ?? r['longitude'] ?? r['yloc'] ?? '').toString());
        return lat != null && lng != null && (lat != 0 || lng != 0);
      }).toList();
      if (mounted) setState(() => _loadingRetailers = false);
    }
  }

  double? _calculateDistance(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    final lastLoc = widget.controller.lastLocation;
    if (lastLoc == null) return null;

    final userLat = (lastLoc['latitude'] as num?)?.toDouble();
    final userLng = (lastLoc['longitude'] as num?)?.toDouble();
    if (userLat == null || userLng == null) return null;

    const r = 6371.0; // Earth radius in km
    final dLat = (lat - userLat) * math.pi / 180.0;
    final dLon = (lng - userLng) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(userLat * math.pi / 180.0) *
            math.cos(lat * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  Future<void> _openNavigation(double lat, double lng, String label) async {
    final googleMapsUrl =
        Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(googleMapsUrl);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open map: $e')),
        );
      }
    }
  }

  Future<void> _startVisitForStop(Map<String, dynamic> stop) async {
    final retailerId = stop['retailerId']?.toString();
    final shopName = stop['shopName']?.toString() ?? 'Shop';
    final placeName = stop['placeName']?.toString() ?? '';

    final visitsData = VisitsData(widget.controller);
    await visitsData.load();

    if (!mounted) return;

    final retailerObj = {
      'id': retailerId,
      'name': shopName,
      'place': placeName,
    };

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VisitForm(
          data: visitsData,
        ),
      ),
    );

    if (result == true) {
      await _loadTodayRoute();
    }
  }

  Future<void> _removeStop(Map<String, dynamic> stop) async {
    final shopName = stop['shopName'] ?? 'this stop';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Stop?'),
        content: Text('Are you sure you want to remove "$shopName" from today\'s route?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xffef4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.controller.api.request('RoutePlan/remove-stop', body: {
        'userId': _effectiveUserId,
        'workDate': _workDate,
        'retailerId': stop['retailerId'],
      });
      await _loadTodayRoute();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed "$shopName" from route.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove stop: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openRoutePlannerModal() async {
    await _loadRetailersForPlanner();
    if (!mounted) return;

    final selectedIds = _stops.map((s) => s['retailerId']?.toString() ?? '').toSet();
    final TextEditingController searchCtrl = TextEditingController();
    String query = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff0f172a),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final filtered = _allRetailers.where((r) {
              if (query.isEmpty) return true;
              final name = (r['name'] ?? r['shopName'] ?? '').toString().toLowerCase();
              final code = (r['id'] ?? r['c_code'] ?? '').toString().toLowerCase();
              final place = (r['place'] ?? '').toString().toLowerCase();
              return name.contains(query) || code.contains(query) || place.contains(query);
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.alt_route_rounded, color: Color(0xff38bdf8), size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _isManagerView
                                  ? "Manage Route: ${widget.targetUserName ?? _effectiveUserId}"
                                  : "Plan Today's Route",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: searchCtrl,
                        onChanged: (val) => setModalState(() => query = val.toLowerCase().trim()),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search shops or area…',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(Icons.search, color: Colors.white54),
                          filled: true,
                          fillColor: const Color(0xff1e293b),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "${selectedIds.length} stops selected",
                            style: const TextStyle(
                              color: Color(0xff38bdf8),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (selectedIds.isNotEmpty)
                            GestureDetector(
                              onTap: () => setModalState(() => selectedIds.clear()),
                              child: const Text(
                                "Clear all",
                                style: TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _loadingRetailers
                            ? const Center(child: CircularProgressIndicator())
                            : filtered.isEmpty
                                ? const Center(
                                    child: Text(
                                      "No matching shops found.",
                                      style: TextStyle(color: Colors.white54),
                                    ),
                                  )
                                : ListView.builder(
                                    controller: scrollController,
                                    itemCount: filtered.length,
                                    itemBuilder: (context, index) {
                                      final r = filtered[index];
                                      final id = (r['id'] ?? r['c_code'] ?? '').toString();
                                      final name = (r['name'] ?? r['shopName'] ?? id).toString();
                                      final place = (r['place'] ?? '').toString();
                                      final isSelected = selectedIds.contains(id);

                                      return Container(
                                        margin: const EdgeInsets.symmetric(vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0x2238bdf8)
                                              : const Color(0xff1e293b),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isSelected
                                                ? const Color(0xff0284c7)
                                                : Colors.transparent,
                                          ),
                                        ),
                                        child: CheckboxListTile(
                                          activeColor: const Color(0xff0284c7),
                                          checkColor: Colors.white,
                                          value: isSelected,
                                          onChanged: (val) {
                                            setModalState(() {
                                              if (val == true) {
                                                selectedIds.add(id);
                                              } else {
                                                selectedIds.remove(id);
                                              }
                                            });
                                          },
                                          title: Text(
                                            name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          subtitle: Text(
                                            place.isNotEmpty ? place : id,
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff2563eb),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            setState(() => _saving = true);
                            try {
                              await widget.controller.api.request('RoutePlan/save', body: {
                                'userId': _effectiveUserId,
                                'workDate': _workDate,
                                'retailerIds': selectedIds.toList(),
                              });
                              await _loadTodayRoute();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Today's route chart updated successfully!")),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to save route: $e')),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _saving = false);
                            }
                          },
                          icon: const Icon(Icons.check_circle_outline, size: 20),
                          label: Text(
                            "Save Route (${selectedIds.length} Stops)",
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = _totalStops > 0 ? (_completedStops / _totalStops).clamp(0.0, 1.0) : 0.0;
    final percent = (progress * 100).round();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xff0b1120) : const Color(0xfff8fafc),
      appBar: AppBar(
        title: Text(
          _isManagerView
              ? "${widget.targetUserName ?? _effectiveUserId}'s Route"
              : "Daily Route Chart",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: isDark ? const Color(0xff0f172a) : Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Route',
            onPressed: _loading ? null : _loadTodayRoute,
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add_rounded),
            tooltip: 'Plan Route',
            onPressed: _openRoutePlannerModal,
          ),
          TrackyuAppBarActions(
            controller: widget.controller,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTodayRoute,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Progress Overview Card
                  _buildProgressHeader(isDark, progress, percent),
                  const SizedBox(height: 20),

                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xfffee2e2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xfffca5a5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xffdc2626)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Color(0xffb91c1c), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_stops.isEmpty)
                    _buildEmptyState(isDark)
                  else ...[
                    Row(
                      children: [
                        const Icon(Icons.directions_walk_rounded, color: Color(0xff3b82f6), size: 18),
                        const SizedBox(width: 6),
                        Text(
                          "TODAY'S JOURNEY SEQUENCE",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._buildTimelineStops(isDark),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xff2563eb),
        foregroundColor: Colors.white,
        onPressed: _openRoutePlannerModal,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: Text(_stops.isEmpty ? "Plan Route" : "Edit Route"),
      ),
    );
  }

  Widget _buildProgressHeader(bool isDark, double progress, int percent) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xff1e293b), const Color(0xff0f172a)]
              : [const Color(0xffe0f2fe), const Color(0xfff0f9ff)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xff334155) : const Color(0xffbae6fd),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xff0284c7).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.near_me_rounded, color: Color(0xff0284c7), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Route Progress",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xff0f172a),
                        ),
                      ),
                      Text(
                        _workDate.isNotEmpty ? _workDate : 'Today',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: percent == 100
                      ? const Color(0xff16a34a)
                      : const Color(0xff0284c7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "$percent% Done",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: isDark ? Colors.white12 : const Color(0xffcbd5e1),
              valueColor: AlwaysStoppedAnimation<Color>(
                percent == 100 ? const Color(0xff22c55e) : const Color(0xff0284c7),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "$_completedStops of $_totalStops Shops Visited",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xffcbd5e1) : const Color(0xff334155),
                ),
              ),
              if (_totalStops - _completedStops > 0)
                Text(
                  "${_totalStops - _completedStops} Pending",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xfff59e0b),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xff1e293b) : const Color(0xfff1f5f9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.route_rounded,
              size: 48,
              color: Color(0xff0284c7),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "No Route Planned For Today",
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xff0f172a),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Select shops to visit today to get a Rapido-style sequential journey map with instant navigation and auto-sync.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff2563eb),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _openRoutePlannerModal,
            icon: const Icon(Icons.add_rounded),
            label: const Text("Plan Today's Route", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTimelineStops(bool isDark) {
    final widgets = <Widget>[];

    for (int i = 0; i < _stops.length; i++) {
      final stop = _stops[i];
      final isLast = i == _stops.length - 1;
      final isCompleted = stop['status'] == 'Completed';
      final isInProgress = stop['status'] == 'InProgress';
      final lat = (stop['latitude'] as num?)?.toDouble();
      final lng = (stop['longitude'] as num?)?.toDouble();
      final distKm = _calculateDistance(lat, lng);
      final distStr = distKm != null
          ? (distKm < 1.0 ? "${(distKm * 1000).round()} m away" : "${distKm.toStringAsFixed(1)} km away")
          : null;

      widgets.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Timeline Pillar (Badge + Line)
              SizedBox(
                width: 44,
                child: Column(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? const Color(0xff16a34a)
                            : isInProgress
                                ? const Color(0xff0284c7)
                                : isDark
                                    ? const Color(0xff334155)
                                    : const Color(0xffe2e8f0),
                        shape: BoxShape.circle,
                        boxShadow: isInProgress
                            ? [
                                BoxShadow(
                                  color: const Color(0xff0284c7).withOpacity(0.4),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                )
                              ]
                            : null,
                      ),
                      child: Center(
                        child: isCompleted
                            ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                            : Text(
                                "${i + 1}",
                                style: TextStyle(
                                  color: isInProgress
                                      ? Colors.white
                                      : isDark
                                          ? const Color(0xffcbd5e1)
                                          : const Color(0xff334155),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: isCompleted
                              ? const Color(0xff16a34a).withOpacity(0.4)
                              : isDark
                                  ? const Color(0xff334155)
                                  : const Color(0xffcbd5e1),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Stop Card
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xff1e293b) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isCompleted
                            ? const Color(0xff16a34a).withOpacity(0.3)
                            : isInProgress
                                ? const Color(0xff0284c7).withOpacity(0.4)
                                : isDark
                                    ? const Color(0xff334155)
                                    : const Color(0xffe2e8f0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    stop['shopName'] ?? 'Shop',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xff0f172a),
                                      decoration: isCompleted ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                  if ((stop['placeName'] ?? '').toString().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        stop['placeName'],
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark
                                              ? const Color(0xff94a3b8)
                                              : const Color(0xff64748b),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isCompleted
                                    ? const Color(0x2222c55e)
                                    : isInProgress
                                        ? const Color(0x2238bdf8)
                                        : const Color(0x2294a3b8),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isCompleted
                                    ? "Completed"
                                    : isInProgress
                                        ? "In Progress"
                                        : "Planned",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isCompleted
                                      ? const Color(0xff16a34a)
                                      : isInProgress
                                          ? const Color(0xff0284c7)
                                          : const Color(0xff64748b),
                                ),
                              ),
                            ),
                          ],
                        ),

                        if ((stop['address'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 14, color: Colors.white38),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  stop['address'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],

                        if (distStr != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.near_me_outlined, size: 13, color: Color(0xff38bdf8)),
                              const SizedBox(width: 4),
                              Text(
                                distStr,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xff38bdf8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 8),

                        // Action Buttons
                        Row(
                          children: [
                            if (lat != null && lng != null)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  side: const BorderSide(color: Color(0xff38bdf8)),
                                  foregroundColor: const Color(0xff38bdf8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => _openNavigation(lat, lng, stop['shopName'] ?? ''),
                                icon: const Icon(Icons.navigation_rounded, size: 14),
                                label: const Text("Navigate", style: TextStyle(fontSize: 12)),
                              ),
                            const Spacer(),
                            if (!isCompleted)
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xff16a34a),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => _startVisitForStop(stop),
                                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                                label: const Text("Start Visit", style: TextStyle(fontSize: 12)),
                              ),
                            if (_isManagerView && !isCompleted) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xffef4444)),
                                tooltip: 'Remove from route',
                                onPressed: () => _removeStop(stop),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return widgets;
  }
}
