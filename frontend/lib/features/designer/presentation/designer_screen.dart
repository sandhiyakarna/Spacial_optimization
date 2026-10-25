import '../../../app/themes/app_theme.dart';
import '../../../core/utils/url_helper.dart';
// ignore_for_file: deprecated_member_use

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/designer_provider.dart';
import '../providers/furniture_placement_provider.dart';
import 'designer_painter.dart';
import 'three_d_designer_view.dart';
import '../../furniture/providers/furniture_provider.dart';
import '../../../shared/widgets/snackbar_manager.dart';
import '../providers/design_score_provider.dart';
import '../providers/recommendation_provider.dart';
import '../providers/validation_provider.dart';
import '../providers/camera_provider.dart';
import '../providers/material_provider.dart';
import '../models/material_model.dart';
import '../providers/optimization_provider.dart';
import '../../furniture/models/furniture_asset.dart';
import 'widgets/properties_panel.dart';
import '../providers/lighting_provider.dart';
import 'widgets/light_properties_panel.dart';
import 'widgets/designer_toolbar.dart';
import 'widgets/designer_status_bar.dart';
import 'widgets/floating_controls.dart';
import 'widgets/furniture_placement_overlay.dart';
import 'widgets/developer_diagnostics_panel.dart';
import 'widgets/mobile_furniture_sheet.dart';
import 'widgets/ai_design_requirements_dialog.dart';
import 'widgets/ai_candidates_comparison_dialog.dart';
import '../../room/providers/room_provider.dart';
import '../../project/providers/project_provider.dart';
import 'dart:async';

// ─── Color palette (04_COLOR_PALETTE.md aligned) ──────────────────────────────
const _kSurface = Color(0xFF111827); // Dark Theme Surface
const _kSurfaceElevated = Color(0xFF1E293B); // Dark Theme Card
const _kBorder = Color(0xFF334155); // Dark Theme Border
const _kAccent = Color(0xFF0F766E); // Brand Primary
const _kAccentLight = Color(
  0xFF5B5BD6,
); // Brand Secondary (AI features/highlights)
const _kTextPrimary = Color(0xFFF8FAFC); // Dark Theme Primary Text
const _kTextSecondary = Color(0xFF94A3B8); // Dark Theme Secondary Text
const _kCanvas2D = Color(
  0xFFF8FAFC,
); // Light Theme Background for blueprint 2D canvas
const _kCanvas3D = Color(0xFF0F172A); // Dark Theme Background for 3D view

enum RecommendationCategory {
  suggestions('Suggestions', Icons.lightbulb_outline, Colors.amberAccent),
  designIssues('Design Issues', Icons.warning_amber_rounded, Colors.redAccent),
  spaceUtilization(
    'Space Utilization',
    Icons.space_dashboard_outlined,
    Colors.blueAccent,
  ),
  furnitureRecommendations(
    'Furniture Recommendations',
    Icons.chair_outlined,
    Colors.purpleAccent,
  ),
  colorHarmony('Color Harmony', Icons.palette_outlined, Colors.tealAccent),
  lightingSuggestions(
    'Lighting Suggestions',
    Icons.light_mode_outlined,
    Colors.orangeAccent,
  );

  final String title;
  final IconData icon;
  final Color color;
  const RecommendationCategory(this.title, this.icon, this.color);
}

class DesignerScreen extends ConsumerStatefulWidget {
  final String roomId;
  final bool isEmbedded;

