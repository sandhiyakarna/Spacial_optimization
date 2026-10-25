import '../../../app/themes/app_theme.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import '../providers/designer_provider.dart';
import '../providers/validation_provider.dart';

class DesignerPainter extends CustomPainter {
  final DesignerLayoutState layout;
  final ValidationState? validationState;
  final bool showGrid;
  final bool showMeasurements;
  final bool showFurnitureLabels;
  final bool showDoors;
  final bool showWindows;

  DesignerPainter({
    required this.layout,
    this.validationState,
    this.showGrid = true,
    this.showMeasurements = true,
    this.showFurnitureLabels = true,
    this.showDoors = true,
    this.showWindows = true,
  });

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

  void _drawWalkwayOverlay(Canvas canvas) {
    if (layout.walls.isEmpty) return;

    // Find bounding box of walls to draw walkway grid inside the room area
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final wall in layout.walls) {
      minX = min(minX, min(wall.start.dx, wall.end.dx));
      maxX = max(maxX, max(wall.start.dx, wall.end.dx));
      minY = min(minY, min(wall.start.dy, wall.end.dy));
      maxY = max(maxY, max(wall.start.dy, wall.end.dy));
    }

    if (minX == double.infinity) return;

    minX -= 20.0;
    maxX += 20.0;
    minY -= 20.0;
    maxY += 20.0;

    final dotPaint = Paint()
      ..color = Colors.green.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    const double cellSize = 20.0;

