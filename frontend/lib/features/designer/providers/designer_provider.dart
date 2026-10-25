import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../project/data/project_sync_repository.dart';
import 'selection_provider.dart';

class Wall {
  Offset start;
  Offset end;
  final double thickness;

  Wall({required this.start, required this.end, this.thickness = 10.0});

  Map<String, dynamic> toJson() => {
    'x1': start.dx,
    'y1': start.dy,
    'x2': end.dx,
    'y2': end.dy,
    'thickness': thickness,
  };

  factory Wall.fromJson(Map<String, dynamic> json) => Wall(
    start: Offset((json['x1'] as num).toDouble(), (json['y1'] as num).toDouble()),
    end: Offset((json['x2'] as num).toDouble(), (json['y2'] as num).toDouble()),
    thickness: (json['thickness'] as num? ?? 10.0).toDouble(),
  );
}

class Opening {
  final String id;
  final String type; // 'door' or 'window'
  Offset position;
  double width;
  double angle; // in radians

  Opening({
    required this.id,
    required this.type,
    required this.position,
    this.width = 80.0,
    this.angle = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'x': position.dx,
    'y': position.dy,
    'width': width,
    'angle': angle,
  };

  factory Opening.fromJson(Map<String, dynamic> json) => Opening(
    id: json['id'] as String? ?? UniqueKey().toString(),
    type: json['type'] as String,
    position: Offset((json['x'] as num).toDouble(), (json['y'] as num).toDouble()),
    width: (json['width'] as num? ?? 80.0).toDouble(),
    angle: (json['angle'] as num? ?? 0.0).toDouble(),
  );
}

class PlacedFurniture {
  final String id;
  final String assetId;
  final String name;
  final double width;
  final double depth;
  final double height;
  final double x; // X position in cm
  final double y; // Y position in cm (height off floor, usually 0)
  final double z; // Z position in cm
  final double rotationX; // Rotation around X-axis in radians
  final double rotationY; // Rotation around Y-axis in radians
  final double rotationZ; // Rotation around Z-axis in radians
  final double scaleX;
  final double scaleY;
  final double scaleZ;
  final String? materialColor; // hex color
  final String? materialType; // 'wood', 'fabric', 'metal', 'plastic', etc.
  final double metallic;
  final double roughness;
  final bool isLocked;
  final bool isVisible;
  final double opacity;
  
  // Custom PBR material fields
  final String? normalMap;
  final String? baseColorMap;
  final String? roughnessMap;
  final String? metallicMap;
  final String? emissiveMap;
  final String? emissiveColor;
  final double emissiveIntensity;
  final double materialScale;
  final double materialRotation;

  PlacedFurniture({
    required this.id,
    required this.assetId,
    required this.name,
    required this.width,
    required this.depth,
    required this.height,
    required this.x,
    this.y = 0.0,
    required this.z,
    this.rotationX = 0.0,
    this.rotationY = 0.0,
    this.rotationZ = 0.0,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.scaleZ = 1.0,
    this.materialColor,
    this.materialType,
    this.metallic = 0.0,
    this.roughness = 0.5,
    this.isLocked = false,
    this.isVisible = true,
    this.opacity = 1.0,
    this.normalMap,
    this.baseColorMap,
    this.roughnessMap,
    this.metallicMap,
    this.emissiveMap,
    this.emissiveColor,
    this.emissiveIntensity = 0.0,
    this.materialScale = 1.0,
    this.materialRotation = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'assetId': assetId,
    'name': name,
    'width': width,
    'depth': depth,
    'height': height,
    'x': x,
    'y': y,
    'z': z,
    'rotationX': rotationX,
    'rotationY': rotationY,
    'rotationZ': rotationZ,
    'scaleX': scaleX,
    'scaleY': scaleY,
    'scaleZ': scaleZ,
    'materialColor': materialColor,
    'materialType': materialType,
    'metallic': metallic,
    'roughness': roughness,
    'isLocked': isLocked,
    'isVisible': isVisible,
    'opacity': opacity,
    'normalMap': normalMap,
    'baseColorMap': baseColorMap,
    'roughnessMap': roughnessMap,
    'metallicMap': metallicMap,
    'emissiveMap': emissiveMap,
    'emissiveColor': emissiveColor,
    'emissiveIntensity': emissiveIntensity,
    'materialScale': materialScale,
    'materialRotation': materialRotation,
  };

  factory PlacedFurniture.fromJson(Map<String, dynamic> json) {
    double rotY = 0.0;
    if (json.containsKey('rotationY')) {
      rotY = (json['rotationY'] as num).toDouble();
    } else if (json.containsKey('rotation_y')) {
      rotY = (json['rotation_y'] as num).toDouble();
    } else if (json.containsKey('rotation')) {
      final rotVal = (json['rotation'] as num).toDouble();
      rotY = rotVal.abs() > 2 * pi ? rotVal * pi / 180.0 : rotVal;
    }

    return PlacedFurniture(
      id: json['id'] as String? ?? json['furniture_id'] as String? ?? UniqueKey().toString(),
      assetId: json['assetId'] as String? ?? json['asset_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Furniture',
      width: (json['width'] as num? ?? 100.0).toDouble(),
      depth: (json['depth'] as num? ?? 100.0).toDouble(),
      height: (json['height'] as num? ?? 100.0).toDouble(),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num? ?? 0.0).toDouble(),
      z: (json['z'] as num).toDouble(),
      rotationX: (json['rotationX'] as num? ?? json['rotation_x'] as num? ?? 0.0).toDouble(),
      rotationY: rotY,
      rotationZ: (json['rotationZ'] as num? ?? json['rotation_z'] as num? ?? 0.0).toDouble(),
      scaleX: (json['scaleX'] as num? ?? json['scale_x'] as num? ?? 1.0).toDouble(),
      scaleY: (json['scaleY'] as num? ?? json['scale_y'] as num? ?? 1.0).toDouble(),
      scaleZ: (json['scaleZ'] as num? ?? json['scale_z'] as num? ?? 1.0).toDouble(),
      materialColor: json['materialColor'] as String? ?? json['material_color'] as String?,
      materialType: json['materialType'] as String? ?? json['material_type'] as String?,
      metallic: (json['metallic'] as num? ?? 0.0).toDouble(),
      roughness: (json['roughness'] as num? ?? 0.5).toDouble(),
      isLocked: json['isLocked'] as bool? ?? json['is_locked'] as bool? ?? false,
      isVisible: json['isVisible'] as bool? ?? json['is_visible'] as bool? ?? true,
      opacity: (json['opacity'] as num? ?? 1.0).toDouble(),
      normalMap: json['normalMap'] as String? ?? json['normal_map'] as String?,
      baseColorMap: json['baseColorMap'] as String? ?? json['base_color_map'] as String?,
      roughnessMap: json['roughnessMap'] as String? ?? json['roughness_map'] as String?,
      metallicMap: json['metallicMap'] as String? ?? json['metallic_map'] as String?,
      emissiveMap: json['emissiveMap'] as String? ?? json['emissive_map'] as String?,
      emissiveColor: json['emissiveColor'] as String? ?? json['emissive_color'] as String?,
      emissiveIntensity: (json['emissiveIntensity'] as num? ?? json['emissive_intensity'] as num? ?? 0.0).toDouble(),
      materialScale: (json['materialScale'] as num? ?? json['material_scale'] as num? ?? 1.0).toDouble(),
      materialRotation: (json['materialRotation'] as num? ?? json['material_rotation'] as num? ?? 0.0).toDouble(),
    );
  }

  PlacedFurniture copyWith({
    String? id,
    String? assetId,
    double? width,
    double? depth,
    double? height,
    double? x,
    double? y,
    double? z,
    double? rotationX,
    double? rotationY,
    double? rotationZ,
    double? scaleX,
    double? scaleY,
    double? scaleZ,
    String? materialColor,
    bool clearColor = false,
    String? materialType,
    double? metallic,
    double? roughness,
    bool? isLocked,
    bool? isVisible,
    String? name,
    double? opacity,
    String? normalMap,
    bool clearNormalMap = false,
    String? baseColorMap,
    bool clearBaseColorMap = false,
    String? roughnessMap,
    bool clearRoughnessMap = false,
    String? metallicMap,
    bool clearMetallicMap = false,
    String? emissiveMap,
    bool clearEmissiveMap = false,
    String? emissiveColor,
    bool clearEmissiveColor = false,
    double? emissiveIntensity,
    double? materialScale,
    double? materialRotation,
  }) {
    return PlacedFurniture(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      name: name ?? this.name,
      width: width ?? this.width,
      depth: depth ?? this.depth,
      height: height ?? this.height,
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      rotationX: rotationX ?? this.rotationX,
      rotationY: rotationY ?? this.rotationY,
      rotationZ: rotationZ ?? this.rotationZ,
      scaleX: scaleX ?? this.scaleX,
      scaleY: scaleY ?? this.scaleY,
      scaleZ: scaleZ ?? this.scaleZ,
      materialColor: clearColor ? null : (materialColor ?? this.materialColor),
      materialType: materialType ?? this.materialType,
      metallic: metallic ?? this.metallic,
      roughness: roughness ?? this.roughness,
      isLocked: isLocked ?? this.isLocked,
      isVisible: isVisible ?? this.isVisible,
      opacity: opacity ?? this.opacity,
      normalMap: clearNormalMap ? null : (normalMap ?? this.normalMap),
      baseColorMap: clearBaseColorMap ? null : (baseColorMap ?? this.baseColorMap),
      roughnessMap: clearRoughnessMap ? null : (roughnessMap ?? this.roughnessMap),
      metallicMap: clearMetallicMap ? null : (metallicMap ?? this.metallicMap),
      emissiveMap: clearEmissiveMap ? null : (emissiveMap ?? this.emissiveMap),
      emissiveColor: clearEmissiveColor ? null : (emissiveColor ?? this.emissiveColor),
      emissiveIntensity: emissiveIntensity ?? this.emissiveIntensity,
      materialScale: materialScale ?? this.materialScale,
      materialRotation: materialRotation ?? this.materialRotation,
    );
  }
}

enum DesignerTool { select, drawWall, placeDoor, placeWindow, pan }

enum TransformMode { select, translate, rotate, scale }

enum AlignmentType {
  left,
  right,
  top,
  bottom,
  centerX,
  centerZ,
  distributeH,
  distributeV,
}

class DesignerLayoutState {
  final List<Wall> walls;
  final List<Opening> openings;
  final List<PlacedFurniture> furniture;
  final DesignerTool tool;
  final TransformMode transformMode;
  final String? selectedWallEndpointId; // Format: "wallIndex_start" or "wallIndex_end"
  final int? selectedWallIndex;
  final String? selectedOpeningId;
  final String? selectedFurnitureId;
  final Set<String> selectedFurnitureIds;
  final bool snapToGrid;
  final double gridSpacing;
  
