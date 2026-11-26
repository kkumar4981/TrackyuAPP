import 'dart:typed_data';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/offline_map_cache.dart';

class TileMemory implements MapCachingProvider {
  CachedMapTile? value;
  @override
  bool get isSupported => true;
  @override
  Future<CachedMapTile?> getTile(String url) async => value;
  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    value = (bytes: bytes!, metadata: metadata);
  }
}

void main() {
  test(
    'stale viewed map tiles work offline without extending saved expiry',
    () async {
      final memory = TileMemory()
        ..value = (
          bytes: Uint8List.fromList([1, 2]),
          metadata: CachedMapTileMetadata(
            staleAt: DateTime.utc(2020),
            lastModified: null,
            etag: 'a',
          ),
        );
      var offline = true;
      final cache = OfflineMapCache(() => offline, cache: memory);
      expect((await cache.getTile('tile'))!.metadata.isStale, false);
      expect(memory.value!.metadata.isStale, true);
      offline = false;
      expect((await cache.getTile('tile'))!.metadata.isStale, true);
      memory.value = null;
      expect(await cache.getTile('unseen area'), isNull);
    },
  );
}