    for (double x = minX; x <= maxX; x += cellSize) {
      for (double y = minY; y <= maxY; y += cellSize) {
        bool collides = false;
        
        // Collide with furniture
        for (final f in layout.furniture) {
          final rot = f.rotationY;
          final cosR = cos(rot).abs();
          final sinR = sin(rot).abs();
          final w = f.width * cosR + f.depth * sinR;
          final d = f.width * sinR + f.depth * cosR;
          final left = f.x - w / 2;
          final right = f.x + w / 2;
          final top = f.z - d / 2;
          final bottom = f.z + d / 2;

          if (x >= left && x <= right && y >= top && y <= bottom) {
            collides = true;
            break;
          }
        }
        if (collides) continue;

        // Collide with wall lines
        for (final wall in layout.walls) {
          final dist = _distanceToSegment(Offset(x, y), wall.start, wall.end);
          if (dist < wall.thickness / 2 + 12.0) {
            collides = true;
            break;
          }
        }

        if (!collides) {
          canvas.drawCircle(Offset(x, y), 2.0, dotPaint);
        }
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Grid (only when showGrid is true)
    if (showGrid) {
      final minorGridPaint = Paint()
        ..color = AppTheme.primary.withOpacity(0.03)
        ..strokeWidth = 1.0;

      final majorGridPaint = Paint()
        ..color = AppTheme.primary.withOpacity(0.1)
        ..strokeWidth = 1.5;

      final double spacing = layout.gridSpacing;
      final double majorSpacing = spacing * 5;

      const double minBound = -10000.0;
      const double maxBound = 10000.0;

      for (double x = minBound; x <= maxBound; x += spacing) {
        if ((x / majorSpacing).round() * majorSpacing != x) {
          canvas.drawLine(Offset(x, minBound), Offset(x, maxBound), minorGridPaint);
        }
      }
      for (double y = minBound; y <= maxBound; y += spacing) {
        if ((y / majorSpacing).round() * majorSpacing != y) {
          canvas.drawLine(Offset(minBound, y), Offset(maxBound, y), minorGridPaint);
        }
      }

      for (double x = minBound; x <= maxBound; x += majorSpacing) {
        canvas.drawLine(Offset(x, minBound), Offset(x, maxBound), majorGridPaint);
      }
      for (double y = minBound; y <= maxBound; y += majorSpacing) {
        canvas.drawLine(Offset(minBound, y), Offset(maxBound, y), majorGridPaint);
      }
    }

    // 2. Draw Walkway Overlay
    _drawWalkwayOverlay(canvas);

    // 3. Draw Wall Highlights
    final wallHighlightPaint = Paint()
      ..color = Colors.orange.withOpacity(0.3)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < layout.walls.length; i++) {
      if (layout.selectedWallIndex == i) {
        final wall = layout.walls[i];
        wallHighlightPaint.strokeWidth = wall.thickness + 10.0;
        canvas.drawLine(wall.start, wall.end, wallHighlightPaint);
      }
    }

    // 4. Draw Walls
    final wallPaint = Paint()
      ..color = AppTheme.primary.shade800
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final vertexPaint = Paint()
      ..color = AppTheme.primary.shade900
      ..style = PaintingStyle.fill;

    final selectedVertexPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.fill;

    for (int i = 0; i < layout.walls.length; i++) {
      final wall = layout.walls[i];
      wallPaint.strokeWidth = wall.thickness;
      canvas.drawLine(wall.start, wall.end, wallPaint);

      final isStartSelected = layout.selectedWallEndpointId == "${i}_start";
      final isEndSelected = layout.selectedWallEndpointId == "${i}_end";

      canvas.drawCircle(wall.start, isStartSelected ? 8.0 : 6.0, isStartSelected ? selectedVertexPaint : vertexPaint);
      canvas.drawCircle(wall.end, isEndSelected ? 8.0 : 6.0, isEndSelected ? selectedVertexPaint : vertexPaint);
    }

    // 5. Draw Openings (Doors & Windows)
    for (final op in layout.openings) {
      if (op.type == 'door' && !showDoors) continue;
      if (op.type == 'window' && !showWindows) continue;
      final isSelected = layout.selectedOpeningId == op.id;

      // Check if opening is blocked based on validation results
      bool isBlocked = false;
      if (validationState != null) {
        final searchType = op.type.toLowerCase();
        isBlocked = validationState!.errors.any((e) => e.message.toLowerCase().contains(searchType)) ||
                    validationState!.warnings.any((e) => e.message.toLowerCase().contains(searchType));
      }

      canvas.save();
      canvas.translate(op.position.dx, op.position.dy);
      canvas.rotate(op.angle);

      final double w = op.width;
      final double halfW = w / 2;

      if (op.type == 'door') {
        // Draw swing area overlay
        final Rect swingRect = Rect.fromCircle(center: Offset(-halfW, 0), radius: w);
        if (isBlocked) {
          final blockPaint = Paint()
            ..color = Colors.red.withOpacity(0.22)
            ..style = PaintingStyle.fill;
          canvas.drawArc(swingRect, -pi / 2, pi / 2, true, blockPaint);
        } else {
          final clearSwingPaint = Paint()
            ..color = Colors.teal.withOpacity(0.06)
            ..style = PaintingStyle.fill;
          canvas.drawArc(swingRect, -pi / 2, pi / 2, true, clearSwingPaint);
        }

        final framePaint = Paint()
          ..color = isBlocked 
              ? Colors.red.shade600 
              : (isSelected ? Colors.orange : Colors.brown.shade700)
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke;

        canvas.drawLine(Offset(-halfW, 0), Offset(halfW, 0), framePaint);
        canvas.drawLine(Offset(-halfW, 0), Offset(-halfW, -w), framePaint);
        
        final arcPaint = Paint()
          ..color = isBlocked 
              ? Colors.red.shade700 
              : (isSelected ? Colors.orange : Colors.teal.shade700.withOpacity(0.6))
          ..strokeWidth = isBlocked ? 2.4 : 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawArc(swingRect, -pi / 2, pi / 2, false, arcPaint);
      } else {
        // Draw window clearance zone overlay if blocked
        if (isBlocked) {
          final blockPaint = Paint()
            ..color = Colors.orange.withOpacity(0.15)
            ..style = PaintingStyle.fill;
          canvas.drawRect(Rect.fromLTRB(-halfW, -30.0, halfW, 30.0), blockPaint);
        }

        final panePaint = Paint()
          ..color = isBlocked 
              ? Colors.red.shade100 
              : (isSelected ? Colors.orange.shade100 : Colors.blue.shade100)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.fill;

        final borderPaint = Paint()
          ..color = isBlocked 
              ? Colors.red.shade700 
              : (isSelected ? Colors.orange : Colors.blue.shade900)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

        final Rect winRect = Rect.fromLTRB(-halfW, -6.0, halfW, 6.0);
        canvas.drawRect(winRect, panePaint);
        canvas.drawRect(winRect, borderPaint);
        canvas.drawLine(Offset(-halfW, 0), Offset(halfW, 0), borderPaint);
      }

      if (isSelected) {
        final selectRingPaint = Paint()
          ..color = Colors.orange.withOpacity(0.2)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset.zero, halfW + 10, selectRingPaint);
      }

      canvas.restore();
    }

