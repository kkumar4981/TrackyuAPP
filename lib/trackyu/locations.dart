import 'legacy_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'api.dart';

LatLng? punchPoint(Json row) {
  final lat = double.tryParse('${row['latitude']}');
  final lng = double.tryParse('${row['longitude']}');
  if (lat == null ||
      lng == null ||
      !lat.isFinite ||
      !lng.isFinite ||
      lat.abs() > 90 ||
      lng.abs() > 180) {
    return null;
  }
  return LatLng(lat, lng);
}

class PunchLocationMap extends StatelessWidget {
  final List<Json> rows;
  const PunchLocationMap({super.key, required this.rows});
  @override
  Widget build(BuildContext context) {
    final points = rows.map(punchPoint).whereType<LatLng>().toList();
    if (points.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Recorded punch locations. This is not a continuous route.',
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 280,
              child: FlutterMap(
                key: ValueKey(
                  points.map((p) => '${p.latitude},${p.longitude}').join(';'),
                ),
                options: MapOptions(
                  initialCenter: points.first,
                  initialZoom: 15,
                  initialCameraFit: points.length > 1
                      ? CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(points),
                          padding: const EdgeInsets.all(32),
                          maxZoom: 16,
                        )
                      : null,
                ),
                children: [
                  legacyMapTiles(),
                  legacyMapAttribution,
                  CircleLayer(
                    circles: [
                      for (final point in points)
                        CircleMarker(
                          point: point,
                          radius: 12,
                          color: const Color(0xff1c6799).withValues(alpha: 0.15),
                          borderColor: const Color(0xff1c6799),
                          borderStrokeWidth: 1.5,
                        ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      for (final point in points)
                        Marker(
                          point: point,
                          width: 38,
                          height: 48,
                          alignment: const Alignment(0, -0.85),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                color: Color(0xff0284c7),
                                size: 44,
                              ),
                              Positioned(
                                top: 7,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.person_rounded,
                                    size: 13,
                                    color: Color(0xff0284c7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
