// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/designer_provider.dart';
import '../../providers/material_provider.dart';
import '../../models/material_model.dart';
import '../../../../shared/widgets/snackbar_manager.dart';

// ─── Color palette ─────────────────────────────────────────────────────────────

const _kTextPrimary = Color(0xFFF8FAFC);
const _kTextSecondary = Color(0xFF94A3B8);

/// Drop zone target type
enum MaterialDropZone { furniture, floor, wall, ceiling }

/// Overlay that renders invisible `DragTarget<MaterialModel>` zones
/// over the 3D viewport for floor / wall / ceiling drag-drop application.
class MaterialDragOverlay extends ConsumerWidget {
  final bool isActive; // Only show when a material drag is in progress
  final String? hoveredFurnitureId;

  const MaterialDragOverlay({
    super.key,
    required this.isActive,
    this.hoveredFurnitureId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isActive) return const SizedBox.shrink();

    return Stack(
      children: [
        // Floor drop zone — bottom 30%
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: MediaQuery.of(context).size.height * 0.30,
          child: _MaterialDropZone(
            zone: MaterialDropZone.floor,
            label: 'Floor',
            icon: Icons.grid_on,
            color: const Color(0xFF0F766E),
            onDrop: (material) => _applyMaterial(context, ref, material, 'floor'),
          ),
        ),
        // Left wall zone
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          width: 80,
          child: _MaterialDropZone(
            zone: MaterialDropZone.wall,
            label: 'Wall',
            icon: Icons.view_in_ar,
            color: const Color(0xFF5B5BD6),
            onDrop: (material) => _applyMaterial(context, ref, material, 'wall'),
          ),
        ),
        // Right wall zone
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: 80,
          child: _MaterialDropZone(
            zone: MaterialDropZone.wall,
            label: 'Wall',
            icon: Icons.view_in_ar,
            color: const Color(0xFF5B5BD6),
            onDrop: (material) => _applyMaterial(context, ref, material, 'wall'),
          ),
        ),
        // Ceiling zone — top 20%
        Positioned(
          top: 0,
          left: 80,
          right: 80,
          height: 80,
          child: _MaterialDropZone(
            zone: MaterialDropZone.ceiling,
            label: 'Ceiling',
            icon: Icons.roofing,
            color: const Color(0xFFF4B740),
            onDrop: (material) => _applyMaterial(context, ref, material, 'ceiling'),
          ),
        ),
        // Center hint label
        const Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: _DragHintOverlay(),
            ),
          ),
        ),
      ],
    );
  }

  void _applyMaterial(BuildContext context, WidgetRef ref, MaterialModel material, String surface) {
    final notifier = ref.read(designerProvider.notifier);
    notifier.applyMaterialFromDrop(
      surface: surface,
      colorHex: material.baseColor?.replaceAll('#', ''),
      materialType: material.category.name.toLowerCase(),
      metallic: material.reflectivity,
      roughness: 1.0 - material.reflectivity,
      reflection: material.reflectivity,
    );
    ref.read(materialProvider.notifier).addRecentlyUsed(material.id);
    final surfaceLabel = surface[0].toUpperCase() + surface.substring(1);
    SnackbarManager.showSuccess(context, 'Applied ${material.name} to $surfaceLabel.');
  }
}

/// Individual drop zone with animated highlight feedback.
class _MaterialDropZone extends StatefulWidget {
  final MaterialDropZone zone;
  final String label;
  final IconData icon;
  final Color color;
  final ValueChanged<MaterialModel> onDrop;

  const _MaterialDropZone({
    required this.zone,
    required this.label,
    required this.icon,
    required this.color,
    required this.onDrop,
  });

  @override
  State<_MaterialDropZone> createState() => _MaterialDropZoneState();
}

class _MaterialDropZoneState extends State<_MaterialDropZone>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<MaterialModel>(
      onWillAcceptWithDetails: (_) {
        setState(() => _isHovered = true);
        return true;
      },
      onLeave: (_) => setState(() => _isHovered = false),
      onAcceptWithDetails: (details) {
        setState(() => _isHovered = false);
        widget.onDrop(details.data);
      },
      builder: (context, candidates, rejected) {
        final isOver = candidates.isNotEmpty || _isHovered;
        return AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isOver
                    ? widget.color.withOpacity(0.25)
                    : widget.color.withOpacity(_pulse.value * 0.08),
                border: Border.all(
                  color: isOver
                      ? widget.color
                      : widget.color.withOpacity(_pulse.value * 0.4),
                  width: isOver ? 2.5 : 1.5,
                ),
              ),
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isOver ? 1.0 : 0.6,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon,
                          color: isOver ? widget.color : widget.color.withOpacity(0.7),
                          size: isOver ? 20 : 16),
                      const SizedBox(height: 4),
                      Text(
                        'Drop on\n${widget.label}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isOver ? widget.color : widget.color.withOpacity(0.7),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Centered hint label shown during material drag.
class _DragHintOverlay extends StatelessWidget {
  const _DragHintOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.drag_indicator, color: Colors.white70, size: 20),
          const SizedBox(height: 6),
          const Text(
            'Drop material on a surface',
            style: TextStyle(
              color: _kTextPrimary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Floor · Wall · Ceiling · Furniture',
            style: TextStyle(color: _kTextSecondary.withOpacity(0.8), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class MaterialDragActiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setDragActive(bool active) {
    state = active;
  }
}

final materialDragActiveProvider = NotifierProvider<MaterialDragActiveNotifier, bool>(MaterialDragActiveNotifier.new);
