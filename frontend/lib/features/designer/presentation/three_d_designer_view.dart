import '../../../app/themes/app_theme.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/designer_provider.dart';
import '../providers/camera_provider.dart';
import 'graphics_3d.dart';
import '../../../shared/widgets/snackbar_manager.dart';
import 'package:http/http.dart' as http;
import 'material_library_screen.dart';
import '../providers/lighting_provider.dart';
import '../../../core/utils/url_helper.dart';
import '../models/material_model.dart';
import '../providers/material_provider.dart';
import '../models/light_source.dart';
import 'widgets/virtual_joystick.dart';
import '../bridge/viewport_controller.dart';
import '../bridge/bridge_client.dart';
import '../bridge/bridge_client_stub.dart';

class ThreeDDesignerView extends ConsumerStatefulWidget {
  final String roomId;
  final List<dynamic> furnitureAssets;
  final bool simplified;
  final bool isWalkthroughMode;

  const ThreeDDesignerView({
    super.key,
    required this.roomId,
    required this.furnitureAssets,
    this.simplified = false,
    this.isWalkthroughMode = false,
  });

  @override
  ConsumerState<ThreeDDesignerView> createState() => _ThreeDDesignerViewState();
}

class _ThreeDDesignerViewState extends ConsumerState<ThreeDDesignerView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  
  // Lighting and Rendering state (synced with lightingProvider)
  bool get _showShadows => ref.read(lightingProvider).showShadows;
  bool get _showCeiling => ref.read(lightingProvider).showCeiling;
  bool _isDebugGeometryEnabled = false;

  // Wall display mode: 'full' = full height opaque, 'low' = half height semi-transparent, 'hidden' = no walls
  String _wallDisplayMode = 'low';


  
  // Selection & Transform states
  String? _selectedGizmoAxis; // 'translateX', 'translateY', 'translateZ', 'rotateX', 'rotateY', 'rotateZ', 'scaleX', 'scaleY', 'scaleZ', 'scaleUniform'
  Offset? _dragStartOffset;
  Vector3D? _dragStartPos;
  Vector3D? _dragStartRot;
  Vector3D? _dragStartScale;
  String? _dragValueHUDText;
  
  // Mouse & gesture tracking states
  int _activePointerButton = 0;
  bool _isMouse = false;
  String? _hoveredDragTarget;
  Offset? _dragPosition;
  
  // FPS Tracking
  int _fps = 60;
  int _frameCount = 0;
  DateTime _lastFpsTime = DateTime.now();

  // Keys pressed (for WASD/Arrows fly-through)
  final Set<LogicalKeyboardKey> _pressedKeys = {};
  
  // Joystick values & open door IDs for Walkthrough Mode
  Offset _joystickValue = Offset.zero;
  final Set<String> _openDoorIds = {};
  
  // Focus node for keyboard capture
  final FocusNode _focusNode = FocusNode();

  // GLB Caching structure
  final Map<String, List<Polygon3D>> _glbPolygonsCache = {};
  final Set<String> _loadingAssetIds = {};
  final Map<String, String> _loadedModelSignatures = {};

  void _loadGlbForAsset(String assetId, String glbUrl) {
    if (_glbPolygonsCache.containsKey(assetId) || _loadingAssetIds.contains(assetId)) {
      return;
    }
    _loadingAssetIds.add(assetId);

    // Resolve URL
    String fullUrl = glbUrl;
    if (!glbUrl.startsWith('http')) {
      fullUrl = glbUrl.startsWith('/') ? '${getBaseUrl()}$glbUrl' : '${getBaseUrl()}/$glbUrl';
    }

    http.get(Uri.parse(fullUrl)).then((response) {
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final defaultColor = AppTheme.primary.shade400;
        final parsedPolys = GlbBinaryMeshParser.parse(bytes, defaultColor);
        if (parsedPolys.isNotEmpty) {
          _glbPolygonsCache[assetId] = parsedPolys;
          if (mounted) {
            setState(() {});
          }
        }
      }
      _loadingAssetIds.remove(assetId);
    }).catchError((err) {
      _loadingAssetIds.remove(assetId);
      debugPrint('Error loading GLB for asset $assetId: $err');
    });
  }

  @override
  void didUpdateWidget(ThreeDDesignerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.furnitureAssets != oldWidget.furnitureAssets) {
      final layout = ref.read(designerProvider);
      _syncFurnitureModels(null, layout);
    }
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((duration) {
      final mode = ref.read(viewModeProvider);
      final layout = ref.read(designerProvider);
      ref.read(cameraProvider.notifier).tick(
        pressedKeys: _pressedKeys,
        isFreeOrWalkthrough: mode == ViewMode.free || widget.isWalkthroughMode,
        layout: layout,
        isWalkthrough: widget.isWalkthroughMode,
        joystickValue: _joystickValue,
      );
      setState(() {
        _frameCount++;
        final now = DateTime.now();
        final diff = now.difference(_lastFpsTime);
        if (diff.inSeconds >= 1) {
          _fps = _frameCount;
          _frameCount = 0;
          _lastFpsTime = now;
          ref.read(designerFpsProvider.notifier).setFps(_fps);
        }
      });
    });
    _ticker.start();
    
    // Position camera initially based on room defaults
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final layout = ref.read(designerProvider);
      ref.read(cameraProvider.notifier).resetToRoom(layout, snap: true);
      _sendLoadRoomCommand(layout);
      _syncFurnitureModels(null, layout);

      // Send initial lighting state
      final lightingState = ref.read(lightingProvider);
      ref.read(viewportControllerProvider.notifier).sendCommand('TOGGLE_SHADOWS', {'enabled': lightingState.showShadows});
      for (final light in lightingState.lights) {
        ref.read(viewportControllerProvider.notifier).sendCommand('UPDATE_LIGHT', light.toJson());
      }

      if (layout.selectedFurnitureId != null) {
        ref.read(viewportControllerProvider.notifier).sendCommand('SELECT_OBJECT', {
          'id': layout.selectedFurnitureId,
          'mode': layout.transformMode.name,
        });
      }
    });
  }

  void _sendLoadRoomCommand(DesignerLayoutState layout) {
    final payload = {
      'walls': layout.walls.map((w) => w.toJson()).toList(),
      'openings': layout.openings.map((o) => o.toJson()).toList(),
      'openDoorIds': _openDoorIds.toList(),
      
      'floorMaterialColor': layout.floorMaterialColor,
      'floorMaterialType': layout.floorMaterialType,
      'floorMetallic': layout.floorMetallic,
      'floorRoughness': layout.floorRoughness,
      'floorBaseColorMap': layout.floorBaseColorMap,
      'floorNormalMap': layout.floorNormalMap,
      'floorRoughnessMap': layout.floorRoughnessMap,
      'floorMetallicMap': layout.floorMetallicMap,
      'floorEmissiveMap': layout.floorEmissiveMap,
      'floorEmissiveColor': layout.floorEmissiveColor,
      'floorEmissiveIntensity': layout.floorEmissiveIntensity,
      'floorScale': layout.floorScale,
      'floorRotation': layout.floorRotation,
      
      'wallMaterialColor': layout.wallMaterialColor,
      'wallMaterialType': layout.wallMaterialType,
      'wallMetallic': layout.wallMetallic,
      'wallRoughness': layout.wallRoughness,
      'wallBaseColorMap': layout.wallBaseColorMap,
      'wallNormalMap': layout.wallNormalMap,
      'wallRoughnessMap': layout.wallRoughnessMap,
      'wallMetallicMap': layout.wallMetallicMap,
      'wallEmissiveMap': layout.wallEmissiveMap,
      'wallEmissiveColor': layout.wallEmissiveColor,
      'wallEmissiveIntensity': layout.wallEmissiveIntensity,
      'wallScale': layout.wallScale,
      'wallRotation': layout.wallRotation,
      
      'ceilingMaterialColor': layout.ceilingMaterialColor,
      'ceilingMaterialType': layout.ceilingMaterialType,
      'ceilingMetallic': layout.ceilingMetallic,
      'ceilingRoughness': layout.ceilingRoughness,
      'ceilingBaseColorMap': layout.ceilingBaseColorMap,
      'ceilingNormalMap': layout.ceilingNormalMap,
      'ceilingRoughnessMap': layout.ceilingRoughnessMap,
      'ceilingMetallicMap': layout.ceilingMetallicMap,
      'ceilingEmissiveMap': layout.ceilingEmissiveMap,
      'ceilingEmissiveColor': layout.ceilingEmissiveColor,
      'ceilingEmissiveIntensity': layout.ceilingEmissiveIntensity,
      'ceilingScale': layout.ceilingScale,
      'ceilingRotation': layout.ceilingRotation,
      
      'showCeiling': ref.read(lightingProvider).showCeiling,
    };
    ref.read(viewportControllerProvider.notifier).sendCommand('LOAD_ROOM', payload);
  }

  void _syncFurnitureModels(DesignerLayoutState? previous, DesignerLayoutState next) {
    void sendLoadModel(PlacedFurniture f) {
      // Find glbUrl from furnitureAssets
      String? glbUrl;
      try {
        final matchingAsset = widget.furnitureAssets.firstWhere((a) => a.id == f.assetId);
        glbUrl = matchingAsset.glbUrl;
      } catch (_) {}
      
      // Fallback GLB URL if catalog metadata is not yet populated or item not found in current page
      if (glbUrl == null || glbUrl.isEmpty) {
        if (f.assetId.isNotEmpty) {
          glbUrl = '/uploads/furniture/models/${f.assetId}.glb';
        }
      }
      
      String fullUrl = '';
      if (glbUrl != null && glbUrl.isNotEmpty) {
        if (!glbUrl.startsWith('http')) {
          fullUrl = glbUrl.startsWith('/') ? '${getBaseUrl()}$glbUrl' : '${getBaseUrl()}/$glbUrl';
        } else {
          fullUrl = glbUrl;
        }
      }

      final signature = '${f.id}_${f.assetId}_${fullUrl}_${f.x}_${f.y}_${f.z}_${f.rotationX}_${f.rotationY}_${f.rotationZ}_${f.scaleX}_${f.scaleY}_${f.scaleZ}_${f.width}_${f.depth}_${f.height}';

      if (_loadedModelSignatures[f.id] == signature) {
        return; // Prevent duplicate LOAD_MODEL command
      }
      _loadedModelSignatures[f.id] = signature;

      double roomWidth = 0.0;
      double roomDepth = 0.0;
      if (next.walls.isNotEmpty) {
        double minX = next.walls.first.start.dx;
        double maxX = minX;
        double minY = next.walls.first.start.dy;
        double maxY = minY;
        for (final w in next.walls) {
          minX = min(minX, min(w.start.dx, w.end.dx));
          maxX = max(maxX, max(w.start.dx, w.end.dx));
          minY = min(minY, min(w.start.dy, w.end.dy));
          maxY = max(maxY, max(w.start.dy, w.end.dy));
        }
        roomWidth = maxX - minX;
        roomDepth = maxY - minY;
      }

      debugPrint('[LAYOUT DEBUG]');
      debugPrint('Room: ${roomWidth.toStringAsFixed(1)}cm x ${roomDepth.toStringAsFixed(1)}cm');
      debugPrint('Asset: ${f.assetId}');
      debugPrint('Backend position: x=${f.x.toStringAsFixed(1)}, y=${f.y.toStringAsFixed(1)}, z=${f.z.toStringAsFixed(1)}');
      debugPrint('Backend dimensions: width=${f.width.toStringAsFixed(1)}, depth=${f.depth.toStringAsFixed(1)}, height=${f.height.toStringAsFixed(1)}');
      debugPrint('Rotation: ${f.rotationY.toStringAsFixed(4)}');
      debugPrint('GLB: $fullUrl');

      ref.read(viewportControllerProvider.notifier).sendCommand('LOAD_MODEL', {
        'id': f.id,
        'assetId': f.assetId,
        'name': f.name,
        'glbUrl': fullUrl,
        'x': f.x,
        'y': f.y,
        'z': f.z,
        'rotationX': f.rotationX,
        'rotationY': f.rotationY,
        'rotationZ': f.rotationZ,
        'scaleX': f.scaleX,
        'scaleY': f.scaleY,
        'scaleZ': f.scaleZ,
        'width': f.width,
        'depth': f.depth,
        'height': f.height,
        'materialColor': f.materialColor,
        'opacity': f.opacity,
        'metallic': f.metallic,
        'roughness': f.roughness,
        'normalMap': f.normalMap,
        'baseColorMap': f.baseColorMap,
        'roughnessMap': f.roughnessMap,
        'metallicMap': f.metallicMap,
        'emissiveMap': f.emissiveMap,
        'emissiveColor': f.emissiveColor,
        'emissiveIntensity': f.emissiveIntensity,
        'scale': f.materialScale,
        'rotation': f.materialRotation,
      });
    }

    // 1. Determine which furniture was added or updated
    for (final f in next.furniture) {
      PlacedFurniture? prevMatch;
      if (previous != null) {
        for (final p in previous.furniture) {
          if (p.id == f.id) {
            prevMatch = p;
            break;
          }
        }
      }
      
      if (prevMatch == null) {
        sendLoadModel(f);
      } else {
        final transformChanged = prevMatch.x != f.x ||
            prevMatch.y != f.y ||
            prevMatch.z != f.z ||
            prevMatch.rotationX != f.rotationX ||
            prevMatch.rotationY != f.rotationY ||
            prevMatch.rotationZ != f.rotationZ ||
            prevMatch.scaleX != f.scaleX ||
            prevMatch.scaleY != f.scaleY ||
            prevMatch.scaleZ != f.scaleZ ||
            prevMatch.width != f.width ||
            prevMatch.depth != f.depth ||
            prevMatch.height != f.height;

        if (transformChanged) {
          sendLoadModel(f);
        } else {
          final materialChanged = prevMatch.materialColor != f.materialColor ||
              prevMatch.opacity != f.opacity ||
              prevMatch.metallic != f.metallic ||
              prevMatch.roughness != f.roughness ||
              prevMatch.normalMap != f.normalMap ||
              prevMatch.baseColorMap != f.baseColorMap ||
              prevMatch.roughnessMap != f.roughnessMap ||
              prevMatch.metallicMap != f.metallicMap ||
              prevMatch.emissiveMap != f.emissiveMap ||
              prevMatch.emissiveColor != f.emissiveColor ||
              prevMatch.emissiveIntensity != f.emissiveIntensity ||
              prevMatch.materialScale != f.materialScale ||
              prevMatch.materialRotation != f.materialRotation;

          if (materialChanged) {
            ref.read(viewportControllerProvider.notifier).sendCommand('UPDATE_MATERIAL', {
              'id': f.id,
              'color': f.materialColor,
              'opacity': f.opacity,
              'metallic': f.metallic,
              'roughness': f.roughness,
              'normalMap': f.normalMap,
              'baseColorMap': f.baseColorMap,
              'roughnessMap': f.roughnessMap,
              'metallicMap': f.metallicMap,
              'emissiveMap': f.emissiveMap,
              'emissiveColor': f.emissiveColor,
              'emissiveIntensity': f.emissiveIntensity,
              'scale': f.materialScale,
              'rotation': f.materialRotation,
            });
          }
        }
      }
    }
    
    // 2. Determine which furniture was removed
    if (previous != null) {
      for (final prevF in previous.furniture) {
        final hasMatch = next.furniture.any((n) => n.id == prevF.id);
        if (!hasMatch) {
          _loadedModelSignatures.remove(prevF.id);
          ref.read(viewportControllerProvider.notifier).sendCommand('REMOVE_MODEL', {
            'id': prevF.id,
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _loadedModelSignatures.clear();
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // --- RAYCAST GIZMO & SELECTION PICKER ---
  void _handleTapDown(TapDownDetails details, Size viewportSize) {
    _focusNode.requestFocus();
    final layout = ref.read(designerProvider);
    final notifier = ref.read(designerProvider.notifier);
    final cameraState = ref.read(cameraProvider);
    final lightingState = ref.read(lightingProvider);
    final lightingNotifier = ref.read(lightingProvider.notifier);
    
    final double px = details.localPosition.dx;
    final double py = details.localPosition.dy;
    final localTap = details.localPosition;

    if (widget.isWalkthroughMode) {
      final hit = _performRaycast(localTap, viewportSize);
      if (hit != null && hit.$1.startsWith('opening:')) {
        final opId = hit.$1.replaceFirst('opening:', '');
        try {
          final op = layout.openings.firstWhere((o) => o.id == opId);
          if (op.type == 'door') {
            final dist = (Offset(cameraState.position.x, cameraState.position.z) - op.position).distance;
            if (dist <= 150.0) {
              _toggleDoor(op);
              return;
            }
          }
        } catch (_) {}
      }
      return;
    }
    
    // 1. Calculate Ray in World Space
    double ndcX = (2.0 * px) / viewportSize.width - 1.0;
    double ndcY = 1.0 - (2.0 * py) / viewportSize.height;

    double halfHeight = tan(cameraState.fov / 2.0);
    double halfWidth = halfHeight * cameraState.aspect;

    final F = (cameraState.target - cameraState.position).normalize();
    final R = F.cross(cameraState.up).normalize();
    final U = R.cross(F).normalize();

    final rayDir = (F + R * (ndcX * halfWidth) + U * (ndcY * halfHeight)).normalize();
    final rayOrigin = cameraState.position;

    // 2. Check if tapped on a Light Gizmo Axis first (if a light is selected and transform mode is active)
    if (lightingState.selectedLightId != null && layout.transformMode != TransformMode.select) {
      try {
        final light = lightingState.lights.firstWhere((l) => l.id == lightingState.selectedLightId);
        final center3d = Vector3D(light.x, light.y, light.z);
        final double axisLength = 100.0;

        final pCenter = cameraState.projectPoint(center3d, viewportSize);
        final xTip3d = center3d + Vector3D(axisLength, 0, 0);
        final yTip3d = center3d + Vector3D(0, axisLength, 0);
        final zTip3d = center3d + Vector3D(0, 0, axisLength);

        final pX = cameraState.projectPoint(xTip3d, viewportSize);
        final pY = cameraState.projectPoint(yTip3d, viewportSize);
        final pZ = cameraState.projectPoint(zTip3d, viewportSize);

        if (pCenter != null) {
          if (layout.transformMode == TransformMode.translate) {
            String? hitAxis;
            double minHitDist = 20.0;

            if (pX != null) {
              final dX = _distanceToSegment(localTap, pCenter, pX);
              if (dX < minHitDist) { hitAxis = 'translateX'; minHitDist = dX; }
            }
            if (pY != null) {
              final dY = _distanceToSegment(localTap, pCenter, pY);
              if (dY < minHitDist) { hitAxis = 'translateY'; minHitDist = dY; }
            }
            if (pZ != null) {
              final dZ = _distanceToSegment(localTap, pCenter, pZ);
              if (dZ < minHitDist) { hitAxis = 'translateZ'; minHitDist = dZ; }
            }

            if (hitAxis != null) {
              setState(() {
                _selectedGizmoAxis = hitAxis;
                _dragStartOffset = localTap;
                _dragStartPos = Vector3D(light.x, light.y, light.z);
                _dragStartRot = Vector3D(light.rotationX, light.rotationY, light.rotationZ);
                _dragValueHUDText = null;
              });
              return;
            }
          } else if (layout.transformMode == TransformMode.rotate) {
            final double ringRadius = 50.0;
            double minDistX = double.infinity;
            double minDistY = double.infinity;
            double minDistZ = double.infinity;

            for (int i = 0; i < 24; i++) {
              double theta = i * 2 * pi / 24;
              final ptX = center3d + Vector3D(0, ringRadius * cos(theta), ringRadius * sin(theta));
              final p2dX = cameraState.projectPoint(ptX, viewportSize);
              if (p2dX != null) minDistX = min(minDistX, (localTap - p2dX).distance);

              final ptY = center3d + Vector3D(ringRadius * cos(theta), 0.1, ringRadius * sin(theta));
              final p2dY = cameraState.projectPoint(ptY, viewportSize);
              if (p2dY != null) minDistY = min(minDistY, (localTap - p2dY).distance);

              final ptZ = center3d + Vector3D(ringRadius * cos(theta), ringRadius * sin(theta), 0);
              final p2dZ = cameraState.projectPoint(ptZ, viewportSize);
              if (p2dZ != null) minDistZ = min(minDistZ, (localTap - p2dZ).distance);
            }

            String? hitRing;
            double minHitDist = 20.0;
            if (minDistX < minHitDist) { hitRing = 'rotateX'; minHitDist = minDistX; }
            if (minDistY < minHitDist) { hitRing = 'rotateY'; minHitDist = minDistY; }
            if (minDistZ < minHitDist) { hitRing = 'rotateZ'; minHitDist = minDistZ; }

            if (hitRing != null) {
              setState(() {
                _selectedGizmoAxis = hitRing;
                _dragStartOffset = localTap;
                _dragStartPos = Vector3D(light.x, light.y, light.z);
                _dragStartRot = Vector3D(light.rotationX, light.rotationY, light.rotationZ);
                _dragValueHUDText = null;
              });
              return;
            }
          }
        }
      } catch (_) {}
    }

    // 3. Check if tapped on a Furniture Gizmo Axis first (if object is selected and a transform mode is active)
    if (layout.selectedFurnitureId != null && layout.transformMode != TransformMode.select) {
      try {
        final f = layout.furniture.firstWhere((item) => item.id == layout.selectedFurnitureId);
        
        final center3d = Vector3D(f.x, f.y + f.height / 2, f.z);
        final double maxDim = max(f.width, max(f.depth, f.height));
        final double axisLength = maxDim / 2.0 + 60.0;

        final pCenter = cameraState.projectPoint(center3d, viewportSize);
        final xTip3d = center3d + Vector3D(axisLength, 0, 0);
        final yTip3d = center3d + Vector3D(0, axisLength, 0);
        final zTip3d = center3d + Vector3D(0, 0, axisLength);

        final pX = cameraState.projectPoint(xTip3d, viewportSize);
        final pY = cameraState.projectPoint(yTip3d, viewportSize);
        final pZ = cameraState.projectPoint(zTip3d, viewportSize);

        if (pCenter != null) {
          if (layout.transformMode == TransformMode.translate) {
            // Check axis handles (X = Red, Y = Green, Z = Blue)
            String? hitAxis;
            double minHitDist = 20.0;

            if (pX != null) {
              final dX = _distanceToSegment(localTap, pCenter, pX);
              if (dX < minHitDist) { hitAxis = 'translateX'; minHitDist = dX; }
            }
            if (pY != null) {
              final dY = _distanceToSegment(localTap, pCenter, pY);
              if (dY < minHitDist) { hitAxis = 'translateY'; minHitDist = dY; }
            }
            if (pZ != null) {
              final dZ = _distanceToSegment(localTap, pCenter, pZ);
              if (dZ < minHitDist) { hitAxis = 'translateZ'; minHitDist = dZ; }
            }

            if (hitAxis != null) {
              setState(() {
                _selectedGizmoAxis = hitAxis;
                _dragStartOffset = localTap;
                _dragStartPos = Vector3D(f.x, f.y, f.z);
                _dragStartRot = Vector3D(f.rotationX, f.rotationY, f.rotationZ);
                _dragStartScale = Vector3D(f.scaleX, f.scaleY, f.scaleZ);
                _dragValueHUDText = null;
              });
              return;
            }
          } 
          
          else if (layout.transformMode == TransformMode.rotate) {
            final double ringRadius = max(f.width, f.depth) / 2.0 + 35.0;
            double minDistX = double.infinity;
            double minDistY = double.infinity;
            double minDistZ = double.infinity;

            for (int i = 0; i < 24; i++) {
              double theta = i * 2 * pi / 24;
              // X-Ring (Y-Z plane)
              final ptX = center3d + Vector3D(0, ringRadius * cos(theta), ringRadius * sin(theta));
              final p2dX = cameraState.projectPoint(ptX, viewportSize);
              if (p2dX != null) minDistX = min(minDistX, (localTap - p2dX).distance);

              // Y-Ring (X-Z plane)
              final ptY = center3d + Vector3D(ringRadius * cos(theta), 0.1, ringRadius * sin(theta));
              final p2dY = cameraState.projectPoint(ptY, viewportSize);
              if (p2dY != null) minDistY = min(minDistY, (localTap - p2dY).distance);

              // Z-Ring (X-Y plane)
              final ptZ = center3d + Vector3D(ringRadius * cos(theta), ringRadius * sin(theta), 0);
              final p2dZ = cameraState.projectPoint(ptZ, viewportSize);
              if (p2dZ != null) minDistZ = min(minDistZ, (localTap - p2dZ).distance);
            }

            String? hitRing;
            double minHitDist = 20.0;
            if (minDistX < minHitDist) { hitRing = 'rotateX'; minHitDist = minDistX; }
            if (minDistY < minHitDist) { hitRing = 'rotateY'; minHitDist = minDistY; }
            if (minDistZ < minHitDist) { hitRing = 'rotateZ'; minHitDist = minDistZ; }

            if (hitRing != null) {
              setState(() {
                _selectedGizmoAxis = hitRing;
                _dragStartOffset = localTap;
                _dragStartPos = Vector3D(f.x, f.y, f.z);
                _dragStartRot = Vector3D(f.rotationX, f.rotationY, f.rotationZ);
                _dragStartScale = Vector3D(f.scaleX, f.scaleY, f.scaleZ);
                _dragValueHUDText = null;
              });
              return;
            }
          } 
          
          else if (layout.transformMode == TransformMode.scale) {
            // Check center uniform scale first
            final distToCenter = (localTap - pCenter).distance;
            if (distToCenter < 18.0) {
              setState(() {
                _selectedGizmoAxis = 'scaleUniform';
                _dragStartOffset = localTap;
                _dragStartPos = Vector3D(f.x, f.y, f.z);
                _dragStartRot = Vector3D(f.rotationX, f.rotationY, f.rotationZ);
                _dragStartScale = Vector3D(f.scaleX, f.scaleY, f.scaleZ);
                _dragValueHUDText = null;
              });
              return;
            }

            // Check axis scale handles
            String? hitScale;
            double minHitDist = 20.0;

            if (pX != null) {
              final dX = _distanceToSegment(localTap, pCenter, pX);
              if (dX < minHitDist) { hitScale = 'scaleX'; minHitDist = dX; }
            }
            if (pY != null) {
              final dY = _distanceToSegment(localTap, pCenter, pY);
              if (dY < minHitDist) { hitScale = 'scaleY'; minHitDist = dY; }
            }
            if (pZ != null) {
              final dZ = _distanceToSegment(localTap, pCenter, pZ);
              if (dZ < minHitDist) { hitScale = 'scaleZ'; minHitDist = dZ; }
            }

            if (hitScale != null) {
              setState(() {
                _selectedGizmoAxis = hitScale;
                _dragStartOffset = localTap;
                _dragStartPos = Vector3D(f.x, f.y, f.z);
                _dragStartRot = Vector3D(f.rotationX, f.rotationY, f.rotationZ);
                _dragStartScale = Vector3D(f.scaleX, f.scaleY, f.scaleZ);
                _dragValueHUDText = null;
              });
              return;
            }
          }
        }
      } catch (_) {}
    }

    // 4. Check if clicked close to a light source gizmo in 2D
    String? hitLightId;
    double minLightDist = 24.0;
    for (final light in lightingState.lights) {
      if (light.type == LightType.ambient) continue;
      final pLight = cameraState.projectPoint(Vector3D(light.x, light.y, light.z), viewportSize);
      if (pLight != null) {
        final dist = (localTap - pLight).distance;
        if (dist < minLightDist) {
          hitLightId = light.id;
          minLightDist = dist;
        }
      }
    }

    if (hitLightId != null) {
      lightingNotifier.selectLight(hitLightId);
      notifier.clearSelection();
      return;
    }

    // 5. Raycast intersect against furniture bounding boxes
    String? closestId;
    double minT = double.infinity;

    for (final f in layout.furniture) {
      final minLoc = Vector3D(-f.width/2, 0.0, -f.depth/2);
      final maxLoc = Vector3D(f.width/2, f.height, f.depth/2);
      
      final transRayOrigin = rayOrigin - Vector3D(f.x, f.y, f.z);
      final rot = -f.rotationY;
      final c = cos(rot);
      final s = sin(rot);
      
      final localRayOrigin = Vector3D(
        transRayOrigin.x * c - transRayOrigin.z * s,
        transRayOrigin.y,
        transRayOrigin.x * s + transRayOrigin.z * c
      );
      final localRayDir = Vector3D(
        rayDir.x * c - rayDir.z * s,
        rayDir.y,
        rayDir.x * s + rayDir.z * c
      ).normalize();

      final aabb = BoundingBox3D(minLoc, maxLoc);
      final outDistance = <double>[];
      if (aabb.intersectsRay(localRayOrigin, localRayDir, outDistance)) {
        final t = outDistance[0];
        if (t < minT) {
          minT = t;
          closestId = f.id;
        }
      }
    }

    if (closestId != null) {
      notifier.selectFurniture(closestId);
      lightingNotifier.clearSelection();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => MaterialLibraryScreen(
            targetElementType: 'furniture',
            targetElementId: closestId,
          ),
        ),
      );
    } else {
      notifier.clearSelection();
      lightingNotifier.clearSelection();
    }
  }

  void _handleDoubleTap(TapDownDetails details, Size viewportSize) {
    final layout = ref.read(designerProvider);
    final cameraState = ref.read(cameraProvider);
    final viewMode = ref.read(viewModeProvider);
    
    final double px = details.localPosition.dx;
    final double py = details.localPosition.dy;
    
    // 1. Calculate Ray in World Space
    double ndcX = (2.0 * px) / viewportSize.width - 1.0;
    double ndcY = 1.0 - (2.0 * py) / viewportSize.height;

    double halfHeight = tan(cameraState.fov / 2.0);
    double halfWidth = halfHeight * cameraState.aspect;

    final F = (cameraState.target - cameraState.position).normalize();
    final R = F.cross(cameraState.up).normalize();
    final U = R.cross(F).normalize();

    final rayDir = (F + R * (ndcX * halfWidth) + U * (ndcY * halfHeight)).normalize();
    final rayOrigin = cameraState.position;

    // 2. Raycast intersect against furniture bounding boxes
    String? closestId;
    double minT = double.infinity;

    for (final f in layout.furniture) {
      final minLoc = Vector3D(-f.width/2, 0.0, -f.depth/2);
      final maxLoc = Vector3D(f.width/2, f.height, f.depth/2);
      
      final transRayOrigin = rayOrigin - Vector3D(f.x, f.y, f.z);
      final rot = -f.rotationY;
      final c = cos(rot);
      final s = sin(rot);
      
      final localRayOrigin = Vector3D(
        transRayOrigin.x * c - transRayOrigin.z * s,
        transRayOrigin.y,
        transRayOrigin.x * s + transRayOrigin.z * c
      );
      final localRayDir = Vector3D(
        rayDir.x * c - rayDir.z * s,
        rayDir.y,
        rayDir.x * s + rayDir.z * c
      ).normalize();

      final aabb = BoundingBox3D(minLoc, maxLoc);
      final outDistance = <double>[];
      if (aabb.intersectsRay(localRayOrigin, localRayDir, outDistance)) {
        final t = outDistance[0];
        if (t < minT) {
          minT = t;
          closestId = f.id;
        }
      }
    }

    if (closestId != null) {
      final f = layout.furniture.firstWhere((item) => item.id == closestId);
      ref.read(cameraProvider.notifier).focusFurniture(f);
      SnackbarManager.showSuccess(context, 'Camera focused on ${f.name}');
    } else {
      final isFree = viewMode == ViewMode.free;
      ref.read(cameraProvider.notifier).zoom(-300.0, isFree); // Zoom in on empty space
      SnackbarManager.showSuccess(context, 'Zoomed in');
    }
  }

  // --- SMOOTH ROTATE, PAN & ZOOM GESTURE HANDLERS ---
  double _prevScale = 1.0;
  Offset _prevFocalPoint = Offset.zero;

  void _handleScaleStart(ScaleStartDetails details) {
    _prevScale = 1.0;
    _prevFocalPoint = details.localFocalPoint;
    _focusNode.requestFocus();
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, Size viewportSize) {
    final layout = ref.read(designerProvider);
    final settings = ref.read(navigationProvider);
    final viewMode = ref.read(viewModeProvider);
    final cameraNotifier = ref.read(cameraProvider.notifier);
    final lightingState = ref.read(lightingProvider);

    // 1. Move/Rotate if dragging a 3D light gizmo handle
    if (_selectedGizmoAxis != null && _dragStartOffset != null && lightingState.selectedLightId != null) {
      final delta = details.localFocalPoint - _dragStartOffset!;
      final lightingNotifier = ref.read(lightingProvider.notifier);
      final cameraState = ref.read(cameraProvider);

      try {
        final light = lightingState.lights.firstWhere((l) => l.id == lightingState.selectedLightId);
        final center3d = Vector3D(light.x, light.y, light.z);
        final double axisLength = 100.0;

        final pCenter = cameraState.projectPoint(center3d, viewportSize);
        final xTip3d = center3d + Vector3D(axisLength, 0, 0);
        final yTip3d = center3d + Vector3D(0, axisLength, 0);
        final zTip3d = center3d + Vector3D(0, 0, axisLength);

        final pX = cameraState.projectPoint(xTip3d, viewportSize);
        final pY = cameraState.projectPoint(yTip3d, viewportSize);
        final pZ = cameraState.projectPoint(zTip3d, viewportSize);

        if (pCenter != null) {
          if (_selectedGizmoAxis!.startsWith('translate')) {
            Offset? pTip;
            if (_selectedGizmoAxis == 'translateX') pTip = pX;
            else if (_selectedGizmoAxis == 'translateY') pTip = pY;
            else pTip = pZ;

            if (pTip != null) {
              final axis2D = pTip - pCenter;
              final axis2DLength = axis2D.distance;
              if (axis2DLength > 2.0) {
                final axis2DDir = axis2D / axis2DLength;
                final dragOnAxis = delta.dx * axis2DDir.dx + delta.dy * axis2DDir.dy;
                double worldDelta = dragOnAxis * (axisLength / axis2DLength);

                double newX = _dragStartPos!.x;
                double newY = _dragStartPos!.y;
                double newZ = _dragStartPos!.z;

                if (_selectedGizmoAxis == 'translateX') newX += worldDelta;
                else if (_selectedGizmoAxis == 'translateY') newY += worldDelta;
                else newZ += worldDelta;

                if (layout.snapToGrid) {
                  final spacing = layout.gridSpacing;
                  newX = (newX / spacing).round() * spacing;
                  newY = (newY / spacing).round() * spacing;
                  newZ = (newZ / spacing).round() * spacing;
                }

                lightingNotifier.updateLight(light.id, x: newX, y: newY, z: newZ);

                setState(() {
                  if (_selectedGizmoAxis == 'translateX') {
                    _dragValueHUDText = 'Move Light X: ${newX.toStringAsFixed(1)} cm';
                  } else if (_selectedGizmoAxis == 'translateY') {
                    _dragValueHUDText = 'Move Light Y: ${newY.toStringAsFixed(1)} cm';
                  } else {
                    _dragValueHUDText = 'Move Light Z: ${newZ.toStringAsFixed(1)} cm';
                  }
                });
              }
            }
          } 
          
          else if (_selectedGizmoAxis!.startsWith('rotate')) {
            final currentAngle = atan2(details.localFocalPoint.dy - pCenter.dy, details.localFocalPoint.dx - pCenter.dx);
            final startAngle = atan2(_dragStartOffset!.dy - pCenter.dy, _dragStartOffset!.dx - pCenter.dx);
            double angleDelta = currentAngle - startAngle;

            if (layout.snapToGrid) {
              final snapAngle = 15.0 * pi / 180.0;
              angleDelta = (angleDelta / snapAngle).round() * snapAngle;
            }

            double newRotX = _dragStartRot!.x;
            double newRotY = _dragStartRot!.y;
            double newRotZ = _dragStartRot!.z;

            if (_selectedGizmoAxis == 'rotateX') newRotX += angleDelta;
            else if (_selectedGizmoAxis == 'rotateY') newRotY += angleDelta;
            else newRotZ += angleDelta;

            lightingNotifier.updateLight(
              light.id,
              rotationX: newRotX,
              rotationY: newRotY,
              rotationZ: newRotZ,
            );

            setState(() {
              if (_selectedGizmoAxis == 'rotateX') {
                _dragValueHUDText = 'Rotate Light X: ${(newRotX * 180 / pi).round()}°';
              } else if (_selectedGizmoAxis == 'rotateY') {
                _dragValueHUDText = 'Rotate Light Y: ${(newRotY * 180 / pi).round()}°';
              } else {
                _dragValueHUDText = 'Rotate Light Z: ${(newRotZ * 180 / pi).round()}°';
              }
            });
          }
        }
      } catch (_) {}
      return;
    }

    // 2. Move/Rotate/Scale furniture if dragging a 3D gizmo handle
    if (_selectedGizmoAxis != null && _dragStartOffset != null && layout.selectedFurnitureId != null) {
      final delta = details.localFocalPoint - _dragStartOffset!;
      final notifier = ref.read(designerProvider.notifier);
      final cameraState = ref.read(cameraProvider);
      
      try {
        final f = layout.furniture.firstWhere((item) => item.id == layout.selectedFurnitureId);
        
        final center3d = Vector3D(f.x, f.y + f.height / 2, f.z);
        final double maxDim = max(f.width, max(f.depth, f.height));
        final double axisLength = maxDim / 2.0 + 60.0;

        final pCenter = cameraState.projectPoint(center3d, viewportSize);
        final xTip3d = center3d + Vector3D(axisLength, 0, 0);
        final yTip3d = center3d + Vector3D(0, axisLength, 0);
        final zTip3d = center3d + Vector3D(0, 0, axisLength);

        final pX = cameraState.projectPoint(xTip3d, viewportSize);
        final pY = cameraState.projectPoint(yTip3d, viewportSize);
        final pZ = cameraState.projectPoint(zTip3d, viewportSize);

        if (pCenter != null) {
          if (_selectedGizmoAxis!.startsWith('translate')) {
            Offset? pTip;
            if (_selectedGizmoAxis == 'translateX') pTip = pX;
            else if (_selectedGizmoAxis == 'translateY') pTip = pY;
            else pTip = pZ;

            if (pTip != null) {
              final axis2D = pTip - pCenter;
              final axis2DLength = axis2D.distance;
              if (axis2DLength > 2.0) {
                final axis2DDir = axis2D / axis2DLength;
                final dragOnAxis = delta.dx * axis2DDir.dx + delta.dy * axis2DDir.dy;
                double worldDelta = dragOnAxis * (axisLength / axis2DLength);

                double newX = _dragStartPos!.x;
                double newY = _dragStartPos!.y;
                double newZ = _dragStartPos!.z;

                if (_selectedGizmoAxis == 'translateX') newX += worldDelta;
                else if (_selectedGizmoAxis == 'translateY') newY += worldDelta;
                else newZ += worldDelta;

                if (layout.snapToGrid) {
                  final spacing = layout.gridSpacing;
                  newX = (newX / spacing).round() * spacing;
                  newY = (newY / spacing).round() * spacing;
                  newZ = (newZ / spacing).round() * spacing;
                }

                notifier.updateSelectedFurnitureTransform(x: newX, y: newY, z: newZ);

                setState(() {
                  if (_selectedGizmoAxis == 'translateX') {
                    _dragValueHUDText = 'Move X: ${newX.toStringAsFixed(1)} cm';
                  } else if (_selectedGizmoAxis == 'translateY') {
                    _dragValueHUDText = 'Move Y: ${newY.toStringAsFixed(1)} cm';
                  } else {
                    _dragValueHUDText = 'Move Z: ${newZ.toStringAsFixed(1)} cm';
                  }
                });
              }
            }
          } 
          
          else if (_selectedGizmoAxis!.startsWith('rotate')) {
            final currentAngle = atan2(details.localFocalPoint.dy - pCenter.dy, details.localFocalPoint.dx - pCenter.dx);
            final startAngle = atan2(_dragStartOffset!.dy - pCenter.dy, _dragStartOffset!.dx - pCenter.dx);
            double angleDelta = currentAngle - startAngle;

            if (layout.snapToGrid) {
              final snapAngle = 15.0 * pi / 180.0;
              angleDelta = (angleDelta / snapAngle).round() * snapAngle;
            }

            double newRotX = _dragStartRot!.x;
            double newRotY = _dragStartRot!.y;
            double newRotZ = _dragStartRot!.z;

            if (_selectedGizmoAxis == 'rotateX') newRotX += angleDelta;
            else if (_selectedGizmoAxis == 'rotateY') newRotY += angleDelta;
            else newRotZ += angleDelta;

            notifier.updateSelectedFurnitureTransform(
              rotationX: newRotX,
              rotationY: newRotY,
              rotationZ: newRotZ,
            );

            setState(() {
              if (_selectedGizmoAxis == 'rotateX') {
                _dragValueHUDText = 'Rotate X: ${(newRotX * 180 / pi).round()}°';
              } else if (_selectedGizmoAxis == 'rotateY') {
                _dragValueHUDText = 'Rotate Y: ${(newRotY * 180 / pi).round()}°';
              } else {
                _dragValueHUDText = 'Rotate Z: ${(newRotZ * 180 / pi).round()}°';
              }
            });
          } 
          
          else if (_selectedGizmoAxis!.startsWith('scale')) {
            if (_selectedGizmoAxis == 'scaleUniform') {
              double startDist = (_dragStartOffset! - pCenter).distance;
              double currentDist = (details.localFocalPoint - pCenter).distance;
              double scaleFactor = startDist > 5.0 ? (currentDist / startDist) : 1.0;

              if (layout.snapToGrid) {
                scaleFactor = (scaleFactor * 10.0).round() / 10.0;
              }

              double newScaleX = (_dragStartScale!.x * scaleFactor).clamp(0.1, 5.0);
              double newScaleY = (_dragStartScale!.y * scaleFactor).clamp(0.1, 5.0);
              double newScaleZ = (_dragStartScale!.z * scaleFactor).clamp(0.1, 5.0);

              notifier.updateSelectedFurnitureTransform(
                scaleX: newScaleX,
                scaleY: newScaleY,
                scaleZ: newScaleZ,
              );

              setState(() {
                _dragValueHUDText = 'Scale: ${scaleFactor.toStringAsFixed(2)}x';
              });
            } 
            
            else {
              Offset? pTip;
              if (_selectedGizmoAxis == 'scaleX') pTip = pX;
              else if (_selectedGizmoAxis == 'scaleY') pTip = pY;
              else pTip = pZ;

              if (pTip != null) {
                final axis2D = pTip - pCenter;
                final axis2DLength = axis2D.distance;
                if (axis2DLength > 2.0) {
                  final axis2DDir = axis2D / axis2DLength;
                  final dragOnAxis = delta.dx * axis2DDir.dx + delta.dy * axis2DDir.dy;
                  double scaleFactor = 1.0 + dragOnAxis / axis2DLength;

                  if (layout.snapToGrid) {
                    scaleFactor = (scaleFactor * 10.0).round() / 10.0;
                  }

                  double newScaleX = _dragStartScale!.x;
                  double newScaleY = _dragStartScale!.y;
                  double newScaleZ = _dragStartScale!.z;

                  if (_selectedGizmoAxis == 'scaleX') {
                    newScaleX = (_dragStartScale!.x * scaleFactor).clamp(0.1, 5.0);
                  } else if (_selectedGizmoAxis == 'scaleY') {
                    newScaleY = (_dragStartScale!.y * scaleFactor).clamp(0.1, 5.0);
                  } else {
                    newScaleZ = (_dragStartScale!.z * scaleFactor).clamp(0.1, 5.0);
                  }

                  notifier.updateSelectedFurnitureTransform(
                    scaleX: newScaleX,
                    scaleY: newScaleY,
                    scaleZ: newScaleZ,
                  );

                  setState(() {
                    if (_selectedGizmoAxis == 'scaleX') {
                      _dragValueHUDText = 'Scale X: ${newScaleX.toStringAsFixed(2)}x';
                    } else if (_selectedGizmoAxis == 'scaleY') {
                      _dragValueHUDText = 'Scale Y: ${newScaleY.toStringAsFixed(2)}x';
                    } else {
                      _dragValueHUDText = 'Scale Z: ${newScaleZ.toStringAsFixed(2)}x';
                    }
                  });
                }
              }
            }
          }
        }
      } catch (_) {}
      return;
    }

    // 2. Default camera controls
    final isFree = viewMode == ViewMode.free;

    if (_isMouse) {
      final delta = details.localFocalPoint - _prevFocalPoint;
      _prevFocalPoint = details.localFocalPoint;
      if (delta != Offset.zero) {
        if (_activePointerButton == kMiddleMouseButton) {
          cameraNotifier.pan(delta.dx, delta.dy);
        } else if (_activePointerButton == kPrimaryMouseButton) {
          cameraNotifier.rotate(delta.dx, delta.dy, settings.rotationSpeed, isFree);
        }
      }
    } else {
      if (details.pointerCount == 2) {
        // Pinch Zoom & Two-finger Pan
        if (details.scale != 1.0) {
          final scaleRatio = details.scale / _prevScale;
          _prevScale = details.scale;
          
          final zoomDelta = (1.0 - scaleRatio) * settings.zoomSpeed * 10.0;
          cameraNotifier.zoom(zoomDelta, isFree);
        }

        final delta = details.localFocalPoint - _prevFocalPoint;
        _prevFocalPoint = details.localFocalPoint;
        if (delta != Offset.zero) {
          cameraNotifier.pan(delta.dx, delta.dy);
        }
      } else if (details.pointerCount == 1) {
        // One-finger Drag to Orbit / Rotate
        final delta = details.localFocalPoint - _prevFocalPoint;
        _prevFocalPoint = details.localFocalPoint;
        if (delta != Offset.zero) {
          cameraNotifier.rotate(delta.dx, delta.dy, settings.rotationSpeed, isFree);
        }
      }
    }
  }

  void _handleScaleEnd() {
    setState(() {
      _selectedGizmoAxis = null;
      _dragStartOffset = null;
      _dragStartPos = null;
      _dragStartRot = null;
      _dragStartScale = null;
      _dragValueHUDText = null;
    });
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final l2 = (a - b).distanceSquared;
    if (l2 == 0) return (p - a).distance;
    final t = ((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2;
    final clampedT = t.clamp(0.0, 1.0);
    final projection = Offset(
      a.dx + clampedT * (b.dx - a.dx),
      a.dy + clampedT * (b.dy - a.dy),
    );
    return (p - projection).distance;
  }

  void _toggleDoor(Opening op) {
    setState(() {
      if (_openDoorIds.contains(op.id)) {
        _openDoorIds.remove(op.id);
        SnackbarManager.showSuccess(context, 'Door closed');
      } else {
        _openDoorIds.add(op.id);
        SnackbarManager.showSuccess(context, 'Door opened');
      }
    });
    _sendLoadRoomCommand(ref.read(designerProvider));
  }

  Opening? _getNearestDoor(Vector3D pos, List<Opening> openings) {
    Opening? nearest;
    double minDist = double.infinity;
    for (final op in openings) {
      if (op.type != 'door') continue;
      final dist = (Offset(pos.x, pos.z) - op.position).distance;
      if (dist < minDist) {
        minDist = dist;
        nearest = op;
      }
    }
    if (minDist <= 150.0) return nearest;
    return null;
  }

  // --- RENDERING PIPELINE ASSEMBLY ---
  List<Polygon3D> _build3DScene(DesignerLayoutState layout) {
    final List<Polygon3D> polys = [];
    
    // 1. FLOOR
    double roomLen = 600.0;
    double roomWid = 450.0;
    double minX = -300.0, maxX = 300.0;
    double minZ = -225.0, maxZ = 225.0;
    if (layout.walls.isNotEmpty) {
      minX = double.infinity; maxX = -double.infinity;
      minZ = double.infinity; maxZ = -double.infinity;
      for (final w in layout.walls) {
        minX = min(minX, min(w.start.dx, w.end.dx));
        maxX = max(maxX, max(w.start.dx, w.end.dx));
        minZ = min(minZ, min(w.start.dy, w.end.dy));
        maxZ = max(maxZ, max(w.start.dy, w.end.dy));
      }
      roomLen = maxX - minX;
      roomWid = maxZ - minZ;
    }
    
    double cx = minX + roomLen / 2;
    double cz = minZ + roomWid / 2;

    Color floorColor = Colors.grey.shade300;
    if (layout.floorMaterialColor != null) {
      try {
        floorColor = Color(int.parse('FF${layout.floorMaterialColor!.replaceAll("#", "")}', radix: 16));
      } catch (_) {}
    } else if (layout.floorMaterialType == 'wood') {
      floorColor = Colors.amber.shade900;
    } else if (layout.floorMaterialType == 'carpet') {
      floorColor = Colors.blueGrey.shade200;
    }
    
    final isSample = layout.walls.length >= 8 &&
                     layout.walls.any((w) => w.start.dx == 1900 && w.end.dx == 1900);
                     
    if (isSample) {
      // Render 5 room floors with realistic colors and materials
      // 1. Bedroom: X: 1500 to 1900, Z: 1600 to 2100. Center: (1700, 1850). Size: 400x500
      polys.addAll(ProceduralMeshGenerator.createBox(
        1700, -2.0, 1850,
        400.0, 4.0, 500.0,
        Colors.brown.shade800,
        roughness: 0.6,
        texture: 'wood',
      ));
      // 2. Balcony: X: 1500 to 1900, Z: 2100 to 2400. Center: (1700, 2250). Size: 400x300
      polys.addAll(ProceduralMeshGenerator.createBox(
        1700, -2.0, 2250,
        400.0, 4.0, 300.0,
        Colors.grey.shade600,
        roughness: 0.9,
        texture: 'tile',
      ));
      // 3. Bathroom: X: 1900 to 2200, Z: 1600 to 1900. Center: (2050, 1750). Size: 300x300
      polys.addAll(ProceduralMeshGenerator.createBox(
        2050, -2.0, 1750,
        300.0, 4.0, 300.0,
        Colors.blueGrey.shade100,
        roughness: 0.8,
        texture: 'tile',
      ));
      // 4. Kitchen: X: 2200 to 2500, Z: 1600 to 1900. Center: (2350, 1750). Size: 300x300
      polys.addAll(ProceduralMeshGenerator.createBox(
        2350, -2.0, 1750,
        300.0, 4.0, 300.0,
        Colors.amber.shade50,
        roughness: 0.9,
        texture: 'tile',
      ));
      // 5. Living/Dining: X: 1900 to 2500, Z: 1900 to 2400. Center: (2200, 2150). Size: 600x500
      polys.addAll(ProceduralMeshGenerator.createBox(
        2200, -2.0, 2150,
        600.0, 4.0, 500.0,
        Colors.amber.shade50,
        roughness: 0.9,
        texture: 'tile',
      ));
    } else {
      polys.addAll(ProceduralMeshGenerator.createBox(
        cx, -2.0, cz,
        roomLen, 4.0, roomWid,
        floorColor,
        metallic: layout.floorMetallic,
        roughness: layout.floorRoughness,
        texture: layout.floorMaterialType ?? 'tile',
      ));
    }

    // 2. CEILING
    if (_showCeiling) {
      Color ceilingColor = Colors.white;
      if (layout.ceilingMaterialColor != null) {
        try {
          ceilingColor = Color(int.parse('FF${layout.ceilingMaterialColor!.replaceAll("#", "")}', radix: 16));
        } catch (_) {}
      }
      polys.addAll(ProceduralMeshGenerator.createBox(
        cx, 300.0, cz,
        roomLen, 4.0, roomWid,
        ceilingColor,
        metallic: layout.ceilingMetallic,
        roughness: layout.ceilingRoughness,
        texture: layout.ceilingMaterialType,
      ));
    }

    // 3. WALLS
    if (_wallDisplayMode != 'hidden') {
    Color wallColor = Colors.grey.shade100;
    if (layout.wallMaterialColor != null) {
      try {
        wallColor = Color(int.parse('FF${layout.wallMaterialColor!.replaceAll("#", "")}', radix: 16));
      } catch (_) {}
    }
    
    // Wall height depends on display mode: full=300, low=120
    final double wallRenderHeight = _wallDisplayMode == 'full' ? 300.0 : 120.0;
    final double wallOpacity = _wallDisplayMode == 'full' ? 1.0 : 0.5;
    
    for (final w in layout.walls) {
      final dx = w.end.dx - w.start.dx;
      final dz = w.end.dy - w.start.dy;
      final len = sqrt(dx*dx + dz*dz);
      if (len == 0) continue;
      
      final wallCenter = Offset(w.start.dx + dx / 2, w.start.dy + dz / 2);
      final angle = atan2(dz, dx);
      
      final isExterior = (w.thickness > 12.0);
      Color currentWallColor = isExterior ? Colors.grey.shade800 : wallColor;
      currentWallColor = currentWallColor.withOpacity(wallOpacity);
      
      final List<Polygon3D> wallBox = ProceduralMeshGenerator.createBox(
        0, wallRenderHeight / 2.0, 0,
        len, wallRenderHeight, w.thickness,
        currentWallColor,
        metallic: isExterior ? 0.0 : layout.wallMetallic,
        roughness: isExterior ? 0.9 : layout.wallRoughness,
        texture: isExterior ? null : layout.wallMaterialType,
      );
      
      final transMatrix = Matrix4x4.multiply(
        Matrix4x4.rotationY(-angle),
        Matrix4x4.translation(wallCenter.dx, 0, wallCenter.dy),
      );
      
      for (final poly in wallBox) {
        polys.add(poly.copyTransformed(transMatrix));
      }
    }
    }

    // 4. OPENINGS
    for (final op in layout.openings) {
      if (op.type == 'door') {
        final List<Polygon3D> doorBox = ProceduralMeshGenerator.createBox(
          0, 100.0, 0,
          op.width, 200.0, 6.0,
          Colors.brown.shade800,
          roughness: 0.8,
        );
        final double doorAngle = _openDoorIds.contains(op.id) ? op.angle + pi / 2 : op.angle;
        final transMatrix = Matrix4x4.multiply(
          Matrix4x4.rotationY(-doorAngle),
          Matrix4x4.translation(op.position.dx, 0.0, op.position.dy),
        );
        for (final poly in doorBox) {
          polys.add(poly.copyTransformed(transMatrix));
        }
      } else {
        final List<Polygon3D> windowBox = ProceduralMeshGenerator.createBox(
          0, 150.0, 0,
          op.width, 100.0, 8.0,
          Colors.lightBlue.withOpacity(0.5),
          roughness: 0.1,
          metallic: 0.1,
        );
        final transMatrix = Matrix4x4.multiply(
          Matrix4x4.rotationY(-op.angle),
          Matrix4x4.translation(op.position.dx, 0.0, op.position.dy),
        );
        for (final poly in windowBox) {
          polys.add(poly.copyTransformed(transMatrix));
        }
      }
    }

    // 5. FURNITURE
    for (final f in layout.furniture) {
      Color fColor = AppTheme.primary.shade400;
      if (f.materialColor != null) {
        try {
          fColor = Color(int.parse('FF${f.materialColor!.replaceAll("#", "")}', radix: 16));
        } catch (_) {}
      }
      fColor = fColor.withOpacity(f.opacity);
      
      String? glbUrl;
      try {
        final matchingAsset = widget.furnitureAssets.firstWhere((a) => a.id == f.assetId);
        glbUrl = matchingAsset.glbUrl;
      } catch (_) {}
      
      if (glbUrl == null || glbUrl.isEmpty) {
        if (f.assetId.isNotEmpty) {
          glbUrl = '/uploads/furniture/models/${f.assetId}.glb';
        }
      }
      
      List<Polygon3D>? itemPolys;
      if (glbUrl != null && glbUrl.isNotEmpty) {
        if (_glbPolygonsCache.containsKey(f.assetId)) {
          final cached = _glbPolygonsCache[f.assetId]!;
          itemPolys = cached.map((p) => Polygon3D(
            vertices: p.vertices,
            baseColor: fColor,
            normal: p.normal,
            metallic: f.metallic,
            roughness: f.roughness,
          )).toList();
        } else {
          _loadGlbForAsset(f.assetId, glbUrl);
        }
      }
      
      itemPolys ??= ProceduralMeshGenerator.generateFurnitureMesh(
        f.name,
        f.width, f.depth, f.height,
        fColor,
        metallic: f.metallic,
        roughness: f.roughness,
      );
      
      final rotMatrix = Matrix4x4.multiply(
        Matrix4x4.multiply(
          Matrix4x4.rotationX(-f.rotationX),
          Matrix4x4.rotationY(-f.rotationY),
        ),
        Matrix4x4.rotationZ(-f.rotationZ),
      );

      final transMatrix = Matrix4x4.multiply(
        Matrix4x4.translation(f.x, f.y, f.z),
        Matrix4x4.multiply(
          rotMatrix,
          Matrix4x4.scale(f.scaleX, f.scaleY, f.scaleZ),
        ),
      );

      for (final poly in itemPolys) {
        polys.add(poly.copyTransformed(transMatrix));
      }
    }

    return polys;
  }

  // --- FLOATING CAMERA TOOLBAR ---
  Widget _buildCameraToolbar(DesignerLayoutState layout) {
    final viewMode = ref.watch(viewModeProvider);

    return Card(
      color: Colors.black.withOpacity(0.85),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // View Preset Selector (Isometric, Top, Front, Left, Right)
            DropdownButtonHideUnderline(
              child: DropdownButton<ViewMode>(
                value: viewMode,
                dropdownColor: Colors.grey.shade900,
                icon: const Icon(Icons.videocam, color: AppTheme.primary, size: 18),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                selectedItemBuilder: (context) {
                  return ViewMode.values.map<Widget>((ViewMode mode) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Text(
                          _getViewModeLabel(mode),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    );
                  }).toList();
                },
                items: ViewMode.values.map((ViewMode mode) {
                  return DropdownMenuItem<ViewMode>(
                    value: mode,
                    child: Text(
                      _getViewModeLabel(mode),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  );
                }).toList(),
                onChanged: (ViewMode? val) {
                  if (val != null) {
                    ref.read(viewModeProvider.notifier).setMode(val);
                    final presetName = val == ViewMode.top ? 'TOP' : (val == ViewMode.front ? 'FRONT' : (val == ViewMode.left ? 'LEFT' : (val == ViewMode.right ? 'RIGHT' : 'ISOMETRIC')));
                    ref.read(viewportControllerProvider.notifier).sendCommand('SET_CAMERA_VIEW', {'preset': presetName});
                    SnackbarManager.showSuccess(context, 'Camera Mode: ${_getViewModeLabel(val)}');
                  }
                },
              ),
            ),
            const SizedBox(width: 4),
            Container(width: 1, height: 20, color: Colors.grey.shade700),
            const SizedBox(width: 4),
            
            // Reset to Isometric Fit
            IconButton(
              icon: const Icon(Icons.restart_alt, color: Colors.white, size: 18),
              tooltip: 'Reset to Isometric View',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () {
                ref.read(viewportControllerProvider.notifier).sendCommand('FIT_CAMERA_TO_ROOM', {});
                ref.read(viewportControllerProvider.notifier).sendCommand('SET_CAMERA_VIEW', {'preset': 'ISOMETRIC'});
                ref.read(cameraProvider.notifier).resetToRoom(layout);
                SnackbarManager.showSuccess(context, 'Camera reset to Isometric Room view.');
              },
            ),
            
            // Focus Button
            IconButton(
              icon: const Icon(Icons.filter_center_focus, color: Colors.white, size: 18),
              tooltip: 'Focus Object',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () {
                if (layout.selectedFurnitureId != null) {
                  final f = layout.furniture.firstWhere((item) => item.id == layout.selectedFurnitureId);
                  ref.read(cameraProvider.notifier).focusFurniture(f);
                  SnackbarManager.showSuccess(context, 'Focused on: ${f.name}');
                } else {
                  ref.read(viewportControllerProvider.notifier).sendCommand('FIT_CAMERA_TO_ROOM', {});
                  SnackbarManager.showSuccess(context, 'No object selected. Reframed room.');
                }
              },
            ),

            const SizedBox(width: 4),
            Container(width: 1, height: 20, color: Colors.grey.shade700),
            const SizedBox(width: 4),

            // Wall Visibility Toggle
            IconButton(
              icon: Icon(
                _wallDisplayMode == 'full' ? Icons.visibility :
                _wallDisplayMode == 'low' ? Icons.visibility_outlined :
                Icons.visibility_off_outlined,
                color: _wallDisplayMode == 'hidden' ? Colors.orange : Colors.white,
                size: 18,
              ),
              tooltip: 'Wall Visibility: ${_wallDisplayMode == "full" ? "Full" : _wallDisplayMode == "low" ? "Low (Cutaway)" : "Hidden"}',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () {
                setState(() {
                  if (_wallDisplayMode == 'low') {
                    _wallDisplayMode = 'full';
                  } else if (_wallDisplayMode == 'full') {
                    _wallDisplayMode = 'hidden';
                  } else {
                    _wallDisplayMode = 'low';
                  }
                });
                SnackbarManager.showSuccess(context, 'Walls: $_wallDisplayMode');
              },
            ),

            const SizedBox(width: 4),
            Container(width: 1, height: 20, color: Colors.grey.shade700),
            const SizedBox(width: 4),

            // Generate Room Image Button
            IconButton(
              icon: const Icon(Icons.camera_enhance, color: Colors.greenAccent, size: 18),
              tooltip: 'Generate Room Image (1920x1080)',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () {
                ref.read(viewportControllerProvider.notifier).sendCommand('GENERATE_IMAGE', {});
                SnackbarManager.showSuccess(context, 'Generating high-res 1920x1080 room render...');
              },
            ),

            // Debug Geometry Button
            IconButton(
              icon: Icon(
                Icons.bug_report,
                color: _isDebugGeometryEnabled ? Colors.cyanAccent : Colors.white,
                size: 18,
              ),
              tooltip: 'Toggle Debug Geometry Mode',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () {
                setState(() {
                  _isDebugGeometryEnabled = !_isDebugGeometryEnabled;
                });
                ref.read(viewportControllerProvider.notifier).sendCommand(
                  'SET_VISUALIZATION_MODE',
                  {'mode': _isDebugGeometryEnabled ? 'debug_geometry' : 'normal'},
                );
                final layout = ref.read(designerProvider);
                ref.read(viewportControllerProvider.notifier).sendCommand(
                  'RUN_DIAGNOSTIC',
                  {
                    'furniture': layout.furniture.map((f) => {
                      'id': f.id,
                      'assetId': f.assetId,
                      'name': f.name,
                      'x': f.x,
                      'y': f.y,
                      'z': f.z,
                      'width': f.width,
                      'depth': f.depth,
                      'height': f.height,
                      'rotationY': f.rotationY,
                    }).toList()
                  },
                );
                SnackbarManager.showSuccess(
                  context,
                  _isDebugGeometryEnabled ? 'DEBUG GEOMETRY Enabled' : 'DEBUG GEOMETRY Disabled',
                );
              },
            ),
            
            // Settings Button
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white, size: 18),
              tooltip: 'Settings',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const NavigationSettingsDialog(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getViewModeLabel(ViewMode mode) {
    switch (mode) {
      case ViewMode.perspective: return 'Perspective';
      case ViewMode.top: return 'Top Pres.';
      case ViewMode.front: return 'Front Pres.';
      case ViewMode.left: return 'Left Pres.';
      case ViewMode.right: return 'Right Pres.';
      case ViewMode.isometric: return 'Isometric';
      case ViewMode.free: return 'Free Flight';
      case ViewMode.orbit: return 'Orbit View';
    }
  }

  // --- FLOATING LIGHTING PANEL ---
  Widget _buildLightingPanel() {
    final lighting = ref.watch(lightingProvider);
    return Positioned(
      top: 16,
      left: 16,
      child: Card(
        color: Theme.of(context).cardColor.withOpacity(0.95),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.all(12),
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Rendering & Lighting', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Divider(),
              
              // Shadow Settings
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Render Projected Shadows', style: TextStyle(fontSize: 12)),
                  Switch(
                    value: lighting.showShadows,
                    activeColor: AppTheme.primary,
                    onChanged: (val) => ref.read(lightingProvider.notifier).toggleShadows(val),
                  ),
                ],
              ),
              
              // Ceiling settings
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Show Ceiling Surface', style: TextStyle(fontSize: 12)),
                  Switch(
                    value: lighting.showCeiling,
                    activeColor: AppTheme.primary,
                    onChanged: (val) => ref.read(lightingProvider.notifier).toggleCeiling(val),
                  ),
                ],
              ),
              
              const SizedBox(height: 6),
              
              // Sun Lighting azimuth slider
              const Text('Sun Direction Angle', style: TextStyle(fontSize: 11, color: Colors.grey)),
              Slider(
                value: lighting.sunAzimuth,
                min: 0.0,
                max: 2 * pi,
                activeColor: Colors.amber,
                onChanged: (val) => ref.read(lightingProvider.notifier).setSunAzimuth(val),
              ),
              
              // Ambient intensity
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Ambient Intensity', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(lighting.ambientLight.toStringAsFixed(2), style: const TextStyle(fontSize: 11)),
                ],
              ),
              Slider(
                value: lighting.ambientLight,
                min: 0.1,
                max: 0.8,
                onChanged: (val) => ref.read(lightingProvider.notifier).setAmbientLight(val),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- STATS OVERLAY ---
  Widget _buildStatsOverlay(int totalPolys) {
    return Positioned(
      bottom: 16,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Performance: $_fps FPS',
              style: TextStyle(
                color: _fps >= 55 ? Colors.green : (_fps >= 30 ? Colors.orange : Colors.red),
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Triangles: $totalPolys',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
            Text(
              'Renderer: Pure Dart Canvas 3D',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  // --- MINI CAMERA WIDGET ---
  Widget _buildMiniCameraWidget(CameraState cameraState) {
    final viewMode = ref.watch(viewModeProvider);
    final distance = (cameraState.position - cameraState.target).length;
    // Base radius is 900
    final zoomLevel = 900.0 / cameraState.orbitRadius;
    final zoomPercent = (zoomLevel * 100).round();

    return Positioned(
      bottom: 110,
      right: 16,
      child: Card(
        color: const Color(0xE61E293B), // Sleek premium dark card background with opacity
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF334155), width: 1.5),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          width: 170,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.videocam_outlined, color: AppTheme.primary, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getViewModeLabel(viewMode),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF334155), height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Distance',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                  Text(
                    '${distance.round()} cm',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Zoom Level',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                  Text(
                    '$zoomPercent%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- QUICK ASSET SPANNER ---
  Widget _buildQuickPlacementBar(DesignerLayoutState layout, DesignerNotifier notifier) {
    return Positioned(
      bottom: 16,
      right: 280,
      left: 360,
      child: Card(
        color: Theme.of(context).cardColor.withOpacity(0.9),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          height: 80,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.add_circle_outline, color: AppTheme.primary),
                  Text('Place', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
              const VerticalDivider(),
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.furnitureAssets.length,
                  itemBuilder: (context, idx) {
                    final asset = widget.furnitureAssets[idx];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ActionChip(
                        backgroundColor: AppTheme.primary.shade50,
                        avatar: const Icon(Icons.chair, size: 14, color: AppTheme.primary),
                        label: Text(asset.name, style: const TextStyle(fontSize: 11, color: AppTheme.primary)),
                        onPressed: () {
                          notifier.addFurniture(asset, 0.0, 0.0);
                          SnackbarManager.showSuccess(context, 'Placed ${asset.name} in room.');
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialPickerSidebar(DesignerLayoutState layout, DesignerNotifier notifier) {
    final selectedF = layout.selectedFurnitureId != null
        ? layout.furniture.firstWhere((f) => f.id == layout.selectedFurnitureId)
        : null;

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(left: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.primary.shade700,
            child: const Row(
              children: [
                Icon(Icons.style, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  '3D Asset Customizer',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Room Surface Styles', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const Divider(),
                  const SizedBox(height: 8),
                  
                  const Text('Floor Pattern', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildMaterialChip(
                        label: 'Wood',
                        active: layout.floorMaterialType == 'wood',
                        onSelected: () => notifier.updateRoomMaterials(floorType: 'wood', floorColor: 'd27d2d'),
                      ),
                      _buildMaterialChip(
                        label: 'Tile',
                        active: layout.floorMaterialType == 'tile',
                        onSelected: () => notifier.updateRoomMaterials(floorType: 'tile', floorColor: 'e5e4e2'),
                      ),
                      _buildMaterialChip(
                        label: 'Carpet',
                        active: layout.floorMaterialType == 'carpet',
                        onSelected: () => notifier.updateRoomMaterials(floorType: 'carpet', floorColor: '6f7378'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.style_outlined, size: 16),
                      label: const Text('Browse Floor Materials', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => MaterialLibraryScreen(
                              targetElementType: 'floor',
                              targetElementId: widget.roomId,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  const Text('Wall Color', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _buildColorBall('ECEFF1', layout.wallMaterialColor == 'ECEFF1', (c) => notifier.updateRoomMaterials(wallColor: c)),
                      _buildColorBall('E0F2F1', layout.wallMaterialColor == 'E0F2F1', (c) => notifier.updateRoomMaterials(wallColor: c)),
                      _buildColorBall('F1F8E9', layout.wallMaterialColor == 'F1F8E9', (c) => notifier.updateRoomMaterials(wallColor: c)),
                      _buildColorBall('FFF3E0', layout.wallMaterialColor == 'FFF3E0', (c) => notifier.updateRoomMaterials(wallColor: c)),
                      _buildColorBall('FFFFFF', layout.wallMaterialColor == 'FFFFFF', (c) => notifier.updateRoomMaterials(wallColor: c)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.color_lens_outlined, size: 16),
                      label: const Text('Browse Wall Materials', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => MaterialLibraryScreen(
                              targetElementType: 'wall',
                              targetElementId: widget.roomId,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (selectedF != null) ...[
                    Text(
                      'Customize: ${selectedF.name}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primary),
                    ),
                    const Divider(),
                    const SizedBox(height: 8),

                    const Text('Base Color', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildColorBall('26A69A', selectedF.materialColor == '26A69A', (c) => notifier.updateSelectedFurnitureMaterial(color: c)),
                        _buildColorBall('EF5350', selectedF.materialColor == 'EF5350', (c) => notifier.updateSelectedFurnitureMaterial(color: c)),
                        _buildColorBall('42A5F5', selectedF.materialColor == '42A5F5', (c) => notifier.updateSelectedFurnitureMaterial(color: c)),
                        _buildColorBall('AB47BC', selectedF.materialColor == 'AB47BC', (c) => notifier.updateSelectedFurnitureMaterial(color: c)),
                        _buildColorBall('78909C', selectedF.materialColor == '78909C', (c) => notifier.updateSelectedFurnitureMaterial(color: c)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.palette_outlined, size: 16),
                        label: const Text('Browse Furniture Materials', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => MaterialLibraryScreen(
                                targetElementType: 'furniture',
                                targetElementId: selectedF.id,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Metallic', style: TextStyle(fontSize: 11)),
                        Text(selectedF.metallic.toStringAsFixed(1), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: selectedF.metallic,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (v) => notifier.updateSelectedFurnitureMaterial(metallic: v),
                    ),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Roughness', style: TextStyle(fontSize: 11)),
                        Text(selectedF.roughness.toStringAsFixed(1), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: selectedF.roughness,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (v) => notifier.updateSelectedFurnitureMaterial(roughness: v),
                    ),
                    const SizedBox(height: 16),

                    const Text('Dimensions & Scale', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Scale X', style: TextStyle(fontSize: 11)),
                        Text(selectedF.scaleX.toStringAsFixed(2), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: selectedF.scaleX,
                      min: 0.5,
                      max: 2.0,
                      onChanged: (v) => notifier.updateSelectedFurnitureTransform(scaleX: v),
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Scale Y', style: TextStyle(fontSize: 11)),
                        Text(selectedF.scaleY.toStringAsFixed(2), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: selectedF.scaleY,
                      min: 0.5,
                      max: 2.0,
                      onChanged: (v) => notifier.updateSelectedFurnitureTransform(scaleY: v),
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Scale Z', style: TextStyle(fontSize: 11)),
                        Text(selectedF.scaleZ.toStringAsFixed(2), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: selectedF.scaleZ,
                      min: 0.5,
                      max: 2.0,
                      onChanged: (v) => notifier.updateSelectedFurnitureTransform(scaleZ: v),
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Rotate Y', style: TextStyle(fontSize: 11)),
                        Text('${(selectedF.rotationY * 180 / pi).round()}°', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: selectedF.rotationY,
                      min: -pi,
                      max: pi,
                      onChanged: (v) => notifier.updateSelectedFurnitureTransform(rotationY: v),
                    ),
                    
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        icon: const Icon(Icons.delete),
                        label: const Text('Delete Furniture'),
                        onPressed: () {
                          notifier.deleteSelected();
                          SnackbarManager.showSuccess(context, 'Furniture removed.');
                        },
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 32),
                    Center(
                      child: Text(
                        'Tap a furniture item to customize its properties.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialChip({required String label, required bool active, required VoidCallback onSelected}) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: active,
      onSelected: (_) => onSelected(),
      selectedColor: AppTheme.primary.shade100,
      checkmarkColor: AppTheme.primary,
    );
  }

  Widget _buildColorBall(String hex, bool selected, ValueChanged<String> onTap) {
    final color = Color(int.parse('FF$hex', radix: 16));
    return GestureDetector(
      onTap: () => onTap(hex),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppTheme.primary : Colors.grey.shade300,
            width: selected ? 3.0 : 1.0,
          ),
          boxShadow: [
            if (selected) const BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
          ],
        ),
      ),
    );
  }

  Widget _buildHUDOverlay(DesignerLayoutState layout) {
    if (layout.selectedFurnitureId == null) return const SizedBox.shrink();
    
    return Positioned(
      top: 90,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.primary.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.15),
                blurRadius: 16,
                spreadRadius: 2,
              )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tune_rounded, color: AppTheme.primary, size: 16),
              const SizedBox(width: 8),
              Text(
                _dragValueHUDText ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                  letterSpacing: 0.4,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- RAYCASTING AND DRAG-DROP UTILITIES ---
  (String, double)? _performRaycast(Offset localPos, Size viewportSize) {
    final layout = ref.read(designerProvider);
    final cameraState = ref.read(cameraProvider);
    
    final double px = localPos.dx;
    final double py = localPos.dy;
    
    double ndcX = (2.0 * px) / viewportSize.width - 1.0;
    double ndcY = 1.0 - (2.0 * py) / viewportSize.height;

    double halfHeight = tan(cameraState.fov / 2.0);
    double halfWidth = halfHeight * cameraState.aspect;

    final F = (cameraState.target - cameraState.position).normalize();
    final R = F.cross(cameraState.up).normalize();
    final U = R.cross(F).normalize();

    final rayDir = (F + R * (ndcX * halfWidth) + U * (ndcY * halfHeight)).normalize();
    final rayOrigin = cameraState.position;

    final List<(String, double)> hits = [];

    // A. Floor & Ceiling Plane Intersections
    if (rayDir.y.abs() > 0.0001) {
      final tFloor = -rayOrigin.y / rayDir.y;
      if (tFloor > 0) {
        hits.add(('floor', tFloor));
      }
      final tCeiling = (300.0 - rayOrigin.y) / rayDir.y;
      if (tCeiling > 0) {
        hits.add(('ceiling', tCeiling));
      }
    }

    // B. Furniture Bounding Box Intersections
    for (final f in layout.furniture) {
      final minLoc = Vector3D(-f.width/2, 0.0, -f.depth/2);
      final maxLoc = Vector3D(f.width/2, f.height, f.depth/2);
      
      final transRayOrigin = rayOrigin - Vector3D(f.x, f.y, f.z);
      final rot = -f.rotationY;
      final c = cos(rot);
      final s = sin(rot);
      
      final localRayOrigin = Vector3D(
        transRayOrigin.x * c - transRayOrigin.z * s,
        transRayOrigin.y,
        transRayOrigin.x * s + transRayOrigin.z * c
      );
      final localRayDir = Vector3D(
        rayDir.x * c - rayDir.z * s,
        rayDir.y,
        rayDir.x * s + rayDir.z * c
      ).normalize();

      final aabb = BoundingBox3D(minLoc, maxLoc);
      final outDistance = <double>[];
      if (aabb.intersectsRay(localRayOrigin, localRayDir, outDistance)) {
        final t = outDistance[0];
        if (t > 0) {
          hits.add(('furniture:${f.id}', t));
        }
      }
    }

    // B2. Door & Window Plane Intersections
    for (final op in layout.openings) {
      final x = op.position.dx;
      final z = op.position.dy;
      final double doorAngle = _openDoorIds.contains(op.id) ? op.angle + pi / 2 : op.angle;
      final wallNormal = Vector3D(-sin(doorAngle), 0.0, cos(doorAngle)).normalize();
      final p0 = Vector3D(x, 0.0, z);

      final denom = rayDir.dot(wallNormal);
      if (denom.abs() > 0.0001) {
        final tOp = (p0 - rayOrigin).dot(wallNormal) / denom;
        if (tOp > 0) {
          final pInt = rayOrigin + rayDir * tOp;
          if (pInt.y >= 0 && pInt.y <= 200.0) {
            final double dx = pInt.x - x;
            final double dz = pInt.z - z;
            final double rotatedX = dx * cos(doorAngle) + dz * sin(doorAngle);
            if (rotatedX.abs() <= op.width / 2.0) {
              hits.add(('opening:${op.id}', tOp));
            }
          }
        }
      }
    }

    // C. Wall Plane Intersections
    for (int i = 0; i < layout.walls.length; i++) {
      final w = layout.walls[i];
      final x1 = w.start.dx;
      final z1 = w.start.dy;
      final x2 = w.end.dx;
      final z2 = w.end.dy;

      final dx = x2 - x1;
      final dz = z2 - z1;
      final lenSq = dx * dx + dz * dz;
      if (lenSq == 0) continue;

      final wallNormal = Vector3D(-dz, 0.0, dx).normalize();
      final p0 = Vector3D(x1, 0.0, z1);

      final denom = rayDir.dot(wallNormal);
      if (denom.abs() > 0.0001) {
        final tWall = (p0 - rayOrigin).dot(wallNormal) / denom;
        if (tWall > 0) {
          final pInt = rayOrigin + rayDir * tWall;
          if (pInt.y >= 0 && pInt.y <= 300.0) {
            final proj = ((pInt.x - x1) * dx + (pInt.z - z1) * dz) / lenSq;
            if (proj >= 0.0 && proj <= 1.0) {
              hits.add(('wall', tWall));
            }
          }
        }
      }
    }

    if (hits.isEmpty) return null;

    hits.sort((a, b) => a.$2.compareTo(b.$2));
    return hits.first;
  }

  void _applyMaterialToTarget(MaterialModel material, String target) {
    final notifier = ref.read(designerProvider.notifier);
    
    String? baseColorMap;
    String? normalMap;
    String? roughnessMap;
    String? metallicMap;
    String? emissiveMap;
    
    for (final tex in material.textures) {
      final type = tex.textureType.toLowerCase();
      if (type == 'base_color' || type == 'basecolor') {
        baseColorMap = tex.filePath;
      } else if (type == 'normal' || type == 'normalmap') {
        normalMap = tex.filePath;
      } else if (type == 'roughness') {
        roughnessMap = tex.filePath;
      } else if (type == 'metallic' || type == 'metalness') {
        metallicMap = tex.filePath;
      } else if (type == 'emissive') {
        emissiveMap = tex.filePath;
      }
    }

    if (target.startsWith('furniture:')) {
      final id = target.replaceFirst('furniture:', '');
      notifier.updateFurnitureMaterialById(
        id: id,
        color: material.baseColor?.replaceAll('#', ''),
        materialType: material.category.name.toLowerCase(),
        metallic: material.reflectivity,
        roughness: 1.0 - material.reflectivity,
        opacity: material.opacity,
        normalMap: normalMap,
        baseColorMap: baseColorMap,
        roughnessMap: roughnessMap,
        metallicMap: metallicMap,
        emissiveMap: emissiveMap,
        emissiveColor: null, // default
        emissiveIntensity: 0.0,
        scale: material.defaultScale,
        rotation: 0.0,
      );
      ref.read(materialProvider.notifier).applyMaterial(id, material.id);
      notifier.selectFurniture(id);
      SnackbarManager.showSuccess(context, 'Applied ${material.name} to furniture.');
    } else {
      notifier.updateRoomSurface(
        surface: target,
        color: material.baseColor?.replaceAll('#', ''),
        materialType: material.category.name.toLowerCase(),
        metallic: material.reflectivity,
        roughness: 1.0 - material.reflectivity,
        reflection: material.reflectivity,
        scale: material.defaultScale,
        rotation: 0.0,
        normalMap: normalMap,
        baseColorMap: baseColorMap,
        roughnessMap: roughnessMap,
        metallicMap: metallicMap,
        emissiveMap: emissiveMap,
        emissiveColor: null,
        emissiveIntensity: 0.0,
      );
      ref.read(materialProvider.notifier).addRecentlyUsed(material.id);
      final targetLabel = target[0].toUpperCase() + target.substring(1);
      SnackbarManager.showSuccess(context, 'Applied ${material.name} to $targetLabel.');
    }
  }

  Widget _buildDragFeedbackOverlay() {
    if (_hoveredDragTarget == null || _dragPosition == null) return const SizedBox.shrink();

    String label = '';
    IconData icon = Icons.texture;
    Color color = AppTheme.primary;

    if (_hoveredDragTarget == 'floor') {
      label = 'Apply to Floor';
      icon = Icons.grid_on;
      color = const Color(0xFF0F766E);
    } else if (_hoveredDragTarget == 'ceiling') {
      label = 'Apply to Ceiling';
      icon = Icons.roofing;
      color = const Color(0xFFF4B740);
    } else if (_hoveredDragTarget == 'wall') {
      label = 'Apply to Wall';
      icon = Icons.view_in_ar;
      color = const Color(0xFF5B5BD6);
    } else if (_hoveredDragTarget!.startsWith('furniture:')) {
      label = 'Apply to Furniture';
      icon = Icons.chair_outlined;
      color = const Color(0xFF10B981);
    }

    return Positioned(
      left: _dragPosition!.dx + 16,
      top: _dragPosition!.dy + 16,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 1,
              )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cameraState = ref.watch(cameraProvider);
    final lightingState = ref.watch(lightingProvider);
    final layout = ref.watch(designerProvider);
    final notifier = ref.read(designerProvider.notifier);
    final viewportState = ref.watch(viewportControllerProvider);
    final bridgeClient = ref.watch(bridgeClientProvider);

    // Send LOAD_ROOM command when layout or ceiling visibility changes
    ref.listen<DesignerLayoutState>(designerProvider, (previous, next) {
      if (previous == null ||
          previous.walls != next.walls ||
          previous.openings != next.openings ||
          previous.floorMaterialColor != next.floorMaterialColor ||
          previous.floorMaterialType != next.floorMaterialType ||
          previous.floorMetallic != next.floorMetallic ||
          previous.floorRoughness != next.floorRoughness ||
          previous.floorBaseColorMap != next.floorBaseColorMap ||
          previous.floorNormalMap != next.floorNormalMap ||
          previous.floorRoughnessMap != next.floorRoughnessMap ||
          previous.floorMetallicMap != next.floorMetallicMap ||
          previous.floorEmissiveMap != next.floorEmissiveMap ||
          previous.floorEmissiveColor != next.floorEmissiveColor ||
          previous.floorEmissiveIntensity != next.floorEmissiveIntensity ||
          previous.floorScale != next.floorScale ||
          previous.floorRotation != next.floorRotation ||
          previous.wallMaterialColor != next.wallMaterialColor ||
          previous.wallMaterialType != next.wallMaterialType ||
          previous.wallMetallic != next.wallMetallic ||
          previous.wallRoughness != next.wallRoughness ||
          previous.wallBaseColorMap != next.wallBaseColorMap ||
          previous.wallNormalMap != next.wallNormalMap ||
          previous.wallRoughnessMap != next.wallRoughnessMap ||
          previous.wallMetallicMap != next.wallMetallicMap ||
          previous.wallEmissiveMap != next.wallEmissiveMap ||
          previous.wallEmissiveColor != next.wallEmissiveColor ||
          previous.wallEmissiveIntensity != next.wallEmissiveIntensity ||
          previous.wallScale != next.wallScale ||
          previous.wallRotation != next.wallRotation ||
          previous.ceilingMaterialColor != next.ceilingMaterialColor ||
          previous.ceilingMaterialType != next.ceilingMaterialType ||
          previous.ceilingMetallic != next.ceilingMetallic ||
          previous.ceilingRoughness != next.ceilingRoughness ||
          previous.ceilingBaseColorMap != next.ceilingBaseColorMap ||
          previous.ceilingNormalMap != next.ceilingNormalMap ||
          previous.ceilingRoughnessMap != next.ceilingRoughnessMap ||
          previous.ceilingMetallicMap != next.ceilingMetallicMap ||
          previous.ceilingEmissiveMap != next.ceilingEmissiveMap ||
          previous.ceilingEmissiveColor != next.ceilingEmissiveColor ||
          previous.ceilingEmissiveIntensity != next.ceilingEmissiveIntensity ||
          previous.ceilingScale != next.ceilingScale ||
          previous.ceilingRotation != next.ceilingRotation) {
        _sendLoadRoomCommand(next);
      }
      _syncFurnitureModels(previous, next);

      // Sync selection and transform mode
      if (previous == null ||
          previous.selectedFurnitureId != next.selectedFurnitureId ||
          previous.transformMode != next.transformMode) {
        ref.read(viewportControllerProvider.notifier).sendCommand('SELECT_OBJECT', {
          'id': next.selectedFurnitureId,
          'mode': next.transformMode.name,
        });
      }
    });

    ref.listen<LightingState>(lightingProvider, (previous, next) {
      final controller = ref.read(viewportControllerProvider.notifier);

      if (previous == null || previous.showShadows != next.showShadows) {
        controller.sendCommand('TOGGLE_SHADOWS', {'enabled': next.showShadows});
      }

      if (previous == null || previous.showCeiling != next.showCeiling) {
        _sendLoadRoomCommand(ref.read(designerProvider));
      }

      if (previous == null) {
        for (final light in next.lights) {
          controller.sendCommand('UPDATE_LIGHT', light.toJson());
        }
      } else {
        // Sync updated or added lights
        for (final light in next.lights) {
          final matches = previous.lights.where((l) => l.id == light.id);
          if (matches.isEmpty) {
            controller.sendCommand('UPDATE_LIGHT', light.toJson());
          } else {
            final prevLight = matches.first;
            if (prevLight.type != light.type ||
                prevLight.x != light.x ||
                prevLight.y != light.y ||
                prevLight.z != light.z ||
                prevLight.rotationX != light.rotationX ||
                prevLight.rotationY != light.rotationY ||
                prevLight.rotationZ != light.rotationZ ||
                prevLight.intensity != light.intensity ||
                prevLight.color != light.color ||
                prevLight.castShadow != light.castShadow ||
                prevLight.radius != light.radius ||
                prevLight.spotAngle != light.spotAngle) {
              controller.sendCommand('UPDATE_LIGHT', light.toJson());
            }
          }
        }

        // Sync removed lights
        for (final prevLight in previous.lights) {
          final stillExists = next.lights.any((l) => l.id == prevLight.id);
          if (!stillExists) {
            controller.sendCommand('REMOVE_LIGHT', {'id': prevLight.id});
          }
        }
      }

      if (previous == null || previous.selectedLightId != next.selectedLightId) {
        if (next.selectedLightId != null) {
          controller.sendCommand('SELECT_OBJECT', {
            'id': next.selectedLightId,
            'mode': ref.read(designerProvider).transformMode.name,
          });
        } else if (ref.read(designerProvider).selectedFurnitureId == null) {
          controller.sendCommand('SELECT_OBJECT', {
            'id': null,
            'mode': 'select',
          });
        }
      }
    });

    // Build the 3D scene from model data
    final scenePolygons = _build3DScene(layout);

    return Scaffold(
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.delete ||
                event.logicalKey == LogicalKeyboardKey.backspace) {
              final layout = ref.read(designerProvider);
              if (layout.selectedFurnitureId != null ||
                  layout.selectedWallIndex != null ||
                  layout.selectedOpeningId != null) {
                ref.read(designerProvider.notifier).deleteSelected();
                SnackbarManager.showSuccess(context, 'Selected element removed.');
                return KeyEventResult.handled;
              }
            }
          }
          final mode = ref.read(viewModeProvider);
          if (widget.isWalkthroughMode && event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyE) {
            final layout = ref.read(designerProvider);
            final cameraState = ref.read(cameraProvider);
            final nearest = _getNearestDoor(cameraState.position, layout.openings);
            if (nearest != null) {
              _toggleDoor(nearest);
              return KeyEventResult.handled;
            }
          }
          if (mode != ViewMode.free && !widget.isWalkthroughMode) return KeyEventResult.ignored;
          if (event is KeyDownEvent) {
            _pressedKeys.add(event.logicalKey);
          } else if (event is KeyUpEvent) {
            _pressedKeys.remove(event.logicalKey);
          }
          return KeyEventResult.handled;
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportSize = Size(
              widget.simplified ? constraints.maxWidth : constraints.maxWidth - 250,
              constraints.maxHeight,
            );



            return Row(
              children: [
                // Interactive 3D Canvas
                Expanded(
                  child: Container(
                    color: const Color(0xFF14171A),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DragTarget<MaterialModel>(
                            onWillAcceptWithDetails: (details) => true,
                            onMove: (details) {
                              final renderBox = context.findRenderObject() as RenderBox?;
                              if (renderBox != null) {
                                final localPos = renderBox.globalToLocal(details.offset);
                                final hit = _performRaycast(localPos, viewportSize);
                                setState(() {
                                  _hoveredDragTarget = hit?.$1;
                                  _dragPosition = localPos;
                                });
                              }
                            },
                            onLeave: (_) {
                              setState(() {
                                _hoveredDragTarget = null;
                                _dragPosition = null;
                              });
                            },
                            onAcceptWithDetails: (details) {
                              final target = _hoveredDragTarget;
                              if (target != null) {
                                _applyMaterialToTarget(details.data, target);
                              }
                              setState(() {
                                _hoveredDragTarget = null;
                                _dragPosition = null;
                              });
                            },
                            builder: (context, candidateData, rejectedData) {
                              final isDraggingOver = candidateData.isNotEmpty;
                              final useGpu = bridgeClient is! StubBridgeClient && viewportState.status != RendererState.ERROR;
                              return Stack(
                                children: [
                                  Positioned.fill(
                                    child: useGpu
                                        ? bridgeClient.buildViewport(context)
                                        : Listener(
                                            onPointerSignal: (pointerSignal) {
                                              if (pointerSignal is PointerScrollEvent) {
                                                final settings = ref.read(navigationProvider);
                                                final isFree = ref.read(viewModeProvider) == ViewMode.free;
                                                final zoomDelta = pointerSignal.scrollDelta.dy * (settings.zoomSpeed / 100.0) * 15.0;
                                                ref.read(cameraProvider.notifier).zoom(zoomDelta, isFree);
                                              }
                                            },
                                            child: GestureDetector(
                                              onTapDown: (details) => _handleTapDown(details, viewportSize),
                                              onDoubleTapDown: (details) => _handleDoubleTap(details, viewportSize),
                                              onScaleStart: _handleScaleStart,
                                              onScaleUpdate: (details) => _handleScaleUpdate(details, viewportSize),
                                              onScaleEnd: (_) => _handleScaleEnd(),
                                              child: CustomPaint(
                                                size: viewportSize,
                                                painter: ThreeDScenePainter(
                                                  scenePolygons: scenePolygons,
                                                  cameraState: cameraState,
                                                  lights: lightingState.lights,
                                                  selectedLightId: lightingState.selectedLightId,
                                                  showShadows: lightingState.showShadows,
                                                  selectedFurnitureId: layout.selectedFurnitureId,
                                                  furniture: layout.furniture,
                                                  transformMode: layout.transformMode,
                                                  activeGizmoAxis: _selectedGizmoAxis,
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),
                                  if (isDraggingOver && _hoveredDragTarget != null)
                                    _buildDragFeedbackOverlay(),
                                  if (useGpu && viewportState.status == RendererState.LOADING)
                                    Positioned.fill(
                                      child: Container(
                                        color: const Color(0xFF14171A).withOpacity(0.85),
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const CircularProgressIndicator(
                                                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                'Connecting to GPU Viewport...',
                                                style: TextStyle(
                                                  color: Colors.grey.shade400,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                        
                        if (_selectedGizmoAxis != null && _dragValueHUDText != null)
                          _buildHUDOverlay(layout),

                        if (widget.isWalkthroughMode) ...[
                          if (_isMouse == false)
                            Positioned(
                              bottom: 30,
                              left: 30,
                              child: VirtualJoystick(
                                onJoystickChanged: (offset) {
                                  setState(() {
                                    _joystickValue = offset;
                                  });
                                },
                              ),
                            ),
                          Consumer(
                            builder: (context, ref, child) {
                              final cameraState = ref.watch(cameraProvider);
                              final nearestDoor = _getNearestDoor(cameraState.position, layout.openings);
                              if (nearestDoor == null) return const SizedBox.shrink();
                              return Positioned(
                                bottom: 120,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.85),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: AppTheme.primary, width: 1.5),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.sensor_door, color: AppTheme.primary, size: 16),
                                        const SizedBox(width: 8),
                                        Text(
                                          _openDoorIds.contains(nearestDoor.id)
                                              ? "Tap or Press E to Close Door"
                                              : "Tap or Press E to Open Door",
                                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],

                        if (!widget.simplified) ...[
                          // Lighting controls sidebar panel
                          _buildLightingPanel(),
                          
                          // Performance and triangle overlay
                          _buildStatsOverlay(scenePolygons.length),
                          
                          // Floating Mini Camera Widget showing View, Distance, Zoom
                          Consumer(
                            builder: (context, ref, child) {
                              final cameraState = ref.watch(cameraProvider);
                              return _buildMiniCameraWidget(cameraState);
                            },
                          ),
                          
                          // Camera Toolbar Floating Panel
                          Positioned(
                            top: 16,
                            left: 16,
                            right: 16,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: _buildCameraToolbar(layout),
                            ),
                          ),
                          
                          // Quick furniture spanner at bottom
                          _buildQuickPlacementBar(layout, notifier),
                        ],
                      ],
                    ),
                  ),
                ),

                if (!widget.simplified)
                  // Properties side panel
                  _buildMaterialPickerSidebar(layout, notifier),
              ],
            );
          },
        ),
      ),
    );
  }
}

// --- OPTIMIZED CUSTOM 3D PAINTER WIDGET ---
class ThreeDScenePainter extends CustomPainter {
  final List<Polygon3D> scenePolygons;
  final CameraState cameraState;
  final List<LightSource> lights;
  final String? selectedLightId;
  final bool showShadows;
  final String? selectedFurnitureId;
  final List<PlacedFurniture> furniture;
  final TransformMode transformMode;
  final String? activeGizmoAxis;

  ThreeDScenePainter({
    required this.scenePolygons,
    required this.cameraState,
    required this.lights,
    required this.selectedLightId,
    required this.showShadows,
    required this.selectedFurnitureId,
    required this.furniture,
    required this.transformMode,
    required this.activeGizmoAxis,
  });

  Color _getAxisColor(String axis, Color defaultColor) {
    if (activeGizmoAxis == null) return defaultColor;
    final act = activeGizmoAxis!.toLowerCase();
    if (axis.toUpperCase() == 'X' && act.contains('x')) {
      return const Color(0xFFFF3D00); // vibrant highlighted red
    }
    if (axis.toUpperCase() == 'Y' && act.contains('y')) {
      return const Color(0xFF00E676); // vibrant highlighted green
    }
    if (axis.toUpperCase() == 'Z' && act.contains('z')) {
      return const Color(0xFF2979FF); // vibrant highlighted blue
    }
    if (axis.toUpperCase() == 'UNIFORM' && act.contains('uniform')) {
      return const Color(0xFFFFEA00); // bright yellow highlight
    }
    return defaultColor;
  }

  void _draw3DCone(
    Canvas canvas,
    Vector3D baseCenter,
    Vector3D tip,
    String axis,
    double radius,
    Color color,
    Size viewportSize,
  ) {
    Vector3D u, v;
    if (axis.toUpperCase() == 'X') {
      u = Vector3D(0, radius, 0);
      v = Vector3D(0, 0, radius);
    } else if (axis.toUpperCase() == 'Y') {
      u = Vector3D(radius, 0, 0);
      v = Vector3D(0, 0, radius);
    } else {
      u = Vector3D(radius, 0, 0);
      v = Vector3D(0, radius, 0);
    }

    final List<Vector3D> basePts = [];
    const int segments = 12;
    for (int i = 0; i < segments; i++) {
      double angle = i * 2 * pi / segments;
      basePts.add(baseCenter + u * cos(angle) + v * sin(angle));
    }

    final pTip = cameraState.projectPoint(tip, viewportSize);
    final List<Offset> pBase = basePts
        .map((p) => cameraState.projectPoint(p, viewportSize))
        .whereType<Offset>()
        .toList();

    if (pTip != null && pBase.length == segments) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      // Draw sides of the cone
      for (int i = 0; i < segments; i++) {
        final p1 = pBase[i];
        final p2 = pBase[(i + 1) % segments];
        
        // Simple faux shading based on triangle orientation
        double shading = 0.8 + 0.2 * sin(i * 2 * pi / segments);
        final shadedColor = Color.fromARGB(
          color.alpha,
          (color.red * shading).round().clamp(0, 255),
          (color.green * shading).round().clamp(0, 255),
          (color.blue * shading).round().clamp(0, 255),
        );
        final sidePaint = Paint()
          ..color = shadedColor
          ..style = PaintingStyle.fill;

        final path = Path()
          ..moveTo(pTip.dx, pTip.dy)
          ..lineTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..close();
        canvas.drawPath(path, sidePaint);
      }

      // Draw base of the cone
      final basePath = Path()..moveTo(pBase[0].dx, pBase[0].dy);
      for (int i = 1; i < segments; i++) {
        basePath.lineTo(pBase[i].dx, pBase[i].dy);
      }
      basePath.close();
      canvas.drawPath(basePath, paint..color = color.withOpacity(0.9));
    }
  }

  void _draw3DBox(
    Canvas canvas,
    Vector3D center,
    double boxSize,
    Color color,
    Size viewportSize,
  ) {
    final d = boxSize / 2.0;
    final List<Vector3D> v = [
      center + Vector3D(-d, -d, -d),
      center + Vector3D(d, -d, -d),
      center + Vector3D(d, d, -d),
      center + Vector3D(-d, d, -d),
      center + Vector3D(-d, -d, d),
      center + Vector3D(d, -d, d),
      center + Vector3D(d, d, d),
      center + Vector3D(-d, d, d),
    ];

    final List<Offset?> projected = v.map((pt) => cameraState.projectPoint(pt, viewportSize)).toList();
    if (projected.any((p) => p == null)) return;

    final faces = [
      [0, 1, 2, 3], // Back
      [4, 5, 6, 7], // Front
      [0, 4, 7, 3], // Left
      [1, 5, 6, 2], // Right
      [0, 1, 5, 4], // Bottom
      [3, 2, 6, 7], // Top
    ];

    final shadingFactors = [0.8, 1.0, 0.7, 0.9, 0.6, 0.95];
    for (int i = 0; i < 6; i++) {
      final face = faces[i];
      final factor = shadingFactors[i];
      final faceColor = Color.fromARGB(
        color.alpha,
        (color.red * factor).round().clamp(0, 255),
        (color.green * factor).round().clamp(0, 255),
        (color.blue * factor).round().clamp(0, 255),
      );

      final paint = Paint()
        ..color = faceColor
        ..style = PaintingStyle.fill;

      final path = Path()
        ..moveTo(projected[face[0]]!.dx, projected[face[0]]!.dy)
        ..lineTo(projected[face[1]]!.dx, projected[face[1]]!.dy)
        ..lineTo(projected[face[2]]!.dx, projected[face[2]]!.dy)
        ..lineTo(projected[face[3]]!.dx, projected[face[3]]!.dy)
        ..close();
      canvas.drawPath(path, paint);
      
      // Draw wireframe overlay on the box for high-quality CAD look
      final wirePaint = Paint()
        ..color = Colors.black.withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      canvas.drawPath(path, wirePaint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Separate and Project Shadows
    final List<Polygon3D> projectedSolidPolys = [];
    final List<Path> shadowPaths = [];

    PlacedFurniture? selectedF;
    if (selectedFurnitureId != null) {
      try {
        selectedF = furniture.firstWhere((item) => item.id == selectedFurnitureId);
      } catch (_) {}
    }

    // 3. Process Solid Polygons (Calculate Shading, Project, depth estimation)
    for (final poly in scenePolygons) {
      bool isSelectedPoly = false;
      if (selectedF != null) {
        double px = 0.0, py = 0.0, pz = 0.0;
        for (final v in poly.vertices) {
          px += v.x; py += v.y; pz += v.z;
        }
        px /= poly.vertices.length;
        py /= poly.vertices.length;
        pz /= poly.vertices.length;
        
        final dist = sqrt(pow(px - selectedF.x, 2) + pow(pz - selectedF.z, 2));
        if (py < 298.0 && py > 2.0 && dist < max(selectedF.width, selectedF.depth) * 0.9) {
          isSelectedPoly = true;
        }
      }

      // Calculate polygon center for positional lighting
      double px = 0.0, py = 0.0, pz = 0.0;
      for (final v in poly.vertices) {
        px += v.x; py += v.y; pz += v.z;
      }
      px /= poly.vertices.length;
      py /= poly.vertices.length;
      pz /= poly.vertices.length;
      final polyCenter = Vector3D(px, py, pz);

      poly.shadedColor = ShadingEngine.calculateMultiLightShading(
        poly,
        polyCenter,
        lights,
        cameraState.position,
        isSelected: isSelectedPoly,
      );

      final List<Offset> pts2d = [];
      double depthSum = 0.0;
      bool fullyClipped = false;

      for (final v in poly.vertices) {
        final viewV = cameraState.viewMatrix.transform(v);
        depthSum += viewV.z;

        final p2d = cameraState.projectPoint(v, size);
        if (p2d == null) {
          fullyClipped = true;
          break;
        }
        pts2d.add(p2d);
      }

      if (fullyClipped) continue;

      poly.projected = poly.vertices;
      poly.depth = depthSum / poly.vertices.length;
      
      projectedSolidPolys.add(poly);

      if (showShadows && poly.vertices.first.y > 1.0) {
        for (final light in lights) {
          if (!light.castShadow || light.intensity <= 0.0) continue;
          List<Vector3D> shadowVerts = [];
          if (light.type == LightType.directional) {
            final dir = getLightDirection(light.rotationX, light.rotationY, light.rotationZ);
            shadowVerts = ShadingEngine.projectShadowVertices(poly.vertices, dir);
          } else if (light.type == LightType.point || light.type == LightType.spot) {
            final pos = Vector3D(light.x, light.y, light.z);
            shadowVerts = ShadingEngine.projectShadowVerticesFromPoint(poly.vertices, pos);
          }
          
          if (shadowVerts.isNotEmpty) {
            final List<Offset> sPts2d = [];
            bool shadowClipped = false;
            for (final sv in shadowVerts) {
              final sp2d = cameraState.projectPoint(sv, size);
              if (sp2d == null) {
                shadowClipped = true;
                break;
              }
              sPts2d.add(sp2d);
            }
            
            if (!shadowClipped && sPts2d.length >= 3) {
              final path = Path();
              path.moveTo(sPts2d[0].dx, sPts2d[0].dy);
              for (int k = 1; k < sPts2d.length; k++) {
                path.lineTo(sPts2d[k].dx, sPts2d[k].dy);
              }
              path.close();
              shadowPaths.add(path);
            }
          }
        }
      }
    }

    // 4. DRAW SHADOWS FIRST
    if (showShadows && shadowPaths.isNotEmpty) {
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.24)
        ..style = PaintingStyle.fill;
      for (final path in shadowPaths) {
        canvas.drawPath(path, shadowPaint);
      }
    }

    // 5. SORT SOLID POLYGONS BY DEPTH
    projectedSolidPolys.sort((a, b) => a.depth.compareTo(b.depth));

    // 6. DRAW SOLID POLYGONS
    final solidPaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (final poly in projectedSolidPolys) {
      final List<Offset> pts2d = poly.vertices.map((v) => cameraState.projectPoint(v, size)!).toList();
      
      final path = Path();
      path.moveTo(pts2d[0].dx, pts2d[0].dy);
      for (int i = 1; i < pts2d.length; i++) {
        path.lineTo(pts2d[i].dx, pts2d[i].dy);
      }
      path.close();

      if (poly.textureType == 'tile') {
        solidPaint.color = poly.shadedColor ?? poly.baseColor;
        canvas.drawPath(path, solidPaint);
        
        strokePaint.color = AppTheme.primary.shade900.withOpacity(0.08);
        canvas.drawPath(path, strokePaint);
      } else {
        solidPaint.color = poly.shadedColor ?? poly.baseColor;
        canvas.drawPath(path, solidPaint);
      }
    }

    // Draw light gizmos
    for (final light in lights) {
      final isSelected = light.id == selectedLightId;
      if (light.type == LightType.point) {
        _drawPointLightGizmo(canvas, light, size, isSelected);
      } else if (light.type == LightType.spot) {
        _drawSpotLightGizmo(canvas, light, size, isSelected);
      } else if (light.type == LightType.directional) {
        _drawDirectionalLightGizmo(canvas, light, size, isSelected);
      }
    }

    // 7. DRAW 3D TRANSFORM GIZMOS ON SELECTED ITEM
    final hasSelectedLight = selectedLightId != null;
    LightSource? selectedLight;
    if (hasSelectedLight) {
      try {
        selectedLight = lights.firstWhere((l) => l.id == selectedLightId);
      } catch (_) {}
    }

    if ((selectedF != null || selectedLight != null) && transformMode != TransformMode.select) {
      final center3d = selectedF != null
          ? Vector3D(selectedF.x, selectedF.y + selectedF.height / 2, selectedF.z)
          : Vector3D(selectedLight!.x, selectedLight.y, selectedLight.z);
      final pCenter = cameraState.projectPoint(center3d, size);

      if (pCenter != null) {
        final double maxDim = selectedF != null
            ? max(selectedF.width, max(selectedF.depth, selectedF.height))
            : 80.0;
        final double axisLength = maxDim / 2.0 + 60.0;

        // Base Axis Colors (Red, Green, Blue)
        final colorX = _getAxisColor('X', const Color(0xFFE53935));
        final colorY = _getAxisColor('Y', const Color(0xFF43A047));
        final colorZ = _getAxisColor('Z', const Color(0xFF1E88E5));

        // ────────── DRAW GIZMOS BASED ON ACTIVE MODE ──────────

        if (transformMode == TransformMode.translate) {
          // X Axis (Red)
          final xTip = center3d + Vector3D(axisLength, 0, 0);
          final pX = cameraState.projectPoint(xTip, size);
          if (pX != null) {
            final isHighlighted = activeGizmoAxis == 'translateX';
            final paintX = Paint()
              ..color = colorX
              ..strokeWidth = isHighlighted ? 5.5 : 3.0
              ..style = PaintingStyle.stroke;
            canvas.drawLine(pCenter, pX, paintX);
            _draw3DCone(canvas, xTip - Vector3D(15, 0, 0), xTip, 'X', isHighlighted ? 7.0 : 5.0, colorX, size);
          }

          // Y Axis (Green)
          final yTip = center3d + Vector3D(0, axisLength, 0);
          final pY = cameraState.projectPoint(yTip, size);
          if (pY != null) {
            final isHighlighted = activeGizmoAxis == 'translateY';
            final paintY = Paint()
              ..color = colorY
              ..strokeWidth = isHighlighted ? 5.5 : 3.0
              ..style = PaintingStyle.stroke;
            canvas.drawLine(pCenter, pY, paintY);
            _draw3DCone(canvas, yTip - Vector3D(0, 15, 0), yTip, 'Y', isHighlighted ? 7.0 : 5.0, colorY, size);
          }

          // Z Axis (Blue)
          final zTip = center3d + Vector3D(0, 0, axisLength);
          final pZ = cameraState.projectPoint(zTip, size);
          if (pZ != null) {
            final isHighlighted = activeGizmoAxis == 'translateZ';
            final paintZ = Paint()
              ..color = colorZ
              ..strokeWidth = isHighlighted ? 5.5 : 3.0
              ..style = PaintingStyle.stroke;
            canvas.drawLine(pCenter, pZ, paintZ);
            _draw3DCone(canvas, zTip - Vector3D(0, 0, 15), zTip, 'Z', isHighlighted ? 7.0 : 5.0, colorZ, size);
          }
        } 
        
        else if (transformMode == TransformMode.rotate) {
          final double ringRadius = selectedF != null
              ? max(selectedF.width, selectedF.depth) / 2.0 + 35.0
              : 50.0;

          // X Rotation Ring (Red, Y-Z Plane)
          final isHighlightedX = activeGizmoAxis == 'rotateX';
          final paintRingX = Paint()
            ..color = colorX
            ..strokeWidth = isHighlightedX ? 5.0 : 2.5
            ..style = PaintingStyle.stroke;
          final List<Offset> ringPtsX = [];
          for (int i = 0; i <= 32; i++) {
            double theta = i * 2 * pi / 32;
            final pt3d = center3d + Vector3D(0, ringRadius * cos(theta), ringRadius * sin(theta));
            final pt2d = cameraState.projectPoint(pt3d, size);
            if (pt2d != null) ringPtsX.add(pt2d);
          }
          for (int i = 0; i < ringPtsX.length - 1; i++) {
            canvas.drawLine(ringPtsX[i], ringPtsX[i + 1], paintRingX);
          }

          // Y Rotation Ring (Green, X-Z Plane)
          final isHighlightedY = activeGizmoAxis == 'rotateY';
          final paintRingY = Paint()
            ..color = colorY
            ..strokeWidth = isHighlightedY ? 5.0 : 2.5
            ..style = PaintingStyle.stroke;
          final List<Offset> ringPtsY = [];
          for (int i = 0; i <= 32; i++) {
            double theta = i * 2 * pi / 32;
            final pt3d = center3d + Vector3D(ringRadius * cos(theta), 0.1, ringRadius * sin(theta));
            final pt2d = cameraState.projectPoint(pt3d, size);
            if (pt2d != null) ringPtsY.add(pt2d);
          }
          for (int i = 0; i < ringPtsY.length - 1; i++) {
            canvas.drawLine(ringPtsY[i], ringPtsY[i + 1], paintRingY);
          }

          // Z Rotation Ring (Blue, X-Y Plane)
          final isHighlightedZ = activeGizmoAxis == 'rotateZ';
          final paintRingZ = Paint()
            ..color = colorZ
            ..strokeWidth = isHighlightedZ ? 5.0 : 2.5
            ..style = PaintingStyle.stroke;
          final List<Offset> ringPtsZ = [];
          for (int i = 0; i <= 32; i++) {
            double theta = i * 2 * pi / 32;
            final pt3d = center3d + Vector3D(ringRadius * cos(theta), ringRadius * sin(theta), 0);
            final pt2d = cameraState.projectPoint(pt3d, size);
            if (pt2d != null) ringPtsZ.add(pt2d);
          }
          for (int i = 0; i < ringPtsZ.length - 1; i++) {
            canvas.drawLine(ringPtsZ[i], ringPtsZ[i + 1], paintRingZ);
          }
        } 
        
        else if (transformMode == TransformMode.scale && selectedF != null) {
          // X Scale handle (Red)
          final xTip = center3d + Vector3D(axisLength, 0, 0);
          final pX = cameraState.projectPoint(xTip, size);
          if (pX != null) {
            final isHighlighted = activeGizmoAxis == 'scaleX';
            final paintX = Paint()
              ..color = colorX
              ..strokeWidth = isHighlighted ? 5.5 : 3.0
              ..style = PaintingStyle.stroke;
            canvas.drawLine(pCenter, pX, paintX);
            _draw3DBox(canvas, xTip, isHighlighted ? 13.0 : 9.0, colorX, size);
          }

          // Y Scale handle (Green)
          final yTip = center3d + Vector3D(0, axisLength, 0);
          final pY = cameraState.projectPoint(yTip, size);
          if (pY != null) {
            final isHighlighted = activeGizmoAxis == 'scaleY';
            final paintY = Paint()
              ..color = colorY
              ..strokeWidth = isHighlighted ? 5.5 : 3.0
              ..style = PaintingStyle.stroke;
            canvas.drawLine(pCenter, pY, paintY);
            _draw3DBox(canvas, yTip, isHighlighted ? 13.0 : 9.0, colorY, size);
          }

          // Z Scale handle (Blue)
          final zTip = center3d + Vector3D(0, 0, axisLength);
          final pZ = cameraState.projectPoint(zTip, size);
          if (pZ != null) {
            final isHighlighted = activeGizmoAxis == 'scaleZ';
            final paintZ = Paint()
              ..color = colorZ
              ..strokeWidth = isHighlighted ? 5.5 : 3.0
              ..style = PaintingStyle.stroke;
            canvas.drawLine(pCenter, pZ, paintZ);
            _draw3DBox(canvas, zTip, isHighlighted ? 13.0 : 9.0, colorZ, size);
          }

          // Uniform scale handle (White/Gold cube at center)
          final isUniformHighlighted = activeGizmoAxis == 'scaleUniform';
          final colorUniform = _getAxisColor('UNIFORM', Colors.white);
          _draw3DBox(canvas, center3d, isUniformHighlighted ? 16.0 : 12.0, colorUniform, size);
        }
      }
    }
  }

  void _drawPointLightGizmo(Canvas canvas, LightSource light, Size size, bool isSelected) {
    final lightPos = Vector3D(light.x, light.y, light.z);
    final pLight = cameraState.projectPoint(lightPos, size);
    if (pLight == null) return;

    final paintIcon = Paint()
      ..color = isSelected ? Colors.amber : Colors.yellow.shade700
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(pLight, 10.0, paintIcon);
    canvas.drawCircle(pLight, 12.0, Paint()..color = Colors.white.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 2.0);
    canvas.drawCircle(pLight, 4.0, Paint()..color = Colors.white..style = PaintingStyle.fill);

    if (isSelected) {
      final paintRange = Paint()
        ..color = Colors.amber.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      final List<Offset> hzCircle = [];
      for (int i = 0; i <= 24; i++) {
        double theta = i * 2 * pi / 24;
        final pt3d = lightPos + Vector3D(light.radius * cos(theta), 0, light.radius * sin(theta));
        final pt2d = cameraState.projectPoint(pt3d, size);
        if (pt2d != null) hzCircle.add(pt2d);
      }
      for (int i = 0; i < hzCircle.length - 1; i++) {
        canvas.drawLine(hzCircle[i], hzCircle[i + 1], paintRange);
      }

      final List<Offset> vtCircle = [];
      for (int i = 0; i <= 24; i++) {
        double theta = i * 2 * pi / 24;
        final pt3d = lightPos + Vector3D(light.radius * cos(theta), light.radius * sin(theta), 0);
        final pt2d = cameraState.projectPoint(pt3d, size);
        if (pt2d != null) vtCircle.add(pt2d);
      }
      for (int i = 0; i < vtCircle.length - 1; i++) {
        canvas.drawLine(vtCircle[i], vtCircle[i + 1], paintRange);
      }
    }
  }

  void _drawSpotLightGizmo(Canvas canvas, LightSource light, Size size, bool isSelected) {
    final lightPos = Vector3D(light.x, light.y, light.z);
    final pLight = cameraState.projectPoint(lightPos, size);
    if (pLight == null) return;

    final paintIcon = Paint()
      ..color = isSelected ? Colors.pinkAccent : Colors.pink.shade700
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(pLight, 10.0, paintIcon);
    canvas.drawCircle(pLight, 12.0, Paint()..color = Colors.white.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 2.0);
    canvas.drawCircle(pLight, 4.0, Paint()..color = Colors.white..style = PaintingStyle.fill);

    final dir = getLightDirection(light.rotationX, light.rotationY, light.rotationZ);

    final pDirEnd = cameraState.projectPoint(lightPos + dir * 60.0, size);
    if (pDirEnd != null) {
      canvas.drawLine(
        pLight,
        pDirEnd,
        Paint()
          ..color = isSelected ? Colors.pinkAccent : Colors.pink.shade300
          ..strokeWidth = 2.0,
      );
    }

    if (isSelected) {
      final paintRange = Paint()
        ..color = Colors.pinkAccent.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      final coneBaseCenter = lightPos + dir * light.radius;
      Vector3D u = dir.cross(Vector3D(0, 1, 0)).normalize();
      if (u.length == 0.0) u = dir.cross(Vector3D(1, 0, 0)).normalize();
      final v = dir.cross(u).normalize();
      
      final baseRadius = light.radius * tan(light.spotAngle);

      final List<Offset> baseCircle = [];
      for (int i = 0; i <= 24; i++) {
        double theta = i * 2 * pi / 24;
        final pt3d = coneBaseCenter + u * (baseRadius * cos(theta)) + v * (baseRadius * sin(theta));
        final pt2d = cameraState.projectPoint(pt3d, size);
        if (pt2d != null) baseCircle.add(pt2d);
      }
      
      for (int i = 0; i < baseCircle.length - 1; i++) {
        canvas.drawLine(baseCircle[i], baseCircle[i + 1], paintRange);
      }

      for (int i = 0; i < 4; i++) {
        double theta = i * pi / 2;
        final pt3d = coneBaseCenter + u * (baseRadius * cos(theta)) + v * (baseRadius * sin(theta));
        final pt2d = cameraState.projectPoint(pt3d, size);
        if (pt2d != null) {
          canvas.drawLine(pLight, pt2d, paintRange);
        }
      }
    }
  }

  void _drawDirectionalLightGizmo(Canvas canvas, LightSource light, Size size, bool isSelected) {
    final lightPos = Vector3D(light.x, light.y, light.z);
    final pLight = cameraState.projectPoint(lightPos, size);
    if (pLight == null) return;

    final paintIcon = Paint()
      ..color = isSelected ? Colors.cyanAccent : Colors.cyan.shade700
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(pLight, 10.0, paintIcon);
    canvas.drawCircle(pLight, 12.0, Paint()..color = Colors.white.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 2.0);
    canvas.drawCircle(pLight, 4.0, Paint()..color = Colors.white..style = PaintingStyle.fill);

    final dir = getLightDirection(light.rotationX, light.rotationY, light.rotationZ);

    final paintRay = Paint()
      ..color = isSelected ? Colors.cyanAccent : Colors.cyan.shade300
      ..strokeWidth = 1.5;

    final pDirEnd = cameraState.projectPoint(lightPos + dir * 80.0, size);
    if (pDirEnd != null) {
      canvas.drawLine(pLight, pDirEnd, paintRay);
    }

    if (isSelected) {
      Vector3D u = dir.cross(Vector3D(0, 1, 0)).normalize();
      if (u.length == 0.0) u = dir.cross(Vector3D(1, 0, 0)).normalize();
      final v = dir.cross(u).normalize();

      final offsets = [
        u * 30.0,
        u * -30.0,
        v * 30.0,
        v * -30.0,
      ];

      for (final offset in offsets) {
        final start = lightPos + offset;
        final end = start + dir * 60.0;
        final pStart = cameraState.projectPoint(start, size);
        final pEnd = cameraState.projectPoint(end, size);
        if (pStart != null && pEnd != null) {
          canvas.drawLine(pStart, pEnd, paintRay);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    final old = oldDelegate as ThreeDScenePainter;
    return old.cameraState != cameraState ||
           old.scenePolygons != scenePolygons ||
           old.lights != lights ||
           old.selectedLightId != selectedLightId ||
           old.showShadows != showShadows ||
           old.selectedFurnitureId != selectedFurnitureId ||
           old.furniture != furniture ||
           old.transformMode != transformMode ||
           old.activeGizmoAxis != activeGizmoAxis;
  }
}

// --- BEAUTIFUL SETTINGS DIALOG ---
class NavigationSettingsDialog extends ConsumerWidget {
  const NavigationSettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(navigationProvider);
    final notifier = ref.read(navigationProvider.notifier);

    return AlertDialog(
      backgroundColor: Colors.grey.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.tune, color: AppTheme.primary),
          SizedBox(width: 8),
          Text('Camera & Navigation Settings', style: TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSettingSlider(
              label: 'Field of View (Degrees)',
              value: (settings.fov * 180 / pi),
              min: 30,
              max: 110,
              displayValue: '${(settings.fov * 180 / pi).round()}°',
              onChanged: (val) => notifier.updateSettings(fov: val * pi / 180),
            ),
            const SizedBox(height: 12),
            _buildSettingSlider(
              label: 'Near Clipping Plane',
              value: settings.near,
              min: 1.0,
              max: 50.0,
              displayValue: '${settings.near.toStringAsFixed(1)} cm',
              onChanged: (val) => notifier.updateSettings(near: val),
            ),
            const SizedBox(height: 12),
            _buildSettingSlider(
              label: 'Far Clipping Plane',
              value: settings.far,
              min: 1000.0,
              max: 10000.0,
              displayValue: '${settings.far.round()} cm',
              onChanged: (val) => notifier.updateSettings(far: val),
            ),
            const SizedBox(height: 12),
            _buildSettingSlider(
              label: 'Movement Speed (WASD)',
              value: settings.movementSpeed,
              min: 1.0,
              max: 20.0,
              displayValue: settings.movementSpeed.toStringAsFixed(1),
              onChanged: (val) => notifier.updateSettings(movementSpeed: val),
            ),
            const SizedBox(height: 12),
            _buildSettingSlider(
              label: 'Rotation Sensitivity',
              value: settings.rotationSpeed,
              min: 0.001,
              max: 0.02,
              displayValue: (settings.rotationSpeed * 1000).toStringAsFixed(1),
              onChanged: (val) => notifier.updateSettings(rotationSpeed: val),
            ),
            const SizedBox(height: 12),
            _buildSettingSlider(
              label: 'Zoom Sensitivity',
              value: settings.zoomSpeed,
              min: 5.0,
              max: 100.0,
              displayValue: settings.zoomSpeed.toStringAsFixed(1),
              onChanged: (val) => notifier.updateSettings(zoomSpeed: val),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildSettingSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
            Text(displayValue, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          activeColor: AppTheme.primary,
          inactiveColor: AppTheme.primary.withOpacity(0.2),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