  // Room surface materials — floor
  final String? floorMaterialColor;
  final String? floorMaterialType;
  final double floorMetallic;
  final double floorRoughness;
  final double floorReflection;
  final double floorScale;
  final double floorRotation;
  final String? floorBaseColorMap;
  final String? floorNormalMap;
  final String? floorRoughnessMap;
  final String? floorMetallicMap;
  final String? floorEmissiveMap;
  final String? floorEmissiveColor;
  final double floorEmissiveIntensity;

  // Room surface materials — wall
  final String? wallMaterialColor;
  final String? wallMaterialType;
  final double wallMetallic;
  final double wallRoughness;
  final double wallReflection;
  final double wallScale;
  final double wallRotation;
  final String? wallBaseColorMap;
  final String? wallNormalMap;
  final String? wallRoughnessMap;
  final String? wallMetallicMap;
  final String? wallEmissiveMap;
  final String? wallEmissiveColor;
  final double wallEmissiveIntensity;

  // Room surface materials — ceiling
  final String? ceilingMaterialColor;
  final String? ceilingMaterialType;
  final double ceilingMetallic;
  final double ceilingRoughness;
  final double ceilingReflection;
  final double ceilingScale;
  final double ceilingRotation;
  final String? ceilingBaseColorMap;
  final String? ceilingNormalMap;
  final String? ceilingRoughnessMap;
  final String? ceilingMetallicMap;
  final String? ceilingEmissiveMap;
  final String? ceilingEmissiveColor;
  final double ceilingEmissiveIntensity;

  const DesignerLayoutState({
    this.walls = const [],
    this.openings = const [],
    this.furniture = const [],
    this.tool = DesignerTool.select,
    this.transformMode = TransformMode.translate,
    this.selectedWallEndpointId,
    this.selectedWallIndex,
    this.selectedOpeningId,
    this.selectedFurnitureId,
    this.selectedFurnitureIds = const {},
    this.snapToGrid = true,
    this.gridSpacing = 20.0,
    this.floorMaterialColor,
    this.floorMaterialType,
    this.floorMetallic = 0.0,
    this.floorRoughness = 0.6,
    this.floorReflection = 0.0,
    this.floorScale = 1.0,
    this.floorRotation = 0.0,
    this.floorBaseColorMap,
    this.floorNormalMap,
    this.floorRoughnessMap,
    this.floorMetallicMap,
    this.floorEmissiveMap,
    this.floorEmissiveColor,
    this.floorEmissiveIntensity = 0.0,
    this.wallMaterialColor,
    this.wallMaterialType,
    this.wallMetallic = 0.0,
    this.wallRoughness = 0.8,
    this.wallReflection = 0.0,
    this.wallScale = 1.0,
    this.wallRotation = 0.0,
    this.wallBaseColorMap,
    this.wallNormalMap,
    this.wallRoughnessMap,
    this.wallMetallicMap,
    this.wallEmissiveMap,
    this.wallEmissiveColor,
    this.wallEmissiveIntensity = 0.0,
    this.ceilingMaterialColor,
    this.ceilingMaterialType,
    this.ceilingMetallic = 0.0,
    this.ceilingRoughness = 0.9,
    this.ceilingReflection = 0.0,
    this.ceilingScale = 1.0,
    this.ceilingRotation = 0.0,
    this.ceilingBaseColorMap,
    this.ceilingNormalMap,
    this.ceilingRoughnessMap,
    this.ceilingMetallicMap,
    this.ceilingEmissiveMap,
    this.ceilingEmissiveColor,
    this.ceilingEmissiveIntensity = 0.0,
  });

  DesignerLayoutState copyWith({
    List<Wall>? walls,
    List<Opening>? openings,
    List<PlacedFurniture>? furniture,
    DesignerTool? tool,
    TransformMode? transformMode,
    String? selectedWallEndpointId,
    bool clearWallEndpoint = false,
    int? selectedWallIndex,
    bool clearWall = false,
    String? selectedOpeningId,
    bool clearOpening = false,
    String? selectedFurnitureId,
    Set<String>? selectedFurnitureIds,
    bool clearFurniture = false,
    bool clearSelectedFurnitureIds = false,
    bool? snapToGrid,
    double? gridSpacing,
    // Floor
    String? floorMaterialColor,
    bool clearFloorColor = false,
    String? floorMaterialType,
    double? floorMetallic,
    double? floorRoughness,
    double? floorReflection,
    double? floorScale,
    double? floorRotation,
    String? floorBaseColorMap,
    bool clearFloorBaseColorMap = false,
    String? floorNormalMap,
    bool clearFloorNormalMap = false,
    String? floorRoughnessMap,
    bool clearFloorRoughnessMap = false,
    String? floorMetallicMap,
    bool clearFloorMetallicMap = false,
    String? floorEmissiveMap,
    bool clearFloorEmissiveMap = false,
    String? floorEmissiveColor,
    bool clearFloorEmissiveColor = false,
    double? floorEmissiveIntensity,
    // Wall
    String? wallMaterialColor,
    bool clearWallColor = false,
    String? wallMaterialType,
    double? wallMetallic,
    double? wallRoughness,
    double? wallReflection,
    double? wallScale,
    double? wallRotation,
    String? wallBaseColorMap,
    bool clearWallBaseColorMap = false,
    String? wallNormalMap,
    bool clearWallNormalMap = false,
    String? wallRoughnessMap,
    bool clearWallRoughnessMap = false,
    String? wallMetallicMap,
    bool clearWallMetallicMap = false,
    String? wallEmissiveMap,
    bool clearWallEmissiveMap = false,
    String? wallEmissiveColor,
    bool clearWallEmissiveColor = false,
    double? wallEmissiveIntensity,
    // Ceiling
    String? ceilingMaterialColor,
    bool clearCeilingColor = false,
    String? ceilingMaterialType,
    double? ceilingMetallic,
    double? ceilingRoughness,
    double? ceilingReflection,
    double? ceilingScale,
    double? ceilingRotation,
    String? ceilingBaseColorMap,
    bool clearCeilingBaseColorMap = false,
    String? ceilingNormalMap,
    bool clearCeilingNormalMap = false,
    String? ceilingRoughnessMap,
    bool clearCeilingRoughnessMap = false,
    String? ceilingMetallicMap,
    bool clearCeilingMetallicMap = false,
    String? ceilingEmissiveMap,
    bool clearCeilingEmissiveMap = false,
    String? ceilingEmissiveColor,
    bool clearCeilingEmissiveColor = false,
    double? ceilingEmissiveIntensity,
  }) {
    return DesignerLayoutState(
      walls: walls ?? this.walls,
      openings: openings ?? this.openings,
      furniture: furniture ?? this.furniture,
      tool: tool ?? this.tool,
      transformMode: transformMode ?? this.transformMode,
      selectedWallIndex: clearWall ? null : (selectedWallIndex ?? this.selectedWallIndex),
      selectedOpeningId: clearOpening ? null : (selectedOpeningId ?? this.selectedOpeningId),
      selectedFurnitureId: clearFurniture ? null : (selectedFurnitureId ?? this.selectedFurnitureId),
      selectedFurnitureIds: clearFurniture || clearSelectedFurnitureIds
          ? const {}
          : (selectedFurnitureIds ?? (selectedFurnitureId != null ? {selectedFurnitureId} : this.selectedFurnitureIds)),
      snapToGrid: snapToGrid ?? this.snapToGrid,
      gridSpacing: gridSpacing ?? this.gridSpacing,
      // Floor
      floorMaterialColor: clearFloorColor ? null : (floorMaterialColor ?? this.floorMaterialColor),
      floorMaterialType: floorMaterialType ?? this.floorMaterialType,
      floorMetallic: floorMetallic ?? this.floorMetallic,
      floorRoughness: floorRoughness ?? this.floorRoughness,
      floorReflection: floorReflection ?? this.floorReflection,
      floorScale: floorScale ?? this.floorScale,
      floorRotation: floorRotation ?? this.floorRotation,
      floorBaseColorMap: clearFloorBaseColorMap ? null : (floorBaseColorMap ?? this.floorBaseColorMap),
      floorNormalMap: clearFloorNormalMap ? null : (floorNormalMap ?? this.floorNormalMap),
      floorRoughnessMap: clearFloorRoughnessMap ? null : (floorRoughnessMap ?? this.floorRoughnessMap),
      floorMetallicMap: clearFloorMetallicMap ? null : (floorMetallicMap ?? this.floorMetallicMap),
      floorEmissiveMap: clearFloorEmissiveMap ? null : (floorEmissiveMap ?? this.floorEmissiveMap),
      floorEmissiveColor: clearFloorEmissiveColor ? null : (floorEmissiveColor ?? this.floorEmissiveColor),
      floorEmissiveIntensity: floorEmissiveIntensity ?? this.floorEmissiveIntensity,
      // Wall
      wallMaterialColor: clearWallColor ? null : (wallMaterialColor ?? this.wallMaterialColor),
      wallMaterialType: wallMaterialType ?? this.wallMaterialType,
      wallMetallic: wallMetallic ?? this.wallMetallic,
      wallRoughness: wallRoughness ?? this.wallRoughness,
      wallReflection: wallReflection ?? this.wallReflection,
      wallScale: wallScale ?? this.wallScale,
      wallRotation: wallRotation ?? this.wallRotation,
      wallBaseColorMap: clearWallBaseColorMap ? null : (wallBaseColorMap ?? this.wallBaseColorMap),
      wallNormalMap: clearWallNormalMap ? null : (wallNormalMap ?? this.wallNormalMap),
      wallRoughnessMap: clearWallRoughnessMap ? null : (wallRoughnessMap ?? this.wallRoughnessMap),
      wallMetallicMap: clearWallMetallicMap ? null : (wallMetallicMap ?? this.wallMetallicMap),
      wallEmissiveMap: clearWallEmissiveMap ? null : (wallEmissiveMap ?? this.wallEmissiveMap),
      wallEmissiveColor: clearWallEmissiveColor ? null : (wallEmissiveColor ?? this.wallEmissiveColor),
      wallEmissiveIntensity: wallEmissiveIntensity ?? this.wallEmissiveIntensity,
      // Ceiling
      ceilingMaterialColor: clearCeilingColor ? null : (ceilingMaterialColor ?? this.ceilingMaterialColor),
      ceilingMaterialType: ceilingMaterialType ?? this.ceilingMaterialType,
      ceilingMetallic: ceilingMetallic ?? this.ceilingMetallic,
      ceilingRoughness: ceilingRoughness ?? this.ceilingRoughness,
      ceilingReflection: ceilingReflection ?? this.ceilingReflection,
      ceilingScale: ceilingScale ?? this.ceilingScale,
      ceilingRotation: ceilingRotation ?? this.ceilingRotation,
      ceilingBaseColorMap: clearCeilingBaseColorMap ? null : (ceilingBaseColorMap ?? this.ceilingBaseColorMap),
      ceilingNormalMap: clearCeilingNormalMap ? null : (ceilingNormalMap ?? this.ceilingNormalMap),
      ceilingRoughnessMap: clearCeilingRoughnessMap ? null : (ceilingRoughnessMap ?? this.ceilingRoughnessMap),
      ceilingMetallicMap: clearCeilingMetallicMap ? null : (ceilingMetallicMap ?? this.ceilingMetallicMap),
      ceilingEmissiveMap: clearCeilingEmissiveMap ? null : (ceilingEmissiveMap ?? this.ceilingEmissiveMap),
      ceilingEmissiveColor: clearCeilingEmissiveColor ? null : (ceilingEmissiveColor ?? this.ceilingEmissiveColor),
      ceilingEmissiveIntensity: ceilingEmissiveIntensity ?? this.ceilingEmissiveIntensity,
    );
  }

