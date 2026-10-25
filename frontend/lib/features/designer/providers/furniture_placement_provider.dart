import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'designer_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  SNAP MODE ENUM
// ─────────────────────────────────────────────────────────────────────────────
enum SnapMode { none, grid, wall, corner, surface }

// ─────────────────────────────────────────────────────────────────────────────
//  PLACEMENT VALIDATION RESULT
// ─────────────────────────────────────────────────────────────────────────────
class PlacementValidationResult {
  final bool isValid;
  final bool isInsideRoom;
  final bool hasCollision;
  final bool hasErgonomicWarning;
  final String? collisionWithId;
  final String? message;

  const PlacementValidationResult({
    required this.isValid,
    required this.isInsideRoom,
    this.hasCollision = false,
    this.hasErgonomicWarning = false,
    this.collisionWithId,
    this.message,
  });

  static const PlacementValidationResult valid =
      PlacementValidationResult(isValid: true, isInsideRoom: true);
  static const PlacementValidationResult outsideRoom = PlacementValidationResult(
      isValid: false, isInsideRoom: false, message: 'Outside room boundaries');
}

// ─────────────────────────────────────────────────────────────────────────────
//  INTERNAL GUIDE
// ─────────────────────────────────────────────────────────────────────────────
class AlignmentGuide {
  final Offset start;
  final Offset end;
  const AlignmentGuide(this.start, this.end);
}

// ─────────────────────────────────────────────────────────────────────────────
//  PLACEMENT STATE
// ─────────────────────────────────────────────────────────────────────────────
class FurniturePlacementState {
  final bool isDraggingFromLibrary;
  final dynamic draggingAsset;
  final Offset? ghostWorldPos;
  final double ghostRotation;
  final Offset? cursorScreenPos;
  final SnapMode snapMode;
  final bool isSnapped;
  final double? distanceToNearestWall;
  final PlacementValidationResult validation;
  final bool isMovingPlaced;
  final String? movingFurnitureId;
  final Offset? moveStartWorldPos;
  final List<AlignmentGuide> alignmentGuides;
  final String? recentlyPlacedId;

  const FurniturePlacementState({
    this.isDraggingFromLibrary = false,
    this.draggingAsset,
    this.ghostWorldPos,
    this.ghostRotation = 0.0,
    this.cursorScreenPos,
    this.snapMode = SnapMode.grid,
    this.isSnapped = false,
    this.distanceToNearestWall,
    this.validation = PlacementValidationResult.valid,
    this.isMovingPlaced = false,
    this.movingFurnitureId,
    this.moveStartWorldPos,
    this.alignmentGuides = const [],
    this.recentlyPlacedId,
  });

  bool get isAnyDragActive => isDraggingFromLibrary || isMovingPlaced;

