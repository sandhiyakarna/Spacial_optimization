import 'dart:math';
import 'package:flutter/material.dart';
import '../../providers/furniture_placement_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PLACEMENT GHOST PAINTER — draws on the 2D canvas over the InteractiveViewer
// ─────────────────────────────────────────────────────────────────────────────
class PlacementGhostPainter extends CustomPainter {
  final FurniturePlacementState placement;

  PlacementGhostPainter({required this.placement});

  @override
  void paint(Canvas canvas, Size size) {
    final pos = placement.ghostWorldPos;
    if (pos == null) return;

    final asset = placement.draggingAsset;
    double width = 100, depth = 100;
    if (asset != null) {
      try {
        width = (asset.width as num).toDouble();
        depth = (asset.depth as num).toDouble();
      } catch (_) {}
    }

    final isValid = placement.validation.isValid;
    final ghostColor = isValid
        ? const Color(0xFF10B981) // green
        : const Color(0xFFEF4444); // red

    // ── Alignment guides ─────────────────────────────────────────────────
    final guidePaint = Paint()
      ..color = const Color(0xFF5B5BD6).withOpacity(0.6)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (final guide in placement.alignmentGuides) {
      canvas.drawLine(guide.start, guide.end, guidePaint);
    }

    // ── Shadow ───────────────────────────────────────────────────────────
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.save();
    canvas.translate(pos.dx + 4, pos.dy + 6);
    canvas.rotate(placement.ghostRotation);
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: width, height: depth),
      shadowPaint,
    );
    canvas.restore();

    // ── Ghost body ───────────────────────────────────────────────────────
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(placement.ghostRotation);

    final bodyPaint = Paint()
      ..color = ghostColor.withOpacity(0.18)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = ghostColor.withOpacity(isValid ? 0.8 : 0.95)
      ..strokeWidth = isValid ? 1.5 : 2.0
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: width,
      height: depth,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    canvas.drawRRect(rrect, bodyPaint);
    canvas.drawRRect(rrect, borderPaint);

    // ── Center crosshair ─────────────────────────────────────────────────
    final crossPaint = Paint()
      ..color = ghostColor.withOpacity(0.6)
      ..strokeWidth = 1.0;

    canvas.drawLine(
        Offset(-8, 0), const Offset(8, 0), crossPaint);
    canvas.drawLine(
        const Offset(0, -8), const Offset(0, 8), crossPaint);

    // ── Forward direction indicator ─────────────────────────────────────
    final arrowPaint = Paint()
      ..color = ghostColor.withOpacity(0.8)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
        const Offset(0, 0), Offset(0, -depth / 3), arrowPaint);

    canvas.restore();

    // ── Rotation label ───────────────────────────────────────────────────
    _drawLabel(
      canvas,
      pos + Offset(width / 2 + 8, -depth / 2),
      '${(placement.ghostRotation * 180 / pi).round()}°',
      const Color(0xFF5B5BD6),
    );

    // ── Distance to wall label ───────────────────────────────────────────
    final dist = placement.distanceToNearestWall;
    if (dist != null && dist.isFinite) {
      _drawLabel(
        canvas,
        pos + Offset(-width / 2 - 8, depth / 2 + 12),
        '${dist.round()} cm',
        const Color(0xFF94A3B8),
      );
    }

    // ── Collision / validity message ─────────────────────────────────────
    if (!isValid && placement.validation.message != null) {
      _drawLabel(
        canvas,
        pos + Offset(0, depth / 2 + 28),
        placement.validation.message!,
        const Color(0xFFEF4444),
        center: true,
      );
    }

    // ── Snap indicator ───────────────────────────────────────────────────
    if (placement.isSnapped) {
      final snapPaint = Paint()
        ..color = const Color(0xFF10B981).withOpacity(0.7)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(pos, width / 2 + 6, snapPaint);
    }
  }

  void _drawLabel(Canvas canvas, Offset pos, String text, Color color,
      {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 3,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final dx = center ? -tp.width / 2 : 0.0;
    tp.paint(canvas, pos + Offset(dx, 0));
  }

  @override
  bool shouldRepaint(PlacementGhostPainter old) =>
      old.placement.ghostWorldPos != placement.ghostWorldPos ||
      old.placement.ghostRotation != placement.ghostRotation ||
      old.placement.validation.isValid != placement.validation.isValid ||
      old.placement.alignmentGuides.length != placement.alignmentGuides.length ||
      old.placement.distanceToNearestWall !=
          placement.distanceToNearestWall;
}