  double get roomWidth {
    if (walls.isEmpty) return 400.0;
    double maxW = 0.0;
    for (final w in walls) {
      if (w.start.dx > maxW) maxW = w.start.dx;
      if (w.end.dx > maxW) maxW = w.end.dx;
    }
    return maxW > 0 ? maxW : 400.0;
  }

  double get roomLength {
    if (walls.isEmpty) return 500.0;
    double maxL = 0.0;
    for (final w in walls) {
      if (w.start.dy > maxL) maxL = w.start.dy;
      if (w.end.dy > maxL) maxL = w.end.dy;
    }
    return maxL > 0 ? maxL : 500.0;
  }

  Set<int> get collisionIndices {
    final Set<int> indices = {};
    for (int i = 0; i < furniture.length; i++) {
      final a = furniture[i];
      final aCos = cos(a.rotationY).abs();
      final aSin = sin(a.rotationY).abs();
      final aHalfW = (a.width * aCos + a.depth * aSin) / 2.0;
      final aHalfD = (a.width * aSin + a.depth * aCos) / 2.0;

      for (int j = i + 1; j < furniture.length; j++) {
        final b = furniture[j];
        final bCos = cos(b.rotationY).abs();
        final bSin = sin(b.rotationY).abs();
        final bHalfW = (b.width * bCos + b.depth * bSin) / 2.0;
        final bHalfD = (b.width * bSin + b.depth * bCos) / 2.0;

        final dx = (a.x - b.x).abs();
        final dz = (a.z - b.z).abs();

        if (dx < (aHalfW + bHalfW - 2.0) && dz < (aHalfD + bHalfD - 2.0)) {
          indices.add(i);
          indices.add(j);
        }
      }
    }
    return indices;
  }
}

class DesignerNotifier extends Notifier<DesignerLayoutState> {
  final ProjectSyncRepository _syncRepository = ProjectSyncRepository();
  
  // Undo/Redo stacks
  final List<List<Wall>> _undoWallStack = [];
  final List<List<Opening>> _undoOpeningStack = [];
  final List<List<PlacedFurniture>> _undoFurnitureStack = [];
  final List<List<Wall>> _redoWallStack = [];
  final List<List<Opening>> _redoOpeningStack = [];
  final List<List<PlacedFurniture>> _redoFurnitureStack = [];

  // Dragging reference state
  List<Wall> _dragStartWalls = [];
  List<Opening> _dragStartOpenings = [];
  Offset? _dragStartScenePos;
  final List<PlacedFurniture> _furnitureClipboard = [];

  @override
  DesignerLayoutState build() {
    return const DesignerLayoutState();
  }

  void pushUndo() {
    _pushHistory();
  }

  void applyFixCorrection({
    required String furnitureId,
    required double proposedX,
    required double proposedZ,
    required double proposedRotation,
  }) {
    pushUndo();
    final updatedList = state.furniture.map((f) {
      if (f.id == furnitureId) {
        return f.copyWith(
          x: proposedX,
          z: proposedZ,
          rotationY: proposedRotation,
        );
      }
      return f;
    }).toList();

    state = state.copyWith(
      furniture: updatedList,
      selectedFurnitureId: furnitureId,
    );
  }

  @visibleForTesting
  void setFurnitureListForTesting(List<PlacedFurniture> list) {
    state = state.copyWith(furniture: list);
  }

  void _pushHistory() {
    final wallsCopy = state.walls.map((w) => Wall(start: w.start, end: w.end, thickness: w.thickness)).toList();
    final openingsCopy = state.openings.map((o) => Opening(id: o.id, type: o.type, position: o.position, width: o.width, angle: o.angle)).toList();
    final furnitureCopy = state.furniture.map((f) => f.copyWith()).toList();
    
    _undoWallStack.add(wallsCopy);
    _undoOpeningStack.add(openingsCopy);
    _undoFurnitureStack.add(furnitureCopy);
    
    _redoWallStack.clear();
    _redoOpeningStack.clear();
    _redoFurnitureStack.clear();
  }

  void undo() {
    if (_undoWallStack.isNotEmpty) {
      final currentWallsCopy = state.walls.map((w) => Wall(start: w.start, end: w.end, thickness: w.thickness)).toList();
      final currentOpeningsCopy = state.openings.map((o) => Opening(id: o.id, type: o.type, position: o.position, width: o.width, angle: o.angle)).toList();
      final currentFurnitureCopy = state.furniture.map((f) => f.copyWith()).toList();
      
      _redoWallStack.add(currentWallsCopy);
      _redoOpeningStack.add(currentOpeningsCopy);
      _redoFurnitureStack.add(currentFurnitureCopy);

      final prevWalls = _undoWallStack.removeLast();
      final prevOpenings = _undoOpeningStack.removeLast();
      final prevFurniture = _undoFurnitureStack.removeLast();
      
      state = state.copyWith(
        walls: prevWalls,
        openings: prevOpenings,
        furniture: prevFurniture,
        clearWallEndpoint: true,
        clearWall: true,
        clearOpening: true,
        clearFurniture: true,
      );
    }
  }

  void redo() {
    if (_redoWallStack.isNotEmpty) {
      final currentWallsCopy = state.walls.map((w) => Wall(start: w.start, end: w.end, thickness: w.thickness)).toList();
      final currentOpeningsCopy = state.openings.map((o) => Opening(id: o.id, type: o.type, position: o.position, width: o.width, angle: o.angle)).toList();
      final currentFurnitureCopy = state.furniture.map((f) => f.copyWith()).toList();
      
      _undoWallStack.add(currentWallsCopy);
      _undoOpeningStack.add(currentOpeningsCopy);
      _undoFurnitureStack.add(currentFurnitureCopy);

      final nextWalls = _redoWallStack.removeLast();
      final nextOpenings = _redoOpeningStack.removeLast();
      final nextFurniture = _redoFurnitureStack.removeLast();

      state = state.copyWith(
        walls: nextWalls,
        openings: nextOpenings,
        furniture: nextFurniture,
        clearWallEndpoint: true,
        clearWall: true,
        clearOpening: true,
        clearFurniture: true,
      );
    }
  }

