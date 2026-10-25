// ignore_for_file: deprecated_member_use
import 'dart:math';
import 'package:flutter/material.dart' hide MaterialState;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/themes/app_theme.dart';
import '../../../../shared/widgets/snackbar_manager.dart';
import '../../providers/designer_provider.dart';
import '../../providers/material_provider.dart';
import '../../models/material_model.dart';
import '../material_library_screen.dart';

// ─── Color palette (04_COLOR_PALETTE.md aligned) ──────────────────────────────
const _kSurface = Color(0xFF111827);
const _kSurfaceElevated = Color(0xFF1E293B);
const _kBorder = Color(0xFF334155);
const _kAccent = Color(0xFF0F766E);
const _kAccentAI = Color(0xFF5B5BD6);
const _kTextPrimary = Color(0xFFF8FAFC);
const _kTextSecondary = Color(0xFF94A3B8);

/// Applied material state for a target (furniture / floor / wall / ceiling)
class AppliedMaterial {
  final String? colorHex;
  final String? materialType;
  final double metallic;
  final double roughness;
  final double opacity;
  final double reflection;
  final double scale;
  final double rotation;
  final String? sourceMaterialId;
  final String? sourceMaterialName;
  final String? normalMap;
  final String? baseColorMap;
  final String? roughnessMap;
  final String? metallicMap;
  final String? emissiveMap;
  final String? emissiveColor;
  final double emissiveIntensity;

  const AppliedMaterial({
    this.colorHex,
    this.materialType,
    this.metallic = 0.0,
    this.roughness = 0.5,
    this.opacity = 1.0,
    this.reflection = 0.0,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.sourceMaterialId,
    this.sourceMaterialName,
    this.normalMap,
    this.baseColorMap,
    this.roughnessMap,
    this.metallicMap,
    this.emissiveMap,
    this.emissiveColor,
    this.emissiveIntensity = 0.0,
  });

  AppliedMaterial copyWith({
    String? colorHex,
    bool clearColor = false,
    String? materialType,
    double? metallic,
    double? roughness,
    double? opacity,
    double? reflection,
    double? scale,
    double? rotation,
    String? sourceMaterialId,
    String? sourceMaterialName,
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
    return AppliedMaterial(
      colorHex: clearColor ? null : (colorHex ?? this.colorHex),
      materialType: materialType ?? this.materialType,
      metallic: metallic ?? this.metallic,
      roughness: roughness ?? this.roughness,
      opacity: opacity ?? this.opacity,
      reflection: reflection ?? this.reflection,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      sourceMaterialId: sourceMaterialId ?? this.sourceMaterialId,
      sourceMaterialName: sourceMaterialName ?? this.sourceMaterialName,
      normalMap: clearNormalMap ? null : (normalMap ?? this.normalMap),
      baseColorMap: clearBaseColorMap ? null : (baseColorMap ?? this.baseColorMap),
      roughnessMap: clearRoughnessMap ? null : (roughnessMap ?? this.roughnessMap),
      metallicMap: clearMetallicMap ? null : (metallicMap ?? this.metallicMap),
      emissiveMap: clearEmissiveMap ? null : (emissiveMap ?? this.emissiveMap),
      emissiveColor: clearEmissiveColor ? null : (emissiveColor ?? this.emissiveColor),
      emissiveIntensity: emissiveIntensity ?? this.emissiveIntensity,
    );
  }
}

/// Full Material Editor panel — can target furniture, floor, wall, or ceiling.
class MaterialEditorPanel extends ConsumerStatefulWidget {
  final String targetType; // 'furniture' | 'floor' | 'wall' | 'ceiling'
  final String? targetId;  // furniture ID (null for room surfaces)
  final DesignerNotifier designerNotifier;

  const MaterialEditorPanel({
    super.key,
    required this.targetType,
    this.targetId,
    required this.designerNotifier,
  });

