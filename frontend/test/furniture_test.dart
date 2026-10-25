import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowspace_frontend/features/furniture/models/furniture_asset.dart';
import 'package:flowspace_frontend/features/furniture/providers/furniture_provider.dart';

void main() {
  group('Furniture Asset Library Unit Tests', () {
    test('AssetCache operations work correctly', () {
      final cache = AssetCache();
      cache.clear();
      
      expect(cache.size, equals(0));
      expect(cache.has('test-url'), isFalse);
      expect(cache.get('test-url'), isNull);

      final dummyBytes = Uint8List.fromList([1, 2, 3, 4]);
      cache.put('test-url', dummyBytes);

      expect(cache.size, equals(1));
      expect(cache.has('test-url'), isTrue);
      expect(cache.get('test-url'), equals(dummyBytes));

      cache.clear();
      expect(cache.size, equals(0));
      expect(cache.has('test-url'), isFalse);
    });

    test('GlbMetadata parser parses valid minimal GLB correctly', () {
      // Create minimal GLB bytes structure:
      // Header: magic (4s = "glTF"), version (I = 2), totalLength (I)
      // Chunk Header: chunkLength (I), chunkType (4s = "JSON")
      // Chunk Data: JSON string bytes (padded to multiple of 4)

      final jsonStr = '{"asset":{"version":"2.0","generator":"TestGen"},"nodes":[{},{}],"meshes":[{}],"materials":[{}]}';
      final jsonBytes = utf8.encode(jsonStr);
      final padding = (4 - (jsonBytes.length % 4)) % 4;
      final paddedJsonBytes = Uint8List(jsonBytes.length + padding);
      paddedJsonBytes.setRange(0, jsonBytes.length, jsonBytes);
      if (padding > 0) {
        for (int i = jsonBytes.length; i < paddedJsonBytes.length; i++) {
          paddedJsonBytes[i] = 32; // space character padding
        }
      }

      final jsonChunkLength = paddedJsonBytes.length;
      final totalLength = 12 + 8 + jsonChunkLength;

      final glbBytes = BytesBuilder();
      
      // 1. Header (12 bytes)
      // Magic: "glTF"
      glbBytes.add(utf8.encode('glTF'));
      // Version: 2
      final versionData = ByteData(4)..setUint32(0, 2, Endian.little);
      glbBytes.add(versionData.buffer.asUint8List());
      // Total Length
      final totalLengthData = ByteData(4)..setUint32(0, totalLength, Endian.little);
      glbBytes.add(totalLengthData.buffer.asUint8List());

      // 2. Chunk 0 Header (8 bytes)
      // Chunk Length
      final chunkLengthData = ByteData(4)..setUint32(0, jsonChunkLength, Endian.little);
      glbBytes.add(chunkLengthData.buffer.asUint8List());
      // Chunk Type: "JSON"
      glbBytes.add(utf8.encode('JSON'));

      // 3. Chunk 0 Data (paddedJsonBytes)
      glbBytes.add(paddedJsonBytes);

      final fullBytes = glbBytes.toBytes();

      // Project the bytes
      final metadata = GlbMetadata.parse(fullBytes);

      expect(metadata.magic, equals('glTF'));
      expect(metadata.version, equals(2));
      expect(metadata.totalLength, equals(totalLength));
      expect(metadata.jsonChunkLength, equals(jsonChunkLength));
      expect(metadata.jsonChunkType, equals('JSON'));
      
      // Inspect parsed JSON content
      expect(metadata.gltfVersion, equals('2.0'));
      expect(metadata.generator, equals('TestGen'));
      expect(metadata.nodesCount, equals(2));
      expect(metadata.meshesCount, equals(1));
      expect(metadata.materialsCount, equals(1));
    });

    test('GlbMetadata parser throws error for invalid GLB', () {
      final invalidBytes = Uint8List.fromList(List.filled(30, 0));
      expect(
        () => GlbMetadata.parse(invalidBytes),
        throwsFormatException,
      );
    });
  });

  group('Furniture State and Model Tests', () {
    test('FurnitureCategory fromJson and toJson', () {
      final json = {'id': 'CAT001', 'name': 'Dining Room', 'description': 'Dining tables and chairs'};
      final cat = FurnitureCategory.fromJson(json);
      expect(cat.id, 'CAT001');
      expect(cat.name, 'Dining Room');
      expect(cat.description, 'Dining tables and chairs');

      final serialized = cat.toJson();
      expect(serialized['id'], 'CAT001');
      expect(serialized['name'], 'Dining Room');
      expect(serialized['description'], 'Dining tables and chairs');
    });

    test('FurnitureAsset copyWith and favorite toggle', () {
      final asset = FurnitureAsset(
        id: 'ASSET001',
        name: 'Test Chair',
        category: 'Office',
        style: 'Modern',
        width: 60.0,
        depth: 60.0,
        height: 90.0,
        clearance: 10.0,
        assemblyClearance: 10.0,
        glbUrl: '/model.glb',
        thumbnailUrl: '/thumb.png',
        createdAt: DateTime(2026, 8, 8),
        isFavorite: false,
      );

      expect(asset.isFavorite, isFalse);

      final favorited = asset.copyWith(isFavorite: true);
      expect(favorited.isFavorite, isTrue);
      expect(favorited.name, 'Test Chair');

      final renamed = asset.copyWith(name: 'Renamed Chair');
      expect(renamed.name, 'Renamed Chair');
      expect(renamed.isFavorite, isFalse);
    });

    test('FurnitureListState copyWith', () {
      const state = FurnitureListState(
        isLoading: false,
        page: 1,
        catalogMode: CatalogMode.all,
      );

      final updated = state.copyWith(
        isLoading: true,
        page: 2,
        catalogMode: CatalogMode.favorites,
      );

      expect(updated.isLoading, isTrue);
      expect(updated.page, 2);
      expect(updated.catalogMode, CatalogMode.favorites);
      expect(updated.search, ''); // preserved
    });
  });
}