  FurniturePlacementState copyWith({
    bool? isDraggingFromLibrary,
    dynamic draggingAsset,
    bool clearDraggingAsset = false,
    Offset? ghostWorldPos,
    bool clearGhostWorldPos = false,
    double? ghostRotation,
    Offset? cursorScreenPos,
    bool clearCursorScreenPos = false,
    SnapMode? snapMode,
    bool? isSnapped,
    double? distanceToNearestWall,
    bool clearDistanceToWall = false,
    PlacementValidationResult? validation,
    bool? isMovingPlaced,
    String? movingFurnitureId,
    bool clearMovingFurnitureId = false,
    Offset? moveStartWorldPos,
    bool clearMoveStartWorldPos = false,
    List<AlignmentGuide>? alignmentGuides,
    String? recentlyPlacedId,
    bool clearRecentlyPlaced = false,
  }) {
    return FurniturePlacementState(
      isDraggingFromLibrary:
          isDraggingFromLibrary ?? this.isDraggingFromLibrary,
      draggingAsset:
          clearDraggingAsset ? null : (draggingAsset ?? this.draggingAsset),
      ghostWorldPos:
          clearGhostWorldPos ? null : (ghostWorldPos ?? this.ghostWorldPos),
      ghostRotation: ghostRotation ?? this.ghostRotation,
      cursorScreenPos: clearCursorScreenPos
          ? null
          : (cursorScreenPos ?? this.cursorScreenPos),
      snapMode: snapMode ?? this.snapMode,
      isSnapped: isSnapped ?? this.isSnapped,
      distanceToNearestWall: clearDistanceToWall
          ? null
          : (distanceToNearestWall ?? this.distanceToNearestWall),
      validation: validation ?? this.validation,
      isMovingPlaced: isMovingPlaced ?? this.isMovingPlaced,
      movingFurnitureId: clearMovingFurnitureId
          ? null
          : (movingFurnitureId ?? this.movingFurnitureId),
      moveStartWorldPos: clearMoveStartWorldPos
          ? null
          : (moveStartWorldPos ?? this.moveStartWorldPos),
      alignmentGuides: alignmentGuides ?? this.alignmentGuides,
      recentlyPlacedId: clearRecentlyPlaced
          ? null
          : (recentlyPlacedId ?? this.recentlyPlacedId),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PLACEMENT NOTIFIER
// ─────────────────────────────────────────────────────────────────────────────
class FurniturePlacementNotifier
    extends Notifier<FurniturePlacementState> {
  static const double _gridSize = 20.0;
  static const double _wallSnapDist = 60.0;
  static const double _cornerSnapDist = 40.0;

  @override
  FurniturePlacementState build() => const FurniturePlacementState();

  void setSnapMode(SnapMode mode) => state = state.copyWith(snapMode: mode);

  void cycleSnapMode() {
    final modes = SnapMode.values;
    final idx = (modes.indexOf(state.snapMode) + 1) % modes.length;
    state = state.copyWith(snapMode: modes[idx]);
  }

  // ── Library drag ─────────────────────────────────────────────────────────
  void startLibraryDrag(dynamic asset, Offset screenPos) {
    state = state.copyWith(
      isDraggingFromLibrary: true,
      draggingAsset: asset,
      cursorScreenPos: screenPos,
      ghostRotation: 0.0,
      validation: PlacementValidationResult.valid,
    );
  }

  void updateLibraryDrag(
      Offset screenPos, Offset worldPos, DesignerLayoutState layout) {
    final snapped = _computeSnapped(worldPos, layout);
    final distToWall = _distToNearestWall(snapped, layout);
    final rotation = _computeWallOrientation(snapped, layout);
    final guides = _computeGuides(snapped, layout);
    final validation = _validate(snapped, state.draggingAsset, null, layout);

    state = state.copyWith(
      cursorScreenPos: screenPos,
      ghostWorldPos: snapped,
      ghostRotation: rotation,
      isSnapped: snapped != worldPos,
      distanceToNearestWall: distToWall,
      alignmentGuides: guides,
      validation: validation,
    );
  }

  void cancelLibraryDrag() {
    state = state.copyWith(
      isDraggingFromLibrary: false,
      clearDraggingAsset: true,
      clearGhostWorldPos: true,
      clearCursorScreenPos: true,
      alignmentGuides: [],
      clearDistanceToWall: true,
      validation: PlacementValidationResult.valid,
    );
  }

  String? commitLibraryDrop(DesignerNotifier designerNotifier) {
    final asset = state.draggingAsset;
    final pos = state.ghostWorldPos;
    if (asset == null || pos == null || !state.validation.isValid) {
      cancelLibraryDrag();
      return null;
    }
    designerNotifier.addFurnitureWithRotation(
        asset, pos.dx, pos.dy, state.ghostRotation);
    final newId = designerNotifier.state.selectedFurnitureId;
    state = FurniturePlacementState(recentlyPlacedId: newId);
    return newId;
  }

  // ── Post-placement move ──────────────────────────────────────────────────
  void startMovingPlaced(String id, Offset worldPos) {
    state = state.copyWith(
      isMovingPlaced: true,
      movingFurnitureId: id,
      moveStartWorldPos: worldPos,
      ghostWorldPos: worldPos,
    );
  }

  void updateMovingPlaced(Offset worldPos, DesignerLayoutState layout) {
    final snapped = _computeSnapped(worldPos, layout);
    PlacedFurniture? f;
    try {
      f = layout.furniture.firstWhere((x) => x.id == state.movingFurnitureId);
    } catch (_) {}
    final validation =
        _validate(snapped, null, f, layout, excludeId: state.movingFurnitureId);

    state = state.copyWith(
      ghostWorldPos: snapped,
      isSnapped: snapped != worldPos,
      distanceToNearestWall: _distToNearestWall(snapped, layout),
      alignmentGuides: _computeGuides(snapped, layout),
      validation: validation,
    );
  }

  void commitMovingPlaced(DesignerNotifier designerNotifier) {
    final pos = state.ghostWorldPos;
    final id = state.movingFurnitureId;
    if (pos != null && id != null && state.validation.isValid) {
      designerNotifier.moveFurnitureTo(id, pos.dx, pos.dy);
    }
    _clearMoveState();
  }

  void cancelMovingPlaced() => _clearMoveState();

  void _clearMoveState() {
    state = state.copyWith(
      isMovingPlaced: false,
      clearMovingFurnitureId: true,
      clearGhostWorldPos: true,
      clearMoveStartWorldPos: true,
      alignmentGuides: [],
      clearDistanceToWall: true,
      validation: PlacementValidationResult.valid,
    );
  }

  // ── Rotation ─────────────────────────────────────────────────────────────
  void rotateGhost(double delta) =>
      state = state.copyWith(ghostRotation: state.ghostRotation + delta);

  void setGhostRotation(double rad) =>
      state = state.copyWith(ghostRotation: rad);

  void clearRecentlyPlaced() =>
      state = state.copyWith(clearRecentlyPlaced: true);

  // ─── Private helpers ──────────────────────────────────────────────────────

  Offset _computeSnapped(Offset pos, DesignerLayoutState layout) {
    switch (state.snapMode) {
      case SnapMode.none:
        return pos;
      case SnapMode.grid:
        return _snapGrid(pos);
      case SnapMode.wall:
        return _snapWall(pos, layout) ?? _snapGrid(pos);
      case SnapMode.corner:
        return _snapCorner(pos, layout) ?? _snapGrid(pos);
      case SnapMode.surface:
        return _snapGrid(pos);
    }
  }

  Offset _snapGrid(Offset p) => Offset(
        (p.dx / _gridSize).round() * _gridSize,
        (p.dy / _gridSize).round() * _gridSize,
      );

  Offset? _snapWall(Offset pos, DesignerLayoutState layout) {
    if (layout.walls.isEmpty) return null;
    Offset? best;
    double bestD = _wallSnapDist;
    for (final w in layout.walls) {
      final ab = w.end - w.start;
      final l2 = ab.distanceSquared;
      if (l2 == 0) continue;
      final t = ((pos - w.start).dx * ab.dx + (pos - w.start).dy * ab.dy) / l2;
      final proj = w.start + ab * t.clamp(0.0, 1.0);
      final d = (pos - proj).distance;
      if (d < bestD) {
        bestD = d;
        final len = sqrt(l2);
        final dir = ab / len;
        final normal = Offset(-dir.dy, dir.dx);
        best = proj + normal * 30.0;
      }
    }
    return best;
  }

  Offset? _snapCorner(Offset pos, DesignerLayoutState layout) {
    if (layout.walls.isEmpty) return null;
    Offset? best;
    double bestD = _cornerSnapDist;
    for (final w in layout.walls) {
      for (final c in [w.start, w.end]) {
        final d = (pos - c).distance;
        if (d < bestD) {
          bestD = d;
          best = c;
        }
      }
    }
    return best;
  }

  double _distToNearestWall(Offset pos, DesignerLayoutState layout) {
    if (layout.walls.isEmpty) return double.infinity;
    double minD = double.infinity;
    for (final w in layout.walls) {
      final ab = w.end - w.start;
      final l2 = ab.distanceSquared;
      if (l2 == 0) continue;
      final t = ((pos - w.start).dx * ab.dx + (pos - w.start).dy * ab.dy) / l2;
      final proj = w.start + ab * t.clamp(0.0, 1.0);
      final d = (pos - proj).distance;
      if (d < minD) minD = d;
    }
    return minD;
  }

  double _computeWallOrientation(Offset pos, DesignerLayoutState layout) {
    if (layout.walls.isEmpty) return state.ghostRotation;
    Wall? nearest;
    double minD = 200.0;
    for (final w in layout.walls) {
      final ab = w.end - w.start;
      final l2 = ab.distanceSquared;
      if (l2 == 0) continue;
      final t = ((pos - w.start).dx * ab.dx + (pos - w.start).dy * ab.dy) / l2;
      final proj = w.start + ab * t.clamp(0.0, 1.0);
      final d = (pos - proj).distance;
      if (d < minD) {
        minD = d;
        nearest = w;
      }
    }
    if (nearest != null) {
      final ab = nearest.end - nearest.start;
      return atan2(ab.dx, ab.dy);
    }
    return state.ghostRotation;
  }

  List<AlignmentGuide> _computeGuides(
      Offset pos, DesignerLayoutState layout) {
    final guides = <AlignmentGuide>[];
    const thresh = 30.0;
    for (final f in layout.furniture) {
      final fp = Offset(f.x, f.z);
      if ((pos.dy - fp.dy).abs() < thresh) {
        guides.add(AlignmentGuide(
          Offset(min(pos.dx, fp.dx) - 50, fp.dy),
          Offset(max(pos.dx, fp.dx) + 50, fp.dy),
        ));
      }
      if ((pos.dx - fp.dx).abs() < thresh) {
        guides.add(AlignmentGuide(
          Offset(fp.dx, min(pos.dy, fp.dy) - 50),
          Offset(fp.dx, max(pos.dy, fp.dy) + 50),
        ));
      }
    }
    return guides;
  }

  PlacementValidationResult _validate(
    Offset pos,
    dynamic asset,
    PlacedFurniture? furniture,
    DesignerLayoutState layout, {
    String? excludeId,
  }) {
    double width = 0, depth = 0;
    if (asset != null) {
      try {
        width = (asset.width as num).toDouble();
        depth = (asset.depth as num).toDouble();
      } catch (_) {}
    } else if (furniture != null) {
      width = furniture.width;
      depth = furniture.depth;
    }

    if (layout.walls.isNotEmpty && !_isInsideRoom(pos, layout)) {
      return PlacementValidationResult.outsideRoom;
    }

    final hw = width / 2;
    final hd = depth / 2;
    for (final f in layout.furniture) {
      if (f.id == excludeId) continue;
      final dx = (pos.dx - f.x).abs();
      final dz = (pos.dy - f.z).abs();
      if (dx < hw + f.width / 2 + 5 && dz < hd + f.depth / 2 + 5) {
        return PlacementValidationResult(
          isValid: false,
          isInsideRoom: true,
          hasCollision: true,
          collisionWithId: f.id,
          message: 'Collision with ${f.name}',
        );
      }
    }
    return PlacementValidationResult.valid;
  }

  bool _isInsideRoom(Offset point, DesignerLayoutState layout) {
    if (layout.walls.isEmpty) return true;
    final allPts = <Offset>[];
    for (final w in layout.walls) {
      allPts.add(w.start);
      allPts.add(w.end);
    }
    final minX = allPts.map((p) => p.dx).reduce(min);
    final maxX = allPts.map((p) => p.dx).reduce(max);
    final minY = allPts.map((p) => p.dy).reduce(min);
    final maxY = allPts.map((p) => p.dy).reduce(max);
    const margin = 20.0;
    return point.dx >= minX + margin &&
        point.dx <= maxX - margin &&
        point.dy >= minY + margin &&
        point.dy <= maxY - margin;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PROVIDER
// ─────────────────────────────────────────────────────────────────────────────
final furniturePlacementProvider =
    NotifierProvider<FurniturePlacementNotifier, FurniturePlacementState>(
  () => FurniturePlacementNotifier(),
);


