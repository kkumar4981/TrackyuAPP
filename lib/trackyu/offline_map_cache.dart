import 'dart:typed_data';
import 'package:flutter_map/flutter_map.dart';

/// Reuses viewed tiles offline without changing their saved HTTP expiry.
/// Route records have separate durable storage and no automatic expiry.
class OfflineMapCache implements MapCachingProvider {
  final bool Function() offline;
  final MapCachingProvider cache;
  OfflineMapCache(this.offline, {MapCachingProvider? cache})
    : cache =
          cache ??
          BuiltInMapCachingProvider.getOrCreateInstance(
            maxCacheSize: 96 * 1024 * 1024,
          );
  @override
  bool get isSupported => cache.isSupported;
  @override
  Future<CachedMapTile?> getTile(String url) async {
    try {
      final tile = await cache.getTile(url);
      if (tile == null || !offline()) return tile;
      return (
        bytes: tile.bytes,
        metadata: CachedMapTileMetadata(
          staleAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          lastModified: tile.metadata.lastModified,
          etag: tile.metadata.etag,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    try {
      await cache.putTile(url: url, metadata: metadata, bytes: bytes);
    } catch (_) {}
  }
}
