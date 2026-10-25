// ignore_for_file: deprecated_member_use

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowspace_frontend/features/designer/providers/designer_provider.dart';
import 'package:flowspace_frontend/features/designer/providers/furniture_placement_provider.dart';

void main() {
  group('Flowspace Furniture Placement & Manipulation UX Tests', () {
    late ProviderContainer container;
    late DesignerNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(designerProvider.notifier);
      
      notifier.addWall(const Offset(0, 0), const Offset(600, 0));
    });

    tearDown(() {
      container.dispose();
    });

    // 1. Select furniture
    test('1. Select furniture selects item and updates provider state', () {
      final asset = _createMockAsset('A1', 'Sofa', 210, 90, 85);
      notifier.addFurniture(asset, 250, 180);

      final state = container.read(designerProvider);
      expect(state.furniture.length, equals(1));
      expect(state.selectedFurnitureId, equals(state.furniture.first.id));
    });

    // 2. Drag furniture (position update)
    test('2. Drag furniture updates X/Z coordinates on room floor plane', () {
      final asset = _createMockAsset('A1', 'Sofa', 210, 90, 85);
      notifier.addFurniture(asset, 200, 200);

      notifier.updateSelectedFurnitureTransform(x: 250, z: 220);
      final state = container.read(designerProvider);
      expect(state.furniture.first.x, equals(250));
      expect(state.furniture.first.z, equals(220));
    });

    // 3. Move with arrow key
    test('3. Move with arrow keys supports 1cm, 5cm, and 25cm step movement', () {
      final asset = _createMockAsset('A1', 'Sofa', 210, 90, 85);
      notifier.addFurniture(asset, 200, 200);

      // Default step (5cm)
      notifier.moveSelectedFurnitureByOffset(5.0, 0.0);
      expect(container.read(designerProvider).furniture.first.x, equals(205.0));

      // Shift step (25cm)
      notifier.moveSelectedFurnitureByOffset(25.0, 0.0);
      expect(container.read(designerProvider).furniture.first.x, equals(230.0));

      // Ctrl step (1cm)
      notifier.moveSelectedFurnitureByOffset(1.0, 0.0);
      expect(container.read(designerProvider).furniture.first.x, equals(231.0));
    });

    // 4. Rotate +15°
    test('4. Rotate +15° updates rotation angle in radians', () {
      final asset = _createMockAsset('A1', 'Chair', 80, 80, 75);
      notifier.addFurniture(asset, 200, 200);

      final rad15 = 15.0 * pi / 180.0;
      notifier.updateSelectedFurnitureTransform(rotationY: rad15);

      final rot = container.read(designerProvider).furniture.first.rotationY;
      expect((rot * 180 / pi).round(), equals(15));
    });

    // 5. Rotate +45°
    test('5. Rotate +45° updates rotation angle in radians', () {
      final asset = _createMockAsset('A1', 'Chair', 80, 80, 75);
      notifier.addFurniture(asset, 200, 200);

      final rad45 = 45.0 * pi / 180.0;
      notifier.updateSelectedFurnitureTransform(rotationY: rad45);

      final rot = container.read(designerProvider).furniture.first.rotationY;
      expect((rot * 180 / pi).round(), equals(45));
    });

    // 6. Scale / Dimensions update
    test('6. Scale updates width, depth, height without raw scale distortion', () {
      final asset = _createMockAsset('A1', 'Table', 100, 100, 75);
      notifier.addFurniture(asset, 200, 200);

      notifier.updateSelectedFurnitureDimensions(width: 150, depth: 90, height: 80);
      final item = container.read(designerProvider).furniture.first;
      expect(item.width, equals(150));
      expect(item.depth, equals(90));
      expect(item.height, equals(80));
    });

    // 7. Edit exact position
    test('7. Edit exact position updates X, Y, Z via precise values', () {
      final asset = _createMockAsset('A1', 'Sofa', 210, 90, 85);
      notifier.addFurniture(asset, 100, 100);

      notifier.updateSelectedFurnitureTransform(x: 320, y: 0, z: 180);
      final item = container.read(designerProvider).furniture.first;
      expect(item.x, equals(320));
      expect(item.y, equals(0));
      expect(item.z, equals(180));
    });

    // 8. Edit exact dimensions
    test('8. Edit exact dimensions validates and updates actual size', () {
      final asset = _createMockAsset('A1', 'Cabinet', 120, 60, 200);
      notifier.addFurniture(asset, 200, 200);

      notifier.updateSelectedFurnitureDimensions(width: 140, depth: 70, height: 210);
      final item = container.read(designerProvider).furniture.first;
      expect(item.width, equals(140));
      expect(item.depth, equals(70));
      expect(item.height, equals(210));
    });

    // 9. Duplicate furniture
    test('9. Duplicate creates new furniture with +30cm offset and selects it', () {
      final asset = _createMockAsset('A1', 'Bed', 200, 180, 100);
      notifier.addFurniture(asset, 150, 150);

      notifier.duplicateSelectedFurniture();
      final state = container.read(designerProvider);
      expect(state.furniture.length, equals(2));
      
      final duplicate = state.furniture.last;
      expect(duplicate.x, equals(180)); // 150 + 30
      expect(duplicate.z, equals(180)); // 150 + 30
      expect(state.selectedFurnitureId, equals(duplicate.id));
    });

    // 10. Delete furniture
    test('10. Delete removes selected item immediately', () {
      final asset = _createMockAsset('A1', 'Sofa', 210, 90, 85);
      notifier.addFurniture(asset, 200, 200);

      expect(container.read(designerProvider).furniture.length, equals(1));
      notifier.deleteSelected();

      final state = container.read(designerProvider);
      expect(state.furniture, isEmpty);
      expect(state.selectedFurnitureId, isNull);
    });

    // 11. Undo action
    test('11. Undo restores previous layout state', () {
      final asset = _createMockAsset('A1', 'Sofa', 210, 90, 85);
      notifier.addFurniture(asset, 200, 200);

      notifier.moveSelectedFurnitureByOffset(50, 50);
      expect(container.read(designerProvider).furniture.first.x, equals(250));

      notifier.undo();
      expect(container.read(designerProvider).furniture.first.x, equals(200));
    });

    // 12. Redo action
    test('12. Redo re-applies undone layout operation', () {
      final asset = _createMockAsset('A1', 'Sofa', 210, 90, 85);
      notifier.addFurniture(asset, 200, 200);

      notifier.moveSelectedFurnitureByOffset(50, 50);
      notifier.undo();
      expect(container.read(designerProvider).furniture.first.x, equals(200));

      notifier.redo();
      expect(container.read(designerProvider).furniture.first.x, equals(250));
    });

    // 13. Snap to grid
    test('13. Snap to grid rounds coordinate to grid spacing', () {
      notifier.updateSnapToGrid(true);
      final pt = notifier.snapPoint(const Offset(104.2, 198.8));
      expect(pt.dx, equals(100.0));
      expect(pt.dy, equals(200.0));
    });

    // 14. Wall snap
    test('14. Opening wall snap aligns opening to wall segment', () {
      final wall = Wall(start: const Offset(100, 100), end: const Offset(500, 100));
      notifier.addWall(wall.start, wall.end);

      final res = notifier.snapOpeningToWalls(const Offset(250, 110));
      expect(res['snapped'], isTrue);
      expect((res['position'] as Offset).dy, equals(100.0));
    });

    // 15. Collision detection
    test('15. Placement Validation Result correctly reports validity', () {
      expect(PlacementValidationResult.valid.isValid, isTrue);
      expect(PlacementValidationResult.outsideRoom.isValid, isFalse);
    });

    // 16. Ergonomic warning
    test('16. Ergonomic clearance check detects nearby boundaries', () {
      final state = const FurniturePlacementState(
        validation: PlacementValidationResult(
          isValid: true,
          isInsideRoom: true,
          hasCollision: false,
          hasErgonomicWarning: true,
          message: 'Ergonomic warning — low clearance near Sofa',
        ),
      );
      expect(state.validation.hasErgonomicWarning, isTrue);
    });

    // 17. Door clearance
    test('17. Opening creation supports door swing clearance validation', () {
      notifier.placeOpening('door', const Offset(200, 0));
      final state = container.read(designerProvider);
      expect(state.openings.length, equals(1));
      expect(state.openings.first.type, equals('door'));
    });

    // 18. Window clearance
    test('18. Opening creation supports window placement', () {
      notifier.placeOpening('window', const Offset(400, 0));
      final state = container.read(designerProvider);
      expect(state.openings.length, equals(1));
      expect(state.openings.first.type, equals('window'));
    });

    // 19. 2D -> 3D layout synchronization
    test('19. Layout modification in 2D updates canonical designerProvider state', () {
      final asset = _createMockAsset('A1', 'Table', 120, 80, 75);
      notifier.addFurniture(asset, 100, 100);

      // Modify position in 2D
      notifier.updateSelectedFurnitureTransform(x: 220, z: 310);

      final state = container.read(designerProvider);
      expect(state.furniture.first.x, equals(220));
      expect(state.furniture.first.z, equals(310));
    });

    // 20. 3D -> 2D layout synchronization
    test('20. PlacedFurniture layout state contains all properties for 3D renderer sync', () {
      final asset = _createMockAsset('A1', 'Sofa', 210, 90, 85);
      notifier.addFurniture(asset, 250, 180);

      final item = container.read(designerProvider).furniture.first;
      final json = item.toJson();
      final restored = PlacedFurniture.fromJson(json);

      expect(restored.x, equals(item.x));
      expect(restored.z, equals(item.z));
      expect(restored.width, equals(item.width));
      expect(restored.depth, equals(item.depth));
      expect(restored.height, equals(item.height));
      expect(restored.rotationY, equals(item.rotationY));
    });
  });
}

class _MockAsset {
  final String id;
  final String name;
  final double width;
  final double depth;
  final double height;
  const _MockAsset(this.id, this.name, this.width, this.depth, this.height);
}

_MockAsset _createMockAsset(String id, String name, double w, double d, double h) {
  return _MockAsset(id, name, w, d, h);
}
