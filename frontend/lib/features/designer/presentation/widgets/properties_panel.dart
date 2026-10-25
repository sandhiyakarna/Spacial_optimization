import '../../../../app/themes/app_theme.dart';
// ignore_for_file: deprecated_member_use

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/snackbar_manager.dart';
import '../../providers/designer_provider.dart';

import '../../../furniture/providers/furniture_provider.dart';
import '../../../furniture/models/furniture_asset.dart';

import 'material_editor_panel.dart';
import '../../providers/lighting_provider.dart';
import '../../models/light_source.dart';

// ─── Color palette (aligned with 04_COLOR_PALETTE.md) ─────────────────────────
const _kSurface = Color(0xFF111827); // Dark Theme Surface
const _kSurfaceElevated = Color(0xFF1E293B); // Dark Theme Card
const _kBorder = Color(0xFF334155); // Dark Theme Border
const _kAccent = Color(0xFF0F766E); // Brand Primary
const _kTextPrimary = Color(0xFFF8FAFC); // Dark Theme Primary Text
const _kTextSecondary = Color(0xFF94A3B8); // Dark Theme Secondary Text

/// Full properties panel shown when a [PlacedFurniture] is selected.
/// Displays 6 collapsible cards as required.
class FurniturePropertiesPanel extends ConsumerStatefulWidget {
  final PlacedFurniture furniture;
  final DesignerNotifier notifier;
  final VoidCallback onDelete;

  const FurniturePropertiesPanel({
    super.key,
    required this.furniture,
    required this.notifier,
    required this.onDelete,
  });

  @override
  ConsumerState<FurniturePropertiesPanel> createState() =>
      _FurniturePropertiesPanelState();
}

class _FurniturePropertiesPanelState extends ConsumerState<FurniturePropertiesPanel> {
  late TextEditingController _nameCtrl;
  late TextEditingController _xCtrl;
  late TextEditingController _yCtrl;
  late TextEditingController _zCtrl;
  late TextEditingController _rotCtrl;
  late TextEditingController _wCtrl;
  late TextEditingController _dCtrl;
  late TextEditingController _hCtrl;

  @override
  void initState() {
    super.initState();
    _initControllers(widget.furniture);
  }

  void _initControllers(PlacedFurniture f) {
    _nameCtrl = TextEditingController(text: f.name);
    _xCtrl = TextEditingController(text: f.x.round().toString());
    _yCtrl = TextEditingController(text: f.y.round().toString());
    _zCtrl = TextEditingController(text: f.z.round().toString());
    _rotCtrl = TextEditingController(
        text: (f.rotationY * 180 / pi).round().toString());
    _wCtrl = TextEditingController(text: f.width.round().toString());
    _dCtrl = TextEditingController(text: f.depth.round().toString());
    _hCtrl = TextEditingController(text: f.height.round().toString());
  }