  const DesignerScreen({
    super.key,
    required this.roomId,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<DesignerScreen> createState() => _DesignerScreenState();
}

class _DesignerScreenState extends ConsumerState<DesignerScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TransformationController _transformationController =
      TransformationController();
  final TextEditingController _furnitureSearchController =
      TextEditingController();
  final TextEditingController _materialSearchController =
      TextEditingController();

  // Custom Asset Uploader Controllers
  final TextEditingController _customAssetNameController =
      TextEditingController();
  final TextEditingController _customAssetWidthController =
      TextEditingController(text: '100');
  final TextEditingController _customAssetDepthController =
      TextEditingController(text: '100');
  final TextEditingController _customAssetHeightController =
      TextEditingController(text: '75');
  String _customAssetCategory = 'Living Room';
  String _customAssetStyle = 'Modern';

  Offset? _drawStart;
  Offset? _dragCurrent;
  bool _isDragging = false;
  final GlobalKey _canvasAreaKey = GlobalKey();
  bool _isDraggingFurniture = false;
  Offset? _dragStartScenePos;
  final Map<String, Offset> _dragStartFurnitureOffsets = {};
  bool _isMultiSelectMode = false;
  bool _is3DMode = true;
  bool _isWalkthroughMode = false;
  bool _showGrid = true;
  bool _measurementsEnabled = true;
  bool _showFurnitureLabels = true;
  bool _showDoors = true;
  bool _showWindows = true;
  bool _showDiagnostics = false;
  String _activeTransformTool = 'move';

  // Tabs state
  String _activeRightTab = 'properties';

  // Sidebar collapse state
  bool _leftSidebarOpen = true;
  bool _rightPanelOpen = true;

  // Fullscreen (collapse both panels) state
  bool _isFullscreen = false;

  // Zoom level displayed in status bar
  double _zoomLevel = 1.0;

  // Mouse canvas position for status bar coordinates
  Offset? _mouseCanvasPos;

  // Auto save & Initial load state variables
  String _autoSaveStatus = 'Saved';
  Timer? _autoSaveTimer;
  bool _isInitialLoad = true;

  // Left Sidebar Category tabs state
  String _selectedCategoryTab = 'Furniture';
  String? _selectedLibraryAssetId;
  final Set<String> _favoriteAssetIds = {};
  final List<dynamic> _recentlyUsedAssets = [];
  final TextEditingController _assetLibrarySearchController =
      TextEditingController();

  final List<String> _assetCategories = [
    'Furniture',
    'Materials',
    'Lighting',
    'Decor',
    'Plants',
    'Doors & Windows',
    'Templates',
    'Favorites',
    'Recently Used',
  ];

  late final List<FurnitureAsset> _mockLightingAssets = [
    FurnitureAsset(
      id: 'LIGHT_001',
      name: 'Floor Lamp',
      category: 'Lighting',
      style: 'Modern',
      width: 40.0,
      depth: 40.0,
      height: 160.0,
      clearance: 10.0,
      assemblyClearance: 10.0,
      glbUrl: '',
      thumbnailUrl: '',
      createdAt: DateTime.now(),
    ),
    FurnitureAsset(
      id: 'LIGHT_002',
      name: 'Table Lamp',
      category: 'Lighting',
      style: 'Modern',
      width: 30.0,
      depth: 30.0,
      height: 50.0,
      clearance: 0.0,
      assemblyClearance: 0.0,
      glbUrl: '',
      thumbnailUrl: '',
      createdAt: DateTime.now(),
    ),
    FurnitureAsset(
      id: 'LIGHT_003',
      name: 'Ceiling Pendant Light',
      category: 'Lighting',
      style: 'Modern',
      width: 50.0,
      depth: 50.0,
      height: 80.0,
      clearance: 20.0,
      assemblyClearance: 20.0,
      glbUrl: '',
      thumbnailUrl: '',
      createdAt: DateTime.now(),
    ),
  ];

  late final List<FurnitureAsset> _mockDecorAssets = [
    FurnitureAsset(
      id: 'DECOR_001',
      name: 'Abstract Wall Painting',
      category: 'Decor',
      style: 'Modern',
      width: 120.0,
      depth: 5.0,
      height: 90.0,
      clearance: 0.0,
      assemblyClearance: 0.0,
      glbUrl: '',
      thumbnailUrl: '',
      createdAt: DateTime.now(),
    ),
    FurnitureAsset(
      id: 'DECOR_002',
      name: 'Round Wall Mirror',
      category: 'Decor',
      style: 'Modern',
      width: 80.0,
      depth: 4.0,
      height: 80.0,
      clearance: 0.0,
      assemblyClearance: 0.0,
      glbUrl: '',
      thumbnailUrl: '',
      createdAt: DateTime.now(),
    ),
    FurnitureAsset(
      id: 'DECOR_003',
      name: 'Ceramic Floor Vase',
      category: 'Decor',
      style: 'Minimal',
      width: 35.0,
      depth: 35.0,
      height: 70.0,
      clearance: 0.0,
      assemblyClearance: 0.0,
      glbUrl: '',
      thumbnailUrl: '',
      createdAt: DateTime.now(),
    ),
  ];

  late final List<FurnitureAsset> _mockPlantsAssets = [
    FurnitureAsset(
      id: 'PLANT_001',
      name: 'Monstera Plant',
      category: 'Plants',
      style: 'Biophilic',
      width: 60.0,
      depth: 60.0,
      height: 100.0,
      clearance: 10.0,
      assemblyClearance: 10.0,
      glbUrl: '',
      thumbnailUrl: '',
      createdAt: DateTime.now(),
    ),
    FurnitureAsset(
      id: 'PLANT_002',
      name: 'Fiddle Leaf Fig Tree',
      category: 'Plants',
      style: 'Biophilic',
      width: 50.0,
      depth: 50.0,
      height: 150.0,
      clearance: 10.0,
      assemblyClearance: 10.0,
      glbUrl: '',
      thumbnailUrl: '',
      createdAt: DateTime.now(),
    ),
    FurnitureAsset(
      id: 'PLANT_003',
      name: 'Snake Plant in Pot',
      category: 'Plants',
      style: 'Biophilic',
      width: 30.0,
      depth: 30.0,
      height: 80.0,
      clearance: 5.0,
      assemblyClearance: 5.0,
      glbUrl: '',
      thumbnailUrl: '',
      createdAt: DateTime.now(),
    ),
  ];

  final List<Map<String, dynamic>> _mockDoorsWindowsAssets = [
    {
      'id': 'OPENING_DOOR',
      'name': 'Standard Single Door',
      'category': 'Doors & Windows',
      'type': 'door',
      'width': 90.0,
      'height': 210.0,
    },
    {
      'id': 'OPENING_SLIDING_GLASS',
      'name': 'Sliding Glass Patio Door',
      'category': 'Doors & Windows',
      'type': 'door',
      'width': 180.0,
      'height': 210.0,
    },
    {
      'id': 'OPENING_WINDOW',
      'name': 'Double Casement Window',
      'category': 'Doors & Windows',
      'type': 'window',
      'width': 120.0,
      'height': 120.0,
    },
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      setState(() => _isInitialLoad = true);
      await ref.read(designerProvider.notifier).loadLayout(widget.roomId);
      if (mounted) {
        setState(() => _isInitialLoad = false);
      }
      ref.read(furnitureProvider.notifier).updateCategoryFilter('Furniture');
      ref
          .read(validationProvider.notifier)
          .loadValidationResults(widget.roomId);
      ref.read(designScoreProvider.notifier).fetchScores(widget.roomId);
      ref.read(roomDetailsProvider.notifier).fetchDetails(widget.roomId);
      ref.read(projectProvider.notifier).fetchProjects();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerView();
    });
    _transformationController.addListener(_onTransformChanged);
    _materialSearchController.addListener(() {
      ref
          .read(materialProvider.notifier)
          .updateSearch(_materialSearchController.text);
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    _furnitureSearchController.dispose();
    _materialSearchController.dispose();
    _customAssetNameController.dispose();
    _customAssetWidthController.dispose();
    _customAssetDepthController.dispose();
    _customAssetHeightController.dispose();
    _assetLibrarySearchController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if (mounted) {
      setState(() => _zoomLevel = scale);
    }
  }

  // ─── Gesture / Canvas Logic (unchanged) ──────────────────────────────────────

  Offset _getCanvasCoords(Offset localPosition) {
    return _transformationController.toScene(localPosition);
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final l2 = (a - b).distanceSquared;
    if (l2 == 0) return (p - a).distance;
    final t =
        ((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2;
    final clampedT = t.clamp(0.0, 1.0);
    final projection = Offset(
      a.dx + clampedT * (b.dx - a.dx),
      a.dy + clampedT * (b.dy - a.dy),
    );
    return (p - projection).distance;
  }

  void _handleTapDown(
    TapDownDetails details,
    DesignerLayoutState layout,
    DesignerNotifier notifier,
  ) {
    final canvasOffset = _getCanvasCoords(details.localPosition);

    switch (layout.tool) {
      case DesignerTool.select:
        // 1. Check Furniture items first (reverse order so top-most item is hit)
        bool furnitureSelected = false;
        for (final f in layout.furniture.reversed) {
          final dx = canvasOffset.dx - f.x;
          final dz = canvasOffset.dy - f.z;
          final cosA = cos(-f.rotationY);
          final sinA = sin(-f.rotationY);
          final localX = dx * cosA - dz * sinA;
          final localZ = dx * sinA + dz * cosA;
          if (localX.abs() <= (f.width / 2.0 + 8.0) &&
              localZ.abs() <= (f.depth / 2.0 + 8.0)) {
            final isShift = HardwareKeyboard.instance.isShiftPressed ||
                HardwareKeyboard.instance.isControlPressed;
            notifier.selectFurniture(f.id, multi: isShift || _isMultiSelectMode);
            furnitureSelected = true;
            break;
          }
        }
        if (furnitureSelected) break;

        // 2. Check Openings
        bool openingSelected = false;
        for (final op in layout.openings) {
          final dist = (op.position - canvasOffset).distance;
          if (dist < 40.0) {
            notifier.selectOpening(op.id);
            openingSelected = true;
            break;
          }
        }
        if (openingSelected) break;

        // 3. Check Wall Endpoints
        bool endpointSelected = false;
        for (int i = 0; i < layout.walls.length; i++) {
          final wall = layout.walls[i];
          if ((wall.start - canvasOffset).distance < 20.0) {
            notifier.selectWallEndpoint(i, true);
            endpointSelected = true;
            break;
          }
          if ((wall.end - canvasOffset).distance < 20.0) {
            notifier.selectWallEndpoint(i, false);
            endpointSelected = true;
            break;
          }
        }
        if (endpointSelected) break;

        // 4. Check Wall Segments
        bool wallSelected = false;
        for (int i = 0; i < layout.walls.length; i++) {
          final wall = layout.walls[i];
          final dist = _distanceToSegment(canvasOffset, wall.start, wall.end);
          if (dist < (wall.thickness / 2 + 15.0)) {
            notifier.selectWall(i);
            wallSelected = true;
            break;
          }
        }
        if (wallSelected) break;

        notifier.clearSelection();
        break;

      case DesignerTool.drawWall:
        setState(() {
          _drawStart = canvasOffset;
          _dragCurrent = canvasOffset;
        });
        break;

      case DesignerTool.placeDoor:
        notifier.placeOpening('door', canvasOffset);
        notifier.selectTool(DesignerTool.select);
        break;

      case DesignerTool.placeWindow:
        notifier.placeOpening('window', canvasOffset);
        notifier.selectTool(DesignerTool.select);
        break;

      case DesignerTool.pan:
        break;
    }
  }

  void _handlePanStart(
    DragStartDetails details,
    DesignerLayoutState layout,
    DesignerNotifier notifier,
  ) {
    if (layout.tool == DesignerTool.select) {
      final canvasOffset = _getCanvasCoords(details.localPosition);

      // Check if user pressed down on furniture to drag it
      String? hitFurnitureId;
      for (final f in layout.furniture.reversed) {
        final dx = canvasOffset.dx - f.x;
        final dz = canvasOffset.dy - f.z;
        final cosA = cos(-f.rotationY);
        final sinA = sin(-f.rotationY);
        final localX = dx * cosA - dz * sinA;
        final localZ = dx * sinA + dz * cosA;
        if (localX.abs() <= (f.width / 2.0 + 8.0) &&
            localZ.abs() <= (f.depth / 2.0 + 8.0)) {
          hitFurnitureId = f.id;
          break;
        }
      }

      if (hitFurnitureId != null) {
        if (!layout.selectedFurnitureIds.contains(hitFurnitureId)) {
          notifier.selectFurniture(hitFurnitureId);
        }
        _dragStartScenePos = canvasOffset;
        _dragStartFurnitureOffsets.clear();
        final targets = layout.selectedFurnitureIds.contains(hitFurnitureId)
            ? layout.selectedFurnitureIds
            : {hitFurnitureId};
        for (final f in layout.furniture) {
          if (targets.contains(f.id)) {
            _dragStartFurnitureOffsets[f.id] = Offset(f.x, f.z);
          }
        }
        notifier.pushUndo();
        ref
            .read(furniturePlacementProvider.notifier)
            .startMovingPlaced(hitFurnitureId, canvasOffset);
        setState(() {
          _isDragging = true;
          _isDraggingFurniture = true;
        });
        return;
      }

      final isEndpoint = layout.selectedWallEndpointId != null;
      final isOpening = layout.selectedOpeningId != null;
      final isWall = layout.selectedWallIndex != null;

      if (isEndpoint || isOpening || isWall) {
        notifier.pushUndo();
        notifier.startDragging(canvasOffset);
        setState(() => _isDragging = true);
      }
    }
  }

  void _handlePanUpdate(
    DragUpdateDetails details,
    DesignerLayoutState layout,
    DesignerNotifier notifier,
  ) {
    final canvasOffset = _getCanvasCoords(details.localPosition);

    if (layout.tool == DesignerTool.drawWall && _drawStart != null) {
      setState(() => _dragCurrent = canvasOffset);
    } else if (layout.tool == DesignerTool.select && _isDragging) {
      if (_isDraggingFurniture && _dragStartScenePos != null) {
        final delta = canvasOffset - _dragStartScenePos!;
        double deltaX = delta.dx;
        double deltaZ = delta.dy;
        if (layout.snapToGrid) {
          final spacing = layout.gridSpacing;
          deltaX = (deltaX / spacing).round() * spacing;
          deltaZ = (deltaZ / spacing).round() * spacing;
        }

        for (final entry in _dragStartFurnitureOffsets.entries) {
          final orig = entry.value;
          notifier.moveFurnitureTo(entry.key, orig.dx + deltaX, orig.dy + deltaZ);
        }

        final primaryId = layout.selectedFurnitureId ??
            _dragStartFurnitureOffsets.keys.firstOrNull;
        if (primaryId != null) {
          ref
              .read(furniturePlacementProvider.notifier)
              .updateMovingPlaced(canvasOffset, layout);
        }
      } else if (layout.selectedOpeningId != null) {
        notifier.moveSelectedOpening(canvasOffset);
      } else if (layout.selectedWallEndpointId != null) {
        notifier.moveWallEndpoint(canvasOffset);
      } else if (layout.selectedWallIndex != null) {
        notifier.moveSelectedWall(canvasOffset);
      }
    }
  }

  void _handlePanEnd(
    DragEndDetails details,
    DesignerLayoutState layout,
    DesignerNotifier notifier,
  ) {
    if (layout.tool == DesignerTool.drawWall &&
        _drawStart != null &&
        _dragCurrent != null) {
      final distance = (_dragCurrent! - _drawStart!).distance;
      if (distance > 10.0) {
        notifier.addWall(_drawStart!, _dragCurrent!);
      }
      setState(() {
        _drawStart = null;
        _dragCurrent = null;
      });
    } else if (layout.tool == DesignerTool.select && _isDragging) {
      if (_isDraggingFurniture) {
        ref.read(furniturePlacementProvider.notifier).cancelMovingPlaced();
        _dragStartFurnitureOffsets.clear();
        _dragStartScenePos = null;
        setState(() {
          _isDragging = false;
          _isDraggingFurniture = false;
        });
      } else {
        setState(() => _isDragging = false);
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isControl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final notifier = ref.read(designerProvider.notifier);

    // Delete / Backspace
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      notifier.deleteSelected();
      return KeyEventResult.handled;
    }

    // Ctrl+Z (Undo)
    if (isControl && event.logicalKey == LogicalKeyboardKey.keyZ && !isShift) {
      notifier.undo();
      return KeyEventResult.handled;
    }

    // Ctrl+Y or Ctrl+Shift+Z (Redo)
    if ((isControl && event.logicalKey == LogicalKeyboardKey.keyY) ||
        (isControl && isShift && event.logicalKey == LogicalKeyboardKey.keyZ)) {
      notifier.redo();
      return KeyEventResult.handled;
    }

    // Ctrl+D (Duplicate)
    if (isControl && event.logicalKey == LogicalKeyboardKey.keyD) {
      notifier.duplicateSelectedFurniture();
      return KeyEventResult.handled;
    }

    // Ctrl+C (Copy)
    if (isControl && event.logicalKey == LogicalKeyboardKey.keyC) {
      notifier.copySelectedFurniture();
      return KeyEventResult.handled;
    }

    // Ctrl+V (Paste)
    if (isControl && event.logicalKey == LogicalKeyboardKey.keyV) {
      notifier.pasteFurniture();
      return KeyEventResult.handled;
    }

    // Ctrl+A (Select All)
    if (isControl && event.logicalKey == LogicalKeyboardKey.keyA) {
      notifier.selectAllFurniture();
      return KeyEventResult.handled;
    }

    // Escape (Deselect)
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      notifier.clearSelection();
      return KeyEventResult.handled;
    }

    // R (Rotate 90 degrees)
    if (event.logicalKey == LogicalKeyboardKey.keyR) {
      notifier.rotateSelectedFurniture90(clockwise: !isShift);
      return KeyEventResult.handled;
    }

    // Arrow keys nudge
    final nudgeStep = isShift ? 25.0 : 5.0;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      notifier.moveSelectedFurnitureGroup(-nudgeStep, 0.0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      notifier.moveSelectedFurnitureGroup(nudgeStep, 0.0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      notifier.moveSelectedFurnitureGroup(0.0, -nudgeStep);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      notifier.moveSelectedFurnitureGroup(0.0, nudgeStep);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _handleSave(DesignerNotifier notifier) async {
    _autoSaveTimer?.cancel();
    setState(() {
      _autoSaveStatus = 'Saving';
    });
    final success = await notifier.saveLayout(widget.roomId);
    if (mounted) {
      setState(() {
        _autoSaveStatus = success ? 'Saved' : 'Error';
      });
      if (success) {
        SnackbarManager.showSuccess(
          context,
          'Room design layout saved successfully.',
        );
        ref.read(validationProvider.notifier).runValidation(widget.roomId);
        ref.read(designScoreProvider.notifier).fetchScores(widget.roomId);
      } else {
        SnackbarManager.showError(
          context,
          'Failed to save room design layout.',
        );
      }
    }
  }

  void _triggerAutoSave() {
    if (!mounted) return;
    setState(() {
      _autoSaveStatus = 'Saving';
    });
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 3), () async {
      final notifier = ref.read(designerProvider.notifier);
      final success = await notifier.saveLayout(widget.roomId);
      if (mounted) {
        setState(() {
          _autoSaveStatus = success ? 'Saved' : 'Error';
        });
        if (success) {
          ref.read(validationProvider.notifier).runValidation(widget.roomId);
          ref.read(designScoreProvider.notifier).fetchScores(widget.roomId);
        }
      }
    });
  }

  void _zoom(double factor) {
    final matrix = _transformationController.value.clone();
    double currentScale = matrix.getMaxScaleOnAxis();
    double targetScale = (currentScale * factor).clamp(0.1, 4.0);
    double actualFactor = targetScale / currentScale;

    final size = MediaQuery.of(context).size;
    final double px = size.width / 2;
    final double py = size.height / 2;

    matrix.translate(px, py);
    matrix.scale(actualFactor);
    matrix.translate(-px, -py);

    setState(() {
      _transformationController.value = matrix;
    });
  }

  void _centerView() {
    final size = MediaQuery.of(context).size;
    const double canvasCenterX = 2000.0;
    const double canvasCenterY = 2000.0;
    const double scale = 1.0;
    final double tx = size.width / 2 - canvasCenterX * scale;
    final double ty = size.height / 2 - canvasCenterY * scale;

    final matrix = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);

    setState(() {
      _transformationController.value = matrix;
    });
  }

  /// Focus 2D view on the selected element by centering the
  /// TransformationController on that element's canvas position.
  void _focusSelection2D() {
    final layout = ref.read(designerProvider);
    double cx = 2000.0;
    double cy = 2000.0;

    if (layout.selectedFurnitureId != null) {
      try {
        final f = layout.furniture.firstWhere(
          (f) => f.id == layout.selectedFurnitureId,
        );
        cx = f.x;
        cy = f.z;
      } catch (_) {}
    } else if (layout.selectedWallIndex != null) {
      final w = layout.walls[layout.selectedWallIndex!];
      cx = (w.start.dx + w.end.dx) / 2;
      cy = (w.start.dy + w.end.dy) / 2;
    } else if (layout.selectedOpeningId != null) {
      try {
        final op = layout.openings.firstWhere(
          (o) => o.id == layout.selectedOpeningId,
        );
        cx = op.position.dx;
        cy = op.position.dy;
      } catch (_) {}
    }

    final size = MediaQuery.of(context).size;
    final double scale = _transformationController.value.getMaxScaleOnAxis();
    final double tx = size.width / 2 - cx * scale;
    final double ty = size.height / 2 - cy * scale;

    final matrix = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);

    setState(() {
      _transformationController.value = matrix;
    });
  }

  /// Toggle fullscreen mode — collapses/restores both side panels.
  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
      if (_isFullscreen) {
        _leftSidebarOpen = false;
        _rightPanelOpen = false;
      } else {
        _leftSidebarOpen = true;
        _rightPanelOpen = true;
      }
    });
  }

  String _getViewModeLabel(ViewMode mode) {
    switch (mode) {
      case ViewMode.perspective:
        return 'Perspective';
      case ViewMode.top:
        return 'Top Plan';
      case ViewMode.front:
        return 'Front Elevation';
      case ViewMode.left:
        return 'Left Elevation';
      case ViewMode.right:
        return 'Right Elevation';
      case ViewMode.isometric:
        return 'Isometric';
      case ViewMode.free:
        return 'Walkthrough Mode';
      case ViewMode.orbit:
        return 'Orbit View';
    }
  }

  String _getToolLabel(DesignerTool tool) {
    switch (tool) {
      case DesignerTool.select:
        return 'Select';
      case DesignerTool.drawWall:
        return 'Draw Wall';
      case DesignerTool.placeDoor:
        return 'Place Door';
      case DesignerTool.placeWindow:
        return 'Place Window';
      case DesignerTool.pan:
        return 'Pan';
    }
  }

  // ─── Score breakdown dialog (unchanged) ───────────────────────────────────────

  void _showScoreBreakdownDialog(DesignScores scores) {
    final validationState = ref.read(validationProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kSurfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: _kAccent),
            SizedBox(width: 8),
            Text(
              'Design Score & Spatial Validation',
              style: TextStyle(color: _kTextPrimary, fontSize: 16),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      Text(
                        '${scores.overallScore.round()}',
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.bold,
                          color: (validationState.errors.isNotEmpty)
                              ? Colors.redAccent
                              : (scores.overallScore >= 80.0
                                  ? Colors.greenAccent
                                  : (scores.overallScore >= 50.0
                                      ? Colors.orange
                                      : Colors.redAccent)),
                        ),
                      ),
                      Text(
                        validationState.errors.isNotEmpty
                            ? 'Issues Detected (Score impacted)'
                            : (scores.overallScore >= 80.0
                                ? 'Great Design Score'
                                : 'Needs Improvement'),
                        style: TextStyle(
                          color: validationState.errors.isNotEmpty ? Colors.redAccent : _kTextSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'SUBSCORES',
                  style: TextStyle(
                    color: _kTextSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                ...scores.subscores.entries.map((entry) {
                  final subVal = entry.value;
                  final subColor = subVal >= 80.0
                      ? Colors.greenAccent
                      : (subVal >= 50.0 ? Colors.orange : Colors.redAccent);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              entry.key.replaceAll('_', ' ').toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 10,
                                color: _kTextSecondary,
                              ),
                            ),
                            Text(
                              '${subVal.round()}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                color: subColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        LinearProgressIndicator(
                          value: subVal / 100.0,
                          backgroundColor: _kBorder,
                          valueColor: AlwaysStoppedAnimation<Color>(subColor),
                        ),
                      ],
                    ),
                  );
                }),
                if (validationState.errors.isNotEmpty || validationState.warnings.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(color: _kBorder, height: 1),
                  const SizedBox(height: 12),
                  const Text(
                    'ACTIVE SPATIAL RULES & WARNINGS',
                    style: TextStyle(
                      color: _kTextSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...validationState.errors.map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                e.ruleName,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          e.message,
                          style: const TextStyle(color: _kTextPrimary, fontSize: 10.5),
                        ),
                        if (e.recommendation != null && e.recommendation!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Action: ${e.recommendation}',
                            style: const TextStyle(color: _kTextSecondary, fontSize: 9.5, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  )),
                  ...validationState.warnings.map((w) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                w.ruleName,
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          w.message,
                          style: const TextStyle(color: _kTextPrimary, fontSize: 10.5),
                        ),
                        if (w.recommendation != null && w.recommendation!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Action: ${w.recommendation}',
                            style: const TextStyle(color: _kTextSecondary, fontSize: 9.5, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  )),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Close',
              style: TextStyle(color: _kAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  TOP TOOLBAR
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  //  LEFT SIDEBAR  (collapsible – furniture library)
  // ═══════════════════════════════════════════════════════════════════════════

  // ─── Collapsible Sidebar Sections ──────────────────────────────────────────

  final List<Map<String, dynamic>> _designTemplates = [
    {
      'title': 'Ergonomic Home Office',
      'description': 'Posture-optimized desk placement and chair layout.',
      'icon': Icons.desk_outlined,
      'furniture': [
        {
          'assetId': 'DESK001',
          'name': 'Industrial Study Desk',
          'x': 2000.0,
          'z': 1800.0,
        },
        {
          'assetId': 'CHAIR001',
          'name': 'Ergonomic Office Chair',
          'x': 2000.0,
          'z': 1950.0,
        },
      ],
    },
    {
      'title': 'Scandinavian Living Room',
      'description':
          'Light wood minimal aesthetics with sofa and dining table.',
      'icon': Icons.chair_outlined,
      'furniture': [
        {'assetId': 'SOFA001', 'name': 'Modern Sofa', 'x': 2000.0, 'z': 1800.0},
        {
          'assetId': 'TABLE001',
          'name': 'Scandinavian Dining Table',
          'x': 2000.0,
          'z': 2200.0,
        },
      ],
    },
    {
      'title': 'Minimalist Bedroom',
      'description': 'Calming bedroom sanctuary layout with a king bed.',
      'icon': Icons.bed_outlined,
      'furniture': [
        {
          'assetId': 'BED001',
          'name': 'Minimalist King Bed',
          'x': 2000.0,
          'z': 2000.0,
        },
      ],
    },
    {
      'title': 'Cozy Reading Nook',
      'description': 'Relaxing layout with a study desk and office chair.',
      'icon': Icons.book_outlined,
      'furniture': [
        {
          'assetId': 'DESK001',
          'name': 'Industrial Study Desk',
          'x': 1800.0,
          'z': 1800.0,
        },
        {
          'assetId': 'CHAIR001',
          'name': 'Ergonomic Office Chair',
          'x': 1820.0,
          'z': 1900.0,
        },
      ],
    },
  ];

  Widget _buildLeftSidebar(
    FurnitureListState state,
    DesignerNotifier notifier,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      width: _leftSidebarOpen ? 280 : 0,
      child: _leftSidebarOpen
          ? _buildSidebarContent(state, notifier)
          : const SizedBox.shrink(),
    );
  }

  void _addRecentlyUsed(dynamic asset) {
    setState(() {
      _recentlyUsedAssets.removeWhere((item) {
        final String id1 = _getAssetId(item);
        final String id2 = _getAssetId(asset);
        return id1 == id2;
      });
      _recentlyUsedAssets.insert(0, asset);
      if (_recentlyUsedAssets.length > 20) {
        _recentlyUsedAssets.removeLast();
      }
    });
  }

  String _getAssetId(dynamic asset) {
    if (asset is FurnitureAsset) return asset.id;
    if (asset is MaterialModel) return asset.id;
    if (asset is Map<String, dynamic>) {
      return (asset['id'] ?? asset['title'] ?? '').toString();
    }
    return '';
  }

  String _getAssetName(dynamic asset) {
    if (asset is FurnitureAsset) return asset.name;
    if (asset is MaterialModel) return asset.name;
    if (asset is Map<String, dynamic>) {
      return (asset['name'] ?? asset['title'] ?? '').toString();
    }
    return 'Unknown';
  }

  String _getAssetCategory(dynamic asset) {
    if (asset is FurnitureAsset) return asset.category;
    if (asset is MaterialModel) return asset.category.name;
    if (asset is Map<String, dynamic>) {
      return (asset['category'] ?? '').toString();
    }
    return '';
  }

  bool _isAssetFavorite(dynamic asset, dynamic materialState) {
    final String id = _getAssetId(asset);
    if (asset is MaterialModel) {
      return materialState.favorites.contains(id);
    }
    return _favoriteAssetIds.contains(id);
  }

  void _toggleAssetFavorite(dynamic asset) {
    final String id = _getAssetId(asset);
    if (asset is MaterialModel) {
      ref.read(materialProvider.notifier).toggleFavorite(id);
    } else {
      setState(() {
        if (_favoriteAssetIds.contains(id)) {
          _favoriteAssetIds.remove(id);
        } else {
          _favoriteAssetIds.add(id);
        }
      });
    }
  }

  void _handleAssetPlacement(dynamic asset, DesignerNotifier notifier) {
    _addRecentlyUsed(asset);
    double cx = 2000.0, cz = 2000.0;
    final layout = ref.read(designerProvider);
    if (layout.walls.isNotEmpty) {
      double minX = double.infinity, maxX = -double.infinity;
      double minZ = double.infinity, maxZ = -double.infinity;
      for (final w in layout.walls) {
        if (w.start.dx < minX) minX = w.start.dx;
        if (w.end.dx < minX) minX = w.end.dx;
        if (w.start.dx > maxX) maxX = w.start.dx;
        if (w.end.dx > maxX) maxX = w.end.dx;

        if (w.start.dy < minZ) minZ = w.start.dy;
        if (w.end.dy < minZ) minZ = w.end.dy;
        if (w.start.dy > maxZ) maxZ = w.start.dy;
        if (w.end.dy > maxZ) maxZ = w.end.dy;
      }
      cx = (minX + maxX) / 2;
      cz = (minZ + maxZ) / 2;
    }

    if (asset is FurnitureAsset) {
      notifier.addFurniture(asset, cx, cz);
      SnackbarManager.showSuccess(
        context,
        'Placed ${asset.name} at room center.',
      );
    } else if (asset is Map<String, dynamic>) {
      if (asset['type'] != null) {
        notifier.placeOpening(asset['type'] as String, Offset(cx, cz));
        SnackbarManager.showSuccess(
          context,
          'Placed ${asset['name']} at room center.',
        );
      } else if (asset['furniture'] != null) {
        _applyTemplateLayout(
          asset['title'] as String,
          List<Map<String, dynamic>>.from(asset['furniture']),
          notifier,
        );
      }
    }
  }

  Widget _buildFallbackThumbnail(String category) {
    IconData iconData;
    switch (category.toLowerCase()) {
      case 'lighting':
        iconData = Icons.wb_incandescent_outlined;
        break;
      case 'decor':
        iconData = Icons.wallpaper_outlined;
        break;
      case 'plants':
        iconData = Icons.park_outlined;
        break;
      default:
        iconData = Icons.chair_outlined;
    }
    return Icon(iconData, size: 36, color: _kAccent);
  }

  IconData _getMaterialCategoryIcon(String categoryName) {
    switch (categoryName.toLowerCase()) {
      case 'wood':
        return Icons.forest_outlined;
      case 'metal':
        return Icons.hardware_outlined;
      case 'glass':
        return Icons.blur_on_outlined;
      case 'fabric':
        return Icons.texture_outlined;
      case 'ceramic':
      case 'marble':
        return Icons.grid_on_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  void _showMaterialOptionsSheet(MaterialModel material) {
    final layout = ref.read(designerProvider);
    final isSelectedFurniture = layout.selectedFurnitureId != null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kSurfaceElevated,
        title: Text(
          'Apply Material: ${material.name}',
          style: const TextStyle(
            color: _kTextPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Select where to apply this material (${material.category.name}):',
          style: const TextStyle(color: _kTextSecondary, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _kTextSecondary),
            ),
          ),
          if (isSelectedFurniture)
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                ref
                    .read(designerProvider.notifier)
                    .updateSelectedFurnitureMaterial(
                      color: material.baseColor?.replaceAll('#', ''),
                      metallic: material.reflectivity,
                      roughness: 1.0 - material.reflectivity,
                      materialType: material.category.name.toLowerCase(),
                    );
                await ref
                    .read(materialProvider.notifier)
                    .applyMaterial(layout.selectedFurnitureId!, material.id);
                _addRecentlyUsed(material);
                SnackbarManager.showSuccess(
                  context,
                  'Applied ${material.name} to selected furniture.',
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Selected Furniture',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(designerProvider.notifier)
                  .updateRoomMaterials(
                    floorColor: material.baseColor?.replaceAll('#', ''),
                    floorType: material.category.name.toLowerCase(),
                  );
              ref.read(materialProvider.notifier).addRecentlyUsed(material.id);
              _addRecentlyUsed(material);
              SnackbarManager.showSuccess(
                context,
                'Applied ${material.name} to room floor.',
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kSurface,
              foregroundColor: _kTextPrimary,
              side: const BorderSide(color: _kBorder),
            ),
            child: const Text('Apply to Floor', style: TextStyle(fontSize: 11)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(designerProvider.notifier)
                  .updateRoomMaterials(
                    wallColor: material.baseColor?.replaceAll('#', ''),
                    wallType: material.category.name.toLowerCase(),
                  );
              ref.read(materialProvider.notifier).addRecentlyUsed(material.id);
              _addRecentlyUsed(material);
              SnackbarManager.showSuccess(
                context,
                'Applied ${material.name} to room walls.',
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kSurface,
              foregroundColor: _kTextPrimary,
              side: const BorderSide(color: _kBorder),
            ),
            child: const Text('Apply to Walls', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Color _parseHexColor(String? hexString, {Color fallback = AppTheme.primary}) {
    if (hexString == null) return fallback;
    try {
      final hex = hexString.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  List<dynamic> _getFilteredAssets(
    FurnitureListState furnitureState,
    dynamic materialState,
  ) {
    final query = _assetLibrarySearchController.text.toLowerCase();
    List<dynamic> list = [];

    switch (_selectedCategoryTab) {
      case 'Furniture':
      case 'Lighting':
      case 'Decor':
      case 'Plants':
        list = furnitureState.assets;
        break;
      case 'Materials':
        list = materialState.materials;
        break;
      case 'Doors & Windows':
        list = _mockDoorsWindowsAssets;
        break;
      case 'Templates':
        list = _designTemplates;
        break;
      case 'Favorites':
        final allFavs = <dynamic>[];
        allFavs.addAll(furnitureState.assets);
        for (final material in materialState.materials) {
          if (materialState.favorites.contains(material.id)) {
            allFavs.add(material);
          }
        }
        list = allFavs;
        break;
      case 'Recently Used':
        list = furnitureState.assets;
        break;
      default:
        list = [];
    }

    if (query.isEmpty) {
      return list;
    }

    return list.where((item) {
      if (item is FurnitureAsset) {
        return item.name.toLowerCase().contains(query) ||
            (item.tags?.toLowerCase().contains(query) ?? false);
      } else if (item is MaterialModel) {
        return item.name.toLowerCase().contains(query) ||
            item.category.name.toLowerCase().contains(query);
      } else if (item is Map<String, dynamic>) {
        final name = (item['name'] ?? item['title'] ?? '')
            .toString()
            .toLowerCase();
        final desc = (item['description'] ?? '').toString().toLowerCase();
        return name.contains(query) || desc.contains(query);
      }
      return false;
    }).toList();
  }

  Widget _buildCategoryTabs() {
    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        physics: const BouncingScrollPhysics(),
        itemCount: _assetCategories.length,
        itemBuilder: (context, index) {
          final cat = _assetCategories[index];
          final isSelected = _selectedCategoryTab == cat;

          IconData iconData;
          switch (cat) {
            case 'Furniture':
              iconData = Icons.chair_outlined;
              break;
            case 'Materials':
              iconData = Icons.texture_outlined;
              break;
            case 'Lighting':
              iconData = Icons.wb_incandescent_outlined;
              break;
            case 'Decor':
              iconData = Icons.wallpaper_outlined;
              break;
            case 'Plants':
              iconData = Icons.park_outlined;
              break;
            case 'Doors & Windows':
              iconData = Icons.door_front_door_outlined;
              break;
            case 'Templates':
              iconData = Icons.dashboard_customize_outlined;
              break;
            case 'Favorites':
              iconData = Icons.favorite_outline_rounded;
              break;
            case 'Recently Used':
              iconData = Icons.history_rounded;
              break;
            default:
              iconData = Icons.help_outline;
          }

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              avatar: Icon(
                iconData,
                size: 14,
                color: isSelected ? Colors.black : _kTextSecondary,
              ),
              label: Text(cat, style: const TextStyle(fontSize: 10.5)),
              selected: isSelected,
              onSelected: (_) {
                setState(() {
                  _selectedCategoryTab = cat;
                  _selectedLibraryAssetId = null;
                });
                _onCategoryTabChanged(cat);
              },
              selectedColor: _kAccent,
              checkmarkColor: Colors.black,
              backgroundColor: _kSurfaceElevated,
              side: const BorderSide(color: _kBorder),
              labelStyle: TextStyle(
                color: isSelected ? Colors.black : _kTextSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          );
        },
      ),
    );
  }

  void _onCategoryTabChanged(String cat) {
    final notifier = ref.read(furnitureProvider.notifier);
    _assetLibrarySearchController.clear();

    switch (cat) {
      case 'Furniture':
        notifier.setCatalogMode(CatalogMode.all);
        notifier.updateCategoryFilter('Furniture');
        break;
      case 'Lighting':
        notifier.setCatalogMode(CatalogMode.all);
        notifier.updateCategoryFilter('Lighting');
        break;
      case 'Decor':
        notifier.setCatalogMode(CatalogMode.all);
        notifier.updateCategoryFilter('Decor');
        break;
      case 'Plants':
        notifier.setCatalogMode(CatalogMode.all);
        notifier.updateCategoryFilter('Plants');
        break;
      case 'Favorites':
        notifier.setCatalogMode(CatalogMode.favorites);
        break;
      case 'Recently Used':
        notifier.setCatalogMode(CatalogMode.recent);
        break;
      default:
        break;
    }
  }

  Widget _buildAssetLibraryCard(
    dynamic asset,
    DesignerNotifier notifier,
    FurnitureListState furnitureState,
    dynamic materialState,
  ) {
    final String id = _getAssetId(asset);
    final String name = _getAssetName(asset);
    final String category = _getAssetCategory(asset);
    final bool isFavorite = _isAssetFavorite(asset, materialState);
    final bool isSelected = _selectedLibraryAssetId == id;

    Widget thumbnailWidget;

    if (asset is FurnitureAsset) {
      final String thumbnailUrl = asset.thumbnailUrl;
      final String resolvedUrl =
          (thumbnailUrl.contains('unsplash.com') || thumbnailUrl.isEmpty)
          ? '/uploads/furniture/thumbnails/${asset.id.replaceAll('model_', '')}.png'
          : thumbnailUrl;
      thumbnailWidget = resolvedUrl.isNotEmpty
          ? Image.network(
              resolvedUrl.startsWith('http')
                  ? resolvedUrl
                  : '${getBaseUrl()}$resolvedUrl',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  _buildFallbackThumbnail(asset.category),
            )
          : _buildFallbackThumbnail(asset.category);
    } else if (asset is MaterialModel) {
      final matColor = _parseHexColor(asset.baseColor);
      thumbnailWidget = Container(
        decoration: BoxDecoration(
          color: matColor,
          gradient: LinearGradient(
            colors: [matColor, matColor.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Icon(
            _getMaterialCategoryIcon(asset.category.name),
            size: 32,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      );
    } else if (asset is Map<String, dynamic> && asset['type'] != null) {
      thumbnailWidget = Icon(
        asset['type'] == 'door'
            ? Icons.door_front_door_outlined
            : Icons.window_outlined,
        size: 36,
        color: _kAccent,
      );
    } else if (asset is Map<String, dynamic> && asset['furniture'] != null) {
      thumbnailWidget = Icon(
        asset['icon'] as IconData? ?? Icons.dashboard_customize_outlined,
        size: 36,
        color: _kAccent,
      );
    } else {
      thumbnailWidget = const Icon(
        Icons.help_outline,
        size: 36,
        color: _kTextSecondary,
      );
    }

    // Only FurnitureAsset cards are draggable
    final isDraggableAsset = asset is FurnitureAsset;

    Widget cardChild = Container(
      decoration: BoxDecoration(
        color: _kSurfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? _kAccent : _kBorder,
          width: isSelected ? 2.0 : 1.0,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: _kAccent.withOpacity(0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: Container(
                color: const Color(0xFF1E293B),
                padding: const EdgeInsets.all(8),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(child: thumbnailWidget),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () {
                          _toggleAssetFavorite(asset);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.4),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isFavorite ? Icons.favorite : Icons.favorite_border,
                            size: 14,
                            color: isFavorite
                                ? Colors.redAccent
                                : _kTextSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _kTextSecondary,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    if (asset is FurnitureAsset)
                      Text(
                        '${asset.width.round()}×${asset.depth.round()}',
                        style: const TextStyle(
                          color: _kTextSecondary,
                          fontSize: 8.5,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (asset is! MaterialModel)
                  SizedBox(
                    width: double.infinity,
                    height: 22,
                    child: ElevatedButton(
                      onPressed: () {
                        _handleAssetPlacement(asset, notifier);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected ? _kAccent : _kBorder,
                        foregroundColor: isSelected
                            ? Colors.white
                            : _kTextPrimary,
                        elevation: 0,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text(
                        asset is Map<String, dynamic> &&
                                asset['furniture'] != null
                            ? 'Apply'
                            : 'Place',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    // Wrap non-material FurnitureAsset cards with LongPressDraggable
    if (isDraggableAsset) {
      final furnitureAsset = asset as FurnitureAsset;
      return LongPressDraggable<FurnitureAsset>(
        data: furnitureAsset,
        delay: const Duration(milliseconds: 180),
        feedback: AssetDragFeedback(
          assetName: furnitureAsset.name,
          category: furnitureAsset.category,
        ),
        onDragStarted: () {
          setState(() => _selectedLibraryAssetId = id);
          ref
              .read(furniturePlacementProvider.notifier)
              .startLibraryDrag(furnitureAsset, Offset.zero);
        },
        onDragEnd: (details) {
          // If not dropped on valid target, cancel
          if (!details.wasAccepted) {
            ref.read(furniturePlacementProvider.notifier).cancelLibraryDrag();
          }
        },
        childWhenDragging: Opacity(opacity: 0.4, child: cardChild),
        child: GestureDetector(
          onTap: () {
            setState(() => _selectedLibraryAssetId = id);
          },
          child: cardChild,
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedLibraryAssetId = id;
        });
        if (asset is MaterialModel) {
          _showMaterialOptionsSheet(asset);
        }
      },
      child: cardChild,
    );
  }

  Widget _buildSidebarContent(
    FurnitureListState furnitureState,
    DesignerNotifier notifier,
  ) {
    final materialState = ref.watch(materialProvider);
    final filteredAssets = _getFilteredAssets(furnitureState, materialState);

    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(right: BorderSide(color: _kBorder, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kBorder)),
            ),
            child: Row(
              children: [
                const Icon(Icons.grid_view_rounded, color: _kAccent, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'ASSET LIBRARY',
                  style: TextStyle(
                    color: _kTextPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _leftSidebarOpen = false),
                  child: const Icon(
                    Icons.close,
                    color: _kTextSecondary,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _assetLibrarySearchController,
              style: const TextStyle(color: _kTextPrimary, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search in ${_selectedCategoryTab.toLowerCase()}...',
                hintStyle: const TextStyle(
                  color: _kTextSecondary,
                  fontSize: 12,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 16,
                  color: _kTextSecondary,
                ),
                suffixIcon: _assetLibrarySearchController.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _assetLibrarySearchController.clear();
                          setState(() {});
                        },
                        child: const Icon(
                          Icons.clear,
                          size: 16,
                          color: _kTextSecondary,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: _kSurfaceElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kAccent, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onChanged: (val) {
                setState(() {});
                if ([
                  'Furniture',
                  'Lighting',
                  'Decor',
                  'Plants',
                  'Favorites',
                  'Recently Used',
                ].contains(_selectedCategoryTab)) {
                  ref.read(furnitureProvider.notifier).updateSearch(val);
                }
              },
            ),
          ),
          _buildCategoryTabs(),
          const Divider(color: _kBorder, height: 1),
          Expanded(
            child: () {
              final isBackendManaged = [
                'Furniture',
                'Lighting',
                'Decor',
                'Plants',
                'Favorites',
                'Recently Used',
              ].contains(_selectedCategoryTab);

              if (isBackendManaged) {
                if (furnitureState.isLoading && furnitureState.assets.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_kAccent),
                    ),
                  );
                }
                if (furnitureState.errorMessage != null &&
                    furnitureState.assets.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.redAccent,
                            size: 36,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Error: ${furnitureState.errorMessage}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () {
                              ref
                                  .read(furnitureProvider.notifier)
                                  .fetchAssets();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kAccent,
                              foregroundColor: Colors.black,
                            ),
                            child: const Text(
                              'Retry',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
              }

              if (filteredAssets.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 32,
                        color: _kTextSecondary.withOpacity(0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No assets found in ${_selectedCategoryTab}.',
                        style: const TextStyle(
                          color: _kTextSecondary,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (_selectedCategoryTab == 'Templates') {
                return ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  itemCount: filteredAssets.length,
                  itemBuilder: (context, index) {
                    final template = filteredAssets[index];
                    final isSelected =
                        _selectedLibraryAssetId == template['title'];
                    return Card(
                      color: _kSurfaceElevated,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isSelected ? _kAccent : _kBorder,
                          width: isSelected ? 2.0 : 0.8,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          setState(() {
                            _selectedLibraryAssetId = template['title'];
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    template['icon'] as IconData? ??
                                        Icons.dashboard_customize_outlined,
                                    color: _kAccent,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      template['title'] as String,
                                      style: const TextStyle(
                                        color: _kTextPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => _toggleAssetFavorite(template),
                                    child: Icon(
                                      _isAssetFavorite(template, materialState)
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      size: 14,
                                      color:
                                          _isAssetFavorite(
                                            template,
                                            materialState,
                                          )
                                          ? Colors.redAccent
                                          : _kTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                template['description'] as String,
                                style: const TextStyle(
                                  color: _kTextSecondary,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () =>
                                    _handleAssetPlacement(template, notifier),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isSelected
                                      ? _kAccent
                                      : _kSurface,
                                  foregroundColor: isSelected
                                      ? Colors.white
                                      : _kAccent,
                                  side: const BorderSide(color: _kBorder),
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(double.infinity, 24),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: const Text(
                                  'Apply Layout',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              }

              return GridView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.70,
                ),
                itemCount: filteredAssets.length,
                itemBuilder: (context, index) {
                  final asset = filteredAssets[index];
                  return _buildAssetLibraryCard(
                    asset,
                    notifier,
                    furnitureState,
                    materialState,
                  );
                },
              );
            }(),
          ),
        ],
      ),
    );
  }

  void _applyTemplateLayout(
    String title,
    List<Map<String, dynamic>> furnitureList,
    DesignerNotifier notifier,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Apply "$title"?'),
        content: const Text(
          'Are you sure you want to load this template layout? '
          'This will overwrite all currently placed furniture in this room.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.pop(context);
              notifier.clearAllFurniture();
              for (final f in furnitureList) {
                final assets = ref.read(furnitureProvider).assets;
                final asset = assets.firstWhere(
                  (a) => a.id == f['assetId'],
                  orElse: () => assets.isNotEmpty
                      ? assets.first
                      : FurnitureAsset(
                          id: f['assetId'] as String,
                          name: f['name'] as String,
                          category: 'Living Room',
                          style: 'Modern',
                          width: 100.0,
                          depth: 100.0,
                          height: 80.0,
                          clearance: 0.0,
                          assemblyClearance: 0.0,
                          glbUrl: '',
                          thumbnailUrl: '',
                          createdAt: DateTime.now(),
                        ),
                );
                notifier.addFurniture(
                  asset,
                  f['x'] as double,
                  f['z'] as double,
                );
              }
              SnackbarManager.showSuccess(
                context,
                'Applied layout template: $title',
              );
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  // ─── 5. Assets Section Content ─────────────────────────────────────────────

  // ═══════════════════════════════════════════════════════════════════════════
  //  RIGHT PROPERTIES PANEL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRightPanel(
    DesignerLayoutState layout,
    DesignerNotifier notifier,
    Opening? selectedOp,
    PlacedFurniture? selectedFurniture,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      width: _rightPanelOpen ? 280 : 0,
      child: _rightPanelOpen
          ? _buildPropertiesPanel(
              layout,
              notifier,
              selectedOp,
              selectedFurniture,
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildRightPanelTabsHeader() {
    return Container(
      height: 40,
      color: _kSurfaceElevated,
      child: Row(
        children: [
          Expanded(
            child: _buildRightTabButton(
              tab: 'properties',
              icon: Icons.tune,
              tooltip: 'Inspector',
            ),
          ),
          Expanded(
            child: _buildRightTabButton(
              tab: 'ai',
              icon: Icons.auto_awesome,
              tooltip: 'AI Layout Assistant',
            ),
          ),
          Expanded(
            child: _buildRightTabButton(
              tab: 'validation',
              icon: Icons.fact_check_outlined,
              tooltip: 'Design Rules',
            ),
          ),
          Container(width: 1, height: 24, color: _kBorder),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: _kTextSecondary),
            onPressed: () => setState(() => _rightPanelOpen = false),
            tooltip: 'Collapse Panel',
          ),
        ],
      ),
    );
  }

  Widget _buildRightTabButton({
    required String tab,
    required IconData icon,
    required String tooltip,
  }) {
    final isActive = _activeRightTab == tab;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          setState(() {
            _activeRightTab = tab;
          });
        },
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? _kAccent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Icon(
            icon,
            color: isActive ? _kAccent : _kTextSecondary,
            size: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildPropertiesPanel(
    DesignerLayoutState layout,
    DesignerNotifier notifier,
    Opening? selectedOp,
    PlacedFurniture? selectedFurniture,
  ) {
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(left: BorderSide(color: _kBorder, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Right panel tabs header
          _buildRightPanelTabsHeader(),

          // Divider
          Container(height: 1, color: _kBorder),

          // Scrollable content body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: _buildRightPanelContent(
                layout,
                notifier,
                selectedOp,
                selectedFurniture,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanelContent(
    DesignerLayoutState layout,
    DesignerNotifier notifier,
    Opening? selectedOp,
    PlacedFurniture? selectedFurniture,
  ) {
    switch (_activeRightTab) {
      case 'ai':
        return _buildInlineAiPanel();
      case 'validation':
        return _buildInlineValidationPanel();
      case 'properties':
      default:
        // ── Wall selected ───────────────────────────────────────────────────────
        if (layout.selectedWallIndex != null) {
          final wall = layout.walls[layout.selectedWallIndex!];
          final length = (wall.end - wall.start).distance;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _propHeader(
                icon: Icons.border_color,
                title: 'Wall #${layout.selectedWallIndex}',
              ),
              _propDivider(),
              _propInfoRow('Length', '${length.round()} cm'),
              const SizedBox(height: 12),
              _propLabel('Thickness: ${wall.thickness.round()} cm'),
              _propSlider(
                value: wall.thickness,
                min: 5,
                max: 50,
                onChangeStart: (_) => notifier.pushUndo(),
                onChanged: notifier.updateSelectedWallThickness,
              ),
              const SizedBox(height: 20),
              _deleteButton('Delete Wall', () {
                notifier.deleteSelected();
                SnackbarManager.showSuccess(context, 'Wall deleted.');
              }),
            ],
          );
        }

        // ── Opening selected ────────────────────────────────────────────────────
        if (selectedOp != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _propHeader(
                icon: selectedOp.type == 'door'
                    ? Icons.door_front_door
                    : Icons.window,
                title:
                    '${selectedOp.type == 'door' ? 'Door' : 'Window'} Properties',
              ),
              _propDivider(),
              _propLabel('Width: ${selectedOp.width.round()} cm'),
              _propSlider(
                value: selectedOp.width,
                min: 40,
                max: 200,
                onChangeStart: (_) => notifier.pushUndo(),
                onChanged: (val) =>
                    notifier.resizeSelectedOpening(val - selectedOp.width),
              ),
              const SizedBox(height: 12),
              _propLabel('Rotation: ${(selectedOp.angle * 180 / pi).round()}°'),
              _propSlider(
                value: selectedOp.angle,
                min: -pi,
                max: pi,
                onChangeStart: (_) => notifier.pushUndo(),
                onChanged: (val) =>
                    notifier.rotateSelectedOpening(val - selectedOp.angle),
              ),
              const SizedBox(height: 20),
              _deleteButton('Delete Opening', () {
                notifier.deleteSelected();
                SnackbarManager.showSuccess(context, 'Opening deleted.');
              }),
            ],
          );
        }

        // ── Furniture selected ──────────────────────────────────────────────────
        if (selectedFurniture != null) {
          return FurniturePropertiesPanel(
            furniture: selectedFurniture,
            notifier: notifier,
            onDelete: () {
              notifier.deleteSelected();
              SnackbarManager.showSuccess(context, 'Furniture removed.');
            },
          );
        }

        // ── Light selected ──────────────────────────────────────────────────────
        final lightingState = ref.watch(lightingProvider);
        if (lightingState.selectedLightId != null) {
          try {
            final selectedLight = lightingState.lights.firstWhere(
              (l) => l.id == lightingState.selectedLightId,
            );
            return LightPropertiesPanel(
              light: selectedLight,
              notifier: ref.read(lightingProvider.notifier),
              onDelete: () {
                ref
                    .read(lightingProvider.notifier)
                    .deleteLight(selectedLight.id);
                SnackbarManager.showSuccess(context, 'Light removed.');
              },
            );
          } catch (_) {}
        }

        // ── Room materials / surface editing when no object is selected ─────────────────
        return RoomMaterialsPanel(notifier: notifier);
    }
  }

  // ─── Property panel helpers ───────────────────────────────────────────────

  Widget _propHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, color: _kAccent, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _kTextPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _propDivider() => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: 12),
    color: _kBorder,
  );

  Widget _propLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: _kTextPrimary,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
  );

  Widget _propInfoRow(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 12)),
      Text(
        value,
        style: const TextStyle(
          color: _kAccent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );

  Widget _propSlider({
    required double value,
    required double min,
    required double max,
    ValueChanged<double>? onChangeStart,
    required ValueChanged<double> onChanged,
  }) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
        activeTrackColor: _kAccent,
        inactiveTrackColor: _kBorder,
        thumbColor: _kAccent,
        overlayColor: _kAccent.withOpacity(0.15),
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChangeStart: onChangeStart,
        onChanged: onChanged,
      ),
    );
  }

  Widget _deleteButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.delete_outline, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3D1515),
          foregroundColor: Colors.redAccent,
          elevation: 0,
          side: const BorderSide(color: Color(0xFF5C2020), width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onPressed: onPressed,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BOTTOM STATUS BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _statusItem({
    required IconData icon,
    required String text,
    Color color = _kTextSecondary,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _statusSep() => Container(
    width: 1,
    height: 12,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    color: _kBorder,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  //  CANVAS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLeftEditorControls(DesignerNotifier notifier) {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_leftSidebarOpen) ...[
            IconButton(
              icon: const Icon(Icons.menu, size: 16, color: _kTextPrimary),
              tooltip: 'Open Sidebar',
              onPressed: () => setState(() => _leftSidebarOpen = true),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
            Container(width: 1, height: 18, color: _kBorder),
          ],
          IconButton(
            icon: const Icon(
              Icons.undo_rounded,
              size: 16,
              color: _kTextPrimary,
            ),
            tooltip: 'Undo (Ctrl+Z)',
            onPressed: notifier.undo,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            icon: const Icon(
              Icons.redo_rounded,
              size: 16,
              color: _kTextPrimary,
            ),
            tooltip: 'Redo (Ctrl+Y)',
            onPressed: notifier.redo,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
          Container(width: 1, height: 18, color: _kBorder),
          IconButton(
            icon: const Icon(
              Icons.center_focus_strong_outlined,
              size: 16,
              color: _kTextPrimary,
            ),
            tooltip: 'Reset View',
            onPressed: _centerView,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildMiddleEditorControls() {
    final viewMode = ref.watch(viewModeProvider);
    return Container(
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _editorModeSegment(
            active: !_is3DMode,
            label: '2D View',
            icon: Icons.map_outlined,
            onTap: _is3DMode ? () => setState(() => _is3DMode = false) : () {},
          ),
          _editorModeSegment(
            active: _is3DMode && viewMode != ViewMode.free,
            label: '3D View',
            icon: Icons.threed_rotation,
            onTap: () {
              setState(() => _is3DMode = true);
              ref.read(viewModeProvider.notifier).setMode(ViewMode.orbit);
            },
          ),
          _editorModeSegment(
            active: _is3DMode && viewMode == ViewMode.free,
            label: 'Walkthrough',
            icon: Icons.directions_walk_rounded,
            onTap: () {
              setState(() => _is3DMode = true);
              ref.read(viewModeProvider.notifier).setMode(ViewMode.free);
            },
          ),
        ],
      ),
    );
  }

  Widget _editorModeSegment({
    required bool active,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: active ? _kAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(
              icon,
              size: 13,
              color: active ? Colors.white : _kTextSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? Colors.white : _kTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomCenterEditorControls(
    DesignerLayoutState layout,
    DesignerNotifier notifier,
  ) {
    final hasSelection =
        layout.selectedFurnitureId != null ||
        layout.selectedWallIndex != null ||
        layout.selectedOpeningId != null;

    if (!hasSelection) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _actionIconBtn(
            icon: Icons.near_me_outlined,
            label: 'Select',
            active: layout.transformMode == TransformMode.select,
            onTap: () {
              notifier.setTransformMode(TransformMode.select);
            },
          ),
          _actionIconBtn(
            icon: Icons.open_with_rounded,
            label: 'Move',
            active: layout.transformMode == TransformMode.translate,
            onTap: () {
              notifier.setTransformMode(TransformMode.translate);
              SnackbarManager.showInfo(
                context,
                'Drag the gizmo handles in the viewport to move',
              );
            },
          ),
          _actionIconBtn(
            icon: Icons.autorenew_rounded,
            label: 'Rotate',
            active: layout.transformMode == TransformMode.rotate,
            onTap: () {
              notifier.setTransformMode(TransformMode.rotate);
              SnackbarManager.showInfo(
                context,
                'Drag the rotation rings in the viewport to rotate',
              );
            },
          ),
          _actionIconBtn(
            icon: Icons.zoom_out_map_rounded,
            label: 'Scale',
            active: layout.transformMode == TransformMode.scale,
            onTap: () {
              notifier.setTransformMode(TransformMode.scale);
              SnackbarManager.showInfo(
                context,
                'Drag the scale handles in the viewport or use the side panel to scale',
              );
            },
          ),
          Container(width: 1, height: 18, color: _kBorder),
          _actionIconBtn(
            icon: Icons.rotate_left_rounded,
            label: 'Rot -45°',
            active: false,
            onTap: () {
              final id = layout.selectedFurnitureId;
              if (id != null) {
                ref
                    .read(furniturePlacementProvider.notifier)
                    .setGhostRotation(0);
                notifier.rotateFurnitureBy(id, -3.14159 / 4);
              }
            },
          ),
          _actionIconBtn(
            icon: Icons.rotate_right_rounded,
            label: 'Rot +45°',
            active: false,
            onTap: () {
              final id = layout.selectedFurnitureId;
              if (id != null) {
                notifier.rotateFurnitureBy(id, 3.14159 / 4);
              }
            },
          ),
          Container(width: 1, height: 18, color: _kBorder),
          _actionIconBtn(
            icon: Icons.copy_rounded,
            label: 'Duplicate',
            active: false,
            onTap: () {
              notifier.duplicateSelectedFurniture();
              SnackbarManager.showSuccess(context, 'Furniture duplicated!');
            },
          ),
          _actionIconBtn(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            active: false,
            color: Colors.redAccent,
            onTap: () {
              notifier.deleteSelected();
              SnackbarManager.showSuccess(context, 'Element deleted.');
            },
          ),
        ],
      ),
    );
  }

  Widget _actionIconBtn({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    Color? color,
  }) {
    final textColor = color ?? (active ? _kAccent : _kTextSecondary);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? _kAccent : textColor),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? _kAccent : _kTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomLeftScoreOverlay(DesignerLayoutState layout) {
    final scoreState = ref.watch(designScoreProvider);
    if (scoreState.isLoading || scoreState.scores == null) {
      return const SizedBox.shrink();
    }

    final validationState = ref.watch(validationProvider);
    final hasErrors = validationState.errors.isNotEmpty;
    final hasWarnings = validationState.warnings.isNotEmpty;

    final bool hasWalkwayError = validationState.errors.any((e) =>
        e.ruleId == 'RULE_WALKWAY' ||
        e.ruleName.toLowerCase().contains('walkway'));
    final bool hasCollision = validationState.errors.any((e) =>
        e.ruleId == 'RULE_COLLISION' ||
        (e.ruleName.toLowerCase().contains('collision') && !e.ruleName.toLowerCase().contains('wall')));
    final bool hasWallCollision = validationState.errors.any((e) =>
        e.ruleId == 'RULE_WALL' ||
        e.ruleName.toLowerCase().contains('wall'));
    final bool hasDoorError = validationState.errors.any((e) =>
        e.ruleId == 'RULE_DOOR' ||
        e.ruleName.toLowerCase().contains('door'));

    final score = scoreState.scores!.overallScore;
    final baseColor = score >= 80
        ? Colors.greenAccent
        : (score >= 50 ? Colors.orangeAccent : Colors.redAccent);

    final Color statusColor = hasErrors ? AppTheme.error : baseColor;

    String title;
    String subtitle;

    if (hasWalkwayError) {
      title = 'Walkway Blocked';
      subtitle = 'Circulation paths need widening.';
    } else if (hasCollision) {
      title = 'Collision Detected';
      subtitle = 'Furniture items overlap.';
    } else if (hasWallCollision) {
      title = 'Wall Collision';
      subtitle = 'Reposition inside room walls.';
    } else if (hasDoorError) {
      title = 'Doorway Blocked';
      subtitle = 'Door clearance zone obstructed.';
    } else if (hasErrors) {
      title = 'Action Required';
      subtitle = 'Resolve spatial errors.';
    } else if (hasWarnings) {
      title = score >= 80 ? 'Good Layout' : (score >= 50 ? 'Good Design' : 'Needs Improvement');
      subtitle = 'Check spatial warnings in details.';
    } else {
      title = score >= 80 ? 'Great Design!' : (score >= 50 ? 'Good Design' : 'Needs Improvement');
      subtitle = score >= 80 ? 'Well balanced layout.' : 'Keep going, you\'re doing great.';
    }

    return Container(
      width: 180,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Design Score',
            style: TextStyle(
              color: _kTextSecondary,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Stack(
                  children: [
                    Center(
                      child: CircularProgressIndicator(
                        value: score / 100,
                        backgroundColor: _kBorder,
                        color: statusColor,
                        strokeWidth: 3,
                      ),
                    ),
                    Center(
                      child: Text(
                        '${score.round()}',
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _kTextSecondary, fontSize: 8),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 20,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: const BorderSide(color: _kBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              onPressed: () {
                if (scoreState.scores != null) {
                  _showScoreBreakdownDialog(scoreState.scores!);
                }
              },
              child: const Text(
                'View Details',
                style: TextStyle(
                  fontSize: 8.5,
                  color: _kTextPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelSelectors() {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _levelBtn('2', false),
          const SizedBox(height: 4),
          _levelBtn('1', true),
          const SizedBox(height: 4),
          _levelBtn('G', false),
        ],
      ),
    );
  }

  Widget _levelBtn(String label, bool active) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: active ? _kAccent : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: () {},
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : _kTextSecondary,
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas(
    DesignerLayoutState layout,
    DesignerNotifier notifier,
    FurnitureListState furnitureState,
  ) {
    final placementState = ref.watch(furniturePlacementProvider);
    final placementNotifier = ref.read(furniturePlacementProvider.notifier);

    PlacedFurniture? selectedFurniture;
    if (layout.selectedFurnitureId != null) {
      try {
        selectedFurniture = layout.furniture.firstWhere(
          (f) => f.id == layout.selectedFurnitureId,
        );
      } catch (_) {}
    }

    return Expanded(
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Container(
          key: _canvasAreaKey,
          color: _is3DMode ? _kCanvas3D : _kCanvas2D,
          child: Stack(
            children: [
              // Viewport rendering
              if (_is3DMode)
                Positioned.fill(
                  child: DragTarget<FurnitureAsset>(
                    onWillAcceptWithDetails: (_) => true,
                    onAcceptWithDetails: (details) {
                      final renderBox = _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
                      double dropX = 300.0;
                      double dropZ = 225.0;
                      if (renderBox != null) {
                        final localPos = renderBox.globalToLocal(details.offset);
                        final widthNorm = (localPos.dx / renderBox.size.width).clamp(0.15, 0.85);
                        final heightNorm = (localPos.dy / renderBox.size.height).clamp(0.15, 0.85);
                        double roomW = 600.0;
                        double roomL = 450.0;
                        if (layout.walls.isNotEmpty) {
                          double maxX = layout.walls.map((w) => max(w.start.dx, w.end.dx)).reduce(max);
                          double maxY = layout.walls.map((w) => max(w.start.dy, w.end.dy)).reduce(max);
                          if (maxX > 100) roomW = maxX;
                          if (maxY > 100) roomL = maxY;
                        }
                        dropX = widthNorm * roomW;
                        dropZ = heightNorm * roomL;
                      }
                      notifier.addFurniture(details.data, dropX, dropZ);
                      _addRecentlyUsed(details.data);
                      SnackbarManager.showSuccess(
                        context,
                        'Placed ${details.data.name} in 3D scene!',
                      );
                    },
                    builder: (context, candidateData, rejectedData) {
                      return ThreeDDesignerView(
                        roomId: widget.roomId,
                        furnitureAssets: furnitureState.assets,
                        simplified: !_isWalkthroughMode,
                        isWalkthroughMode: _isWalkthroughMode,
                      );
                    },
                  ),
                )
              else
                Positioned.fill(
                  child: DragTarget<FurnitureAsset>(
                    onWillAcceptWithDetails: (details) {
                      // Always accept for visual feedback
                      return true;
                    },
                    onMove: (details) {
                      // Convert screen position to canvas/world position
                      final renderBox = _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
                      if (renderBox == null) return;
                      final localPos = renderBox.globalToLocal(details.offset);
                      final canvasPos = _transformationController.toScene(
                        localPos,
                      );
                      placementNotifier.updateLibraryDrag(
                        localPos,
                        canvasPos,
                        layout,
                      );
                    },
                    onAcceptWithDetails: (details) {
                      final renderBox = _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
                      if (renderBox == null) {
                        placementNotifier.cancelLibraryDrag();
                        return;
                      }
                      final localPos = renderBox.globalToLocal(details.offset);
                      final canvasPos = _transformationController.toScene(
                        localPos,
                      );
                      placementNotifier.updateLibraryDrag(
                        localPos,
                        canvasPos,
                        layout,
                      );
                      final id = placementNotifier.commitLibraryDrop(notifier);
                      if (id != null) {
                        _addRecentlyUsed(details.data);
                        SnackbarManager.showSuccess(
                          context,
                          'Placed ${details.data.name}!',
                        );
                      } else {
                        notifier.addFurniture(details.data, canvasPos.dx, canvasPos.dy);
                        _addRecentlyUsed(details.data);
                        SnackbarManager.showSuccess(context, 'Placed ${details.data.name}!');
                      }
                    },
                  onLeave: (_) {
                    placementNotifier.cancelLibraryDrag();
                  },
                  builder: (context, candidateData, rejectedData) {
                    return ClipRect(
                      child: InteractiveViewer(
                        transformationController: _transformationController,
                        boundaryMargin: const EdgeInsets.all(2000.0),
                        minScale: 0.1,
                        maxScale: 4.0,
                        panEnabled:
                            layout.tool != DesignerTool.drawWall &&
                            !_isDragging &&
                            !placementState.isAnyDragActive,
                        scaleEnabled:
                            layout.tool != DesignerTool.drawWall &&
                            !_isDragging &&
                            !placementState.isAnyDragActive,
                        child: Listener(
                          onPointerHover: (event) {
                            final canvasPos = _transformationController.toScene(
                              event.localPosition,
                            );
                            if (mounted) {
                              setState(() => _mouseCanvasPos = canvasPos);
                            }
                          },
                          onPointerMove: (event) {
                            final canvasPos = _transformationController.toScene(
                              event.localPosition,
                            );
                            if (mounted) {
                              setState(() => _mouseCanvasPos = canvasPos);
                            }
                          },
                          onPointerSignal: (event) {
                            final canvasPos = _transformationController.toScene(
                              event.localPosition,
                            );
                            if (mounted) {
                              setState(() => _mouseCanvasPos = canvasPos);
                            }
                          },
                          child: GestureDetector(
                            onTapDown: (d) =>
                                _handleTapDown(d, layout, notifier),
                            onPanStart: (d) =>
                                _handlePanStart(d, layout, notifier),
                            onPanUpdate: (d) =>
                                _handlePanUpdate(d, layout, notifier),
                            onPanEnd: (d) => _handlePanEnd(d, layout, notifier),
                            child: CustomPaint(
                              size: const Size(4000, 4000),
                              painter: DesignerPainter(
                                layout: layout,
                                showGrid: _showGrid,
                                showMeasurements: _measurementsEnabled,
                                showFurnitureLabels: _showFurnitureLabels,
                                showDoors: _showDoors,
                                showWindows: _showWindows,
                                validationState: ref.watch(validationProvider),
                              ),
                              foregroundPainter:
                                  _drawStart != null && _dragCurrent != null
                                  ? _TempWallPainter(
                                      start: _drawStart!,
                                      end: _dragCurrent!,
                                    )
                                  : placementState.isAnyDragActive &&
                                        placementState.ghostWorldPos != null
                                  ? PlacementGhostPainter(
                                      placement: placementState,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // ── Drag-over overlay highlight (2D only) ─────────────────────
            if (!_is3DMode && placementState.isDraggingFromLibrary)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: placementState.validation.isValid
                            ? const Color(0xFF0F766E).withOpacity(0.4)
                            : const Color(0xFFEF4444).withOpacity(0.4),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),

            // ── Ghost drop hint label ─────────────────────────────────────
            if (!_is3DMode &&
                placementState.isDraggingFromLibrary &&
                placementState.ghostWorldPos == null)
              const Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.file_download_outlined,
                          size: 36,
                          color: Color(0xFF0F766E),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Drop to place furniture',
                          style: TextStyle(
                            color: Color(0xFF0F766E),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Collision warning banner ──────────────────────────────────
            if (!_is3DMode &&
                placementState.isAnyDragActive &&
                !placementState.validation.isValid)
              Positioned(
                top: 56,
                left: 0,
                right: 0,
                child: Center(
                  child: IgnorePointer(
                    child: CollisionWarningBanner(
                      message:
                          placementState.validation.message ??
                          'Invalid placement',
                    ),
                  ),
                ),
              ),

            // ── Real-time Metrics Card (top-left, 2D only) ──────────────
            if (!_is3DMode)
              Positioned(top: 56, left: 12, child: _buildRealTimeMetricsCard()),

            // ── Snap mode chip (top-right, 2D only) ─────────────────────
            if (!_is3DMode)
              Positioned(
                top: 56,
                right: 12,
                child: SnapModeChip(
                  mode: placementState.snapMode,
                  onTap: () => placementNotifier.cycleSnapMode(),
                ),
              ),

            // ── Floating Controls — bottom-right corner ──────────────────
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingControls(
                is3DMode: _is3DMode,
                // 2D callbacks
                onZoomIn: () => _zoom(1.2),
                onZoomOut: () => _zoom(1 / 1.2),
                onResetView: _centerView,
                onFocusSelection2D: _focusSelection2D,
                // Shared
                onToggleFullscreen: _toggleFullscreen,
                isFullscreen: _isFullscreen,
              ),
            ),

            // ── Developer Diagnostics Panel ─────────────────────────────
            DeveloperDiagnosticsPanel(
              isVisible: _showDiagnostics,
              onClose: () => setState(() => _showDiagnostics = false),
            ),

            // ── Level selection stack ────────────────────────────────────
            Positioned(
              bottom:
                  232, // Floating neatly on top-right above FloatingControls
              right: 16,
              child: _buildLevelSelectors(),
            ),

            // ── Floating editor controls: Top-Left (Undo, Redo, Reset) - Only when embedded/walkthrough ────
            if (widget.isEmbedded || _isWalkthroughMode)
              Positioned(
                top: 12,
                left: 12,
                child: _buildLeftEditorControls(notifier),
              ),

            // ── Floating editor controls: Top-Middle (2D/3D/Walkthrough) - Only when embedded/walkthrough ─
            if (widget.isEmbedded || _isWalkthroughMode)
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(child: _buildMiddleEditorControls()),
              ),

            // ── Bottom Left Design Score overlay ──────────────────────────
            Positioned(
              bottom: 16,
              left: 12,
              child: _buildBottomLeftScoreOverlay(layout),
            ),

            // ── Floating editor controls: Bottom-Middle (Select/Move/Rotate/Scale/Duplicate/Delete) ──
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: _buildBottomCenterEditorControls(layout, notifier),
              ),
            ),

            // Walkthrough hint — top-left corner (3D only when walkthrough active)
            if (_is3DMode && _isWalkthroughMode)
              Positioned(top: 12, left: 12, child: _buildWalkthroughHint()),

            if (_isWalkthroughMode)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Card(
                    color: const Color(0xE60F172A),
                    elevation: 6,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                      side: const BorderSide(
                        color: Color(0xFF334155),
                        width: 1.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.directions_run,
                            color: Color(0xFF0D9488),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Walkthrough Mode',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            width: 1,
                            height: 20,
                            color: const Color(0xFF334155),
                          ),
                          const SizedBox(width: 8),

                          // Reset Position Button
                          TextButton.icon(
                            icon: const Icon(
                              Icons.restart_alt,
                              color: Colors.white,
                              size: 16,
                            ),
                            label: const Text(
                              'Reset Position',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                            onPressed: () {
                              ref
                                  .read(cameraProvider.notifier)
                                  .resetToWalkthrough(layout);
                              SnackbarManager.showSuccess(
                                context,
                                'Position reset.',
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 1,
                            height: 20,
                            color: const Color(0xFF334155),
                          ),
                          const SizedBox(width: 8),

                          // Exit Walkthrough Button
                          ElevatedButton.icon(
                            icon: const Icon(Icons.exit_to_app, size: 14),
                            label: const Text(
                              'Exit Walkthrough',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _isWalkthroughMode = false;
                                _leftSidebarOpen = true;
                                _rightPanelOpen = true;
                              });
                              ref
                                  .read(viewModeProvider.notifier)
                                  .setMode(ViewMode.orbit);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // ── Mobile Bottom Sheet (mobile layout only) ────────────────
            if (selectedFurniture != null &&
                MediaQuery.of(context).size.width < 750)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: MobileFurnitureSheet(
                  furniture: selectedFurniture,
                  notifier: notifier,
                  activeTransformTool: _activeTransformTool,
                  onChangeTransformTool: (tool) =>
                      setState(() => _activeTransformTool = tool),
                  onOpenPrecisePlacement: () => setState(() {
                    _rightPanelOpen = true;
                    _activeRightTab = 'properties';
                  }),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildWalkthroughHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, color: Colors.amber, size: 12),
          SizedBox(width: 6),
          Text(
            'Walkthrough: Use W/A/S/D or Arrow keys to walk',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  UNCHANGED HELPER WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(designerProvider);
    final notifier = ref.read(designerProvider.notifier);
    final furnitureState = ref.watch(furnitureProvider);
    final scoreState = ref.watch(designScoreProvider);
    final viewMode = ref.watch(viewModeProvider);

    // Auto-validate and auto-save on state change
    ref.listen<DesignerLayoutState>(designerProvider, (previous, next) {
      if (previous != null) {
        ref.read(validationProvider.notifier).scheduleValidation(widget.roomId);

        // Auto-save logic on actual changes
        if (!_isInitialLoad &&
            (previous.walls != next.walls ||
                previous.openings != next.openings ||
                previous.furniture != next.furniture ||
                previous.floorMaterialColor != next.floorMaterialColor ||
                previous.floorMaterialType != next.floorMaterialType ||
                previous.wallMaterialColor != next.wallMaterialColor ||
                previous.wallMaterialType != next.wallMaterialType)) {
          _triggerAutoSave();
        }

        // Automatic centering / focusing when selection changes
        if (next.selectedFurnitureId != previous.selectedFurnitureId &&
            next.selectedFurnitureId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focusSelection2D();
          });
        }
        if (next.selectedWallIndex != previous.selectedWallIndex &&
            next.selectedWallIndex != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focusSelection2D();
          });
        }
        if (next.selectedOpeningId != previous.selectedOpeningId &&
            next.selectedOpeningId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focusSelection2D();
          });
        }
      }
    });

    Opening? selectedOp;
    if (layout.selectedOpeningId != null) {
      try {
        selectedOp = layout.openings.firstWhere(
          (o) => o.id == layout.selectedOpeningId,
        );
      } catch (_) {}
    }

    PlacedFurniture? selectedFurniture;
    if (layout.selectedFurnitureId != null) {
      try {
        selectedFurniture = layout.furniture.firstWhere(
          (f) => f.id == layout.selectedFurnitureId,
        );
      } catch (_) {}
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _kSurface,
      appBar: widget.isEmbedded || _isWalkthroughMode
          ? null
          : DesignerToolbar(
              roomId: widget.roomId,
              isEmbedded: widget.isEmbedded,
              is3DMode: _is3DMode,
              showGrid: _showGrid,
              leftSidebarOpen: _leftSidebarOpen,
              viewMode: viewMode,
              layout: layout,
              notifier: notifier,
              isWalkthroughMode: _isWalkthroughMode,
              onToggleWalkthrough: () {
                setState(() {
                  _isWalkthroughMode = !_isWalkthroughMode;
                  if (_isWalkthroughMode) {
                    _is3DMode = true;
                    _leftSidebarOpen = false;
                    _rightPanelOpen = false;
                    ref.read(viewModeProvider.notifier).setMode(ViewMode.free);
                    ref
                        .read(cameraProvider.notifier)
                        .resetToWalkthrough(layout);
                  } else {
                    _leftSidebarOpen = true;
                    _rightPanelOpen = true;
                    ref.read(viewModeProvider.notifier).setMode(ViewMode.orbit);
                  }
                });
              },
              onSave: () => _handleSave(notifier),
              onToggle3D: () => setState(() => _is3DMode = !_is3DMode),
              onToggleGrid: () => setState(() => _showGrid = !_showGrid),
              onToggleLeftSidebar: () =>
                  setState(() => _leftSidebarOpen = !_leftSidebarOpen),
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              },
              isFullscreen: _isFullscreen,
              onToggleFullscreen: _toggleFullscreen,
              measurementsEnabled: _measurementsEnabled,
              onToggleMeasurements: () =>
                  setState(() => _measurementsEnabled = !_measurementsEnabled),
              showFurnitureLabels: _showFurnitureLabels,
              onToggleFurnitureLabels: () =>
                  setState(() => _showFurnitureLabels = !_showFurnitureLabels),
              showDoors: _showDoors,
              onToggleDoors: () => setState(() => _showDoors = !_showDoors),
              showWindows: _showWindows,
              onToggleWindows: () =>
                  setState(() => _showWindows = !_showWindows),
              showDiagnostics: _showDiagnostics,
              onToggleDiagnostics: () =>
                  setState(() => _showDiagnostics = !_showDiagnostics),
              activeTransformTool: _activeTransformTool,
              onChangeTransformTool: (tool) =>
                  setState(() => _activeTransformTool = tool),
              activeRightTab: _activeRightTab,
              rightPanelOpen: _rightPanelOpen,
              onToggleRightPanel: (tab, open) {
                setState(() {
                  _activeRightTab = tab;
                  _rightPanelOpen = open;
                });
                if (tab == 'validation') {
                  ref
                      .read(validationProvider.notifier)
                      .loadValidationResults(widget.roomId);
                } else if (tab == 'ai') {
                  ref
                      .read(designScoreProvider.notifier)
                      .fetchScores(widget.roomId);
                  ref
                      .read(recommendationProvider.notifier)
                      .fetchRecommendations(widget.roomId);
                }
              },
            ),
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final primaryFocus = FocusManager.instance.primaryFocus;
            if (primaryFocus != null &&
                primaryFocus.context?.widget is EditableText) {
              return KeyEventResult.ignored;
            }

            final isShift = HardwareKeyboard.instance.isShiftPressed;
            final isCtrl = HardwareKeyboard.instance.isControlPressed;
            final step = isShift ? 25.0 : (isCtrl ? 1.0 : 5.0);
            final key = event.logicalKey;

            if (key == LogicalKeyboardKey.arrowUp) {
              notifier.moveSelectedFurnitureByOffset(0, -step);
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.arrowDown) {
              notifier.moveSelectedFurnitureByOffset(0, step);
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.arrowLeft) {
              notifier.moveSelectedFurnitureByOffset(-step, 0);
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.arrowRight) {
              notifier.moveSelectedFurnitureByOffset(step, 0);
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.delete ||
                key == LogicalKeyboardKey.backspace) {
              if (layout.selectedFurnitureId != null ||
                  layout.selectedWallIndex != null ||
                  layout.selectedOpeningId != null) {
                notifier.deleteSelected();
                SnackbarManager.showSuccess(
                  context,
                  'Selected element removed.',
                );
                return KeyEventResult.handled;
              }
            } else if (isCtrl && key == LogicalKeyboardKey.keyZ) {
              notifier.undo();
              return KeyEventResult.handled;
            } else if (isCtrl && key == LogicalKeyboardKey.keyY) {
              notifier.redo();
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.escape) {
              notifier.clearSelection();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          children: [
            // ── Main workspace row ─────────────────────────────────────────────
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Left collapsible Sidebar
                  _buildLeftSidebar(furnitureState, notifier),

                  // 2. Central design Canvas
                  _buildCanvas(layout, notifier, furnitureState),

                  // 3. Right collapsible properties panel
                  _buildRightPanel(
                    layout,
                    notifier,
                    selectedOp,
                    selectedFurniture,
                  ),
                ],
              ),
            ),

            // ── Bottom status bar ──────────────────────────────────────────────
            DesignerStatusBar(
              roomId: widget.roomId,
              layout: layout,
              scoreState: scoreState,
              validationState: ref.watch(validationProvider),
              zoomLevel: _zoomLevel,
              mouseCanvasPos: _mouseCanvasPos,
              onScoreTap: scoreState.scores != null
                  ? () => _showScoreBreakdownDialog(scoreState.scores!)
                  : null,
              is3DMode: _is3DMode,
              showGrid: _showGrid,
              autoSaveStatus: _autoSaveStatus,
              translation2D: Offset(
                _transformationController.value.storage[12],
                _transformationController.value.storage[13],
              ),
            ),
          ],
        ),
      ),
    );
  }

  RecommendationCategory _getRecommendationCategory(Recommendation card) {
    final type = card.type.toLowerCase();
    final rule = card.ruleTriggered.toLowerCase();
    final title = card.title.toLowerCase();

    if (type == 'validation' ||
        rule.contains('clearance') && rule.contains('door') ||
        rule.contains('safety')) {
      return RecommendationCategory.designIssues;
    } else if (type == 'lighting' ||
        rule.contains('lighting') ||
        rule.contains('window')) {
      return RecommendationCategory.lightingSuggestions;
    } else if (type == 'ai' ||
        rule.contains('missing') ||
        title.contains('add')) {
      return RecommendationCategory.furnitureRecommendations;
    } else if (rule.contains('material') ||
        rule.contains('color') ||
        title.contains('material')) {
      return RecommendationCategory.colorHarmony;
    } else if (rule.contains('balance') ||
        rule.contains('space') ||
        rule.contains('utilization') ||
        title.contains('balance')) {
      return RecommendationCategory.spaceUtilization;
    } else {
      return RecommendationCategory.suggestions;
    }
  }

  Widget _buildInlineAiPanel() {
    final scoreState = ref.watch(designScoreProvider);
    final recState = ref.watch(recommendationProvider);
    final optState = ref.watch(optimizationProvider);

    // Filter cards
    final allCards = recState.recommendations;
    final ignoredCards = allCards
        .where(
          (c) =>
              recState.ignoredIds.contains(c.id) ||
              recState.ignoredTitles.contains(c.title),
        )
        .toList();
    final savedCards = allCards
        .where(
          (c) =>
              !ignoredCards.contains(c) &&
              (recState.savedIds.contains(c.id) ||
                  recState.savedTitles.contains(c.title)),
        )
        .toList();
    final visibleCards = allCards
        .where((c) => !ignoredCards.contains(c))
        .toList();

    // Grouping
    final Map<RecommendationCategory, List<Recommendation>> grouped = {
      RecommendationCategory.suggestions: [],
      RecommendationCategory.designIssues: [],
      RecommendationCategory.spaceUtilization: [],
      RecommendationCategory.furnitureRecommendations: [],
      RecommendationCategory.colorHarmony: [],
      RecommendationCategory.lightingSuggestions: [],
    };

    for (final card in visibleCards) {
      final cat = _getRecommendationCategory(card);
      grouped[cat]!.add(card);
    }

    final layout = ref.watch(designerProvider);
    final notifier = ref.read(designerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 0. AI Layout Studio (Multi-Candidate Generation)
        _buildAiStudioCard(layout, notifier),
        const SizedBox(height: 12.0),

        // 1. Overall Design Score
        if (scoreState.isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2),
            ),
          )
        else if (scoreState.scores != null) ...[
          _buildInlineScoreDashboard(scoreState.scores!),
          const SizedBox(height: 12.0),
        ],

        // 2. Optimization Button
        _buildInlineOptimizationCard(optState),
        const SizedBox(height: 16.0),

        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Layout Recommendations',
              style: TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.bold,
                color: _kTextPrimary,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 16, color: _kTextSecondary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                ref
                    .read(designScoreProvider.notifier)
                    .fetchScores(widget.roomId);
                ref
                    .read(recommendationProvider.notifier)
                    .fetchRecommendations(widget.roomId);
              },
            ),
          ],
        ),
        const SizedBox(height: 6.0),

        if (recState.isLoading)
          const Center(
            child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2),
          )
        else ...[
          // Saved Recommendations Section
          if (savedCards.isNotEmpty) ...[
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Row(
                  children: [
                    const Icon(Icons.bookmark, color: Colors.amber, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Saved Recommendations (${savedCards.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
                children: savedCards
                    .map((c) => _buildInlineRecommendationCard(c))
                    .toList(),
              ),
            ),
            const Divider(color: _kBorder, height: 1),
          ],

          // Categories ExpansionTiles
          ...RecommendationCategory.values.map((cat) {
            final cards = grouped[cat] ?? [];
            return Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: Icon(cat.icon, color: cat.color, size: 18),
                title: Text(
                  '${cat.title} (${cards.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cards.isNotEmpty ? _kTextPrimary : _kTextSecondary,
                  ),
                ),
                children: cards.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8.0,
                            horizontal: 16.0,
                          ),
                          child: Text(
                            'No recommendations for ${cat.title}.',
                            style: const TextStyle(
                              color: _kTextSecondary,
                              fontSize: 11.0,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ]
                    : cards
                          .map((c) => _buildInlineRecommendationCard(c))
                          .toList(),
              ),
            );
          }),

          // Ignored Recommendations Section
          if (ignoredCards.isNotEmpty) ...[
            const Divider(color: _kBorder, height: 16),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text(
                  'Ignored (${ignoredCards.length})',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _kTextSecondary,
                  ),
                ),
                children: ignoredCards
                    .map(
                      (c) => _buildInlineRecommendationCard(
                        c,
                        isIgnoredView: true,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildInlineScoreDashboard(DesignScores scores) {
    final overall = scores.overallScore;
    final color = overall >= 80.0
        ? Colors.greenAccent
        : (overall >= 50.0 ? Colors.orangeAccent : Colors.redAccent);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kSurfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Overall Score',
                style: TextStyle(color: _kTextSecondary, fontSize: 11),
              ),
              Text(
                '${overall.round()}/100',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: overall / 100.0,
              backgroundColor: _kBorder,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          ...scores.subscores.entries.map((entry) {
            final val = entry.value;
            final subColor = val >= 80.0
                ? Colors.greenAccent
                : (val >= 50.0 ? Colors.orangeAccent : Colors.redAccent);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    entry.key.replaceAll('_', ' ').toUpperCase(),
                    style: const TextStyle(fontSize: 9, color: _kTextSecondary),
                  ),
                  Text(
                    '${val.round()}%',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: subColor,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAiStudioCard(DesignerLayoutState layout, DesignerNotifier notifier) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0F766E).withOpacity(0.35),
            const Color(0xFF5B5BD6).withOpacity(0.25),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF14B8A6).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Icon(Icons.psychology, color: Color(0xFF14B8A6), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI Layout Studio',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
              Chip(
                label: Text('3 OPTIONS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                backgroundColor: Color(0xFF0F766E),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Synthesize Balanced, Space-Efficient, and Style-Focused arrangements based on your room dimensions, openings, and accessibility criteria.',
            style: TextStyle(fontSize: 11, color: _kTextSecondary, height: 1.35),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 15),
            label: const Text('Design with AI (Multi-Option)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AiDesignRequirementsDialog(
                  roomId: widget.roomId,
                  layout: layout,
                  notifier: notifier,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInlineOptimizationCard(OptimizationState state) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.shade900.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.shade800.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: _kAccent, size: 16),
              SizedBox(width: 6),
              Text(
                'Auto Layout Optimizer',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _kAccent,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Rearranges furniture using simulated annealing to satisfy all rules and optimize layout.',
            style: TextStyle(fontSize: 10.5, color: _kTextSecondary),
          ),
          const SizedBox(height: 8),
          if (state.isLoading)
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(color: _kAccent, strokeWidth: 2),
                  SizedBox(height: 4),
                  Text(
                    'Optimizing...',
                    style: TextStyle(fontSize: 9, color: _kTextSecondary),
                  ),
                ],
              ),
            )
          else
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow, size: 14),
              label: const Text(
                'Run Optimization',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                final ok = await ref
                    .read(optimizationProvider.notifier)
                    .runOptimization(widget.roomId);
                if (ok && mounted) {
                  SnackbarManager.showSuccess(
                    context,
                    'Layout optimized successfully!',
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: EdgeInsets.zero,
                minimumSize: const Size(double.infinity, 28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInlineRecommendationCard(
    Recommendation card, {
    bool isIgnoredView = false,
  }) {
    final recState = ref.watch(recommendationProvider);
    final isSaved =
        recState.savedIds.contains(card.id) ||
        recState.savedTitles.contains(card.title);
    final hasAction =
        card.action.isNotEmpty && card.action['action_type'] != 'none';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: _kSurfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSaved ? Colors.amber.withOpacity(0.5) : _kBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getRecommendationCategory(
                    card,
                  ).color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _getRecommendationCategory(
                      card,
                    ).color.withOpacity(0.5),
                  ),
                ),
                child: Text(
                  _getRecommendationCategory(card).title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 8.0,
                    fontWeight: FontWeight.bold,
                    color: _getRecommendationCategory(card).color,
                  ),
                ),
              ),
              Text(
                card.scoreImpact,
                style: const TextStyle(
                  fontSize: 11.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.greenAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            card.title,
            style: const TextStyle(
              fontSize: 12.0,
              fontWeight: FontWeight.bold,
              color: _kTextPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            card.description,
            style: const TextStyle(fontSize: 10.5, color: _kTextSecondary),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(6.0),
            color: const Color(0xFF1E2127),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rule: ${card.ruleTriggered}',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: _kTextSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Reason: ${card.reason}',
                  style: const TextStyle(fontSize: 9, color: _kTextPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Improvement: ${card.expectedImprovement}',
                  style: const TextStyle(fontSize: 9, color: _kTextPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isIgnoredView) ...[
                TextButton.icon(
                  icon: const Icon(Icons.restore, size: 14),
                  label: const Text('Restore', style: TextStyle(fontSize: 10)),
                  onPressed: () {
                    ref.read(recommendationProvider.notifier).unignore(card);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: _kAccentLight,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ] else ...[
                IconButton(
                  icon: Icon(
                    isSaved ? Icons.star : Icons.star_border,
                    color: isSaved ? Colors.amber : _kTextSecondary,
                    size: 18,
                  ),
                  tooltip: isSaved
                      ? 'Unsave Recommendation'
                      : 'Save Recommendation',
                  onPressed: () {
                    if (isSaved) {
                      ref.read(recommendationProvider.notifier).unsave(card);
                      SnackbarManager.showSuccess(
                        context,
                        'Recommendation removed from saved list.',
                      );
                    } else {
                      ref.read(recommendationProvider.notifier).save(card);
                      SnackbarManager.showSuccess(
                        context,
                        'Recommendation saved successfully!',
                      );
                    }
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(
                    Icons.visibility_off_outlined,
                    color: _kTextSecondary,
                    size: 18,
                  ),
                  tooltip: 'Ignore Suggestion',
                  onPressed: () {
                    ref.read(recommendationProvider.notifier).ignore(card);
                    SnackbarManager.showSuccess(context, 'Suggestion ignored.');
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const Spacer(),
                if (hasAction)
                  ElevatedButton(
                    onPressed: () async {
                      final success = await ref
                          .read(recommendationProvider.notifier)
                          .apply(widget.roomId, card.id);
                      if (success && mounted) {
                        ref
                            .read(designScoreProvider.notifier)
                            .fetchScores(widget.roomId);
                        SnackbarManager.showSuccess(
                          context,
                          'Recommendation applied successfully!',
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary.shade800,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(80, 26),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: const Text(
                      'Apply',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInlineValidationPanel() {
    final state = ref.watch(validationProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2),
            ),
          )
        else ...[
          // 0. Active Fix Candidate Preview Card
          if (state.activeFixCandidate != null || state.isEvaluatingFix || state.fixErrorMessage != null)
            _buildInlineFixPreviewCard(state),

          // Usability & Walking Passage Configuration
          _buildInlineUsabilityConfig(state),
          const SizedBox(height: 12.0),

          // 1. Overall Status Card
          if (state.summary != null)
            _buildInlineValidationSummary(state.summary!),
          const SizedBox(height: 12.0),

          // 2. Checklist Section
          _buildInlineChecklistSection(state),
          const SizedBox(height: 16.0),

          // 3. Issues Section
          _buildInlineIssuesSection(state),
        ],
      ],
    );
  }

  Widget _buildInlineScoreBar(String label, double score) {
    final color = score >= 80.0
        ? Colors.greenAccent
        : (score >= 50.0 ? Colors.orangeAccent : Colors.redAccent);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10.0,
                  color: _kTextSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${score.round()}/100',
                style: TextStyle(
                  fontSize: 10.0,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2.0),
          ClipRRect(
            borderRadius: BorderRadius.circular(2.0),
            child: LinearProgressIndicator(
              value: score / 100.0,
              color: color,
              backgroundColor: _kBorder,
              minHeight: 3.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineValidationSummary(ValidationSummary summary) {
    Color statusColor = Colors.redAccent;
    if (summary.overallStatus.toLowerCase() == 'pass') {
      statusColor = Colors.greenAccent;
    } else if (summary.overallStatus.toLowerCase() == 'warning') {
      statusColor = Colors.orangeAccent;
    }

    final scoreColor = summary.overallScore >= 80.0
        ? Colors.greenAccent
        : (summary.overallScore >= 50.0
              ? Colors.orangeAccent
              : Colors.redAccent);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Health: ${summary.overallStatus.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    '${summary.passRate.round()}% pass rate',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: _kTextSecondary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10.0,
                  vertical: 6.0,
                ),
                decoration: BoxDecoration(
                  color: scoreColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: scoreColor.withOpacity(0.5)),
                ),
                child: Column(
                  children: [
                    Text(
                      '${summary.overallScore.round()}',
                      style: TextStyle(
                        color: scoreColor,
                        fontSize: 18.0,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    const Text(
                      'Design Score',
                      style: TextStyle(
                        color: _kTextSecondary,
                        fontSize: 8.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          ClipRRect(
            borderRadius: BorderRadius.circular(4.0),
            child: LinearProgressIndicator(
              value: summary.passRate / 100.0,
              color: statusColor,
              backgroundColor: _kBorder,
              minHeight: 4.0,
            ),
          ),
          const SizedBox(height: 8.0),
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              unselectedWidgetColor: _kTextSecondary,
              colorScheme: const ColorScheme.dark(primary: _kAccentLight),
            ),
            child: ExpansionTile(
              title: const Text(
                'View Score Details',
                style: TextStyle(
                  fontSize: 11.0,
                  fontWeight: FontWeight.bold,
                  color: _kTextPrimary,
                ),
              ),
              dense: true,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 2.0, bottom: 4.0),
              children: [
                _buildInlineScoreBar(
                  'Space Utilization',
                  summary.spaceUtilizationScore,
                ),
                _buildInlineScoreBar(
                  'Accessibility',
                  summary.accessibilityScore,
                ),
                _buildInlineScoreBar(
                  'Comfort/Ergonomics',
                  summary.ergonomicScore,
                ),
                _buildInlineScoreBar(
                  'Lighting Coverage',
                  summary.lightingScore,
                ),
                _buildInlineScoreBar(
                  'Visual Balance',
                  summary.furnitureBalanceScore,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineChecklistSection(ValidationState state) {
    if (state.checklist.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Design Checklist',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: _kTextPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: _kSurfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorder),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: state.checklist.length,
            itemBuilder: (context, index) {
              final item = state.checklist[index];
              return Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    item.completed ? Icons.check_circle : Icons.cancel_outlined,
                    color: item.completed
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    size: 16.0,
                  ),
                  title: Text(
                    item.checklistItem,
                    style: TextStyle(
                      fontSize: 10.5,
                      decoration: item.completed
                          ? TextDecoration.lineThrough
                          : null,
                      color: item.completed ? _kTextSecondary : _kTextPrimary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInlineIssuesSection(ValidationState state) {
    if (state.errors.isEmpty &&
        state.warnings.isEmpty &&
        state.suggestions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: Colors.greenAccent,
              size: 20.0,
            ),
            SizedBox(width: 8.0),
            Expanded(
              child: Text(
                'No issues detected! Your layout complies with all rules.',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final List<Widget> issuesList = [];

    // Group 1: Critical Violations (Errors)
    if (state.errors.isNotEmpty) {
      issuesList.add(
        const Padding(
          padding: EdgeInsets.only(top: 8.0, bottom: 4.0),
          child: Row(
            children: [
              Icon(Icons.cancel, color: Colors.redAccent, size: 14.0),
              SizedBox(width: 4.0),
              Text(
                'Critical Errors',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
        ),
      );
      for (final err in state.errors) {
        issuesList.add(
          _buildInlineIssueCard(err, Colors.redAccent, Icons.error_outline),
        );
        issuesList.add(const SizedBox(height: 6.0));
      }
    }

    // Group 2: Warnings
    if (state.warnings.isNotEmpty) {
      issuesList.add(
        const Padding(
          padding: EdgeInsets.only(top: 8.0, bottom: 4.0),
          child: Row(
            children: [
              Icon(Icons.warning, color: Colors.orangeAccent, size: 14.0),
              SizedBox(width: 4.0),
              Text(
                'Warnings & Alerts',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.orangeAccent,
                ),
              ),
            ],
          ),
        ),
      );
      for (final wrn in state.warnings) {
        issuesList.add(
          _buildInlineIssueCard(
            wrn,
            Colors.orangeAccent,
            Icons.warning_amber_outlined,
          ),
        );
        issuesList.add(const SizedBox(height: 6.0));
      }
    }

    // Group 3: Suggestions
    if (state.suggestions.isNotEmpty) {
      issuesList.add(
        const Padding(
          padding: EdgeInsets.only(top: 8.0, bottom: 4.0),
          child: Row(
            children: [
              Icon(Icons.lightbulb, color: Colors.blueAccent, size: 14.0),
              SizedBox(width: 4.0),
              Text(
                'Suggestions',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueAccent,
                ),
              ),
            ],
          ),
        ),
      );
      for (final sug in state.suggestions) {
        issuesList.add(
          _buildInlineIssueCard(sug, Colors.blueAccent, Icons.info_outline),
        );
        issuesList.add(const SizedBox(height: 6.0));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Warning Panel & Recommendations',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: _kTextPrimary,
          ),
        ),
        const SizedBox(height: 6),
        ...issuesList,
      ],
    );
  }

  Widget _buildInlineUsabilityConfig(ValidationState state) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kSurfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune, size: 14.0, color: _kAccentLight),
              SizedBox(width: 6.0),
              Text(
                'Usability & Clearance Config',
                style: TextStyle(
                  fontSize: 11.0,
                  fontWeight: FontWeight.bold,
                  color: _kTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Min Walkway Width:', style: TextStyle(fontSize: 10.5, color: _kTextSecondary)),
              Text(
                '${state.minWalkwayClearance.round()} cm',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: _kAccentLight),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10.0),
            ),
            child: Slider(
              value: state.minWalkwayClearance.clamp(60.0, 120.0),
              min: 60.0,
              max: 120.0,
              divisions: 12,
              activeColor: _kAccentLight,
              inactiveColor: _kBorder,
              onChanged: (val) {
                ref.read(validationProvider.notifier).setWalkwayClearance(widget.roomId, val);
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bed Dual Egress', style: TextStyle(fontSize: 10.5, color: _kTextPrimary)),
                    Text('Require clearance on both sides', style: TextStyle(fontSize: 9.0, color: _kTextSecondary)),
                  ],
                ),
              ),
              Switch(
                value: state.requireBothSidesBedAccess,
                activeColor: _kAccentLight,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (val) {
                  ref.read(validationProvider.notifier).setRequireBothSidesBedAccess(widget.roomId, val);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInlineFixPreviewCard(ValidationState state) {
    if (state.isEvaluatingFix) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10.0),
        padding: const EdgeInsets.all(10.0),
        decoration: BoxDecoration(
          color: Colors.blueAccent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
        ),
        child: const Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.blueAccent)),
            SizedBox(width: 8.0),
            Expanded(
              child: Text('Calculating minimal-displacement fix candidate...', style: TextStyle(fontSize: 10.5, color: _kTextPrimary)),
            ),
          ],
        ),
      );
    }

    if (state.fixErrorMessage != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10.0),
        padding: const EdgeInsets.all(10.0),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 16.0),
            const SizedBox(width: 6.0),
            Expanded(
              child: Text(state.fixErrorMessage!, style: const TextStyle(fontSize: 10.5, color: Colors.redAccent)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 14.0, color: Colors.redAccent),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => ref.read(validationProvider.notifier).dismissFixPreview(),
            ),
          ],
        ),
      );
    }

    final candidate = state.activeFixCandidate;
    if (candidate == null) return const SizedBox.shrink();

    if (candidate.canFix) {
      final change = candidate.changes.isNotEmpty ? candidate.changes.first : null;
      return Container(
        margin: const EdgeInsets.only(bottom: 12.0),
        padding: const EdgeInsets.all(10.0),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.6), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_fix_high, color: Colors.greenAccent, size: 16.0),
                const SizedBox(width: 6.0),
                const Expanded(
                  child: Text(
                    'One-Click Correction Preview',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 14.0, color: _kTextSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => ref.read(validationProvider.notifier).dismissFixPreview(),
                ),
              ],
            ),
            const SizedBox(height: 4.0),
            Text(
              candidate.explanation,
              style: const TextStyle(fontSize: 10.5, color: _kTextPrimary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6.0),
            if (candidate.measuredBefore != null && candidate.measuredAfter != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2127),
                  borderRadius: BorderRadius.circular(4.0),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Before: ${candidate.measuredBefore!.toStringAsFixed(0)} cm',
                      style: const TextStyle(fontSize: 10.0, color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                    const Icon(Icons.arrow_forward, size: 12.0, color: Colors.greenAccent),
                    Text(
                      'Predicted: ${candidate.measuredAfter!.toStringAsFixed(0)} cm',
                      style: const TextStyle(fontSize: 10.0, color: Colors.greenAccent, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '(Req: ${candidate.requiredClearance?.toStringAsFixed(0) ?? "75"} cm)',
                      style: const TextStyle(fontSize: 9.0, color: _kTextSecondary),
                    ),
                  ],
                ),
              ),
            if (change != null) ...[
              const SizedBox(height: 4.0),
              Text(
                'Preservation: Shifts only ${candidate.targetFurnitureId} by ${change.movementDistance.round()} cm. Non-involved items unchanged.',
                style: const TextStyle(fontSize: 9.5, fontStyle: FontStyle.italic, color: _kTextSecondary),
              ),
            ],
            const SizedBox(height: 8.0),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: state.isApplyingFix 
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                        : const Icon(Icons.check, size: 14.0),
                    label: const Text('Apply Fix (Undo Supported)', style: TextStyle(fontSize: 10.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: state.isApplyingFix
                        ? null
                        : () async {
                            final success = await ref.read(validationProvider.notifier).applyCandidateFix(
                              widget.roomId,
                              onApplyLocally: (id, x, z, rot) async {
                                ref.read(designerProvider.notifier).applyFixCorrection(
                                  furnitureId: id,
                                  proposedX: x,
                                  proposedZ: z,
                                  proposedRotation: rot,
                                );
                              },
                            );
                            if (mounted && success) {
                              SnackbarManager.showSuccess(context, 'Layout correction applied! Press Ctrl+Z to undo anytime.');
                            }
                          },
                  ),
                ),
                const SizedBox(width: 6.0),
                OutlinedButton(
                  onPressed: () => ref.read(validationProvider.notifier).dismissFixPreview(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 10.5)),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      return Container(
        margin: const EdgeInsets.only(bottom: 12.0),
        padding: const EdgeInsets.all(10.0),
        decoration: BoxDecoration(
          color: Colors.orangeAccent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: Colors.orangeAccent.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 16.0),
                const SizedBox(width: 6.0),
                const Expanded(
                  child: Text(
                    'No Valid Correction Found',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 14.0, color: _kTextSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => ref.read(validationProvider.notifier).dismissFixPreview(),
                ),
              ],
            ),
            const SizedBox(height: 4.0),
            Text(
              candidate.explanation,
              style: const TextStyle(fontSize: 10.0, color: _kTextPrimary),
            ),
            if (candidate.alternativeSuggestions.isNotEmpty) ...[
              const SizedBox(height: 6.0),
              const Text('Suggested Alternatives:', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: _kTextPrimary)),
              const SizedBox(height: 2.0),
              ...candidate.alternativeSuggestions.map((alt) => Padding(
                padding: const EdgeInsets.only(bottom: 2.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontSize: 9.0, fontWeight: FontWeight.bold, color: _kTextSecondary)),
                    Expanded(child: Text(alt, style: const TextStyle(fontSize: 9.5, color: _kTextSecondary))),
                  ],
                ),
              )),
            ],
          ],
        ),
      );
    }
  }

  Widget _buildInlineIssueCard(
    ValidationIssue issue,
    Color color,
    IconData icon,
  ) {
    final hasClearance = issue.measuredClearance != null;
    final isFixable = issue.isFixable && issue.affectedFurnitureIds.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kSurfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 16.0),
              const SizedBox(width: 6.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            issue.ruleName,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: color.withOpacity(0.3)),
                          ),
                          child: Text(
                            issue.severity.toUpperCase(),
                            style: TextStyle(fontSize: 8.0, fontWeight: FontWeight.bold, color: color),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      issue.message,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: _kTextPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasClearance) ...[
            const SizedBox(height: 4.0),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(4.0),
                border: Border.all(color: color.withOpacity(0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Measured: ${issue.measuredClearance!.toStringAsFixed(1)} cm',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: color),
                  ),
                  Text(
                    'Required: ${issue.requiredClearance?.toStringAsFixed(1) ?? "75.0"} cm',
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: _kTextPrimary),
                  ),
                  if (issue.clearanceSource != null)
                    Text(
                      issue.clearanceSource!,
                      style: const TextStyle(fontSize: 8.5, color: _kTextSecondary, fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
          ],
          if (issue.recommendation != null) ...[
            const SizedBox(height: 6.0),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6.0),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2127),
                borderRadius: BorderRadius.circular(4.0),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: Colors.orangeAccent,
                        size: 12.0,
                      ),
                      SizedBox(width: 4.0),
                      Text(
                        'Suggested Fix',
                        style: TextStyle(
                          fontSize: 9.0,
                          color: _kTextPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    issue.recommendation!,
                    style: const TextStyle(
                      fontSize: 10.0,
                      color: _kTextSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (issue.affectedFurnitureIds.isNotEmpty)
                TextButton.icon(
                  icon: Icon(Icons.center_focus_strong, size: 12.0, color: color),
                  label: Text(
                    'Highlight in Room',
                    style: TextStyle(fontSize: 10.0, color: color),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    visualDensity: VisualDensity.compact,
                    minimumSize: Size.zero,
                  ),
                  onPressed: () {
                    final targetId = issue.affectedFurnitureIds.first;
                    ref.read(validationProvider.notifier).highlightFurniture(targetId);
                    ref.read(designerProvider.notifier).selectFurniture(targetId);
                    SnackbarManager.showInfo(
                      context,
                      'Focused furniture for rule: ${issue.ruleName}',
                    );
                    _focusSelection2D();
                  },
                ),
              if (isFixable) ...[
                const SizedBox(width: 6.0),
                ElevatedButton.icon(
                  icon: const Icon(Icons.auto_fix_high, size: 12.0),
                  label: const Text('One-Click Fix', style: TextStyle(fontSize: 10.0)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    visualDensity: VisualDensity.compact,
                    minimumSize: Size.zero,
                  ),
                  onPressed: () {
                    ref.read(validationProvider.notifier).requestFixCandidate(widget.roomId, issue);
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRealTimeMetricsCard() {
    final scoreState = ref.watch(designScoreProvider);
    final validationState = ref.watch(validationProvider);

    final overall =
        scoreState.scores?.overallScore ??
        (validationState.summary != null
            ? validationState.summary!.overallScore / 100.0
            : 0.0);
    final subscores = scoreState.scores?.subscores ?? {};

    double ergonomics =
        subscores['ergonomics'] ??
        (validationState.summary != null
            ? validationState.summary!.ergonomicScore / 100.0
            : 0.0);
    double circulation =
        subscores['accessibility'] ??
        (validationState.summary != null
            ? validationState.summary!.accessibilityScore / 100.0
            : 0.0);

    // Normalize if they are on 0-100 scale
    final overallPct = (overall > 1.0 ? overall : overall * 100).round();
    final ergoPct = (ergonomics > 1.0 ? ergonomics : ergonomics * 100).round();
    final circPct = (circulation > 1.0 ? circulation : circulation * 100)
        .round();

    final hasCollisions = validationState.errors.any(
      (e) =>
          e.message.toLowerCase().contains('collision') ||
          e.ruleName.toLowerCase().contains('collision') ||
          e.category.toLowerCase().contains('safety') ||
          e.category.toLowerCase().contains('collision'),
    );

    return Container(
      width: 180,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.9), // Dark card surface
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Metrics',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF8FAFC),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: hasCollisions
                      ? const Color(0xFFEF4444).withOpacity(0.2)
                      : const Color(0xFF10B981).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: hasCollisions
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF10B981),
                    width: 0.6,
                  ),
                ),
                child: Text(
                  hasCollisions ? '🔴 Collision' : '🟢 Safe',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: hasCollisions
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFFA7F3D0),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(color: Color(0xFF334155), height: 1),
          const SizedBox(height: 6),
          _metricRow('Overall Design', '$overallPct%', const Color(0xFF3B82F6)),
          const SizedBox(height: 5),
          _metricRow('Ergonomics', '$ergoPct%', const Color(0xFFEC4899)),
          const SizedBox(height: 5),
          _metricRow('Circulation', '$circPct%', const Color(0xFFF59E0B)),
        ],
      ),
    );
  }

  Widget _metricRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Color(0xFFF8FAFC),
          ),
        ),
      ],
    );
  }
}

// ─── Mini Blueprint Painter ──────────────────────────────────────────────────
class _MiniBlueprintPainter extends CustomPainter {
  final DesignerLayoutState layout;
  _MiniBlueprintPainter({required this.layout});

  @override
  void paint(Canvas canvas, Size size) {
    // Fill background
    final bgPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    if (layout.walls.isEmpty) return;

    // Find bounding box of all walls to scale to size
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final w in layout.walls) {
      minX = min(minX, min(w.start.dx, w.end.dx));
      maxX = max(maxX, max(w.start.dx, w.end.dx));
      minY = min(minY, min(w.start.dy, w.end.dy));
      maxY = max(maxY, max(w.start.dy, w.end.dy));
    }

    final double width = maxX - minX;
    final double height = maxY - minY;
    if (width <= 0 || height <= 0) return;

    // Scale and center walls in size
    final double scale = min(
      (size.width - 16) / width,
      (size.height - 16) / height,
    );
    final double dx = (size.width - width * scale) / 2 - minX * scale;
    final double dy = (size.height - height * scale) / 2 - minY * scale;

    final floorPaint = Paint()..color = const Color(0xFF1E293B);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), floorPaint);

    final wallPaint = Paint()
      ..color = const Color(0xFF0F766E)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    for (final w in layout.walls) {
      canvas.drawLine(
        Offset(w.start.dx * scale + dx, w.start.dy * scale + dy),
        Offset(w.end.dx * scale + dx, w.end.dy * scale + dy),
        wallPaint,
      );
    }

    final furniturePaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.fill;

    for (final f in layout.furniture) {
      final fx = f.x * scale + dx;
      final fy = f.z * scale + dy;
      final fw = max(4.0, f.width * scale);
      final fd = max(4.0, f.depth * scale);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(fx, fy), width: fw, height: fd),
        furniturePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniBlueprintPainter oldDelegate) {
    return oldDelegate.layout != layout;
  }
}

// ─── Temp wall painter (unchanged) ──────────────────────────────────────────

class _TempWallPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  _TempWallPainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final tempPaint = Paint()
      ..color = Colors.orange.withOpacity(0.7)
      ..strokeWidth = 10.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, end, tempPaint);
  }

  @override
  bool shouldRepaint(covariant _TempWallPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}

// ─── Collapsible Section Widget ──────────────────────────────────────────────
class _CollapsibleSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;

  const _CollapsibleSection({
    required this.title,
    required this.icon,
    required this.child,
    this.initiallyExpanded = false,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _controller;
  late Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      value: _isExpanded ? 1.0 : 0.0,
      vsync: this,
    );
    _heightFactor = _controller.drive(CurveTween(curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section Header Button
        InkWell(
          onTap: _toggleExpand,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF22262F), // Matches _kSurfaceElevated
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFF2E3340),
                  width: 0.8,
                ), // Matches _kBorder
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  color: _isExpanded
                      ? const Color(0xFF00BFA5)
                      : const Color(0xFF8892A4),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: TextStyle(
                    color: _isExpanded
                        ? const Color(0xFFECEFF4)
                        : const Color(0xFF8892A4),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                RotationTransition(
                  turns: Tween(begin: 0.0, end: 0.5).animate(_controller),
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Color(0xFF8892A4),
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Section Content
        AnimatedBuilder(
          animation: _heightFactor,
          builder: (context, child) {
            return ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: _heightFactor.value,
                child: child,
              ),
            );
          },
          child: widget.child,
        ),
      ],
    );
  }
}
