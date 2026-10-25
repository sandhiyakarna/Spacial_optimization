import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/designer_provider.dart';

const _kSurfaceElevated = Color(0xFF1E293B);
const _kBorder = Color(0xFF334155);
const _kAccent = Color(0xFF0F766E);
const _kTextPrimary = Color(0xFFF8FAFC);
const _kTextSecondary = Color(0xFF94A3B8);

class MobileFurnitureSheet extends ConsumerWidget {
  final PlacedFurniture furniture;
  final DesignerNotifier notifier;
  final String activeTransformTool;
  final ValueChanged<String> onChangeTransformTool;
  final VoidCallback onOpenPrecisePlacement;

  const MobileFurnitureSheet({
    super.key,
    required this.furniture,
    required this.notifier,
    required this.activeTransformTool,
    required this.onChangeTransformTool,
    required this.onOpenPrecisePlacement,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: _kSurfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: _kBorder, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar indicator
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Furniture Name & Dimensions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        furniture.name,
                        style: const TextStyle(
                          color: _kTextPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${furniture.width.round()} × ${furniture.depth.round()} × ${furniture.height.round()} cm',
                        style: const TextStyle(
                          color: _kTextSecondary,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: _kTextSecondary, size: 20),
                  onPressed: () => notifier.deselectFurniture(),
                  tooltip: 'Deselect',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Primary action buttons (Move, Rotate, Scale, Duplicate, Delete)
            Row(
              children: [
                _buildActionButton(
                  icon: Icons.open_with,
                  label: 'Move',
                  isActive: activeTransformTool == 'move',
                  onTap: () => onChangeTransformTool('move'),
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  icon: Icons.rotate_right,
                  label: 'Rotate',
                  isActive: activeTransformTool == 'rotate',
                  onTap: () => onChangeTransformTool('rotate'),
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  icon: Icons.zoom_out_map,
                  label: 'Size',
                  isActive: activeTransformTool == 'scale',
                  onTap: () => onChangeTransformTool('scale'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildActionButton(
                  icon: Icons.copy,
                  label: 'Duplicate',
                  isActive: false,
                  onTap: () => notifier.duplicateSelectedFurniture(),
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  isActive: false,
                  isDanger: true,
                  onTap: () => notifier.deleteSelected(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Precise Placement button link
            InkWell(
              onTap: onOpenPrecisePlacement,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kBorder),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune, color: _kAccent, size: 18),
                        SizedBox(width: 10),
                        Text(
                          'Precise Placement',
                          style: TextStyle(
                            color: _kTextPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Icon(Icons.chevron_right, color: _kTextSecondary, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    final bg = isActive
        ? _kAccent
        : (isDanger ? const Color(0xFF7F1D1D) : const Color(0xFF0F172A));
    final fg = isActive
        ? Colors.white
        : (isDanger ? const Color(0xFFEF4444) : _kTextPrimary);

    return Expanded(
      child: SizedBox(
        height: 48, // Touch target >= 44px
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18, color: fg),
          label: Text(
            isActive ? '$label ✓' : label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: bg,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: isActive ? _kAccent : _kBorder),
            ),
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