  Future<void> loadLayout(String roomId) async {
    try {
      final room = await _syncRepository.getRoomDetails(roomId);
      final props = room['properties'] as String?;
      Map<String, dynamic> decoded = {};
      if (props != null && props.isNotEmpty) {
        try {
          decoded = jsonDecode(props) as Map<String, dynamic>;
        } catch (_) {}
      }

      List<Wall> loadedWalls = [];
      List<Opening> loadedOpenings = [];
      List<PlacedFurniture> loadedFurniture = [];

      if (decoded.containsKey('walls') && (decoded['walls'] as List).isNotEmpty) {
        final wallsJson = decoded['walls'] as List<dynamic>? ?? [];
        loadedWalls = wallsJson.map((w) => Wall.fromJson(w as Map<String, dynamic>)).toList();
      }

      if (decoded.containsKey('openings')) {
        final openingsJson = decoded['openings'] as List<dynamic>? ?? [];
        loadedOpenings = openingsJson.map((o) => Opening.fromJson(o as Map<String, dynamic>)).toList();
      }

      if (decoded.containsKey('furniture')) {
        final furnitureJson = decoded['furniture'] as List<dynamic>? ?? [];
        loadedFurniture = furnitureJson.map((f) => PlacedFurniture.fromJson(f as Map<String, dynamic>)).toList();
      }

      // If walls are missing or empty, procedurally generate dimension-matched boundary walls & openings
      if (loadedWalls.isEmpty) {
        final measurements = room['measurements'] as Map<String, dynamic>?;
        double length = 600.0;
        double width = 450.0;
        if (measurements != null) {
          length = (measurements['length'] as num? ?? 600.0).toDouble();
          width = (measurements['width'] as num? ?? 450.0).toDouble();
        }
        if (length <= 0) length = 600.0;
        if (width <= 0) width = 450.0;

        loadedWalls = [
          Wall(start: const Offset(0, 0), end: Offset(width, 0)),
          Wall(start: Offset(width, 0), end: Offset(width, length)),
          Wall(start: Offset(width, length), end: Offset(0, length)),
          Wall(start: Offset(0, length), end: const Offset(0, 0)),
        ];

        if (loadedOpenings.isEmpty) {
          // Door on bottom wall
          loadedOpenings.add(Opening(
            id: 'door_main',
            type: 'door',
            position: Offset(width / 2, length),
            width: 80.0,
            angle: 0.0,
          ));
          // Window on top wall
          loadedOpenings.add(Opening(
            id: 'window_main',
            type: 'window',
            position: Offset(width / 2, 0),
            width: 120.0,
            angle: 0.0,
          ));
        }
      }

      state = state.copyWith(
        walls: loadedWalls,
        openings: loadedOpenings,
        furniture: loadedFurniture,
        floorMaterialColor: decoded['floorMaterialColor'] as String?,
        floorMaterialType: decoded['floorMaterialType'] as String?,
        floorMetallic: (decoded['floorMetallic'] as num?)?.toDouble() ?? 0.0,
        floorRoughness: (decoded['floorRoughness'] as num?)?.toDouble() ?? 0.6,
        floorBaseColorMap: decoded['floorBaseColorMap'] as String?,
        floorNormalMap: decoded['floorNormalMap'] as String?,
        floorRoughnessMap: decoded['floorRoughnessMap'] as String?,
        floorMetallicMap: decoded['floorMetallicMap'] as String?,
        floorEmissiveMap: decoded['floorEmissiveMap'] as String?,
        floorEmissiveColor: decoded['floorEmissiveColor'] as String?,
        floorEmissiveIntensity: (decoded['floorEmissiveIntensity'] as num?)?.toDouble() ?? 0.0,
        wallMaterialColor: decoded['wallMaterialColor'] as String?,
        wallMaterialType: decoded['wallMaterialType'] as String?,
        wallMetallic: (decoded['wallMetallic'] as num?)?.toDouble() ?? 0.0,
        wallRoughness: (decoded['wallRoughness'] as num?)?.toDouble() ?? 0.8,
        wallBaseColorMap: decoded['wallBaseColorMap'] as String?,
        wallNormalMap: decoded['wallNormalMap'] as String?,
        wallRoughnessMap: decoded['wallRoughnessMap'] as String?,
        wallMetallicMap: decoded['wallMetallicMap'] as String?,
        wallEmissiveMap: decoded['wallEmissiveMap'] as String?,
        wallEmissiveColor: decoded['wallEmissiveColor'] as String?,
        wallEmissiveIntensity: (decoded['wallEmissiveIntensity'] as num?)?.toDouble() ?? 0.0,
        ceilingMaterialColor: decoded['ceilingMaterialColor'] as String?,
        ceilingMaterialType: decoded['ceilingMaterialType'] as String?,
        ceilingMetallic: (decoded['ceilingMetallic'] as num?)?.toDouble() ?? 0.0,
        ceilingRoughness: (decoded['ceilingRoughness'] as num?)?.toDouble() ?? 0.9,
        ceilingBaseColorMap: decoded['ceilingBaseColorMap'] as String?,
        ceilingNormalMap: decoded['ceilingNormalMap'] as String?,
        ceilingRoughnessMap: decoded['ceilingRoughnessMap'] as String?,
        ceilingMetallicMap: decoded['ceilingMetallicMap'] as String?,
        ceilingEmissiveMap: decoded['ceilingEmissiveMap'] as String?,
        ceilingEmissiveColor: decoded['ceilingEmissiveColor'] as String?,
        ceilingEmissiveIntensity: (decoded['ceilingEmissiveIntensity'] as num?)?.toDouble() ?? 0.0,
        clearWallEndpoint: true,
        clearWall: true,
        clearOpening: true,
        clearFurniture: true,
      );
    } catch (_) {
      state = const DesignerLayoutState();
    }
  }

  Future<bool> saveLayout(String roomId) async {
    try {
      // Load existing properties to preserve all AI metadata and existing keys
      Map<String, dynamic> existingProps = {};
      try {
        final room = await _syncRepository.getRoomDetails(roomId);
        final props = room['properties'] as String?;
        if (props != null && props.isNotEmpty) {
          existingProps = jsonDecode(props) as Map<String, dynamic>;
        }
      } catch (_) {}

      final layoutData = Map<String, dynamic>.from(existingProps);
      layoutData['walls'] = state.walls.map((w) => w.toJson()).toList();
      layoutData['openings'] = state.openings.map((o) => o.toJson()).toList();
      layoutData['furniture'] = state.furniture.map((f) => f.toJson()).toList();
      layoutData['floorMaterialColor'] = state.floorMaterialColor;
      layoutData['floorMaterialType'] = state.floorMaterialType;
      layoutData['floorMetallic'] = state.floorMetallic;
      layoutData['floorRoughness'] = state.floorRoughness;
      layoutData['floorBaseColorMap'] = state.floorBaseColorMap;
      layoutData['floorNormalMap'] = state.floorNormalMap;
      layoutData['floorRoughnessMap'] = state.floorRoughnessMap;
      layoutData['floorMetallicMap'] = state.floorMetallicMap;
      layoutData['floorEmissiveMap'] = state.floorEmissiveMap;
      layoutData['floorEmissiveColor'] = state.floorEmissiveColor;
      layoutData['floorEmissiveIntensity'] = state.floorEmissiveIntensity;
      layoutData['wallMaterialColor'] = state.wallMaterialColor;
      layoutData['wallMaterialType'] = state.wallMaterialType;
      layoutData['wallMetallic'] = state.wallMetallic;
      layoutData['wallRoughness'] = state.wallRoughness;
      layoutData['wallBaseColorMap'] = state.wallBaseColorMap;
      layoutData['wallNormalMap'] = state.wallNormalMap;
      layoutData['wallRoughnessMap'] = state.wallRoughnessMap;
      layoutData['wallMetallicMap'] = state.wallMetallicMap;
      layoutData['wallEmissiveMap'] = state.wallEmissiveMap;
      layoutData['wallEmissiveColor'] = state.wallEmissiveColor;
      layoutData['wallEmissiveIntensity'] = state.wallEmissiveIntensity;
      layoutData['ceilingMaterialColor'] = state.ceilingMaterialColor;
      layoutData['ceilingMaterialType'] = state.ceilingMaterialType;
      layoutData['ceilingMetallic'] = state.ceilingMetallic;
      layoutData['ceilingRoughness'] = state.ceilingRoughness;
      layoutData['ceilingBaseColorMap'] = state.ceilingBaseColorMap;
      layoutData['ceilingNormalMap'] = state.ceilingNormalMap;
      layoutData['ceilingRoughnessMap'] = state.ceilingRoughnessMap;
      layoutData['ceilingMetallicMap'] = state.ceilingMetallicMap;
      layoutData['ceilingEmissiveMap'] = state.ceilingEmissiveMap;
      layoutData['ceilingEmissiveColor'] = state.ceilingEmissiveColor;
      layoutData['ceilingEmissiveIntensity'] = state.ceilingEmissiveIntensity;

      final encoded = jsonEncode(layoutData);
      await _syncRepository.updateRoom(roomId, properties: encoded);
      return true;
    } catch (_) {
      return false;
    }
  }

  void selectTool(DesignerTool tool) {
    state = state.copyWith(
      tool: tool,
      clearWallEndpoint: true,
      clearWall: true,
      clearOpening: true,
      clearFurniture: true,
    );
  }

  void setTransformMode(TransformMode mode) {
    state = state.copyWith(transformMode: mode);
  }

  void updateSnapToGrid(bool snap) {
    state = state.copyWith(snapToGrid: snap);
  }

  Offset snapPoint(Offset p) {
    if (!state.snapToGrid) return p;
    final grid = state.gridSpacing;
    final x = (p.dx / grid).round() * grid;
    final y = (p.dy / grid).round() * grid;
    return Offset(x, y);
  }

