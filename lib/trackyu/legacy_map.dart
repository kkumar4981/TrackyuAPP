import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'offline_map_cache.dart';

/// The original tile renderer. GPS records and camera overlays remain local.
Widget legacyMapTiles({bool Function()? offline, bool darkMode = false}) =>
    TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.fieldforce.fieldforce_hrms',
      tileProvider: NetworkTileProvider(
        silenceExceptions: true,
        cachingProvider: OfflineMapCache(offline ?? () => false),
      ),
      tileBuilder: darkMode
          ? (context, tile, _) => ColorFiltered(
              colorFilter: const ColorFilter.matrix([
                -0.85,
                0,
                0,
                0,
                240,
                0,
                -0.85,
                0,
                0,
                240,
                0,
                0,
                -0.85,
                0,
                240,
                0,
                0,
                0,
                1,
                0,
              ]),
              child: tile,
            )
          : null,
    );

const legacyMapAttribution = RichAttributionWidget(
  attributions: [TextSourceAttribution('OpenStreetMap contributors')],
);
