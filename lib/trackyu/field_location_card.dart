import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'address_cache.dart';
import 'api.dart';
import 'controller.dart';
import 'duty_tracking.dart';

class FieldAttendanceLocationCard extends StatefulWidget {
  final TrackyuController controller;
  const FieldAttendanceLocationCard({super.key, required this.controller});

  @override
  State<FieldAttendanceLocationCard> createState() =>
      _FieldAttendanceLocationCardState();
}

class _FieldAttendanceLocationCardState
    extends State<FieldAttendanceLocationCard> {
  Timer? _timer;
  Json? _lastFix;
  String? _resolvedAddress;

  @override
  void initState() {
    super.initState();
    TrackyuAddressCache.init();
    widget.controller.addListener(_onController);
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _poll());
  }

  @override
  void didUpdateWidget(FieldAttendanceLocationCard old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _poll();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (mounted) setState(() {});
    _resolve();
  }

  Future<void> _poll() async {
    final c = widget.controller;
    if (c.onDuty && DutyTracker.supported) {
      try {
        final st = await DutyTracker.status();
        final fix = st['lastPoint'];
        if (fix is Map && mounted) {
          setState(() => _lastFix = Map<String, dynamic>.from(fix));
        }
      } catch (_) {}
    } else if (!c.onDuty && !c.completed) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted) {
          setState(() {
            _lastFix = {
              'latitude': last.latitude,
              'longitude': last.longitude,
              'accuracyMeters': last.accuracy,
            };
          });
        }
      } catch (_) {}
    }
    _resolve();
  }

  void _resolve() {
    final c = widget.controller;
    double? lat;
    double? lng;
    String? knownAddr;

    if (c.completed) {
      final loc = c.punchOutLocation ?? c.lastLocation;
      lat = (loc?['latitude'] as num?)?.toDouble();
      lng = (loc?['longitude'] as num?)?.toDouble();
      knownAddr =
          loc?['address']?.toString() ??
          loc?['telemetry']?['address']?.toString() ??
          loc?['telemetry']?['city']?.toString() ??
          c.attendance?['punchOutAddress']?.toString() ??
          c.attendance?['address']?.toString();
    } else {
      final loc = _lastFix ?? c.lastLocation;
      lat = (loc?['latitude'] as num?)?.toDouble();
      lng = (loc?['longitude'] as num?)?.toDouble();
      knownAddr =
          loc?['address']?.toString() ??
          loc?['telemetry']?['address']?.toString() ??
          loc?['telemetry']?['city']?.toString();
    }

    if (knownAddr != null && knownAddr.trim().isNotEmpty) {
      if (lat != null && lng != null) {
        TrackyuAddressCache.put(lat, lng, knownAddr);
      }
      if (_resolvedAddress != knownAddr && mounted) {
        setState(() => _resolvedAddress = knownAddr);
      }
      return;
    }

    if (lat != null && lng != null) {
      final cached = TrackyuAddressCache.get(lat, lng);
      if (cached != null) {
        if (_resolvedAddress != cached && mounted) {
          setState(() => _resolvedAddress = cached);
        }
        return;
      }
      try {
        Geocoding()
            .placemarkFromCoordinates(lat, lng)
            .then((places) {
              if (places.isNotEmpty) {
                final p = places.first;
                final parts =
                    [p.name, p.subLocality, p.locality, p.administrativeArea]
                        .whereType<String>()
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toSet()
                        .toList();
                final addr = parts.isNotEmpty
                    ? parts.join(', ')
                    : [p.street, p.locality]
                          .whereType<String>()
                          .where((s) => s.trim().isNotEmpty)
                          .join(', ');
                if (addr.isNotEmpty) {
                  TrackyuAddressCache.put(lat, lng, addr, placeName: p.subLocality ?? p.locality);
                  if (mounted) setState(() => _resolvedAddress = addr);
                }
              }
            })
            .catchError((_) {});
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;

    // 1. Before punch-in: show current location with punch-ready helper
    final isBeforePunch = !c.onDuty && !c.completed;

    // 2. On-Duty: CURRENT LOCATION
    // 3. Completed: LOGOUT LOCATION
    final isOut = c.completed;
    final loc = isOut
        ? (c.punchOutLocation ?? c.lastLocation)
        : (_lastFix ?? c.lastLocation);
    final lat = (loc?['latitude'] as num?)?.toDouble();
    final lng = (loc?['longitude'] as num?)?.toDouble();
    final accuracy = (loc?['accuracyMeters'] as num?)?.round();

    final locationText =
        _resolvedAddress != null && _resolvedAddress!.isNotEmpty
        ? _resolvedAddress!
        : (lat != null && lng != null
              ? '${lat.toStringAsFixed(4)}°, ${lng.toStringAsFixed(4)}°'
              : (isOut
                    ? 'Logout location recorded'
                    : 'Fetching current location...'));

    final isDark = c.isDarkMode;
    final primaryTone = isOut
        ? (isDark ? const Color(0xff94a3b8) : const Color(0xff475569))
        : (isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7));
    final bgTone = isDark
        ? const Color(0xff1e1e1e)
        : (isOut ? const Color(0xfff8fafc) : const Color(0xfff0f9ff));
    final borderTone = isDark
        ? const Color(0xff2d3135)
        : (isOut ? const Color(0xffe2e8f0) : const Color(0xffbae6fd));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: bgTone,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderTone, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: primaryTone.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: primaryTone.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              isOut ? Icons.location_off_rounded : Icons.person_pin_circle_rounded,
              size: 17,
              color: primaryTone,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isOut
                            ? const Color(0xff64748b)
                            : const Color(0xff10b981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        isOut ? 'LOGOUT LOCATION' : 'CURRENT LOCATION',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: primaryTone,
                        ),
                      ),
                    ),
                    if (accuracy != null) ...[
                      const SizedBox(width: 5),
                      Text(
                        '• ±${accuracy}m',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          color: Color(0xff64748b),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  locationText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xff1e293b),
                    height: 1.3,
                  ),
                ),
                if (isBeforePunch) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Field attendance • Punch from your current location.',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7),
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
}