  Map<String, dynamic> snapOpeningToWalls(Offset point, {double maxDistance = 50.0}) {
    if (state.walls.isEmpty) {
      return {'position': point, 'angle': 0.0, 'snapped': false};
    }

    Offset bestPoint = point;
    double bestAngle = 0.0;
    double minDistance = double.infinity;

    for (final wall in state.walls) {
      final a = wall.start;
      final b = wall.end;
      final ab = b - a;
      final l2 = ab.distanceSquared;
      if (l2 == 0) continue;

      final t = ((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / l2;
      final clampedT = t.clamp(0.0, 1.0);
      final projection = a + ab * clampedT;

      final dist = (point - projection).distance;
      if (dist < minDistance) {
        minDistance = dist;
        bestPoint = projection;
        bestAngle = atan2(ab.dy, ab.dx);
      }
    }

    if (minDistance <= maxDistance) {
      return {'position': bestPoint, 'angle': bestAngle, 'snapped': true};
    }

    return {'position': point, 'angle': 0.0, 'snapped': false};
  }

  void addWall(Offset start, Offset end) {
    _pushHistory();
    final newWall = Wall(start: snapPoint(start), end: snapPoint(end));
    state = state.copyWith(walls: [...state.walls, newWall]);
  }

  void selectWallEndpoint(int wallIndex, bool isStart) {
    state = state.copyWith(
      selectedWallEndpointId: "${wallIndex}_${isStart ? 'start' : 'end'}",
      clearWall: true,
      clearOpening: true,
      clearFurniture: true,
    );
    ref.read(selectionProvider.notifier).selectElement('wall_endpoint');
  }

  void selectWall(int index) {
    state = state.copyWith(
      selectedWallIndex: index,
      clearWallEndpoint: true,
      clearOpening: true,
      clearFurniture: true,
    );
    ref.read(selectionProvider.notifier).selectElement('wall');
  }

  void startDragging(Offset scenePos) {
    _dragStartScenePos = scenePos;
    _dragStartWalls = state.walls.map((w) => Wall(start: w.start, end: w.end, thickness: w.thickness)).toList();
    _dragStartOpenings = state.openings.map((o) => Opening(id: o.id, type: o.type, position: o.position, width: o.width, angle: o.angle)).toList();
  }

  void moveWallEndpoint(Offset newPosition) {
    if (state.selectedWallEndpointId == null) return;
    
    final parts = state.selectedWallEndpointId!.split('_');
    final index = int.parse(parts[0]);
    final isStart = parts[1] == 'start';

    final snapped = snapPoint(newPosition);
    final updatedWalls = List<Wall>.from(state.walls);
    
    final originalWall = _dragStartWalls.length > index ? _dragStartWalls[index] : state.walls[index];
    
    if (isStart) {
      updatedWalls[index] = Wall(start: snapped, end: originalWall.end, thickness: originalWall.thickness);
    } else {
      updatedWalls[index] = Wall(start: originalWall.start, end: snapped, thickness: originalWall.thickness);
    }

    state = state.copyWith(walls: updatedWalls);
  }

  void moveSelectedWall(Offset newPosition) {
    if (state.selectedWallIndex == null || _dragStartScenePos == null) return;
    
    final index = state.selectedWallIndex!;
    if (index >= _dragStartWalls.length) return;
    
    final originalWall = _dragStartWalls[index];
    final delta = newPosition - _dragStartScenePos!;
    
    final newStart = snapPoint(originalWall.start + delta);
    final newEnd = snapPoint(originalWall.end + delta);
    
    final updatedWalls = List<Wall>.from(state.walls);
    updatedWalls[index] = Wall(start: newStart, end: newEnd, thickness: originalWall.thickness);
    
    state = state.copyWith(walls: updatedWalls);
  }

  void updateSelectedWallThickness(double thickness) {
    if (state.selectedWallIndex == null) return;
    
    final updatedWalls = List<Wall>.from(state.walls);
    final index = state.selectedWallIndex!;
    final w = updatedWalls[index];
    updatedWalls[index] = Wall(start: w.start, end: w.end, thickness: thickness);
    
    state = state.copyWith(walls: updatedWalls);
  }

  void placeOpening(String type, Offset position) {
    _pushHistory();
    Offset finalPos = position;
    double finalAngle = 0.0;
    
    final snapResult = snapOpeningToWalls(position);
    if (snapResult['snapped'] as bool) {
      finalPos = snapResult['position'] as Offset;
      finalAngle = snapResult['angle'] as double;
    } else {
      finalPos = snapPoint(position);
    }
    
    final id = UniqueKey().toString();
    final newOp = Opening(id: id, type: type, position: finalPos, angle: finalAngle);
    state = state.copyWith(openings: [...state.openings, newOp]);
  }

  void selectOpening(String id) {
    state = state.copyWith(
      selectedOpeningId: id,
      clearWallEndpoint: true,
      clearWall: true,
      clearFurniture: true,
    );
    ref.read(selectionProvider.notifier).selectElement('opening');
  }

  void moveSelectedOpening(Offset newPosition) {
    if (state.selectedOpeningId == null || _dragStartScenePos == null) return;
    
    final opIndex = _dragStartOpenings.indexWhere((o) => o.id == state.selectedOpeningId);
    if (opIndex == -1) return;
    
    final originalOp = _dragStartOpenings[opIndex];
    final delta = newPosition - _dragStartScenePos!;
    final proposedPosition = originalOp.position + delta;
    
    Offset finalPos = proposedPosition;
    double finalAngle = originalOp.angle;
    
    final snapResult = snapOpeningToWalls(proposedPosition);
    if (snapResult['snapped'] as bool) {
      finalPos = snapResult['position'] as Offset;
      finalAngle = snapResult['angle'] as double;
    } else {
      finalPos = snapPoint(proposedPosition);
    }

    final updatedOpenings = state.openings.map((o) {
      if (o.id == state.selectedOpeningId) {
        return Opening(id: o.id, type: o.type, position: finalPos, width: o.width, angle: finalAngle);
      }
      return o;
    }).toList();

    state = state.copyWith(openings: updatedOpenings);
  }

  void rotateSelectedOpening(double deltaAngleRad) {
    if (state.selectedOpeningId == null) return;
    
    final updatedOpenings = state.openings.map((o) {
      if (o.id == state.selectedOpeningId) {
        return Opening(id: o.id, type: o.type, position: o.position, width: o.width, angle: o.angle + deltaAngleRad);
      }
      return o;
    }).toList();

    state = state.copyWith(openings: updatedOpenings);
  }

  void resizeSelectedOpening(double deltaWidth) {
    if (state.selectedOpeningId == null) return;
    
    final updatedOpenings = state.openings.map((o) {
      if (o.id == state.selectedOpeningId) {
        final newWidth = (o.width + deltaWidth).clamp(30.0, 300.0);
        return Opening(id: o.id, type: o.type, position: o.position, width: newWidth, angle: o.angle);
      }
      return o;
    }).toList();

    state = state.copyWith(openings: updatedOpenings);
  }

  // --- 3D FURNITURE PLACEMENT ACTIONS ---
  
  void addFurniture(dynamic asset, double x, double z) {
    _pushHistory();
    final newId = UniqueKey().toString();
    final newFurniture = PlacedFurniture(
      id: newId,
      assetId: asset.id,
      name: asset.name,
      width: asset.width,
      depth: asset.depth,
      height: asset.height,
      x: x,
      z: z,
      y: 0.0,
      rotationY: 0.0,
    );
    state = state.copyWith(
      furniture: [...state.furniture, newFurniture],
      selectedFurnitureId: newId,
      clearWallEndpoint: true,
      clearWall: true,
      clearOpening: true,
    );
    ref.read(selectionProvider.notifier).selectFurniture(newId);
  }

  void placeFurnitureFromLayout(List<dynamic> layoutItems, [List<dynamic>? furnitureAssets]) {
    _pushHistory();
    final List<PlacedFurniture> newPlacedList = [];

    for (final item in layoutItems) {
      if (item is! Map<String, dynamic> && item is! Map) continue;
      final map = item is Map<String, dynamic> ? item : Map<String, dynamic>.from(item as Map);

      final assetId = map['asset_id'] ?? map['assetId'] ?? '';
      final name = map['name'] ?? 'Furniture';
      final width = (map['width'] as num? ?? 100.0).toDouble();
      final depth = (map['depth'] as num? ?? 100.0).toDouble();
      final height = (map['height'] as num? ?? 100.0).toDouble();
      final x = (map['x'] as num? ?? 0.0).toDouble();
      final y = (map['y'] as num? ?? 0.0).toDouble();
      final z = (map['z'] as num? ?? 0.0).toDouble();
      final rotY = (map['rotationY'] as num? ?? map['rotation'] as num? ?? 0.0).toDouble();
      final rotX = (map['rotationX'] as num? ?? 0.0).toDouble();
      final rotZ = (map['rotationZ'] as num? ?? 0.0).toDouble();

      final id = map['id'] != null && map['id'].toString().isNotEmpty
          ? map['id'].toString()
          : UniqueKey().toString();

      newPlacedList.add(PlacedFurniture(
        id: id,
        assetId: assetId.toString(),
        name: name.toString(),
        width: width,
        depth: depth,
        height: height,
        x: x,
        y: y,
        z: z,
        rotationX: rotX,
        rotationY: rotY,
        rotationZ: rotZ,
      ));
    }

    state = state.copyWith(
      furniture: newPlacedList,
      clearFurniture: true,
      clearWallEndpoint: true,
      clearWall: true,
      clearOpening: true,
    );
  }

  void selectFurniture(String id, {bool multi = false}) {
    Set<String> newSelectedIds;
    if (multi) {
      newSelectedIds = Set<String>.from(state.selectedFurnitureIds);
      if (newSelectedIds.contains(id)) {
        newSelectedIds.remove(id);
      } else {
        newSelectedIds.add(id);
      }
    } else {
      newSelectedIds = {id};
    }

    state = state.copyWith(
      selectedFurnitureId: newSelectedIds.isNotEmpty ? newSelectedIds.last : null,
      selectedFurnitureIds: newSelectedIds,
      clearFurniture: newSelectedIds.isEmpty,
      clearWallEndpoint: true,
      clearWall: true,
      clearOpening: true,
    );
    if (newSelectedIds.isNotEmpty) {
      ref.read(selectionProvider.notifier).selectFurniture(newSelectedIds.last);
    } else {
      ref.read(selectionProvider.notifier).clearSelection();
    }
  }

  void toggleFurnitureSelection(String id) {
    selectFurniture(id, multi: true);
  }

  void selectAllFurniture() {
    final allIds = state.furniture.map((f) => f.id).toSet();
    state = state.copyWith(
      selectedFurnitureIds: allIds,
      selectedFurnitureId: allIds.isNotEmpty ? allIds.first : null,
      clearWallEndpoint: true,
      clearWall: true,
      clearOpening: true,
    );
    if (allIds.isNotEmpty) {
      ref.read(selectionProvider.notifier).selectFurniture(allIds.first);
    }
  }

  void deselectFurniture() {
    state = state.copyWith(
      clearFurniture: true,
      clearSelectedFurnitureIds: true,
      clearWallEndpoint: true,
      clearWall: true,
      clearOpening: true,
    );
    ref.read(selectionProvider.notifier).clearSelection();
  }

  void updateSelectedFurnitureTransform({
    double? x,
    double? y,
    double? z,
    double? rotationX,
    double? rotationY,
    double? rotationZ,
    double? scaleX,
    double? scaleY,
    double? scaleZ,
  }) {
    if (state.selectedFurnitureId == null) return;
    
    final updated = state.furniture.map((f) {
      if (f.id == state.selectedFurnitureId) {
        return f.copyWith(
          x: x,
          y: y,
          z: z,
          rotationX: rotationX,
          rotationY: rotationY,
          rotationZ: rotationZ,
          scaleX: scaleX,
          scaleY: scaleY,
          scaleZ: scaleZ,
        );
      }
      return f;
    }).toList();
    
    state = state.copyWith(furniture: updated);
  }

  void updateSelectedFurnitureMaterial({
    String? color,
    String? materialType,
    double? metallic,
    double? roughness,
    double? opacity,
  }) {
    if (state.selectedFurnitureId == null) return;
    
    final updated = state.furniture.map((f) {
      if (f.id == state.selectedFurnitureId) {
        return f.copyWith(
          materialColor: color,
          materialType: materialType,
          metallic: metallic,
          roughness: roughness,
          opacity: opacity,
        );
      }
      return f;
    }).toList();
    
    state = state.copyWith(furniture: updated);
  }

  void updateSelectedFurnitureName(String name) {
    if (state.selectedFurnitureId == null) return;
    final updated = state.furniture.map((f) {
      if (f.id == state.selectedFurnitureId) {
        return f.copyWith(name: name);
      }
      return f;
    }).toList();
    state = state.copyWith(furniture: updated);
  }

  void duplicateSelectedFurniture() {
    final targets = state.selectedFurnitureIds.isNotEmpty 
        ? state.selectedFurnitureIds 
        : (state.selectedFurnitureId != null ? {state.selectedFurnitureId!} : <String>{});
    if (targets.isEmpty) return;
    
    _pushHistory();
    final List<PlacedFurniture> duplicates = [];
    final Set<String> newIds = {};
    for (final orig in state.furniture) {
      if (targets.contains(orig.id)) {
        final newId = UniqueKey().toString();
        newIds.add(newId);
        duplicates.add(orig.copyWith(
          id: newId,
          name: "${orig.name} (Copy)",
          x: orig.x + 30.0,
          z: orig.z + 30.0,
        ));
      }
    }

    state = state.copyWith(
      furniture: [...state.furniture, ...duplicates],
      selectedFurnitureIds: newIds,
      selectedFurnitureId: newIds.isNotEmpty ? newIds.last : null,
      clearWallEndpoint: true,
      clearWall: true,
      clearOpening: true,
    );
    if (newIds.isNotEmpty) {
      ref.read(selectionProvider.notifier).selectFurniture(newIds.last);
    }
  }

  void resetSelectedFurnitureTransform() {
    final targets = state.selectedFurnitureIds.isNotEmpty 
        ? state.selectedFurnitureIds 
        : (state.selectedFurnitureId != null ? {state.selectedFurnitureId!} : <String>{});
    if (targets.isEmpty) return;
    
    final updated = state.furniture.map((f) {
      if (targets.contains(f.id)) {
        return f.copyWith(
          y: 0.0,
          rotationY: 0.0,
          scaleX: 1.0,
          scaleY: 1.0,
          scaleZ: 1.0,
        );
      }
      return f;
    }).toList();
    
    state = state.copyWith(furniture: updated);
  }

  void updateSelectedFurnitureDimensions({
    double? width,
    double? depth,
    double? height,
  }) {
    if (state.selectedFurnitureId == null) return;
    _pushHistory();

    final updated = state.furniture.map((f) {
      if (f.id == state.selectedFurnitureId) {
        final newW = (width ?? f.width).clamp(10.0, 1000.0);
        final newD = (depth ?? f.depth).clamp(10.0, 1000.0);
        final newH = (height ?? f.height).clamp(10.0, 1000.0);
        return f.copyWith(
          width: newW,
          depth: newD,
          height: newH,
        );
      }
      return f;
    }).toList();

    state = state.copyWith(furniture: updated);
  }

  void moveSelectedFurnitureByOffset(double deltaX, double deltaZ) {
    _pushHistory();
    moveSelectedFurnitureGroup(deltaX, deltaZ);
  }

  void moveSelectedFurnitureGroup(double deltaX, double deltaZ) {
    final targets = state.selectedFurnitureIds.isNotEmpty 
        ? state.selectedFurnitureIds 
        : (state.selectedFurnitureId != null ? {state.selectedFurnitureId!} : <String>{});
    if (targets.isEmpty) return;

    final updated = state.furniture.map((f) {
      if (targets.contains(f.id) && !f.isLocked) {
        return f.copyWith(
          x: f.x + deltaX,
          z: f.z + deltaZ,
        );
      }
      return f;
    }).toList();

    state = state.copyWith(furniture: updated);
  }

  void rotateSelectedFurniture90({bool clockwise = true}) {
    final delta = clockwise ? (pi / 2.0) : (-pi / 2.0);
    rotateSelectedFurnitureBy(delta);
  }

  void rotateSelectedFurnitureBy(double deltaRad) {
    final targets = state.selectedFurnitureIds.isNotEmpty 
        ? state.selectedFurnitureIds 
        : (state.selectedFurnitureId != null ? {state.selectedFurnitureId!} : <String>{});
    if (targets.isEmpty) return;
    _pushHistory();

    final updated = state.furniture.map((f) {
      if (targets.contains(f.id) && !f.isLocked) {
        double newRot = (f.rotationY + deltaRad) % (2 * pi);
        if (newRot < 0) newRot += (2 * pi);
        return f.copyWith(rotationY: newRot);
      }
      return f;
    }).toList();

    state = state.copyWith(furniture: updated);
  }

  void alignSelectedFurniture(AlignmentType type, [double roomWidth = 600.0, double roomLength = 450.0]) {
    final targets = state.selectedFurnitureIds.isNotEmpty 
        ? state.selectedFurnitureIds 
        : (state.selectedFurnitureId != null ? {state.selectedFurnitureId!} : <String>{});
    if (targets.isEmpty) return;
    _pushHistory();

    final selectedItems = state.furniture.where((f) => targets.contains(f.id)).toList();
    if (selectedItems.isEmpty) return;

    if (selectedItems.length == 1) {
      final item = selectedItems.first;
      double newX = item.x;
      double newZ = item.z;
      switch (type) {
        case AlignmentType.left:
          newX = item.width / 2.0 + 10.0;
          break;
        case AlignmentType.right:
          newX = roomWidth - item.width / 2.0 - 10.0;
          break;
        case AlignmentType.top:
          newZ = item.depth / 2.0 + 10.0;
          break;
        case AlignmentType.bottom:
          newZ = roomLength - item.depth / 2.0 - 10.0;
          break;
        case AlignmentType.centerX:
          newX = roomWidth / 2.0;
          break;
        case AlignmentType.centerZ:
          newZ = roomLength / 2.0;
          break;
        default:
          break;
      }
      final updated = state.furniture.map((f) => f.id == item.id ? f.copyWith(x: newX, z: newZ) : f).toList();
      state = state.copyWith(furniture: updated);
      return;
    }

    double minX = selectedItems.map((f) => f.x - f.width / 2).reduce(min);
    double maxX = selectedItems.map((f) => f.x + f.width / 2).reduce(max);
    double minZ = selectedItems.map((f) => f.z - f.depth / 2).reduce(min);
    double maxZ = selectedItems.map((f) => f.z + f.depth / 2).reduce(max);
    double avgX = selectedItems.map((f) => f.x).reduce((a, b) => a + b) / selectedItems.length;
    double avgZ = selectedItems.map((f) => f.z).reduce((a, b) => a + b) / selectedItems.length;

    var updated = state.furniture.map((f) {
      if (!targets.contains(f.id) || f.isLocked) return f;
      double newX = f.x;
      double newZ = f.z;
      switch (type) {
        case AlignmentType.left:
          newX = minX + f.width / 2.0;
          break;
        case AlignmentType.right:
          newX = maxX - f.width / 2.0;
          break;
        case AlignmentType.top:
          newZ = minZ + f.depth / 2.0;
          break;
        case AlignmentType.bottom:
          newZ = maxZ - f.depth / 2.0;
          break;
        case AlignmentType.centerX:
          newX = avgX;
          break;
        case AlignmentType.centerZ:
          newZ = avgZ;
          break;
        case AlignmentType.distributeH:
        case AlignmentType.distributeV:
          break;
      }
      return f.copyWith(x: newX, z: newZ);
    }).toList();

    if (type == AlignmentType.distributeH && selectedItems.length > 2) {
      final sorted = List<PlacedFurniture>.from(selectedItems)..sort((a, b) => a.x.compareTo(b.x));
      final step = (maxX - minX) / (sorted.length - 1);
      for (int i = 0; i < sorted.length; i++) {
        final id = sorted[i].id;
        final targetX = minX + i * step;
        final idx = updated.indexWhere((f) => f.id == id);
        if (idx != -1) updated[idx] = updated[idx].copyWith(x: targetX);
      }
    } else if (type == AlignmentType.distributeV && selectedItems.length > 2) {
      final sorted = List<PlacedFurniture>.from(selectedItems)..sort((a, b) => a.z.compareTo(b.z));
      final step = (maxZ - minZ) / (sorted.length - 1);
      for (int i = 0; i < sorted.length; i++) {
        final id = sorted[i].id;
        final targetZ = minZ + i * step;
        final idx = updated.indexWhere((f) => f.id == id);
        if (idx != -1) updated[idx] = updated[idx].copyWith(z: targetZ);
      }
    }

    state = state.copyWith(furniture: updated);
  }

  void bringSelectedFurnitureToFront() {
    final targets = state.selectedFurnitureIds.isNotEmpty 
        ? state.selectedFurnitureIds 
        : (state.selectedFurnitureId != null ? {state.selectedFurnitureId!} : <String>{});
    if (targets.isEmpty) return;
    _pushHistory();
    final nonSelected = state.furniture.where((f) => !targets.contains(f.id)).toList();
    final selected = state.furniture.where((f) => targets.contains(f.id)).toList();
    state = state.copyWith(furniture: [...nonSelected, ...selected]);
  }

  void sendSelectedFurnitureToBack() {
    final targets = state.selectedFurnitureIds.isNotEmpty 
        ? state.selectedFurnitureIds 
        : (state.selectedFurnitureId != null ? {state.selectedFurnitureId!} : <String>{});
    if (targets.isEmpty) return;
    _pushHistory();
    final nonSelected = state.furniture.where((f) => !targets.contains(f.id)).toList();
    final selected = state.furniture.where((f) => targets.contains(f.id)).toList();
    state = state.copyWith(furniture: [...selected, ...nonSelected]);
  }

  void copySelectedFurniture() {
    final targets = state.selectedFurnitureIds.isNotEmpty 
        ? state.selectedFurnitureIds 
        : (state.selectedFurnitureId != null ? {state.selectedFurnitureId!} : <String>{});
    if (targets.isEmpty) return;
    _furnitureClipboard.clear();
    for (final f in state.furniture) {
      if (targets.contains(f.id)) {
        _furnitureClipboard.add(f.copyWith());
      }
    }
  }

  void pasteFurniture() {
    if (_furnitureClipboard.isEmpty) return;
    _pushHistory();
    final List<PlacedFurniture> pasted = [];
    final Set<String> newIds = {};
    for (final orig in _furnitureClipboard) {
      final newId = UniqueKey().toString();
      newIds.add(newId);
      pasted.add(orig.copyWith(
        id: newId,
        name: "${orig.name} (Copy)",
        x: orig.x + 25.0,
        z: orig.z + 25.0,
      ));
    }
    state = state.copyWith(
      furniture: [...state.furniture, ...pasted],
      selectedFurnitureIds: newIds,
      selectedFurnitureId: newIds.isNotEmpty ? newIds.last : null,
      clearWallEndpoint: true,
      clearWall: true,
      clearOpening: true,
    );
    if (newIds.isNotEmpty) {
      ref.read(selectionProvider.notifier).selectFurniture(newIds.last);
    }
  }

  bool findValidPositionForSelected({double roomWidth = 600.0, double roomLength = 450.0}) {
    if (state.selectedFurnitureId == null) return false;
    final targetId = state.selectedFurnitureId!;
    final itemIndex = state.furniture.indexWhere((f) => f.id == targetId);
    if (itemIndex == -1) return false;
    final item = state.furniture[itemIndex];

    final cosR = cos(item.rotationY).abs();
    final sinR = sin(item.rotationY).abs();
    final halfW = (item.width * cosR + item.depth * sinR) / 2.0;
    final halfD = (item.width * sinR + item.depth * cosR) / 2.0;

    final minX = halfW + 15.0;
    final maxX = roomWidth - halfW - 15.0;
    final minZ = halfD + 15.0;
    final maxZ = roomLength - halfD - 15.0;

    final otherFurniture = state.furniture.where((f) => f.id != targetId).toList();
    final doorOpenings = state.openings.where((o) => o.type == 'door').toList();

    bool isPositionValid(double testX, double testZ) {
      if (testX < minX || testX > maxX || testZ < minZ || testZ > maxZ) return false;
      final testRect = Rect.fromCenter(center: Offset(testX, testZ), width: halfW * 2, height: halfD * 2);

      for (final door in doorOpenings) {
        final dX = (door.position.dx - testX).abs();
        final dZ = (door.position.dy - testZ).abs();
        if (dX < (halfW + 45.0) && dZ < (halfD + 45.0)) return false;
      }

      for (final other in otherFurniture) {
        final oCos = cos(other.rotationY).abs();
        final oSin = sin(other.rotationY).abs();
        final oHalfW = (other.width * oCos + other.depth * oSin) / 2.0;
        final oHalfD = (other.width * oSin + other.depth * oCos) / 2.0;
        final oRect = Rect.fromCenter(center: Offset(other.x, other.z), width: oHalfW * 2, height: oHalfD * 2);
        if (testRect.overlaps(oRect)) return false;
      }
      return true;
    }

    if (isPositionValid(item.x, item.z)) return true;

    for (double r = 20.0; r <= 450.0; r += 20.0) {
      for (int i = 0; i < 16; i++) {
        final angle = i * (2 * pi / 16.0);
        final candX = (item.x + r * cos(angle)).clamp(minX, maxX);
        final candZ = (item.z + r * sin(angle)).clamp(minZ, maxZ);
        if (isPositionValid(candX, candZ)) {
          _pushHistory();
          final updated = state.furniture.map((f) => f.id == targetId ? f.copyWith(x: candX, z: candZ) : f).toList();
          state = state.copyWith(furniture: updated);
          return true;
        }
      }
    }

    final candidateWallAnchors = [
      Offset(minX, minZ),
      Offset(maxX, minZ),
      Offset(minX, maxZ),
      Offset(maxX, maxZ),
      Offset(roomWidth / 2, minZ),
      Offset(roomWidth / 2, maxZ),
      Offset(minX, roomLength / 2),
      Offset(maxX, roomLength / 2),
    ];
    for (final anchor in candidateWallAnchors) {
      if (isPositionValid(anchor.dx, anchor.dy)) {
        _pushHistory();
        final updated = state.furniture.map((f) => f.id == targetId ? f.copyWith(x: anchor.dx, z: anchor.dy) : f).toList();
        state = state.copyWith(furniture: updated);
        return true;
      }
    }

    return false;
  }

  void updateRoomMaterials({
    String? floorColor,
    String? floorType,
    String? wallColor,
    String? wallType,
  }) {
    _pushHistory();
    state = state.copyWith(
      floorMaterialColor: floorColor ?? state.floorMaterialColor,
      floorMaterialType: floorType ?? state.floorMaterialType,
      wallMaterialColor: wallColor ?? state.wallMaterialColor,
      wallMaterialType: wallType ?? state.wallMaterialType,
    );
  }

  /// Update material on a specific furniture by ID (not just selected).
  void updateFurnitureMaterialById({
    required String id,
    String? color,
    bool clearColor = false,
    String? materialType,
    double? metallic,
    double? roughness,
    double? opacity,
    String? normalMap,
    bool clearNormalMap = false,
    String? baseColorMap,
    bool clearBaseColorMap = false,
    String? roughnessMap,
    bool clearRoughnessMap = false,
    String? metallicMap,
    bool clearMetallicMap = false,
    String? emissiveMap,
    bool clearEmissiveMap = false,
    String? emissiveColor,
    bool clearEmissiveColor = false,
    double? emissiveIntensity,
    double? scale,
    double? rotation,
  }) {
    final updated = state.furniture.map((f) {
      if (f.id == id) {
        return f.copyWith(
          materialColor: clearColor ? null : (color ?? f.materialColor),
          clearColor: clearColor,
          materialType: materialType ?? f.materialType,
          metallic: metallic ?? f.metallic,
          roughness: roughness ?? f.roughness,
          opacity: opacity ?? f.opacity,
          normalMap: clearNormalMap ? null : (normalMap ?? f.normalMap),
          clearNormalMap: clearNormalMap,
          baseColorMap: clearBaseColorMap ? null : (baseColorMap ?? f.baseColorMap),
          clearBaseColorMap: clearBaseColorMap,
          roughnessMap: clearRoughnessMap ? null : (roughnessMap ?? f.roughnessMap),
          clearRoughnessMap: clearRoughnessMap,
          metallicMap: clearMetallicMap ? null : (metallicMap ?? f.metallicMap),
          clearMetallicMap: clearMetallicMap,
          emissiveMap: clearEmissiveMap ? null : (emissiveMap ?? f.emissiveMap),
          clearEmissiveMap: clearEmissiveMap,
          emissiveColor: clearEmissiveColor ? null : (emissiveColor ?? f.emissiveColor),
          clearEmissiveColor: clearEmissiveColor,
          emissiveIntensity: emissiveIntensity ?? f.emissiveIntensity,
          materialScale: scale ?? f.materialScale,
          materialRotation: rotation ?? f.materialRotation,
        );
      }
      return f;
    }).toList();
    state = state.copyWith(furniture: updated);
  }

  /// Apply material from drag drop to any surface or furniture.
  void applyMaterialFromDrop({
    required String surface, // 'furniture:{id}', 'floor', 'wall', 'ceiling'
    required String? colorHex,
    required String? materialType,
    double metallic = 0.0,
    double roughness = 0.5,
    double reflection = 0.0,
    double opacity = 1.0,
    String? normalMap,
    String? baseColorMap,
    String? roughnessMap,
    String? metallicMap,
    String? emissiveMap,
    String? emissiveColor,
    double emissiveIntensity = 0.0,
    double scale = 1.0,
    double rotation = 0.0,
  }) {
    if (surface.startsWith('furniture:')) {
      final id = surface.replaceFirst('furniture:', '');
      updateFurnitureMaterialById(
        id: id,
        color: colorHex,
        materialType: materialType,
        metallic: metallic,
        roughness: roughness,
        opacity: opacity,
        normalMap: normalMap,
        baseColorMap: baseColorMap,
        roughnessMap: roughnessMap,
        metallicMap: metallicMap,
        emissiveMap: emissiveMap,
        emissiveColor: emissiveColor,
        emissiveIntensity: emissiveIntensity,
        scale: scale,
        rotation: rotation,
      );
    } else {
      updateRoomSurface(
        surface: surface,
        color: colorHex,
        materialType: materialType,
        metallic: metallic,
        roughness: roughness,
        reflection: reflection,
        scale: scale,
        rotation: rotation,
        normalMap: normalMap,
        baseColorMap: baseColorMap,
        roughnessMap: roughnessMap,
        metallicMap: metallicMap,
        emissiveMap: emissiveMap,
        emissiveColor: emissiveColor,
        emissiveIntensity: emissiveIntensity,
      );
    }
  }

  /// Update a room surface (floor/wall/ceiling) with full PBR properties.
  void updateRoomSurface({
    required String surface,
    String? color,
    bool clearColor = false,
    String? materialType,
    double? metallic,
    double? roughness,
    double? reflection,
    double? scale,
    double? rotation,
    String? normalMap,
    bool clearNormalMap = false,
    String? baseColorMap,
    bool clearBaseColorMap = false,
    String? roughnessMap,
    bool clearRoughnessMap = false,
    String? metallicMap,
    bool clearMetallicMap = false,
    String? emissiveMap,
    bool clearEmissiveMap = false,
    String? emissiveColor,
    bool clearEmissiveColor = false,
    double? emissiveIntensity,
  }) {
    _pushHistory();
    switch (surface) {
      case 'floor':
        state = state.copyWith(
          floorMaterialColor: clearColor ? null : (color ?? state.floorMaterialColor),
          clearFloorColor: clearColor,
          floorMaterialType: materialType ?? state.floorMaterialType,
          floorMetallic: metallic ?? state.floorMetallic,
          floorRoughness: roughness ?? state.floorRoughness,
          floorReflection: reflection ?? state.floorReflection,
          floorScale: scale ?? state.floorScale,
          floorRotation: rotation ?? state.floorRotation,
          floorNormalMap: clearNormalMap ? null : (normalMap ?? state.floorNormalMap),
          clearFloorNormalMap: clearNormalMap,
          floorBaseColorMap: clearBaseColorMap ? null : (baseColorMap ?? state.floorBaseColorMap),
          clearFloorBaseColorMap: clearBaseColorMap,
          floorRoughnessMap: clearRoughnessMap ? null : (roughnessMap ?? state.floorRoughnessMap),
          clearFloorRoughnessMap: clearRoughnessMap,
          floorMetallicMap: clearMetallicMap ? null : (metallicMap ?? state.floorMetallicMap),
          clearFloorMetallicMap: clearMetallicMap,
          floorEmissiveMap: clearEmissiveMap ? null : (emissiveMap ?? state.floorEmissiveMap),
          clearFloorEmissiveMap: clearEmissiveMap,
          floorEmissiveColor: clearEmissiveColor ? null : (emissiveColor ?? state.floorEmissiveColor),
          clearFloorEmissiveColor: clearEmissiveColor,
          floorEmissiveIntensity: emissiveIntensity ?? state.floorEmissiveIntensity,
        );
        break;
      case 'wall':
        state = state.copyWith(
          wallMaterialColor: clearColor ? null : (color ?? state.wallMaterialColor),
          clearWallColor: clearColor,
          wallMaterialType: materialType ?? state.wallMaterialType,
          wallMetallic: metallic ?? state.wallMetallic,
          wallRoughness: roughness ?? state.wallRoughness,
          wallReflection: reflection ?? state.wallReflection,
          wallScale: scale ?? state.wallScale,
          wallRotation: rotation ?? state.wallRotation,
          wallNormalMap: clearNormalMap ? null : (normalMap ?? state.wallNormalMap),
          clearWallNormalMap: clearNormalMap,
          wallBaseColorMap: clearBaseColorMap ? null : (baseColorMap ?? state.wallBaseColorMap),
          clearWallBaseColorMap: clearBaseColorMap,
          wallRoughnessMap: clearRoughnessMap ? null : (roughnessMap ?? state.wallRoughnessMap),
          clearWallRoughnessMap: clearRoughnessMap,
          wallMetallicMap: clearMetallicMap ? null : (metallicMap ?? state.wallMetallicMap),
          clearWallMetallicMap: clearMetallicMap,
          wallEmissiveMap: clearEmissiveMap ? null : (emissiveMap ?? state.wallEmissiveMap),
          clearWallEmissiveMap: clearEmissiveMap,
          wallEmissiveColor: clearEmissiveColor ? null : (emissiveColor ?? state.wallEmissiveColor),
          clearWallEmissiveColor: clearEmissiveColor,
          wallEmissiveIntensity: emissiveIntensity ?? state.wallEmissiveIntensity,
        );
        break;
      case 'ceiling':
        state = state.copyWith(
          ceilingMaterialColor: clearColor ? null : (color ?? state.ceilingMaterialColor),
          clearCeilingColor: clearColor,
          ceilingMaterialType: materialType ?? state.ceilingMaterialType,
          ceilingMetallic: metallic ?? state.ceilingMetallic,
          ceilingRoughness: roughness ?? state.ceilingRoughness,
          ceilingReflection: reflection ?? state.ceilingReflection,
          ceilingScale: scale ?? state.ceilingScale,
          ceilingRotation: rotation ?? state.ceilingRotation,
          ceilingNormalMap: clearNormalMap ? null : (normalMap ?? state.ceilingNormalMap),
          clearCeilingNormalMap: clearNormalMap,
          ceilingBaseColorMap: clearBaseColorMap ? null : (baseColorMap ?? state.ceilingBaseColorMap),
          clearCeilingBaseColorMap: clearBaseColorMap,
          ceilingRoughnessMap: clearRoughnessMap ? null : (roughnessMap ?? state.ceilingRoughnessMap),
          clearCeilingRoughnessMap: clearRoughnessMap,
          ceilingMetallicMap: clearMetallicMap ? null : (metallicMap ?? state.ceilingMetallicMap),
          clearCeilingMetallicMap: clearMetallicMap,
          ceilingEmissiveMap: clearEmissiveMap ? null : (emissiveMap ?? state.ceilingEmissiveMap),
          clearCeilingEmissiveMap: clearEmissiveMap,
          ceilingEmissiveColor: clearEmissiveColor ? null : (emissiveColor ?? state.ceilingEmissiveColor),
          clearCeilingEmissiveColor: clearEmissiveColor,
          ceilingEmissiveIntensity: emissiveIntensity ?? state.ceilingEmissiveIntensity,
        );
        break;
    }
  }

  // --- DELETE SELECTION ACTION ---

  void deleteSelected() {
    if (state.selectedOpeningId != null) {
      _pushHistory();
      final updated = state.openings.where((o) => o.id != state.selectedOpeningId).toList();
      state = state.copyWith(openings: updated, clearOpening: true);
    } else if (state.selectedWallEndpointId != null) {
      _pushHistory();
      final parts = state.selectedWallEndpointId!.split('_');
      final index = int.parse(parts[0]);
      final updated = List<Wall>.from(state.walls)..removeAt(index);
      state = state.copyWith(walls: updated, clearWallEndpoint: true);
    } else if (state.selectedWallIndex != null) {
      _pushHistory();
      final index = state.selectedWallIndex!;
      final updated = List<Wall>.from(state.walls)..removeAt(index);
      state = state.copyWith(walls: updated, clearWall: true);
    } else if (state.selectedFurnitureIds.isNotEmpty || state.selectedFurnitureId != null) {
      _pushHistory();
      final idsToDelete = Set<String>.from(state.selectedFurnitureIds);
      if (state.selectedFurnitureId != null) idsToDelete.add(state.selectedFurnitureId!);
      final updated = state.furniture.where((f) => !idsToDelete.contains(f.id)).toList();
      state = state.copyWith(
        furniture: updated,
        clearFurniture: true,
        clearSelectedFurnitureIds: true,
      );
      ref.read(selectionProvider.notifier).clearSelection();
    }
  }

  void clearAllFurniture() {
    _pushHistory();
    state = state.copyWith(furniture: [], clearFurniture: true);
  }

  void toggleSelectedFurnitureLock() {
    if (state.selectedFurnitureId == null) return;
    final updated = state.furniture.map((f) {
      if (f.id == state.selectedFurnitureId) {
        return f.copyWith(isLocked: !f.isLocked);
      }
      return f;
    }).toList();
    state = state.copyWith(furniture: updated);
  }

  void toggleSelectedFurnitureVisibility() {
    if (state.selectedFurnitureId == null) return;
    final updated = state.furniture.map((f) {
      if (f.id == state.selectedFurnitureId) {
        return f.copyWith(isVisible: !f.isVisible);
      }
      return f;
    }).toList();
    state = state.copyWith(furniture: updated);
  }

  void clearSelection() {
    state = state.copyWith(
      clearWallEndpoint: true,
      clearWall: true,
      clearOpening: true,
      clearFurniture: true,
    );
    ref.read(selectionProvider.notifier).clearSelection();
  }

  void loadSampleApartment() {
    state = _generateSampleApartment();
  }

  DesignerLayoutState _generateSampleApartment() {
    return DesignerLayoutState(
      walls: [
        // Exterior walls (15cm) for Living Room 600cm x 450cm
        Wall(start: const Offset(0, 0), end: const Offset(600, 0), thickness: 15.0), // Top
        Wall(start: const Offset(600, 0), end: const Offset(600, 450), thickness: 15.0), // Right
        Wall(start: const Offset(600, 450), end: const Offset(0, 450), thickness: 15.0), // Bottom
        Wall(start: const Offset(0, 450), end: const Offset(0, 0), thickness: 15.0), // Left
      ],
      openings: [
        Opening(id: 'op_living_win', type: 'window', position: const Offset(600, 225), width: 140.0, angle: pi / 2),
        Opening(id: 'op_entrance_door', type: 'door', position: const Offset(80, 450), width: 90.0, angle: 0.0),
      ],
      furniture: [
        // Modern Sofa centered along bottom zone
        PlacedFurniture(
          id: 'placed_sofa_001',
          assetId: 'SOFA001',
          name: 'Modern Sofa',
          width: 210, depth: 90, height: 85,
          x: 300, y: 0.0, z: 330,
          rotationY: 0.0,
          materialColor: 'b0bec5',
          materialType: 'fabric',
          roughness: 0.7,
        ),
        // Coffee Table in front of Sofa
        PlacedFurniture(
          id: 'placed_coffee_001',
          assetId: 'COFFEE001',
          name: 'Modern Coffee Table',
          width: 100, depth: 60, height: 45,
          x: 300, y: 0.0, z: 230,
          rotationY: 0.0,
          materialColor: '8d6e63',
          materialType: 'wood',
          roughness: 0.5,
        ),
        // TV Console facing the sofa
        PlacedFurniture(
          id: 'placed_tv_001',
          assetId: 'TV001',
          name: 'Modern TV Console',
          width: 150, depth: 40, height: 60,
          x: 300, y: 0.0, z: 40,
          rotationY: 0.0,
          materialColor: '212121',
          materialType: 'wood',
          roughness: 0.4,
        ),
      ],
      floorMaterialType: 'hardwood',
      floorMaterialColor: 'D7CCC8',
      wallMaterialColor: 'FFFFFF',
      wallMaterialType: 'paint',
    );
  }

  void addFurnitureWithRotation(
    dynamic asset,
    double x,
    double z,
    double rotationY,
  ) {
    pushUndo();
    final newId = UniqueKey().toString();
    final assetId = _extractAssetString(asset, 'id') ?? '';
    final assetName = _extractAssetString(asset, 'name') ?? 'Furniture';
    final assetWidth = _extractAssetDouble(asset, 'width') ?? 100.0;
    final assetDepth = _extractAssetDouble(asset, 'depth') ?? 100.0;
    final assetHeight = _extractAssetDouble(asset, 'height') ?? 75.0;

    final nf = PlacedFurniture(
      id: newId,
      assetId: assetId,
      name: assetName,
      width: assetWidth,
      depth: assetDepth,
      height: assetHeight,
      x: x,
      z: z,
      y: 0.0,
      rotationY: rotationY,
    );
    state = state.copyWith(
      furniture: [...state.furniture, nf],
      selectedFurnitureId: newId,
      clearWallEndpoint: true,
      clearWall: true,
      clearOpening: true,
    );
  }

  void moveFurnitureTo(String id, double x, double z) {
    pushUndo();
    final updated = state.furniture
        .map((f) => f.id == id ? f.copyWith(x: x, z: z) : f)
        .toList();
    state = state.copyWith(furniture: updated);
  }

  void rotateFurnitureBy(String id, double delta) {
    final updated = state.furniture
        .map((f) =>
            f.id == id ? f.copyWith(rotationY: f.rotationY + delta) : f)
        .toList();
    state = state.copyWith(furniture: updated);
  }

  String? _extractAssetString(dynamic obj, String key) {
    try {
      if (obj is Map) return obj[key]?.toString();
      switch (key) {
        case 'id':
          return (obj.id as String?);
        case 'name':
          return (obj.name as String?);
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  double? _extractAssetDouble(dynamic obj, String key) {
    try {
      if (obj is Map) return (obj[key] as num?)?.toDouble();
      switch (key) {
        case 'width':
          return (obj.width as num?)?.toDouble();
        case 'depth':
          return (obj.depth as num?)?.toDouble();
        case 'height':
          return (obj.height as num?)?.toDouble();
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}

final designerProvider = NotifierProvider<DesignerNotifier, DesignerLayoutState>(() {
  return DesignerNotifier();
});

class DeveloperModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void setMode(bool val) => state = val;
}

final developerModeProvider = NotifierProvider<DeveloperModeNotifier, bool>(() {
  return DeveloperModeNotifier();
});

class DesignerFpsNotifier extends Notifier<int> {
  @override
  int build() => 60;

  void setFps(int val) => state = val;
}

final designerFpsProvider = NotifierProvider<DesignerFpsNotifier, int>(() {
  return DesignerFpsNotifier();
});

