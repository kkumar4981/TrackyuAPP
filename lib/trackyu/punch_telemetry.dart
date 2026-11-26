import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'address_cache.dart';
import 'api.dart';

Future<String> phoneDescription() async {
  final info = DeviceInfoPlugin();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final phone = await info.androidInfo;
    return 'B : ${phone.manufacturer} ,M : ${phone.model} ,OSVer : ${phone.version.release}';
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    final phone = await info.iosInfo;
    return 'B : Apple ,M : ${phone.utsname.machine} ,OSVer : ${phone.systemVersion}';
  }
  throw UnsupportedError('Phone metadata is unavailable on this platform.');
}

class PunchTelemetryCollector {
  final Future<int> Function() battery;
  final Future<String> Function() device;
  final Future<List<Placemark>> Function(double, double) geocode;
  PunchTelemetryCollector({
    Future<int> Function()? battery,
    Future<String> Function()? device,
    Future<List<Placemark>> Function(double, double)? geocode,
  }) : battery = battery ?? (() => Battery().batteryLevel),
       device = device ?? phoneDescription,
       geocode =
           geocode ??
           ((lat, lng) => Geocoding().placemarkFromCoordinates(lat, lng));

  Future<Json> collect(double latitude, double longitude) async {
    final result = <String, dynamic>{
      'batteryPercent': null,
      'deviceInfo': null,
      'city': null,
      'address': null,
    };
    await Future.wait([
      () async {
        try {
          final value = await battery().timeout(const Duration(seconds: 2));
          if (value >= 0 && value <= 100) result['batteryPercent'] = value;
        } catch (_) {
          /* Unknown is not a zero-percent battery. */
        }
      }(),
      () async {
        try {
          final value = (await device().timeout(
            const Duration(seconds: 2),
          )).trim();
          if (value.isNotEmpty) {
            result['deviceInfo'] = value.length <= 100
                ? value
                : value.substring(0, 100);
          }
        } catch (_) {
          /* No fabricated model or OS. */
        }
      }(),
      () async {
        try {
          final places = await geocode(
            latitude,
            longitude,
          ).timeout(const Duration(seconds: 4));
          if (places.isEmpty) return;
          final place =
              places
                  .where((p) => p.locality?.trim().isNotEmpty == true)
                  .firstOrNull ??
              places.first;
          final city =
              (place.locality?.trim().isNotEmpty == true
                      ? place.locality
                      : place.subAdministrativeArea)
                  ?.trim();
          if (city != null && city.isNotEmpty && city.length <= 200) {
            result['city'] = city;
          }
          final parts =
              [
                    place.street,
                    place.subLocality,
                    place.locality,
                    place.subAdministrativeArea,
                    place.administrativeArea,
                    place.postalCode,
                    place.country,
                  ]
                  .whereType<String>()
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toSet();
          final address = parts.join(', ');
          if (address.isNotEmpty && address.length <= 2000) {
            result['address'] = address;
            TrackyuAddressCache.put(latitude, longitude, address, placeName: city);
          }
        } catch (_) {
          /* Geocoder/network failures must not invalidate a valid GPS punch. */
        }
      }(),
    ]);
    return result;
  }
}