// ─────────────────────────────────────────────────────────────────────────────
//  ASSET DRAG FEEDBACK — shown while dragging from library panel
// ─────────────────────────────────────────────────────────────────────────────
class AssetDragFeedback extends StatelessWidget {
  final String assetName;
  final String? category;
  final bool isDark;

  const AssetDragFeedback({
    super.key,
    required this.assetName,
    this.category,
    this.isDark = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.90,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 130),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F766E),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F766E).withOpacity(0.45),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chair_outlined, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assetName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    if (category != null)
                      Text(
                        category!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 9,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SNAP MODE INDICATOR CHIP
// ─────────────────────────────────────────────────────────────────────────────
class SnapModeChip extends StatelessWidget {
  final SnapMode mode;
  final VoidCallback onTap;

  const SnapModeChip({super.key, required this.mode, required this.onTap});

  static final _labels = {
    SnapMode.none: 'No Snap',
    SnapMode.grid: 'Grid',
    SnapMode.wall: 'Wall',
    SnapMode.corner: 'Corner',
    SnapMode.surface: 'Surface',
  };

  static final _icons = {
    SnapMode.none: Icons.close,
    SnapMode.grid: Icons.grid_on,
    SnapMode.wall: Icons.border_outer,
    SnapMode.corner: Icons.crop_free,
    SnapMode.surface: Icons.layers_outlined,
  };

  @override
  Widget build(BuildContext context) {
    const active = Color(0xFF0F766E);
    final label = _labels[mode] ?? 'Grid';
    final icon = _icons[mode] ?? Icons.grid_on;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active.withOpacity(0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: active),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
                color: Color(0xFFF8FAFC),
                fontSize: 10,
                fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PLACEMENT TOOLBAR — shown when furniture is selected
// ─────────────────────────────────────────────────────────────────────────────
class PlacementToolbar extends StatelessWidget {
  final String furnitureId;
  final String furnitureName;
  final VoidCallback onMove;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onScale;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onReplaceMaterial;
  final VoidCallback onCenterCamera;

  const PlacementToolbar({
    super.key,
    required this.furnitureId,
    required this.furnitureName,
    required this.onMove,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onScale,
    required this.onDuplicate,
    required this.onDelete,
    required this.onReplaceMaterial,
    required this.onCenterCamera,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111827).withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Selected furniture name
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.chair_outlined,
                    color: Color(0xFF0F766E), size: 12),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Text(
                    furnitureName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFF8FAFC),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _btn(Icons.open_with_rounded, 'Move', onMove),
              _btn(Icons.rotate_left_rounded, 'Rot -', onRotateLeft),
              _btn(Icons.rotate_right_rounded, 'Rot +', onRotateRight),
              _btn(Icons.zoom_out_map_rounded, 'Scale', onScale),
              _sep(),
              _btn(Icons.copy_rounded, 'Copy', onDuplicate),
              _btn(Icons.palette_outlined, 'Mat', onReplaceMaterial),
              _btn(Icons.center_focus_strong_outlined, 'Focus',
                  onCenterCamera),
              _sep(),
              _btn(Icons.delete_outline_rounded, 'Delete', onDelete,
                  danger: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap,
      {bool danger = false}) {

    final iconColor = danger ? const Color(0xFFEF4444) : const Color(0xFF94A3B8);
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 7.5,
                  color: danger ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sep() => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: const Color(0xFF334155),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  COLLISION WARNING TOAST  (shown inline in viewport)
// ─────────────────────────────────────────────────────────────────────────────
class CollisionWarningBanner extends StatelessWidget {
  final String message;

  const CollisionWarningBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withOpacity(0.3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_rounded, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
