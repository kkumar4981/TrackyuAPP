import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';

/// Persistent coordinate-to-address store and cache.
/// Prevents redundant reverse-geocoding, shares known addresses across punches,
/// visits, recent GPS fixes, and timeline halts, and survives app restarts.
class TrackyuAddressCache {
  static final Map<String, String> _cache = {};
  static final Map<String, String> _placeNames = {};
  static bool _initialized = false;
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'trackyu.address_cache.v1';
  static Timer? _saveDebounce;

  static String _key(double lat, double lng) =>
      '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';

  static String _key3(double lat, double lng) =>
      '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final jsonStr = await _storage.read(key: _storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final data = jsonDecode(jsonStr);
        if (data is Map) {
          for (final e in data.entries) {
            final val = e.value?.toString().trim() ?? '';
            if (val.isNotEmpty &&
                val != '-' &&
                val != 'Stop location' &&
                val != 'Halt location' &&
                !val.contains('Address not loaded')) {
              _cache[e.key.toString()] = val;
            }
          }
        }
      }
    } catch (_) {}
  }

  static void put(
    double? lat,
    double? lng,
    String? address, {
    String? placeName,
  }) {
    if (lat == null || lng == null || address == null) return;
    final clean = address.trim();
    if (clean.isEmpty ||
        clean == '-' ||
        clean == 'Stop location' ||
        clean == 'Halt location' ||
        clean == 'Resolving address...' ||
        clean.contains('Address not loaded')) {
      return;
    }
    final k4 = _key(lat, lng);
    final k3 = _key3(lat, lng);
    _cache[k4] = clean;
    _cache[k3] = clean;

    if (placeName != null && placeName.trim().isNotEmpty) {
      _placeNames[k4] = placeName.trim();
      _placeNames[k3] = placeName.trim();
    }

    _scheduleSave();
  }

  /// Retrieve cached address by exact 4-decimal coordinates, 3-decimal cluster,
  /// or proximity search within 120 meters.
  static String? get(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    final k4 = _key(lat, lng);
    if (_cache.containsKey(k4)) return _cache[k4];

    final k3 = _key3(lat, lng);
    if (_cache.containsKey(k3)) return _cache[k3];

    // Proximity search within 120 meters
    const distCalc = Distance();
    final target = LatLng(lat, lng);
    for (final entry in _cache.entries) {
      final parts = entry.key.split(',');
      if (parts.length == 2) {
        final pLat = double.tryParse(parts[0]);
        final pLng = double.tryParse(parts[1]);
        if (pLat != null && pLng != null) {
          try {
            if (distCalc(target, LatLng(pLat, pLng)) <= 120.0) {
              return entry.value;
            }
          } catch (_) {}
        }
      }
    }
    return null;
  }

  static String? getPlaceName(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    final k4 = _key(lat, lng);
    if (_placeNames.containsKey(k4)) return _placeNames[k4];
    final k3 = _key3(lat, lng);
    if (_placeNames.containsKey(k3)) return _placeNames[k3];
    return null;
  }

  /// Reverse geocode on demand if not present in cache.
  static Future<String?> reverseGeocode(double lat, double lng) async {
    final cached = get(lat, lng);
    if (cached != null) return cached;
    try {
      final places = await Geocoding()
          .placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 4));
      if (places.isNotEmpty) {
        final place = places
                .where((p) => (p.locality?.trim().isNotEmpty ?? false))
                .firstOrNull ??
            places.first;
        final parts = [
          place.name,
          place.street,
          place.subLocality,
          place.locality,
          place.subAdministrativeArea,
          place.administrativeArea,
          place.postalCode,
        ]
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet();
        final address = parts.isNotEmpty
            ? parts.join(', ')
            : [place.street, place.locality]
                .whereType<String>()
                .where((s) => s.trim().isNotEmpty)
                .join(', ');
        if (address.isNotEmpty) {
          final placeName = place.subLocality ?? place.locality ?? place.name;
          put(lat, lng, address, placeName: placeName);
          return address;
        }
      }
    } catch (_) {}

    // Fallback: OpenStreetMap Nominatim reverse geocode if native geocoder failed
    try {
      final dio = Dio();
      final resp = await dio.get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'format': 'json',
          'lat': lat,
          'lon': lng,
          'zoom': 18,
          'addressdetails': 1,
        },
        options: Options(
          headers: {'User-Agent': 'Trackyu-Mobile/1.0.96'},
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );
      if (resp.data is Map && resp.data['display_name'] != null) {
        final display = resp.data['display_name'].toString().trim();
        if (display.isNotEmpty) {
          put(lat, lng, display);
          return display;
        }
      }
    } catch (_) {}

    return null;
  }

  static void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 3), () async {
      try {
        final toSave = <String, String>{};
        final entries = _cache.entries.toList();
        final start = entries.length > 250 ? entries.length - 250 : 0;
        for (var i = start; i < entries.length; i++) {
          toSave[entries[i].key] = entries[i].value;
        }
        await _storage.write(key: _storageKey, value: jsonEncode(toSave));
      } catch (_) {}
    });
  }
}