  @override
  ConsumerState<MaterialEditorPanel> createState() => _MaterialEditorPanelState();
}

class _MaterialEditorPanelState extends ConsumerState<MaterialEditorPanel>
    with SingleTickerProviderStateMixin {
  late AppliedMaterial _local;
  late AnimationController _previewAnim;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _previewAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _previewAnim, curve: Curves.easeInOut),
    );
    _local = _readCurrentState();
  }

  @override
  void didUpdateWidget(MaterialEditorPanel old) {
    super.didUpdateWidget(old);
    if (old.targetType != widget.targetType || old.targetId != widget.targetId) {
      _local = _readCurrentState();
    }
  }

  @override
  void dispose() {
    _previewAnim.dispose();
    super.dispose();
  }

  // ── Read the designer state to populate local sliders ─────────────────────
  AppliedMaterial _readCurrentState() {
    final layout = ref.read(designerProvider);
    if (widget.targetType == 'furniture' && widget.targetId != null) {
      try {
        final f = layout.furniture.firstWhere((x) => x.id == widget.targetId);
        return AppliedMaterial(
          colorHex: f.materialColor,
          materialType: f.materialType,
          metallic: f.metallic,
          roughness: f.roughness,
          opacity: f.opacity,
          reflection: f.metallic, // use metallic as reflection proxy
          scale: f.materialScale,
          rotation: f.materialRotation,
          normalMap: f.normalMap,
          baseColorMap: f.baseColorMap,
          roughnessMap: f.roughnessMap,
          metallicMap: f.metallicMap,
          emissiveMap: f.emissiveMap,
          emissiveColor: f.emissiveColor,
          emissiveIntensity: f.emissiveIntensity,
        );
      } catch (_) {}
    } else if (widget.targetType == 'floor') {
      return AppliedMaterial(
        colorHex: layout.floorMaterialColor,
        materialType: layout.floorMaterialType,
        metallic: layout.floorMetallic,
        roughness: layout.floorRoughness,
        opacity: 1.0,
        reflection: layout.floorReflection,
        scale: layout.floorScale,
        rotation: layout.floorRotation,
        normalMap: layout.floorNormalMap,
        baseColorMap: layout.floorBaseColorMap,
        roughnessMap: layout.floorRoughnessMap,
        metallicMap: layout.floorMetallicMap,
        emissiveMap: layout.floorEmissiveMap,
        emissiveColor: layout.floorEmissiveColor,
        emissiveIntensity: layout.floorEmissiveIntensity,
      );
    } else if (widget.targetType == 'wall') {
      return AppliedMaterial(
        colorHex: layout.wallMaterialColor,
        materialType: layout.wallMaterialType,
        metallic: layout.wallMetallic,
        roughness: layout.wallRoughness,
        opacity: 1.0,
        reflection: layout.wallReflection,
        scale: layout.wallScale,
        rotation: layout.wallRotation,
        normalMap: layout.wallNormalMap,
        baseColorMap: layout.wallBaseColorMap,
        roughnessMap: layout.wallRoughnessMap,
        metallicMap: layout.wallMetallicMap,
        emissiveMap: layout.wallEmissiveMap,
        emissiveColor: layout.wallEmissiveColor,
        emissiveIntensity: layout.wallEmissiveIntensity,
      );
    } else if (widget.targetType == 'ceiling') {
      return AppliedMaterial(
        colorHex: layout.ceilingMaterialColor,
        materialType: layout.ceilingMaterialType,
        metallic: layout.ceilingMetallic,
        roughness: layout.ceilingRoughness,
        opacity: 1.0,
        reflection: layout.ceilingReflection,
        scale: layout.ceilingScale,
        rotation: layout.ceilingRotation,
        normalMap: layout.ceilingNormalMap,
        baseColorMap: layout.ceilingBaseColorMap,
        roughnessMap: layout.ceilingRoughnessMap,
        metallicMap: layout.ceilingMetallicMap,
        emissiveMap: layout.ceilingEmissiveMap,
        emissiveColor: layout.ceilingEmissiveColor,
        emissiveIntensity: layout.ceilingEmissiveIntensity,
      );
    }
    return const AppliedMaterial();
  }

  // ── Commit changes to designer state in real-time ─────────────────────────
  void _commit(AppliedMaterial updated) {
    setState(() => _local = updated);

    if (widget.targetType == 'furniture' && widget.targetId != null) {
      widget.designerNotifier.updateFurnitureMaterialById(
        id: widget.targetId!,
        color: updated.colorHex,
        materialType: updated.materialType,
        metallic: updated.metallic,
        roughness: updated.roughness,
        opacity: updated.opacity,
        scale: updated.scale,
        rotation: updated.rotation,
        normalMap: updated.normalMap,
        baseColorMap: updated.baseColorMap,
        roughnessMap: updated.roughnessMap,
        metallicMap: updated.metallicMap,
        emissiveMap: updated.emissiveMap,
        emissiveColor: updated.emissiveColor,
        emissiveIntensity: updated.emissiveIntensity,
      );
    } else if (widget.targetType == 'floor') {
      widget.designerNotifier.updateRoomSurface(
        surface: 'floor',
        color: updated.colorHex,
        materialType: updated.materialType,
        metallic: updated.metallic,
        roughness: updated.roughness,
        reflection: updated.reflection,
        scale: updated.scale,
        rotation: updated.rotation,
        normalMap: updated.normalMap,
        baseColorMap: updated.baseColorMap,
        roughnessMap: updated.roughnessMap,
        metallicMap: updated.metallicMap,
        emissiveMap: updated.emissiveMap,
        emissiveColor: updated.emissiveColor,
        emissiveIntensity: updated.emissiveIntensity,
      );
    } else if (widget.targetType == 'wall') {
      widget.designerNotifier.updateRoomSurface(
        surface: 'wall',
        color: updated.colorHex,
        materialType: updated.materialType,
        metallic: updated.metallic,
        roughness: updated.roughness,
        reflection: updated.reflection,
        scale: updated.scale,
        rotation: updated.rotation,
        normalMap: updated.normalMap,
        baseColorMap: updated.baseColorMap,
        roughnessMap: updated.roughnessMap,
        metallicMap: updated.metallicMap,
        emissiveMap: updated.emissiveMap,
        emissiveColor: updated.emissiveColor,
        emissiveIntensity: updated.emissiveIntensity,
      );
    } else if (widget.targetType == 'ceiling') {
      widget.designerNotifier.updateRoomSurface(
        surface: 'ceiling',
        color: updated.colorHex,
        materialType: updated.materialType,
        metallic: updated.metallic,
        roughness: updated.roughness,
        reflection: updated.reflection,
        scale: updated.scale,
        rotation: updated.rotation,
        normalMap: updated.normalMap,
        baseColorMap: updated.baseColorMap,
        roughnessMap: updated.roughnessMap,
        metallicMap: updated.metallicMap,
        emissiveMap: updated.emissiveMap,
        emissiveColor: updated.emissiveColor,
        emissiveIntensity: updated.emissiveIntensity,
      );
    }
  }

  // ── Color parse helper ─────────────────────────────────────────────────────
  Color _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF6B7280);
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return const Color(0xFF6B7280);
    }
  }

  String _colorToHex(Color color) {
    return color.value.toRadixString(16).substring(2).toUpperCase();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final matState = ref.watch(materialProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        _buildHeader(),
        const SizedBox(height: 12),

        // ── Texture Preview Sphere ───────────────────────────────────────────
        _buildTexturePreview(),
        const SizedBox(height: 16),

        // ── Color Picker Row ─────────────────────────────────────────────────
        _buildColorSection(),
        const SizedBox(height: 14),

        // ── Emissive Section ─────────────────────────────────────────────────
        _buildEmissiveSection(),
        const SizedBox(height: 14),

        // ── PBR Sliders ──────────────────────────────────────────────────────
        _buildSliderSection('Roughness', _local.roughness, Icons.grain,
            const Color(0xFFFFCC80), (v) => _commit(_local.copyWith(roughness: v))),
        const SizedBox(height: 8),
        _buildSliderSection('Metallic', _local.metallic, Icons.opacity,
            const Color(0xFFB0BEC5), (v) => _commit(_local.copyWith(metallic: v))),
        const SizedBox(height: 8),
        _buildSliderSection('Opacity', _local.opacity, Icons.tune,
            Colors.purple.shade300, (v) => _commit(_local.copyWith(opacity: v))),
        const SizedBox(height: 8),
        _buildSliderSection('Reflection', _local.reflection, Icons.wb_iridescent_outlined,
            Colors.cyan.shade300, (v) => _commit(_local.copyWith(reflection: v))),
        const SizedBox(height: 8),
        _buildSliderSection('Scale', _local.scale, Icons.zoom_out_map,
            const Color(0xFF81C784), (v) => _commit(_local.copyWith(scale: v)),
            min: 0.1, max: 5.0),
        const SizedBox(height: 8),
        _buildSliderSection('Rotation', _local.rotation, Icons.rotate_right,
            const Color(0xFFE57373), (v) => _commit(_local.copyWith(rotation: v)),
            min: 0.0, max: 360.0, isAngle: true),
        const SizedBox(height: 16),

        // ── Texture Maps Section ──────────────────────────────────────────────
        _buildTextureMapsSection(),
        const SizedBox(height: 16),

        // ── Material Type chips ───────────────────────────────────────────────
        _buildMaterialTypeSection(),
        const SizedBox(height: 16),

        // ── Actions ──────────────────────────────────────────────────────────
        _buildActionsSection(matState),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Emissive Section ───────────────────────────────────────────────────────
  Widget _buildEmissiveSection() {
    final currentEmissive = _hexToColor(_local.emissiveColor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.lightbulb_outline, size: 12, color: Colors.yellow),
            const SizedBox(width: 5),
            const Text('EMISSIVE COLOR', style: TextStyle(
              color: _kTextSecondary, fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 0.8,
            )),
            const Spacer(),
            GestureDetector(
              onTap: () => _showEmissiveColorPickerDialog(currentEmissive),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 14, height: 14,
                      decoration: BoxDecoration(
                        color: currentEmissive,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.white24),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '#${_local.emissiveColor?.toUpperCase() ?? '000000'}',
                      style: const TextStyle(color: _kTextPrimary, fontSize: 10, fontFamily: 'monospace'),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.colorize, size: 12, color: _kTextSecondary),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildSliderSection('Emissive Intensity', _local.emissiveIntensity, Icons.wb_sunny_outlined,
            Colors.yellow.shade400, (v) => _commit(_local.copyWith(emissiveIntensity: v)),
            min: 0.0, max: 5.0),
      ],
    );
  }

  void _showEmissiveColorPickerDialog(Color current) {
    showDialog(
      context: context,
      builder: (ctx) => _ColorPickerDialog(
        initial: current,
        onColorSelected: (c) {
          _commit(_local.copyWith(emissiveColor: _colorToHex(c)));
        },
      ),
    );
  }

  // ── Texture Maps Section ───────────────────────────────────────────────────
  Widget _buildTextureMapsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('TEXTURE MAPS', style: TextStyle(
          color: _kTextSecondary, fontSize: 9,
          fontWeight: FontWeight.w700, letterSpacing: 0.8,
        )),
        const SizedBox(height: 6),
        _buildTextureMapRow('Base Color Map', _local.baseColorMap, (v) => _commit(_local.copyWith(baseColorMap: v, clearBaseColorMap: v == null))),
        _buildTextureMapRow('Normal Map', _local.normalMap, (v) => _commit(_local.copyWith(normalMap: v, clearNormalMap: v == null))),
        _buildTextureMapRow('Roughness Map', _local.roughnessMap, (v) => _commit(_local.copyWith(roughnessMap: v, clearRoughnessMap: v == null))),
        _buildTextureMapRow('Metallic Map', _local.metallicMap, (v) => _commit(_local.copyWith(metallicMap: v, clearMetallicMap: v == null))),
        _buildTextureMapRow('Emissive Map', _local.emissiveMap, (v) => _commit(_local.copyWith(emissiveMap: v, clearEmissiveMap: v == null))),
      ],
    );
  }

  Widget _buildTextureMapRow(String label, String? currentPath, Function(String?) onUpdated) {
    final hasTexture = currentPath != null && currentPath.isNotEmpty;
    final displayPath = hasTexture ? currentPath.split('/').last : 'None';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(color: _kTextSecondary, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kBorder),
              ),
              child: Text(
                displayPath,
                style: const TextStyle(color: _kTextPrimary, fontSize: 9, fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _miniActionButton(
            icon: Icons.link_rounded,
            tooltip: 'Assign Path',
            color: _kAccent,
            onTap: () => _showTexturePathDialog(label, currentPath, onUpdated),
          ),
          if (hasTexture) ...[
            const SizedBox(width: 4),
            _miniActionButton(
              icon: Icons.clear_rounded,
              tooltip: 'Clear Map',
              color: const Color(0xFFEF4444),
              onTap: () => onUpdated(null),
            ),
          ],
        ],
      ),
    );
  }

  void _showTexturePathDialog(String label, String? current, Function(String?) onUpdated) {
    final ctrl = TextEditingController(text: current ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurfaceElevated,
        title: Text('Assign $label', style: const TextStyle(color: _kTextPrimary, fontSize: 13)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter local/remote texture file path or URL:', style: TextStyle(color: _kTextSecondary, fontSize: 11)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: _kTextPrimary, fontSize: 11),
              decoration: InputDecoration(
                filled: true,
                fillColor: _kSurface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kAccent, width: 1.5)),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Quick Predefined Assets:', style: TextStyle(color: _kTextSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _quickTextureChip('/static/textures/wood_base.png', 'Wood Base', ctrl),
                _quickTextureChip('/static/textures/wood_normal.png', 'Wood Normal', ctrl),
                _quickTextureChip('/static/textures/marble_base.png', 'Marble Base', ctrl),
                _quickTextureChip('/static/textures/concrete_normal.png', 'Concrete Normal', ctrl),
                _quickTextureChip('/static/textures/steel_metallic.png', 'Steel Metallic', ctrl),
              ],
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: _kTextSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
            onPressed: () {
              final path = ctrl.text.trim();
              onUpdated(path.isEmpty ? null : path);
              Navigator.pop(ctx);
            },
            child: const Text('Assign', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _quickTextureChip(String path, String label, TextEditingController ctrl) {
    return GestureDetector(
      onTap: () {
        ctrl.text = path;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _kBorder),
        ),
        child: Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 9)),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final icon = switch (widget.targetType) {
      'furniture' => Icons.chair_outlined,
      'floor' => Icons.grid_on,
      'wall' => Icons.view_in_ar,
      'ceiling' => Icons.roofing,
      _ => Icons.texture,
    };
    final label = switch (widget.targetType) {
      'furniture' => 'Furniture Material',
      'floor' => 'Floor Material',
      'wall' => 'Wall Material',
      'ceiling' => 'Ceiling Material',
      _ => 'Material',
    };

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _kAccent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kAccent.withOpacity(0.3)),
          ),
          child: Icon(icon, color: _kAccent, size: 14),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: _kTextPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ),
        // Replace material button
        _miniActionButton(
          icon: Icons.swap_horiz_rounded,
          tooltip: 'Replace from Library',
          color: _kAccent,
          onTap: _openMaterialLibrary,
        ),
        const SizedBox(width: 4),
        // Remove material button
        _miniActionButton(
          icon: Icons.clear_rounded,
          tooltip: 'Remove Material',
          color: const Color(0xFFEF4444),
          onTap: _removeMaterial,
        ),
      ],
    );
  }

  Widget _miniActionButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, color: color, size: 12),
        ),
      ),
    );
  }

  // ── Texture Preview Sphere ─────────────────────────────────────────────────
  Widget _buildTexturePreview() {
    final baseColor = _hexToColor(_local.colorHex);
    final roughness = _local.roughness;
    final metallic = _local.metallic;
    final opacity = _local.opacity;

    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background grid pattern
            CustomPaint(
              painter: _CheckerboardPainter(),
              child: const SizedBox.expand(),
            ),
            // Sphere preview
            AnimatedBuilder(
              animation: _shimmer,
              builder: (context, _) {
                return CustomPaint(
                  size: const Size(100, 100),
                  painter: _MaterialSpherePainter(
                    baseColor: baseColor,
                    roughness: roughness,
                    metallic: metallic,
                    opacity: opacity,
                    shimmerT: _shimmer.value,
                    rotation: _local.rotation,
                  ),
                );
              },
            ),
            // Info overlay
            Positioned(
              bottom: 8,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10, height: 10,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: baseColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                    ),
                    Text(
                      '${_local.materialType?.toUpperCase() ?? 'DEFAULT'}  '
                      '${opacity < 1 ? '${(opacity * 100).round()}% ' : ''}'
                      '${metallic > 0.5 ? '· METAL' : roughness < 0.3 ? '· GLOSS' : '· ROUGH'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Color Section ─────────────────────────────────────────────────────────
  Widget _buildColorSection() {
    final currentColor = _hexToColor(_local.colorHex);
    final presetColors = [
      const Color(0xFFFFFFFF),
      const Color(0xFFF5F5F5),
      const Color(0xFF90A4AE),
      const Color(0xFF546E7A),
      const Color(0xFF263238),
      const Color(0xFF111111),
      const Color(0xFFC8A26E), // Wood
      const Color(0xFF8D6E63), // Brown wood
      const Color(0xFFA1887F), // Light wood
      const Color(0xFF4E342E), // Dark wood
      const Color(0xFF78909C), // Metal grey
      const Color(0xFF1565C0), // Blue
      const Color(0xFF2E7D32), // Green
      const Color(0xFFB71C1C), // Red
      const Color(0xFFF9A825), // Gold
      const Color(0xFF6A1B9A), // Purple
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('COLOR', style: TextStyle(
              color: _kTextSecondary, fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 0.8,
            )),
            const Spacer(),
            // Current color swatch + hex display
            Expanded(
              flex: 4,
              child: GestureDetector(
                onTap: () => _showColorPickerDialog(currentColor),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 14, height: 14,
                        decoration: BoxDecoration(
                          color: currentColor,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Colors.white24),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '#${_local.colorHex?.toUpperCase() ?? 'DEFAULT'}',
                          style: const TextStyle(color: _kTextPrimary, fontSize: 10, fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.colorize, size: 12, color: _kTextSecondary),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Preset color swatches
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: presetColors.map((color) {
            final hex = _colorToHex(color);
            final isSelected = _local.colorHex?.toUpperCase() == hex;
            return GestureDetector(
              onTap: () => _commit(_local.copyWith(colorHex: hex)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSelected ? _kAccent : Colors.white24,
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: isSelected ? [
                    BoxShadow(color: _kAccent.withOpacity(0.4), blurRadius: 6),
                  ] : null,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Slider ────────────────────────────────────────────────────────────────
  Widget _buildSliderSection(
    String label,
    double value,
    IconData icon,
    Color color,
    ValueChanged<double> onChanged, {
    double min = 0.0,
    double max = 1.0,
    bool isAngle = false,
  }) {
    final displayVal = isAngle
        ? '${value.round()}°'
        : value.toStringAsFixed(2);

    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(
              color: _kTextSecondary, fontSize: 10, fontWeight: FontWeight.w600,
            )),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(displayVal, style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.bold,
              )),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: color,
            inactiveTrackColor: color.withOpacity(0.2),
            thumbColor: color,
            overlayColor: color.withOpacity(0.15),
            valueIndicatorColor: color,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  // ── Material Type chips ────────────────────────────────────────────────────
  Widget _buildMaterialTypeSection() {
    final types = ['wood', 'fabric', 'metal', 'glass', 'marble', 'concrete', 'leather', 'paint', 'plastic', 'ceramic'];
    final typeIcons = {
      'wood': Icons.forest_outlined,
      'fabric': Icons.texture_outlined,
      'metal': Icons.precision_manufacturing_outlined,
      'glass': Icons.wb_iridescent_outlined,
      'marble': Icons.foundation_outlined,
      'concrete': Icons.foundation_outlined,
      'leather': Icons.backpack_outlined,
      'paint': Icons.format_paint_outlined,
      'plastic': Icons.circle_outlined,
      'ceramic': Icons.grid_view_outlined,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('MATERIAL TYPE', style: TextStyle(
          color: _kTextSecondary, fontSize: 9,
          fontWeight: FontWeight.w700, letterSpacing: 0.8,
        )),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: types.map((type) {
            final isSelected = _local.materialType == type;
            return GestureDetector(
              onTap: () => _commit(_local.copyWith(materialType: type)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected ? _kAccent.withOpacity(0.2) : _kSurfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? _kAccent : _kBorder,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      typeIcons[type] ?? Icons.texture,
                      size: 11,
                      color: isSelected ? _kAccent : _kTextSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${type[0].toUpperCase()}${type.substring(1)}',
                      style: TextStyle(
                        color: isSelected ? _kAccent : _kTextSecondary,
                        fontSize: 10,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  Widget _buildActionsSection(MaterialState matState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('ACTIONS', style: TextStyle(
          color: _kTextSecondary, fontSize: 9,
          fontWeight: FontWeight.w700, letterSpacing: 0.8,
        )),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _actionButton(
                label: 'Replace',
                icon: Icons.swap_horiz_rounded,
                color: _kAccent,
                onTap: _openMaterialLibrary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _actionButton(
                label: 'Duplicate',
                icon: Icons.copy_all_rounded,
                color: _kAccentAI,
                onTap: _duplicateMaterial,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _actionButton(
                label: 'Save Custom',
                icon: Icons.save_outlined,
                color: const Color(0xFF10B981),
                onTap: _saveCustomMaterial,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _actionButton(
                label: 'Remove',
                icon: Icons.delete_outline_rounded,
                color: const Color(0xFFEF4444),
                onTap: _removeMaterial,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            )),
          ],
        ),
      ),
    );
  }

  // ── Handlers ───────────────────────────────────────────────────────────────

  void _openMaterialLibrary() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MaterialLibraryScreen(
        targetElementType: widget.targetType,
        targetElementId: widget.targetId,
      ),
    ));
  }

  void _removeMaterial() {
    if (widget.targetType == 'furniture' && widget.targetId != null) {
      widget.designerNotifier.updateFurnitureMaterialById(
        id: widget.targetId!,
        color: null,
        clearColor: true,
        materialType: null,
        metallic: 0.0,
        roughness: 0.5,
        opacity: 1.0,
      );
    } else {
      widget.designerNotifier.updateRoomSurface(
        surface: widget.targetType,
        color: null,
        clearColor: true,
        materialType: null,
        metallic: 0.0,
        roughness: 0.5,
        reflection: 0.0,
        scale: 1.0,
        rotation: 0.0,
      );
    }
    setState(() => _local = const AppliedMaterial());
    SnackbarManager.showSuccess(context, 'Material removed from ${widget.targetType}.');
  }

  void _duplicateMaterial() {
    final current = _local;
    // Clone to a sibling target type as a visual cue
    final types = ['floor', 'wall', 'ceiling', 'furniture'];
    final next = types.firstWhere((t) => t != widget.targetType, orElse: () => 'floor');
    if (next != 'furniture') {
      widget.designerNotifier.updateRoomSurface(
        surface: next,
        color: current.colorHex,
        materialType: current.materialType,
        metallic: current.metallic,
        roughness: current.roughness,
        reflection: current.reflection,
        scale: current.scale,
        rotation: current.rotation,
      );
    }
    SnackbarManager.showSuccess(context, 'Material duplicated to $next.');
  }

  void _saveCustomMaterial() {
    _showSaveCustomDialog();
  }

  void _showSaveCustomDialog() {
    final nameCtrl = TextEditingController(text: '${_local.materialType ?? 'Custom'} Material');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurfaceElevated,
        title: const Text('Save Custom Material', style: TextStyle(color: _kTextPrimary, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Give this material a name:', style: TextStyle(color: _kTextSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: const TextStyle(color: _kTextPrimary, fontSize: 12),
              decoration: InputDecoration(
                filled: true,
                fillColor: _kSurface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kAccent, width: 1.5)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _kTextSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              ref.read(materialProvider.notifier).saveCustomMaterial(
                name: name,
                colorHex: _local.colorHex,
                materialType: _local.materialType,
                metallic: _local.metallic,
                roughness: _local.roughness,
                opacity: _local.opacity,
                reflection: _local.reflection,
                scale: _local.scale,
                rotation: _local.rotation,
              );
              SnackbarManager.showSuccess(context, 'Custom material "$name" saved.');
            },
            child: const Text('Save', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ── Color Picker Dialog ────────────────────────────────────────────────────
  void _showColorPickerDialog(Color currentColor) {
    showDialog(
      context: context,
      builder: (ctx) => _ColorPickerDialog(
        initial: currentColor,
        onColorSelected: (c) {
          _commit(_local.copyWith(colorHex: _colorToHex(c)));
        },
      ),
    );
  }
}

// ─── Color Picker Dialog ───────────────────────────────────────────────────────
class _ColorPickerDialog extends StatefulWidget {
  final Color initial;
  final ValueChanged<Color> onColorSelected;

  const _ColorPickerDialog({required this.initial, required this.onColorSelected});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late double _hue, _sat, _val;
  final TextEditingController _hexCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initial);
    _hue = hsv.hue;
    _sat = hsv.saturation;
    _val = hsv.value;
    _hexCtrl.text = _toHex(_currentColor);
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  Color get _currentColor => HSVColor.fromAHSV(1.0, _hue, _sat, _val).toColor();

  String _toHex(Color c) =>
      c.value.toRadixString(16).substring(2).toUpperCase();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _kSurfaceElevated,
      title: const Text('Pick Color', style: TextStyle(color: _kTextPrimary, fontSize: 14)),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hue gradient
            _gradientSlider('Hue', _hue, 0, 360, _hueGradient(), (v) {
              setState(() { _hue = v; _hexCtrl.text = _toHex(_currentColor); });
            }),
            const SizedBox(height: 8),
            _gradientSlider('Saturation', _sat, 0, 1, _satGradient(), (v) {
              setState(() { _sat = v; _hexCtrl.text = _toHex(_currentColor); });
            }),
            const SizedBox(height: 8),
            _gradientSlider('Value', _val, 0, 1, _valGradient(), (v) {
              setState(() { _val = v; _hexCtrl.text = _toHex(_currentColor); });
            }),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _currentColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _hexCtrl,
                    style: const TextStyle(color: _kTextPrimary, fontSize: 12, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      prefixText: '#',
                      prefixStyle: const TextStyle(color: _kTextSecondary, fontSize: 12),
                      filled: true,
                      fillColor: _kSurface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kAccent, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onSubmitted: (hex) {
                      try {
                        final c = Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
                        final hsv = HSVColor.fromColor(c);
                        setState(() {
                          _hue = hsv.hue;
                          _sat = hsv.saturation;
                          _val = hsv.value;
                        });
                      } catch (_) {}
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: _kTextSecondary))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
          onPressed: () {
            widget.onColorSelected(_currentColor);
            Navigator.pop(context);
          },
          child: const Text('Apply', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  LinearGradient _hueGradient() {
    return LinearGradient(colors: [
      const HSVColor.fromAHSV(1, 0, 1, 1).toColor(),
      const HSVColor.fromAHSV(1, 60, 1, 1).toColor(),
      const HSVColor.fromAHSV(1, 120, 1, 1).toColor(),
      const HSVColor.fromAHSV(1, 180, 1, 1).toColor(),
      const HSVColor.fromAHSV(1, 240, 1, 1).toColor(),
      const HSVColor.fromAHSV(1, 300, 1, 1).toColor(),
      const HSVColor.fromAHSV(1, 360, 1, 1).toColor(),
    ]);
  }

  LinearGradient _satGradient() {
    return LinearGradient(colors: [
      HSVColor.fromAHSV(1, _hue, 0, _val).toColor(),
      HSVColor.fromAHSV(1, _hue, 1, _val).toColor(),
    ]);
  }

  LinearGradient _valGradient() {
    return LinearGradient(colors: [
      Colors.black,
      HSVColor.fromAHSV(1, _hue, _sat, 1).toColor(),
    ]);
  }

  Widget _gradientSlider(String label, double value, double min, double max,
      LinearGradient gradient, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 10)),
        const SizedBox(height: 4),
        Container(
          height: 20,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 20,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayColor: Colors.white12,
              trackShape: const RectangularSliderTrackShape(),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Material Sphere Preview Painter ──────────────────────────────────────────
class _MaterialSpherePainter extends CustomPainter {
  final Color baseColor;
  final double roughness;
  final double metallic;
  final double opacity;
  final double shimmerT;
  final double rotation;

  _MaterialSpherePainter({
    required this.baseColor,
    required this.roughness,
    required this.metallic,
    required this.opacity,
    required this.shimmerT,
    required this.rotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.42;

    // Drop shadow
    final shadowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
      ..color = Colors.black.withOpacity(0.5);
    canvas.drawCircle(center + const Offset(4, 6), radius, shadowPaint);

    // Base sphere radial gradient
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.45),
        radius: 0.85,
        colors: [
          Color.alphaBlend(Colors.white.withOpacity(0.3 * (1 - roughness)), baseColor.withOpacity(opacity)),
          baseColor.withOpacity(opacity),
          Color.alphaBlend(Colors.black.withOpacity(0.45), baseColor.withOpacity(opacity)),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, paint);

    // Specular highlight (reduced by roughness, enhanced by metallic)
    if (roughness < 0.95) {
      final specRadius = radius * 0.25 * (1 - roughness * 0.7);
      final specCenter = center + Offset(-radius * 0.35, -radius * 0.38);
      final specOpacity = ((1 - roughness) * 0.8 + metallic * 0.15).clamp(0.0, 1.0);
      final specPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withOpacity(specOpacity),
            Colors.white.withOpacity(0),
          ],
        ).createShader(Rect.fromCircle(center: specCenter, radius: specRadius));
      canvas.drawCircle(specCenter, specRadius, specPaint);
    }

    // Metallic shimmer band
    if (metallic > 0.2) {
      final shimmerPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment(shimmerT - 0.5, -1),
          end: Alignment(shimmerT + 0.3, 1),
          colors: [
            Colors.white.withOpacity(0),
            Colors.white.withOpacity(metallic * 0.25),
            Colors.white.withOpacity(0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));
      canvas.drawRect(Rect.fromCircle(center: center, radius: radius * 2), shimmerPaint);
      canvas.restore();
    }

    // Rotation indicator arc
    if (rotation > 0) {
      final arcPaint = Paint()
        ..color = Colors.white.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 0.7),
        -pi / 2,
        rotation * pi / 180,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_MaterialSpherePainter old) =>
      old.baseColor != baseColor ||
      old.roughness != roughness ||
      old.metallic != metallic ||
      old.opacity != opacity ||
      old.shimmerT != shimmerT ||
      old.rotation != rotation;
}

// ─── Checkerboard for opacity background ──────────────────────────────────────
class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const s = 10.0;
    final p1 = Paint()..color = const Color(0xFF1E293B);
    final p2 = Paint()..color = const Color(0xFF334155);
    for (double y = 0; y < size.height; y += s) {
      for (double x = 0; x < size.width; x += s) {
        final even = ((x / s).toInt() + (y / s).toInt()) % 2 == 0;
        canvas.drawRect(Rect.fromLTWH(x, y, s, s), even ? p1 : p2);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter old) => false;
}

// ─── Compact inline material badge for library cards ─────────────────────────
class MaterialDragFeedback extends StatelessWidget {
  final MaterialModel material;
  const MaterialDragFeedback({super.key, required this.material});

  Color _hexToColor(String? hex) {
    if (hex == null) return AppTheme.primary;
    try { return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16)); }
    catch (_) { return AppTheme.primary; }
  }

  @override
  Widget build(BuildContext context) {
    final color = _hexToColor(material.baseColor);
    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.9,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kAccent, width: 1.5),
            boxShadow: [BoxShadow(color: _kAccent.withOpacity(0.3), blurRadius: 12)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(material.name, style: const TextStyle(color: _kTextPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                  Text(material.category.name, style: const TextStyle(color: _kAccent, fontSize: 9)),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.drag_indicator, color: _kTextSecondary, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}
