// ignore_for_file: deprecated_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowspace_frontend/features/designer/providers/furniture_placement_provider.dart';
import 'package:flowspace_frontend/features/designer/providers/designer_provider.dart';

// --- Helpers -----------------------------------------------------------------

DesignerLayoutState _roomWithWalls() {
  final walls = [
    Wall(start: const Offset(1800, 1800), end: const Offset(2200, 1800)),
    Wall(start: const Offset(2200, 1800), end: const Offset(2200, 2200)),
    Wall(start: const Offset(2200, 2200), end: const Offset(1800, 2200)),
    Wall(start: const Offset(1800, 2200), end: const Offset(1800, 1800)),
  ];
  return DesignerLayoutState(walls: walls);
}

class _MockAsset {
  final String id = 'A1';
  final String name = 'Test Chair';
  final double width = 80.0;
  final double depth = 80.0;
  final double height = 75.0;
  const _MockAsset();
}

class _FakeAsset {
  final String id;
  final String name;
  final double width;
  final double depth;
  final double height;
  const _FakeAsset({
    required this.id,
    required this.name,
    required double w,
    required double d,
    required double h,
  })  : width = w,
        depth = d,
        height = h;
}

// --- Tests -------------------------------------------------------------------

void main() {
  group('FurniturePlacementState', () {
    test('initial state has sensible defaults', () {
      const s = FurniturePlacementState();
      expect(s.isDraggingFromLibrary, isFalse);
      expect(s.isMovingPlaced, isFalse);
      expect(s.isAnyDragActive, isFalse);
      expect(s.snapMode, SnapMode.grid);
      expect(s.ghostWorldPos, isNull);
      expect(s.alignmentGuides, isEmpty);
      expect(s.validation.isValid, isTrue);
    });

    test('isAnyDragActive is true during library drag', () {
      const s = FurniturePlacementState(isDraggingFromLibrary: true);
      expect(s.isAnyDragActive, isTrue);
    });

    test('isAnyDragActive is true during move', () {
      const s = FurniturePlacementState(isMovingPlaced: true);
      expect(s.isAnyDragActive, isTrue);
    });

    test('copyWith clears fields via bool flags', () {
      const s = FurniturePlacementState(
        ghostWorldPos: Offset(100, 200),
        movingFurnitureId: 'X',
        recentlyPlacedId: 'Y',
      );
      final cleared = s.copyWith(
        clearGhostWorldPos: true,
        clearMovingFurnitureId: true,
        clearRecentlyPlaced: true,
      );
      expect(cleared.ghostWorldPos, isNull);
      expect(cleared.movingFurnitureId, isNull);
      expect(cleared.recentlyPlacedId, isNull);
    });
  });

  group('PlacementValidationResult', () {
    test('valid constant has isValid=true', () {
      expect(PlacementValidationResult.valid.isValid, isTrue);
      expect(PlacementValidationResult.valid.isInsideRoom, isTrue);
      expect(PlacementValidationResult.valid.hasCollision, isFalse);
    });

    test('outsideRoom constant has isValid=false', () {
      expect(PlacementValidationResult.outsideRoom.isValid, isFalse);
      expect(PlacementValidationResult.outsideRoom.isInsideRoom, isFalse);
    });
  });

  group('FurniturePlacementNotifier snap mode', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('setSnapMode changes mode', () {
      container.read(furniturePlacementProvider.notifier).setSnapMode(SnapMode.wall);
      expect(container.read(furniturePlacementProvider).snapMode, SnapMode.wall);
    });

    test('cycleSnapMode cycles through all modes and wraps', () {
      final notifier = container.read(furniturePlacementProvider.notifier);
      // Initial mode is SnapMode.grid; cycle through all 5 modes and verify wrap-around
      final startMode = container.read(furniturePlacementProvider).snapMode;
      // Cycle 5 times (total modes) — should be back to startMode
      for (int i = 0; i < SnapMode.values.length; i++) {
        notifier.cycleSnapMode();
      }
      expect(container.read(furniturePlacementProvider).snapMode, startMode);
    });
  });

  group('FurniturePlacementNotifier library drag flow', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('startLibraryDrag sets isDraggingFromLibrary and stores asset', () {
      final asset = _MockAsset();
      container.read(furniturePlacementProvider.notifier)
          .startLibraryDrag(asset, const Offset(100, 100));
      final state = container.read(furniturePlacementProvider);
      expect(state.isDraggingFromLibrary, isTrue);
      expect(state.draggingAsset, same(asset));
      expect(state.cursorScreenPos, const Offset(100, 100));
    });

    test('cancelLibraryDrag clears all drag state', () {
      final asset = _MockAsset();
      final notifier = container.read(furniturePlacementProvider.notifier);
      notifier.startLibraryDrag(asset, const Offset(100, 100));
      notifier.cancelLibraryDrag();
      final state = container.read(furniturePlacementProvider);
      expect(state.isDraggingFromLibrary, isFalse);
      expect(state.draggingAsset, isNull);
      expect(state.ghostWorldPos, isNull);
      expect(state.alignmentGuides, isEmpty);
      expect(state.validation.isValid, isTrue);
    });
  });

  group('FurniturePlacementNotifier grid snapping', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('updateLibraryDrag snaps (23,37) to (20,40)', () {
      final notifier = container.read(furniturePlacementProvider.notifier);
      final asset = _MockAsset();
      notifier.startLibraryDrag(asset, Offset.zero);
      notifier.updateLibraryDrag(
        const Offset(23, 37), const Offset(23, 37), const DesignerLayoutState());
      final state = container.read(furniturePlacementProvider);
      expect(state.ghostWorldPos, const Offset(20, 40));
      expect(state.isSnapped, isTrue);
    });

    test('no snap when mode is none', () {
      final notifier = container.read(furniturePlacementProvider.notifier);
      notifier.setSnapMode(SnapMode.none);
      final asset = _MockAsset();
      notifier.startLibraryDrag(asset, Offset.zero);
      notifier.updateLibraryDrag(
        const Offset(23, 37), const Offset(23, 37), const DesignerLayoutState());
      final state = container.read(furniturePlacementProvider);
      expect(state.ghostWorldPos, const Offset(23, 37));
      expect(state.isSnapped, isFalse);
    });
  });

  group('FurniturePlacementNotifier wall snapping', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('wall snap projects near a horizontal wall', () {
      final notifier = container.read(furniturePlacementProvider.notifier);
      notifier.setSnapMode(SnapMode.wall);
      final layout = DesignerLayoutState(walls: [
        Wall(start: const Offset(400, 500), end: const Offset(800, 500)),
      ]);
      final asset = _MockAsset();
      notifier.startLibraryDrag(asset, Offset.zero);
      notifier.updateLibraryDrag(
        const Offset(600, 520), const Offset(600, 520), layout);
      final state = container.read(furniturePlacementProvider);
      expect(state.ghostWorldPos, isNotNull);
      expect(state.ghostWorldPos!.dx, closeTo(600, 5));
    });

    test('corner snap snaps exactly to wall endpoint', () {
      final notifier = container.read(furniturePlacementProvider.notifier);
      notifier.setSnapMode(SnapMode.corner);
      final layout = DesignerLayoutState(walls: [
        Wall(start: const Offset(400, 400), end: const Offset(600, 400)),
      ]);
      final asset = _MockAsset();
      notifier.startLibraryDrag(asset, Offset.zero);
      notifier.updateLibraryDrag(
        const Offset(402, 398), const Offset(402, 398), layout);
      final state = container.read(furniturePlacementProvider);
      expect(state.ghostWorldPos, const Offset(400, 400));
    });
  });

  group('FurniturePlacementNotifier room boundary validation', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('position outside room fails validation', () {
      final notifier = container.read(furniturePlacementProvider.notifier);
      notifier.setSnapMode(SnapMode.none);
      final layout = _roomWithWalls();
      final asset = _MockAsset();
      notifier.startLibraryDrag(asset, Offset.zero);
      notifier.updateLibraryDrag(
        const Offset(100, 100), const Offset(100, 100), layout);
      final state = container.read(furniturePlacementProvider);
      expect(state.validation.isValid, isFalse);
      expect(state.validation.isInsideRoom, isFalse);
    });

    test('position inside room passes validation', () {
      final notifier = container.read(furniturePlacementProvider.notifier);
      notifier.setSnapMode(SnapMode.none);
      final layout = _roomWithWalls();
      final asset = _MockAsset();
      notifier.startLibraryDrag(asset, Offset.zero);
      notifier.updateLibraryDrag(
        const Offset(2000, 2000), const Offset(2000, 2000), layout);
      final state = container.read(furniturePlacementProvider);
      expect(state.validation.isValid, isTrue);
      expect(state.validation.isInsideRoom, isTrue);
    });
  });

  group('FurniturePlacementNotifier collision detection', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('overlapping existing furniture triggers collision', () {
      final notifier = container.read(furniturePlacementProvider.notifier);
      notifier.setSnapMode(SnapMode.none);
      final layout = DesignerLayoutState(furniture: [
        PlacedFurniture(
          id: 'sofa1', assetId: 'S', name: 'Sofa',
          width: 200, depth: 100, height: 80, x: 2000, z: 2000),
      ]);
      final asset = _MockAsset();
      notifier.startLibraryDrag(asset, Offset.zero);
      notifier.updateLibraryDrag(
        const Offset(2000, 2000), const Offset(2000, 2000), layout);
      final state = container.read(furniturePlacementProvider);
      expect(state.validation.isValid, isFalse);
      expect(state.validation.hasCollision, isTrue);
      expect(state.validation.collisionWithId, 'sofa1');
    });

    test('far from existing furniture is valid', () {
      final notifier = container.read(furniturePlacementProvider.notifier);
      notifier.setSnapMode(SnapMode.none);
      final layout = DesignerLayoutState(furniture: [
        PlacedFurniture(
          id: 'sofa1', assetId: 'S', name: 'Sofa',
          width: 200, depth: 100, height: 80, x: 2000, z: 2000),
      ]);
      final asset = _MockAsset();
      notifier.startLibraryDrag(asset, Offset.zero);
      notifier.updateLibraryDrag(
        const Offset(2600, 2600), const Offset(2600, 2600), layout);
      final state = container.read(furniturePlacementProvider);
      expect(state.validation.hasCollision, isFalse);
    });
  });

  group('FurniturePlacementNotifier ghost rotation', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('rotateGhost adds delta', () {
      final notifier = container.read(furniturePlacementProvider.notifier);
      notifier.rotateGhost(0.5);
      expect(container.read(furniturePlacementProvider).ghostRotation,
          closeTo(0.5, 0.001));
      notifier.rotateGhost(-0.2);
      expect(container.read(furniturePlacementProvider).ghostRotation,
          closeTo(0.3, 0.001));
    });

    test('setGhostRotation sets absolute angle', () {
      final notifier = container.read(furniturePlacementProvider.notifier);
      notifier.rotateGhost(1.0);
      notifier.setGhostRotation(0.0);
      expect(container.read(furniturePlacementProvider).ghostRotation, 0.0);
    });
  });

  group('FurniturePlacementNotifier move placed furniture', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('startMovingPlaced activates move state', () {
      container.read(furniturePlacementProvider.notifier)
          .startMovingPlaced('fid1', const Offset(300, 300));
      final state = container.read(furniturePlacementProvider);
      expect(state.isMovingPlaced, isTrue);
      expect(state.movingFurnitureId, 'fid1');
      expect(state.ghostWorldPos, const Offset(300, 300));
    });

    test('cancelMovingPlaced clears move state', () {
      final notifier = container.read(furniturePlacementProvider.notifier);
      notifier.startMovingPlaced('fid1', const Offset(300, 300));
      notifier.cancelMovingPlaced();
      final state = container.read(furniturePlacementProvider);
      expect(state.isMovingPlaced, isFalse);
      expect(state.movingFurnitureId, isNull);
      expect(state.ghostWorldPos, isNull);
    });

    test('updateMovingPlaced snaps to grid', () {
      final notifier = container.read(furniturePlacementProvider.notifier);
      notifier.startMovingPlaced('fid1', const Offset(300, 300));
      notifier.updateMovingPlaced(const Offset(315, 318), const DesignerLayoutState());
      final state = container.read(furniturePlacementProvider);
      expect(state.ghostWorldPos, const Offset(320, 320));
    });
  });

  group('DesignerNotifier duplicate and delete', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('addFurniture adds item and selects it', () {
      final notifier = container.read(designerProvider.notifier);
      notifier.addFurniture(
          _FakeAsset(id: 'A', name: 'Chair', w: 80, d: 80, h: 75), 2000, 2000);
      final state = container.read(designerProvider);
      expect(state.furniture, hasLength(1));
      expect(state.furniture.first.name, 'Chair');
      expect(state.selectedFurnitureId, isNotNull);
    });

    test('duplicateSelectedFurniture creates an offset copy', () {
      final notifier = container.read(designerProvider.notifier);
      notifier.addFurniture(
          _FakeAsset(id: 'A', name: 'Chair', w: 80, d: 80, h: 75), 2000, 2000);
      notifier.duplicateSelectedFurniture();
      final state = container.read(designerProvider);
      expect(state.furniture, hasLength(2));
      expect(state.furniture.last.name, contains('Copy'));
      expect(state.furniture.last.x, closeTo(2030, 1));
      expect(state.furniture.last.z, closeTo(2030, 1));
    });

    test('deleteSelected removes selected furniture', () {
      final notifier = container.read(designerProvider.notifier);
      notifier.addFurniture(
          _FakeAsset(id: 'A', name: 'Chair', w: 80, d: 80, h: 75), 2000, 2000);
      notifier.deleteSelected();
      final state = container.read(designerProvider);
      expect(state.furniture, isEmpty);
      expect(state.selectedFurnitureId, isNull);
    });
  });

  group('DesignerNotifier undo/redo with furniture', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('undo after addFurniture removes it', () {
      final notifier = container.read(designerProvider.notifier);
      notifier.addFurniture(
          _FakeAsset(id: 'A', name: 'Chair', w: 80, d: 80, h: 75), 2000, 2000);
      expect(container.read(designerProvider).furniture, hasLength(1));
      notifier.undo();
      expect(container.read(designerProvider).furniture, isEmpty);
    });

    test('redo after undo re-adds furniture', () {
      final notifier = container.read(designerProvider.notifier);
      notifier.addFurniture(
          _FakeAsset(id: 'A', name: 'Chair', w: 80, d: 80, h: 75), 2000, 2000);
      notifier.undo();
      notifier.redo();
      expect(container.read(designerProvider).furniture, hasLength(1));
    });

    test('undo after moveFurnitureTo restores position', () {
      final notifier = container.read(designerProvider.notifier);
      notifier.addFurniture(
          _FakeAsset(id: 'A', name: 'Chair', w: 80, d: 80, h: 75), 2000, 2000);
      final id = container.read(designerProvider).furniture.first.id;
      notifier.moveFurnitureTo(id, 2200, 2200);
      expect(container.read(designerProvider).furniture.first.x, closeTo(2200, 1));
      notifier.undo();
      expect(container.read(designerProvider).furniture.first.x, closeTo(2000, 1));
    });

    test('rotateFurnitureBy applies rotation delta and reverts', () {
      final notifier = container.read(designerProvider.notifier);
      notifier.addFurniture(
          _FakeAsset(id: 'A', name: 'Chair', w: 80, d: 80, h: 75), 2000, 2000);
      final id = container.read(designerProvider).furniture.first.id;
      notifier.rotateFurnitureBy(id, 3.14159 / 4);
      expect(container.read(designerProvider).furniture.first.rotationY,
          closeTo(3.14159 / 4, 0.001));
      notifier.rotateFurnitureBy(id, -(3.14159 / 4));
      expect(container.read(designerProvider).furniture.first.rotationY,
          closeTo(0.0, 0.001));
    });
  });

  group('AlignmentGuide', () {
    test('stores start and end offsets', () {
      const guide = AlignmentGuide(Offset(0, 0), Offset(100, 0));
      expect(guide.start, const Offset(0, 0));
      expect(guide.end, const Offset(100, 0));
    });
  });
}