      // 6. Draw Placed Furniture & Architectural Symbols (2D Floor Plan)
      for (final f in layout.furniture) {
        final isSelected = layout.selectedFurnitureId == f.id || layout.selectedFurnitureIds.contains(f.id);
        
        bool isInvalid = false;
        if (validationState != null) {
          isInvalid = validationState!.errors.any((e) => e.affectedFurnitureIds.contains(f.id)) ||
                      validationState!.warnings.any((e) => e.affectedFurnitureIds.contains(f.id));
        }

        final double w = f.width;
        final double d = f.depth;
        final String nameLower = (f.name + " " + f.assetId).toLowerCase();

        // 6a. Draw Clearance Zone (Yellow / Orange translucent overlay)
        final clearancePaint = Paint()
          ..color = Colors.amber.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill;
        final clearanceBorder = Paint()
          ..color = Colors.amber.shade700.withValues(alpha: 0.3)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

        canvas.save();
        canvas.translate(f.x, f.z);
        canvas.rotate(f.rotationY);

        if (nameLower.contains('bed')) {
          // 60cm bedside & front clearance zone
          final Rect clRect = Rect.fromLTRB(-w / 2 - 40.0, -d / 2, w / 2 + 40.0, d / 2 + 60.0);
          canvas.drawRRect(RRect.fromRectAndRadius(clRect, const Radius.circular(8.0)), clearancePaint);
          canvas.drawRRect(RRect.fromRectAndRadius(clRect, const Radius.circular(8.0)), clearanceBorder);
        } else if (nameLower.contains('desk')) {
          // 80cm chair pullout clearance zone in front
          final Rect clRect = Rect.fromLTRB(-w / 2, -d / 2, w / 2, d / 2 + 80.0);
          canvas.drawRect(clRect, clearancePaint);
          canvas.drawRect(clRect, clearanceBorder);
        } else if (nameLower.contains('wardrobe') || nameLower.contains('cabinet')) {
          // 80cm front clearance zone
          final Rect clRect = Rect.fromLTRB(-w / 2, -d / 2, w / 2, d / 2 + 80.0);
          canvas.drawRect(clRect, clearancePaint);
          canvas.drawRect(clRect, clearanceBorder);
        }

        // 6b. Main Furniture Base
        final fillPaint = Paint()
          ..color = isInvalid 
              ? Colors.red.shade50.withValues(alpha: 0.9 * f.opacity)
              : (isSelected ? AppTheme.primary.shade50.withValues(alpha: 0.9 * f.opacity) : Colors.grey.shade100.withValues(alpha: 0.9 * f.opacity))
          ..style = PaintingStyle.fill;

        final borderPaint = Paint()
          ..color = (isInvalid 
              ? Colors.red.shade600 
              : (isSelected ? AppTheme.primary.shade700 : Colors.grey.shade700)).withValues(alpha: f.opacity)
          ..strokeWidth = isSelected || isInvalid ? 2.5 : 1.5
          ..style = PaintingStyle.stroke;

        final detailPaint = Paint()
          ..color = (isInvalid ? Colors.red.shade800 : Colors.grey.shade800).withValues(alpha: f.opacity)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;

        final Rect rect = Rect.fromCenter(center: Offset.zero, width: w, height: d);

        // Draw main body box
        canvas.drawRect(rect, fillPaint);

        if (isInvalid) {
          final dashPaint = Paint()
            ..color = Colors.red.shade600.withValues(alpha: f.opacity)
            ..strokeWidth = 2.5
            ..style = PaintingStyle.stroke;
          const double dashWidth = 6.0;
          const double dashSpace = 4.0;
          for (double dx = -w / 2; dx < w / 2; dx += dashWidth + dashSpace) {
            canvas.drawLine(Offset(dx, -d / 2), Offset(min(dx + dashWidth, w / 2), -d / 2), dashPaint);
            canvas.drawLine(Offset(dx, d / 2), Offset(min(dx + dashWidth, w / 2), d / 2), dashPaint);
          }
          for (double dy = -d / 2; dy < d / 2; dy += dashWidth + dashSpace) {
            canvas.drawLine(Offset(-w / 2, dy), Offset(-w / 2, min(dy + dashWidth, d / 2)), dashPaint);
            canvas.drawLine(Offset(w / 2, dy), Offset(w / 2, min(dy + dashWidth, d / 2)), dashPaint);
          }
        } else {
          canvas.drawRect(rect, borderPaint);
        }

        // 6c. Top-Down Architectural Symbols
        if (nameLower.contains('bed')) {
          // Headboard at -d/2
          canvas.drawRect(Rect.fromLTRB(-w / 2, -d / 2, w / 2, -d / 2 + 12.0), detailPaint);
          // Pillows
          final pillowW = min(w * 0.35, 60.0);
          final pillowH = min(d * 0.2, 35.0);
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-w / 2 + 10.0, -d / 2 + 16.0, pillowW, pillowH), const Radius.circular(4.0)), detailPaint);
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w / 2 - 10.0 - pillowW, -d / 2 + 16.0, pillowW, pillowH), const Radius.circular(4.0)), detailPaint);
          // Mattress fold line
          canvas.drawLine(Offset(-w / 2 + 5.0, d / 4), Offset(w / 2 - 5.0, d / 4), detailPaint);
        } else if (nameLower.contains('sofa') || nameLower.contains('couch')) {
          // Backrest at -d/2
          canvas.drawRect(Rect.fromLTRB(-w / 2, -d / 2, w / 2, -d / 2 + 16.0), detailPaint);
          // Left and right armrests
          canvas.drawRect(Rect.fromLTRB(-w / 2, -d / 2, -w / 2 + 14.0, d / 2), detailPaint);
          canvas.drawRect(Rect.fromLTRB(w / 2 - 14.0, -d / 2, w / 2, d / 2), detailPaint);
          // Seat cushion split lines
          canvas.drawLine(Offset(0.0, -d / 2 + 16.0), Offset(0.0, d / 2), detailPaint);
        } else if (nameLower.contains('table')) {
          // Inner perimeter border / table edge detail
          canvas.drawRect(Rect.fromLTRB(-w / 2 + 8.0, -d / 2 + 8.0, w / 2 - 8.0, d / 2 - 8.0), detailPaint);
        } else if (nameLower.contains('desk')) {
          // Drawer divider line
          canvas.drawLine(Offset(-w / 2 + 30.0, -d / 2), Offset(-w / 2 + 30.0, d / 2), detailPaint);
          // Computer screen outline
          canvas.drawRect(Rect.fromCenter(center: const Offset(0.0, -10.0), width: min(w * 0.5, 50.0), height: 8.0), detailPaint);
        } else if (nameLower.contains('wardrobe') || nameLower.contains('cabinet')) {
          // Double door split line
          canvas.drawLine(Offset(0.0, -d / 2), Offset(0.0, d / 2), detailPaint);
          // Coat hanger / shelf lines
          canvas.drawLine(Offset(-w / 2 + 10.0, 0.0), Offset(w / 2 - 10.0, 0.0), detailPaint);
        } else if (nameLower.contains('counter') || nameLower.contains('sink') || nameLower.contains('kitchen')) {
          // Countertop inner border line
          canvas.drawRect(Rect.fromLTRB(-w / 2 + 6.0, -d / 2 + 6.0, w / 2 - 6.0, d / 2 - 6.0), detailPaint);
          if (nameLower.contains('sink')) {
            // Double sink basins
            canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(-w / 4, 0.0), width: w * 0.35, height: d * 0.6), const Radius.circular(4.0)), detailPaint);
            canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w / 4, 0.0), width: w * 0.35, height: d * 0.6), const Radius.circular(4.0)), detailPaint);
          }
        }

        // Front directional line
        canvas.drawLine(Offset(-w / 2, d / 2), Offset(w / 2, d / 2), detailPaint);

        // Label text
        if (showFurnitureLabels && w > 35 && d > 15) {
          final textPainter = TextPainter(
            text: TextSpan(
              text: f.name,
              style: TextStyle(
                color: isInvalid 
                    ? Colors.red.shade900 
                    : (isSelected ? AppTheme.primary.shade900 : Colors.grey.shade800),
                fontSize: 9.0,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '...',
          );
          textPainter.layout(maxWidth: w - 8);
          textPainter.paint(
            canvas, 
            Offset(-textPainter.width / 2, -textPainter.height / 2),
          );
        }

        // Selection handles and dimensions badge
        if (isSelected) {
          final handlePaint = Paint()
            ..color = AppTheme.primary
            ..style = PaintingStyle.fill;
          final handleStroke = Paint()
            ..color = Colors.white
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke;
          const double hSize = 6.0;
          final corners = [
            Offset(-w / 2, -d / 2),
            Offset(w / 2, -d / 2),
            Offset(w / 2, d / 2),
            Offset(-w / 2, d / 2),
          ];
          for (final corner in corners) {
            final hRect = Rect.fromCenter(center: corner, width: hSize, height: hSize);
            canvas.drawRect(hRect, handlePaint);
            canvas.drawRect(hRect, handleStroke);
          }

          // Dimension badge above furniture
          final dimText = "${w.toInt()} × ${d.toInt()} cm";
          final dimPainter = TextPainter(
            text: TextSpan(
              text: dimText,
              style: TextStyle(
                color: Colors.white,
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                backgroundColor: AppTheme.primary.shade800.withValues(alpha: 0.85),
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          dimPainter.layout();
          dimPainter.paint(canvas, Offset(-dimPainter.width / 2, -d / 2 - dimPainter.height - 4));
        }

        // Warning marker bubble
        if (isInvalid) {
          final markerPaint = Paint()
            ..color = Colors.red.shade600
            ..style = PaintingStyle.fill;
          canvas.drawCircle(Offset(w / 2 - 8, -d / 2 + 8), 7.0, markerPaint);
          
          final iconPainter = TextPainter(
            text: const TextSpan(
              text: '!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          iconPainter.layout();
          iconPainter.paint(canvas, Offset(w / 2 - 8 - iconPainter.width / 2, -d / 2 + 8 - iconPainter.height / 2));
        }

        canvas.restore();
      }

      // 6d. Draw Attention Rings for Usability Highlight
      final highlightedId = validationState?.highlightedFurnitureId;
      if (highlightedId != null) {
        final matches = layout.furniture.where((f) => f.id == highlightedId);
        if (matches.isNotEmpty) {
          final target = matches.first;
          canvas.save();
          canvas.translate(target.x, target.z);
          canvas.rotate(target.rotationY);
          final ringPaint = Paint()
            ..color = Colors.amber.shade700
            ..strokeWidth = 3.0
            ..style = PaintingStyle.stroke;
          final glowPaint = Paint()
            ..color = Colors.amber.withOpacity(0.18)
            ..style = PaintingStyle.fill;
          final rRect = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: target.width + 16, height: target.depth + 16),
            const Radius.circular(8.0),
          );
          canvas.drawRRect(rRect, glowPaint);
          canvas.drawRRect(rRect, ringPaint);
          canvas.restore();
        }
      }

      // 6e. Draw One-Click Fix Ghost Candidate Preview
      final activeFix = validationState?.activeFixCandidate;
      if (activeFix != null && activeFix.canFix && activeFix.changes.isNotEmpty) {
        for (final change in activeFix.changes) {
          final matches = layout.furniture.where((f) => f.id == change.furnitureId);
          final target = matches.isNotEmpty ? matches.first : null;
          final double w = target?.width ?? 100.0;
          final double d = target?.depth ?? 80.0;
          final String name = target?.name ?? 'Furniture';

          // 1. Draw trajectory line and displacement from original to proposed
          final startPt = Offset(change.originalX, change.originalZ);
          final endPt = Offset(change.proposedX, change.proposedZ);
          
          final arrowLinePaint = Paint()
            ..color = Colors.green.shade700
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke;
          canvas.drawLine(startPt, endPt, arrowLinePaint);

          if (change.movementDistance > 5.0) {
            final midPt = Offset((startPt.dx + endPt.dx) / 2, (startPt.dy + endPt.dy) / 2);
            final moveBadge = TextPainter(
              text: TextSpan(
                text: ' Move ${change.movementDistance.round()} cm ',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.0,
                  fontWeight: FontWeight.bold,
                  backgroundColor: Colors.green,
                ),
              ),
              textDirection: TextDirection.ltr,
            );
            moveBadge.layout();
            moveBadge.paint(canvas, Offset(midPt.dx - moveBadge.width / 2, midPt.dy - moveBadge.height / 2));
          }

          // 2. Draw ghost box at proposed position
          canvas.save();
          canvas.translate(change.proposedX, change.proposedZ);
          canvas.rotate(change.proposedRotation);

          final ghostFill = Paint()
            ..color = Colors.greenAccent.withOpacity(0.2)
            ..style = PaintingStyle.fill;
          final ghostBorder = Paint()
            ..color = Colors.green.shade700
            ..strokeWidth = 2.5
            ..style = PaintingStyle.stroke;

          final ghostRect = Rect.fromCenter(center: Offset.zero, width: w, height: d);
          canvas.drawRect(ghostRect, ghostFill);

          const double dWidth = 6.0;
          const double dSpace = 4.0;
          for (double dx = -w / 2; dx < w / 2; dx += dWidth + dSpace) {
            canvas.drawLine(Offset(dx, -d / 2), Offset(min(dx + dWidth, w / 2), -d / 2), ghostBorder);
            canvas.drawLine(Offset(dx, d / 2), Offset(min(dx + dWidth, w / 2), d / 2), ghostBorder);
          }
          for (double dy = -d / 2; dy < d / 2; dy += dWidth + dSpace) {
            canvas.drawLine(Offset(-w / 2, dy), Offset(-w / 2, min(dy + dWidth, d / 2)), ghostBorder);
            canvas.drawLine(Offset(w / 2, dy), Offset(w / 2, min(dy + dWidth, d / 2)), ghostBorder);
          }

          final labelPainter = TextPainter(
            text: TextSpan(
              text: '✓ Proposed Safe: $name',
              style: TextStyle(
                color: Colors.green.shade900,
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          labelPainter.layout(maxWidth: w);
          labelPainter.paint(canvas, Offset(-labelPainter.width / 2, -labelPainter.height / 2));

          canvas.restore();
        }
      }

    // Draw wall measurements and overall room dimension lines
    if (showMeasurements && layout.walls.isNotEmpty) {
      double minX = double.infinity;
      double maxX = -double.infinity;
      double minY = double.infinity;
      double maxY = -double.infinity;

      for (final wall in layout.walls) {
        minX = min(minX, min(wall.start.dx, wall.end.dx));
        maxX = max(maxX, max(wall.start.dx, wall.end.dx));
        minY = min(minY, min(wall.start.dy, wall.end.dy));
        maxY = max(maxY, max(wall.start.dy, wall.end.dy));

        final length = (wall.start - wall.end).distance;
        final mid = Offset((wall.start.dx + wall.end.dx) / 2, (wall.start.dy + wall.end.dy) / 2);
        
        final dx = wall.end.dx - wall.start.dx;
        final dy = wall.end.dy - wall.start.dy;
        final angle = atan2(dy, dx);
        
        // Offset perpendicular to the wall
        final perpX = -sin(angle) * 15.0;
        final perpY = cos(angle) * 15.0;
        
        final textPainter = TextPainter(
          text: TextSpan(
            text: "${length.round()} cm",
            style: TextStyle(
              color: Colors.blueGrey.shade700,
              fontSize: 10.0,
              fontWeight: FontWeight.bold,
              backgroundColor: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        
        canvas.save();
        canvas.translate(mid.dx + perpX, mid.dy + perpY);
        canvas.rotate(angle);
        textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
        canvas.restore();
      }

      // Draw overall room dimension arrows (Top and Left boundaries)
      if (minX != double.infinity && maxX > minX && maxY > minY) {
        final roomWidth = (maxX - minX).round();
        final roomLength = (maxY - minY).round();

        // Top dimension arrow (width)
        _drawDimensionLine(
          canvas,
          Offset(minX, minY - 35.0),
          Offset(maxX, minY - 35.0),
          "$roomWidth cm",
        );

        // Left dimension arrow (length)
        _drawDimensionLine(
          canvas,
          Offset(minX - 35.0, minY),
          Offset(minX - 35.0, maxY),
          "$roomLength cm",
        );

        // Draw North Indicator
        _drawNorthArrow(canvas, Offset(maxX + 40.0, minY - 30.0));
      }
    }
  }

  void _drawNorthArrow(Canvas canvas, Offset center) {
    final circlePaint = Paint()
      ..color = Colors.indigo.shade900
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final northArrowPaint = Paint()
      ..color = Colors.red.shade700
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 18.0, circlePaint);

    final Path nPath = Path();
    nPath.moveTo(center.dx, center.dy - 16.0);
    nPath.lineTo(center.dx - 5.0, center.dy + 4.0);
    nPath.lineTo(center.dx, center.dy);
    nPath.lineTo(center.dx + 5.0, center.dy + 4.0);
    nPath.close();
    canvas.drawPath(nPath, northArrowPaint);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: "N",
        style: TextStyle(
          color: Colors.white,
          fontSize: 9.0,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy - 12.0));
  }

  void _drawDimensionLine(Canvas canvas, Offset start, Offset end, String text) {
    final paint = Paint()
      ..color = Colors.indigo.shade700
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(start, end, paint);

    final angle = atan2(end.dy - start.dy, end.dx - start.dx);
    const arrowSize = 6.0;

    canvas.drawLine(start, start + Offset(cos(angle + pi / 6) * arrowSize, sin(angle + pi / 6) * arrowSize), paint);
    canvas.drawLine(start, start + Offset(cos(angle - pi / 6) * arrowSize, sin(angle - pi / 6) * arrowSize), paint);

    canvas.drawLine(end, end - Offset(cos(angle + pi / 6) * arrowSize, sin(angle + pi / 6) * arrowSize), paint);
    canvas.drawLine(end, end - Offset(cos(angle - pi / 6) * arrowSize, sin(angle - pi / 6) * arrowSize), paint);

    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.indigo.shade900,
          fontSize: 11.0,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    canvas.save();
    canvas.translate(mid.dx, mid.dy);
    if ((end.dy - start.dy).abs() > (end.dx - start.dx).abs()) {
      canvas.rotate(-pi / 2);
    }
    textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DesignerPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.validationState != validationState ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.showMeasurements != showMeasurements ||
        oldDelegate.showFurnitureLabels != showFurnitureLabels ||
        oldDelegate.showDoors != showDoors ||
        oldDelegate.showWindows != showWindows;
  }
}