  @override
  void didUpdateWidget(FurniturePropertiesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.furniture.id != widget.furniture.id) {
      for (final c in [_nameCtrl, _xCtrl, _yCtrl, _zCtrl, _rotCtrl, _wCtrl, _dCtrl, _hCtrl]) {
        c.dispose();
      }
      _initControllers(widget.furniture);
    } else {
      if (_nameCtrl.text != widget.furniture.name) {
        _nameCtrl.text = widget.furniture.name;
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _xCtrl, _yCtrl, _zCtrl, _rotCtrl, _wCtrl, _dCtrl, _hCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  Color _hexToColor(String? hex, {Color fallback = AppTheme.primary}) {
    if (hex == null) return fallback;
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  void _syncControllersFromFurniture() {
    final f = widget.furniture;
    _xCtrl.text = f.x.round().toString();
    _yCtrl.text = f.y.round().toString();
    _zCtrl.text = f.z.round().toString();
    _rotCtrl.text = (f.rotationY * 180 / pi).round().toString();
    _wCtrl.text = f.width.round().toString();
    _dCtrl.text = f.depth.round().toString();
    _hCtrl.text = f.height.round().toString();
  }

  void _applyPrecisePlacement() {
    final x = double.tryParse(_xCtrl.text);
    final y = double.tryParse(_yCtrl.text);
    final z = double.tryParse(_zCtrl.text);
    final rotDeg = double.tryParse(_rotCtrl.text);
    final w = double.tryParse(_wCtrl.text);
    final d = double.tryParse(_dCtrl.text);
    final h = double.tryParse(_hCtrl.text);

    if (x != null && y != null && z != null) {
      widget.notifier.updateSelectedFurnitureTransform(
        x: x.clamp(0, 4000),
        y: y.clamp(0, 500),
        z: z.clamp(0, 4000),
        rotationY: rotDeg != null ? rotDeg * pi / 180.0 : null,
      );
    }

    if (w != null || d != null || h != null) {
      widget.notifier.updateSelectedFurnitureDimensions(
        width: w,
        depth: d,
        height: h,
      );
    }

    SnackbarManager.showSuccess(context, 'Precise placement applied.');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final f = widget.furniture;

    final assets = ref.watch(furnitureProvider).assets;
    FurnitureAsset? matchingAsset;
    try {
      matchingAsset = assets.firstWhere((a) => a.id == f.assetId);
    } catch (_) {}
    final category = matchingAsset?.category ?? 'Furniture';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 1. Object Information Card ──────────────────────────────────────
        _CollapsibleCard(
          title: 'Object Information',
          icon: Icons.info_outline,
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Name', style: TextStyle(color: _kTextSecondary, fontSize: 10)),
              const SizedBox(height: 4),
              SizedBox(
                height: 38,
                child: TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: _kTextPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _kSurface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                  ),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) {
                      widget.notifier.updateSelectedFurnitureName(v.trim());
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              _buildReadOnlyInfoRow('Category', category),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildReadOnlyInfoRow('ID', f.id.length > 12 ? '${f.id.substring(0, 12)}...' : f.id),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14, color: _kAccent),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: f.id));
                      SnackbarManager.showSuccess(context, 'Copied object ID to clipboard');
                    },
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    tooltip: 'Copy ID',
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── 2. Quick Rotation Controls Card ─────────────────────────────────
        _CollapsibleCard(
          title: 'Rotation Controls',
          icon: Icons.rotate_right,
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Current Angle', style: TextStyle(color: _kTextSecondary, fontSize: 11)),
                  Text(
                    '${(f.rotationY * 180 / pi).round()}°',
                    style: const TextStyle(color: _kAccent, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildRotationPresetButton('-45°', () {
                    final newRad = f.rotationY - (45 * pi / 180);
                    widget.notifier.updateSelectedFurnitureTransform(rotationY: newRad);
                  }),
                  _buildRotationPresetButton('-15°', () {
                    final newRad = f.rotationY - (15 * pi / 180);
                    widget.notifier.updateSelectedFurnitureTransform(rotationY: newRad);
                  }),
                  _buildRotationPresetButton('+15°', () {
                    final newRad = f.rotationY + (15 * pi / 180);
                    widget.notifier.updateSelectedFurnitureTransform(rotationY: newRad);
                  }),
                  _buildRotationPresetButton('+45°', () {
                    final newRad = f.rotationY + (45 * pi / 180);
                    widget.notifier.updateSelectedFurnitureTransform(rotationY: newRad);
                  }),
                  _buildRotationPresetButton('90°', () {
                    final newRad = f.rotationY + (90 * pi / 180);
                    widget.notifier.updateSelectedFurnitureTransform(rotationY: newRad);
                  }),
                ],
              ),
            ],
          ),
        ),

        // ── 3. Dimensions Card ───────────────────────────────────────────────
        _CollapsibleCard(
          title: 'Dimensions',
          icon: Icons.aspect_ratio,
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDimensionRow('Width', f.width, (val) {
                widget.notifier.updateSelectedFurnitureDimensions(width: val);
              }),
              const SizedBox(height: 8),
              _buildDimensionRow('Depth', f.depth, (val) {
                widget.notifier.updateSelectedFurnitureDimensions(depth: val);
              }),
              const SizedBox(height: 8),
              _buildDimensionRow('Height', f.height, (val) {
                widget.notifier.updateSelectedFurnitureDimensions(height: val);
              }),
            ],
          ),
        ),

        // ── 4. Precise Placement Panel ─────────────────────────────────────
        _CollapsibleCard(
          title: 'Precise Placement',
          icon: Icons.tune,
          initiallyExpanded: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('POSITION (cm)'),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _buildNumberInput('X', _xCtrl)),
                  const SizedBox(width: 6),
                  Expanded(child: _buildNumberInput('Y', _yCtrl)),
                  const SizedBox(width: 6),
                  Expanded(child: _buildNumberInput('Z', _zCtrl)),
                ],
              ),
              const SizedBox(height: 12),
              _sectionLabel('ROTATION (Y °)'),
              const SizedBox(height: 6),
              _buildNumberInput('Y °', _rotCtrl),
              const SizedBox(height: 12),
              _sectionLabel('DIMENSIONS (cm)'),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _buildNumberInput('Width', _wCtrl)),
                  const SizedBox(width: 6),
                  Expanded(child: _buildNumberInput('Depth', _dCtrl)),
                  const SizedBox(width: 6),
                  Expanded(child: _buildNumberInput('Height', _hCtrl)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _applyPrecisePlacement,
                      child: const Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _kBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        widget.notifier.resetSelectedFurnitureTransform();
                        _syncControllersFromFurniture();
                        SnackbarManager.showSuccess(context, 'Transform reset.');
                      },
                      child: const Text('Reset', style: TextStyle(color: _kTextSecondary)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── 4. Material Card ─────────────────────────────────────────────────
        _CollapsibleCard(
          title: 'Material',
          icon: Icons.texture,
          initiallyExpanded: true,
          child: MaterialEditorPanel(
            targetType: 'furniture',
            targetId: f.id,
            designerNotifier: widget.notifier,
          ),
        ),

        // ── 5. Appearance Card ──────────────────────────────────────────────
        _CollapsibleCard(
          title: 'Appearance',
          icon: Icons.palette,
          initiallyExpanded: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionLabel('COLOR'),
              const SizedBox(height: 8),
              _buildColorRow(f),
              const SizedBox(height: 14),
              _buildSimpleSlider(
                label: 'Opacity',
                value: f.opacity,
                min: 0.0,
                max: 1.0,
                color: Colors.purple.shade300,
                onChanged: (v) =>
                    widget.notifier.updateSelectedFurnitureMaterial(opacity: v),
              ),
              const SizedBox(height: 14),
              _buildLockVisibilityRow(f),
            ],
          ),
        ),

        // ── 6. Actions Card ───────────────────────────────────────────────
        _CollapsibleCard(
          title: 'Actions',
          icon: Icons.bolt,
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.copy_all, size: 14),
                        label: const Text('Duplicate', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kSurface,
                          foregroundColor: _kTextPrimary,
                          elevation: 0,
                          side: const BorderSide(color: _kBorder, width: 1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () {
                          widget.notifier.duplicateSelectedFurniture();
                          SnackbarManager.showSuccess(context, 'Furniture duplicated.');
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.restart_alt, size: 14),
                        label: const Text('Reset', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kSurface,
                          foregroundColor: _kTextPrimary,
                          elevation: 0,
                          side: const BorderSide(color: _kBorder, width: 1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () {
                          widget.notifier.resetSelectedFurnitureTransform();
                          _syncControllersFromFurniture();
                          SnackbarManager.showSuccess(context, 'Transform reset.');
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Auto-Place / Collision Resolution
              SizedBox(
                width: double.infinity,
                height: 36,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.auto_fix_high, size: 14, color: Colors.tealAccent),
                  label: const Text('Auto-Place / Resolve Collision', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E).withOpacity(0.35),
                    foregroundColor: Colors.tealAccent,
                    elevation: 0,
                    side: const BorderSide(color: Color(0xFF0F766E), width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () {
                    final success = widget.notifier.findValidPositionForSelected();
                    if (success) {
                      _syncControllersFromFurniture();
                      SnackbarManager.showSuccess(context, 'Valid collision-free position found & applied!');
                    } else {
                      SnackbarManager.showError(context, 'Could not find nearby non-colliding location.');
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              // Alignment controls
              _sectionLabel('ALIGNMENT & LAYERING'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildActionButton(Icons.align_horizontal_left, 'Left', () {
                    widget.notifier.alignSelectedFurniture(AlignmentType.left);
                  }),
                  _buildActionButton(Icons.align_horizontal_center, 'Center X', () {
                    widget.notifier.alignSelectedFurniture(AlignmentType.centerX);
                  }),
                  _buildActionButton(Icons.align_horizontal_right, 'Right', () {
                    widget.notifier.alignSelectedFurniture(AlignmentType.right);
                  }),
                  _buildActionButton(Icons.align_vertical_top, 'Top', () {
                    widget.notifier.alignSelectedFurniture(AlignmentType.top);
                  }),
                  _buildActionButton(Icons.align_vertical_center, 'Center Z', () {
                    widget.notifier.alignSelectedFurniture(AlignmentType.centerZ);
                  }),
                  _buildActionButton(Icons.align_vertical_bottom, 'Bottom', () {
                    widget.notifier.alignSelectedFurniture(AlignmentType.bottom);
                  }),
                  _buildActionButton(Icons.flip_to_front, 'Front', () {
                    widget.notifier.bringSelectedFurnitureToFront();
                    SnackbarManager.showSuccess(context, 'Moved object to front layer');
                  }),
                  _buildActionButton(Icons.flip_to_back, 'Back', () {
                    widget.notifier.sendSelectedFurnitureToBack();
                    SnackbarManager.showSuccess(context, 'Moved object to back layer');
                  }),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 36,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 14),
                  label: const Text('Delete Object', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D1515),
                    foregroundColor: Colors.redAccent,
                    elevation: 0,
                    side: const BorderSide(color: Color(0xFF5C2020), width: 1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onPressed: widget.onDelete,
                ),
              ),
            ],
          ),
        ),

        // ── 7. Smart Alternatives Card ────────────────────────────────────
        _CollapsibleCard(
          title: 'Smart Alternatives',
          icon: Icons.lightbulb_outline,
          initiallyExpanded: true,
          child: Builder(
            builder: (context) {
              final currentFootprint = f.width * f.depth;
              final alternatives = assets
                  .where((a) =>
                      a.category.toLowerCase() == category.toLowerCase() &&
                      a.id != f.assetId &&
                      (a.width * a.depth) <= currentFootprint)
                  .toList()
                ..sort((a, b) =>
                    (b.width * b.depth).compareTo(a.width * a.depth));

              if (alternatives.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No smaller alternatives in this category.',
                    style: TextStyle(color: _kTextSecondary, fontSize: 11),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: alternatives.take(3).map((alt) {
                  final altFootprint = alt.width * alt.depth;
                  final areaPctDiff = (((currentFootprint - altFootprint) / currentFootprint) * 100).round();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alt.name,
                                style: const TextStyle(
                                  color: _kTextPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${alt.width.round()} × ${alt.depth.round()} cm  (-$areaPctDiff% area)',
                                style: const TextStyle(
                                  color: Colors.tealAccent,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 28,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: _kAccent),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            onPressed: () {
                              widget.notifier.pushUndo();
                              final updated = widget.notifier.state.furniture.map<PlacedFurniture>((item) {
                                if (item.id == f.id) {
                                  return item.copyWith(
                                    assetId: alt.id,
                                    name: alt.name,
                                    width: alt.width,
                                    depth: alt.depth,
                                    height: alt.height,
                                  );
                                }
                                return item;
                              }).toList();
                              widget.notifier.state = widget.notifier.state.copyWith(furniture: updated);
                              _syncControllersFromFurniture();
                              SnackbarManager.showSuccess(context, 'Swapped to ${alt.name}');
                            },
                            child: const Text('Swap', style: TextStyle(color: _kAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }


  // ── Sub-builders ──────────────────────────────────────────────────────────

  Widget _buildReadOnlyInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 10)),
        Text(value, style: const TextStyle(color: _kTextPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildRotationPresetButton(String label, VoidCallback onTap) {
    return SizedBox(
      height: 32,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: _kBorder),
          backgroundColor: _kSurface,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: const TextStyle(color: _kTextPrimary, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return SizedBox(
      height: 30,
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 12, color: _kAccent),
        label: Text(label, style: const TextStyle(color: _kTextPrimary, fontSize: 10, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: _kBorder),
          backgroundColor: _kSurface,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildDimensionRow(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 11)),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, size: 18, color: _kTextSecondary),
          onPressed: () => onChanged((value - 5.0).clamp(10.0, 1000.0)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _kBorder),
            ),
            child: Text(
              '${value.round()} cm',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kTextPrimary, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, size: 18, color: _kAccent),
          onPressed: () => onChanged((value + 5.0).clamp(10.0, 1000.0)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _buildNumberInput(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 9)),
        const SizedBox(height: 2),
        SizedBox(
          height: 34,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            style: const TextStyle(color: _kTextPrimary, fontSize: 11, fontFamily: 'monospace'),
            decoration: InputDecoration(
              filled: true,
              fillColor: _kSurface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _kAccent)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLockVisibilityRow(PlacedFurniture f) {
    return Row(
      children: [
        Expanded(
          child: _buildToggleButton(
            icon: f.isLocked ? Icons.lock : Icons.lock_open_outlined,
            label: f.isLocked ? 'Locked' : 'Unlocked',
            active: f.isLocked,
            activeColor: Colors.amber,
            onTap: () => widget.notifier.toggleSelectedFurnitureLock(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildToggleButton(
            icon: f.isVisible ? Icons.visibility : Icons.visibility_off_outlined,
            label: f.isVisible ? 'Visible' : 'Hidden',
            active: !f.isVisible,
            activeColor: Colors.redAccent,
            inactiveColor: _kAccent,
            onTap: () => widget.notifier.toggleSelectedFurnitureVisibility(),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleButton({
    required IconData icon,
    required String label,
    required bool active,
    required Color activeColor,
    Color inactiveColor = _kTextSecondary,
    required VoidCallback onTap,
  }) {
    final color = active ? activeColor : inactiveColor;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? activeColor.withOpacity(0.12) : _kSurfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? activeColor.withOpacity(0.5) : _kBorder,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }





  static const _colorPresets = [
    ('Cream',   'E0D2BC'),
    ('Walnut',  '8B5A2B'),
    ('Charcoal','4A4A4A'),
    ('White',   'FFFFFF'),
    ('Navy',    '2E5B82'),
    ('Red',     'C0392B'),
    ('Gold',    'F1C40F'),
    ('Sage',    '7F9972'),
    ('Slate',   '607D8B'),
    ('Blush',   'E8A598'),
  ];

  Widget _buildColorRow(PlacedFurniture f) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ..._colorPresets.map((entry) {
              final (name, hex) = entry;
              final isSelected = f.materialColor == hex;
              return Tooltip(
                message: name,
                child: GestureDetector(
                  onTap: () => widget.notifier
                      .updateSelectedFurnitureMaterial(color: hex),
                  child: AnimatedContainer(
                     duration: const Duration(milliseconds: 150),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _hexToColor(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : _kBorder,
                        width: isSelected ? 2.5 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                  color: _hexToColor(hex).withOpacity(0.6),
                                  blurRadius: 5)
                            ]
                          : [],
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 10, color: Colors.black54)
                        : null,
                  ),
                ),
              );
            }),
            // Custom picker button
            GestureDetector(
              onTap: () => _showCustomColorPicker(f),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _kBorder),
                  gradient: const SweepGradient(colors: [
                    Color(0xFFFF0000),
                    Color(0xFFFF8000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ]),
                ),
                child: const Icon(Icons.add, size: 10, color: Colors.white),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSimpleSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: const TextStyle(color: _kTextSecondary, fontSize: 10)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 9),
              activeTrackColor: color,
              inactiveTrackColor: _kBorder,
              thumbColor: color,
              overlayColor: color.withOpacity(0.15),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style:
                const TextStyle(color: _kAccent, fontSize: 9, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ── Custom color picker dialog ─────────────────────────────────────────────

  void _showCustomColorPicker(PlacedFurniture f) {
    Color pickedColor =
        _hexToColor(f.materialColor, fallback: AppTheme.primary);
    final hexCtrl = TextEditingController(
        text: f.materialColor ?? '00BFA5');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurfaceElevated,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.colorize, color: _kAccent),
          SizedBox(width: 8),
          Text('Custom Color',
              style: TextStyle(color: _kTextPrimary, fontSize: 14)),
        ]),
        content: StatefulBuilder(
          builder: (_, setS) => SizedBox(
            width: 260,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Preview swatch
                Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    color: pickedColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kBorder),
                  ),
                ),
                const SizedBox(height: 14),

                // Hue slider
                _buildColorSlider(
                  label: 'Hue',
                  value: HSVColor.fromColor(pickedColor).hue,
                  min: 0,
                  max: 360,
                  gradient: const LinearGradient(colors: [
                    Color(0xFFFF0000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ]),
                  onChanged: (v) {
                    final hsv = HSVColor.fromColor(pickedColor);
                    pickedColor = hsv.withHue(v).toColor();
                    final r = pickedColor.red.toRadixString(16).padLeft(2, '0');
                    final g = pickedColor.green.toRadixString(16).padLeft(2, '0');
                    final b = pickedColor.blue.toRadixString(16).padLeft(2, '0');
                    hexCtrl.text = '$r$g$b'.toUpperCase();
                    setS(() {});
                  },
                ),
                // Saturation slider
                _buildColorSlider(
                  label: 'Sat.',
                  value: HSVColor.fromColor(pickedColor).saturation,
                  min: 0,
                  max: 1,
                  gradient: LinearGradient(colors: [
                    Colors.white,
                    HSVColor.fromColor(pickedColor)
                        .withSaturation(1)
                        .toColor(),
                  ]),
                  onChanged: (v) {
                    final hsv = HSVColor.fromColor(pickedColor);
                    pickedColor = hsv.withSaturation(v).toColor();
                    setS(() {});
                  },
                ),
                // Brightness slider
                _buildColorSlider(
                  label: 'Bri.',
                  value: HSVColor.fromColor(pickedColor).value,
                  min: 0,
                  max: 1,
                  gradient: LinearGradient(colors: [
                    Colors.black,
                    HSVColor.fromColor(pickedColor).withValue(1).toColor(),
                  ]),
                  onChanged: (v) {
                    final hsv = HSVColor.fromColor(pickedColor);
                    pickedColor = hsv.withValue(v).toColor();
                    setS(() {});
                  },
                ),

                const SizedBox(height: 8),
                // Hex input
                TextField(
                  controller: hexCtrl,
                  style: const TextStyle(
                      color: _kTextPrimary, fontSize: 12, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    prefixText: '#  ',
                    prefixStyle: const TextStyle(
                        color: _kTextSecondary, fontSize: 12),
                    hintText: 'RRGGBB',
                    hintStyle: const TextStyle(color: _kTextSecondary),
                    filled: true,
                    fillColor: _kSurface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _kBorder)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _kBorder)),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onChanged: (v) {
                    if (v.length == 6) {
                      try {
                        pickedColor =
                            Color(int.parse('FF$v', radix: 16));
                        setS(() {});
                      } catch (_) {}
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: _kTextSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final hex =
                  hexCtrl.text.toUpperCase().padRight(6, '0').substring(0, 6);
              widget.notifier.updateSelectedFurnitureMaterial(color: hex);
              Navigator.of(ctx).pop();
              if (mounted) {
                SnackbarManager.showSuccess(context, 'Color applied: #$hex');
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Widget _buildColorSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required LinearGradient gradient,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(label,
                style: const TextStyle(
                    color: _kTextSecondary, fontSize: 9)),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(gradient: gradient),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 10,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white24,
                  ),
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            color: _kAccent,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8),
      );
}

// ─── Reusable Collapsible Card Widget ────────────────────────────────────────

class _CollapsibleCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;

  const _CollapsibleCard({
    required this.title,
    required this.icon,
    required this.child,
    this.initiallyExpanded = false,
  });

  @override
  State<_CollapsibleCard> createState() => _CollapsibleCardState();
}

class _CollapsibleCardState extends State<_CollapsibleCard> with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _controller;
  late Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    if (_isExpanded) {
      _controller.value = 1.0;
    }
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _kSurfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header InkWell
          InkWell(
            onTap: _toggleExpand,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(widget.icon, color: _kAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: _kTextPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  RotationTransition(
                    turns: _controller.drive(Tween<double>(begin: 0.0, end: 0.5)),
                    child: const Icon(
                      Icons.expand_more,
                      color: _kTextSecondary,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Body content
          AnimatedBuilder(
            animation: _controller.view,
            builder: (context, child) {
              return ClipRect(
                child: Align(
                  heightFactor: _heightFactor.value,
                  child: child,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 14, right: 14, bottom: 14),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Room Materials Panel ─────────────────────────────────────────────────────
/// Shown when no furniture is selected — allows editing floor/wall/ceiling materials.
class RoomMaterialsPanel extends ConsumerStatefulWidget {
  final DesignerNotifier notifier;

  const RoomMaterialsPanel({super.key, required this.notifier});

  @override
  ConsumerState<RoomMaterialsPanel> createState() => _RoomMaterialsPanelState();
}

class _RoomMaterialsPanelState extends ConsumerState<RoomMaterialsPanel> {
  String _activeSurface = 'floor';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Surface selector tabs
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              _surfaceTab('Floor', Icons.grid_on, 'floor'),
              _surfaceTab('Wall', Icons.view_in_ar, 'wall'),
              _surfaceTab('Ceiling', Icons.roofing, 'ceiling'),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Material editor for the active surface
        _CollapsibleCard(
          title: '${_activeSurface[0].toUpperCase()}${_activeSurface.substring(1)} Material',
          icon: _activeSurface == 'floor'
              ? Icons.grid_on
              : _activeSurface == 'wall'
                  ? Icons.view_in_ar
                  : Icons.roofing,
          initiallyExpanded: true,
          child: MaterialEditorPanel(
            key: ValueKey(_activeSurface),
            targetType: _activeSurface,
            targetId: null,
            designerNotifier: widget.notifier,
          ),
        ),

        // Quick info
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kSurface.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder.withOpacity(0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.drag_indicator, color: _kTextSecondary, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Drag materials from the library directly onto any surface in the viewport.',
                  style: TextStyle(color: _kTextSecondary.withOpacity(0.8), fontSize: 10),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildLightingManagerCard(),
      ],
    );
  }

  Widget _buildLightingManagerCard() {
    return Consumer(
      builder: (context, ref, child) {
        final lightingState = ref.watch(lightingProvider);
        final lightingNotifier = ref.read(lightingProvider.notifier);

        return _CollapsibleCard(
          title: 'Lighting Manager',
          icon: Icons.lightbulb,
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (lightingState.lights.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'No light sources in the scene.',
                    style: TextStyle(color: _kTextSecondary, fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: lightingState.lights.length,
                  itemBuilder: (context, idx) {
                    final light = lightingState.lights[idx];
                    final isSel = lightingState.selectedLightId == light.id;

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: isSel ? _kAccent.withOpacity(0.15) : _kSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSel ? _kAccent : _kBorder,
                          width: 1,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          leading: Icon(
                            light.type == LightType.ambient
                                ? Icons.filter_drama_outlined
                                : light.type == LightType.directional
                                    ? Icons.wb_sunny_outlined
                                    : light.type == LightType.point
                                        ? Icons.lightbulb_outline
                                        : Icons.highlight_outlined,
                            size: 16,
                            color: isSel ? _kAccent : _kTextSecondary,
                          ),
                          title: Text(
                            light.name,
                            style: TextStyle(
                              color: isSel ? _kTextPrimary : _kTextSecondary,
                              fontSize: 12,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            '${light.type.name.toUpperCase()} • ${light.intensity.toStringAsFixed(1)}x',
                            style: TextStyle(color: _kTextSecondary.withOpacity(0.7), fontSize: 9),
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400),
                            onPressed: () {
                              lightingNotifier.deleteLight(light.id);
                              SnackbarManager.showSuccess(context, 'Light deleted');
                            },
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                          ),
                          onTap: () {
                            lightingNotifier.selectLight(light.id);
                            widget.notifier.clearSelection();
                          },
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 12),
              const Text(
                'ADD NEW LIGHT SOURCE',
                style: TextStyle(color: _kTextSecondary, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(height: 6),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 2.8,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                children: [
                  _addLightBtn(context, lightingNotifier, LightType.ambient, 'Ambient', Icons.filter_drama_outlined),
                  _addLightBtn(context, lightingNotifier, LightType.directional, 'Directional', Icons.wb_sunny_outlined),
                  _addLightBtn(context, lightingNotifier, LightType.point, 'Point Light', Icons.lightbulb_outline),
                  _addLightBtn(context, lightingNotifier, LightType.spot, 'Spot Light', Icons.highlight_outlined),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _addLightBtn(
    BuildContext context,
    LightingNotifier notifier,
    LightType type,
    String label,
    IconData icon,
  ) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 12, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: _kAccent,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () {
        notifier.addLight(type);
        SnackbarManager.showSuccess(context, 'Added $label Light source.');
      },
    );
  }

  Widget _surfaceTab(String label, IconData icon, String surface) {
    final isActive = _activeSurface == surface;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeSurface = surface),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? _kAccent.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? _kAccent.withOpacity(0.5) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 14, color: isActive ? _kAccent : _kTextSecondary),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? _kAccent : _kTextSecondary,
                  fontSize: 9,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
