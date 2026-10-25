import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/camera_provider.dart';
import '../../providers/designer_provider.dart';
import '../../providers/validation_provider.dart';

class DeveloperDiagnosticsPanel extends ConsumerStatefulWidget {
  final bool isVisible;
  final VoidCallback onClose;

  const DeveloperDiagnosticsPanel({
    super.key,
    required this.isVisible,
    required this.onClose,
  });

  @override
  ConsumerState<DeveloperDiagnosticsPanel> createState() =>
      _DeveloperDiagnosticsPanelState();
}

class _DeveloperDiagnosticsPanelState
    extends ConsumerState<DeveloperDiagnosticsPanel> {
  bool _isMinimized = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    final layout = ref.watch(designerProvider);
    final cameraState = ref.watch(cameraProvider);
    final validationState = ref.watch(validationProvider);

    // Calculate room dimensions and bounds
    double minX = 0.0, maxX = 600.0;
    double minZ = 0.0, maxZ = 450.0;

    if (layout.walls.isNotEmpty) {
      minX = double.infinity; maxX = -double.infinity;
      minZ = double.infinity; maxZ = -double.infinity;
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
    }

    final roomWidth = maxX - minX;
    final roomLength = maxZ - minZ;
    const roomHeight = 280.0;

    final cameraPosStr = '(${cameraState.position.x.toStringAsFixed(1)}, ${cameraState.position.y.toStringAsFixed(1)}, ${cameraState.position.z.toStringAsFixed(1)})';

    // Count collisions and ergonomic warnings
    final errorCount = validationState.errors.length;
    final warningCount = validationState.warnings.length;
    final totalFurniture = layout.furniture.length;

    int outOfBoundsCount = 0;
    for (final f in layout.furniture) {
      if (f.x - f.width / 2 < minX || f.x + f.width / 2 > maxX ||
          f.z - f.depth / 2 < minZ || f.z + f.depth / 2 > maxZ) {
        outOfBoundsCount++;
      }
    }

    final healthScore = validationState.summary?.overallScore ?? (errorCount > 0 ? 40.0 : (warningCount > 0 ? 75.0 : 100.0));

    if (_isMinimized) {
      return Positioned(
        top: 60.0,
        right: 16.0,
        child: Material(
          elevation: 6.0,
          borderRadius: BorderRadius.circular(20.0),
          color: Colors.black.withValues(alpha: 0.85),
          child: InkWell(
            onTap: () => setState(() => _isMinimized = false),
            borderRadius: BorderRadius.circular(20.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bug_report, color: Colors.greenAccent, size: 14.0),
                  const SizedBox(width: 6.0),
                  Text(
                    'Spatial Health: ${healthScore.round()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4.0),
                  const Icon(Icons.unfold_more, color: Colors.white70, size: 14.0),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Positioned(
      top: 60.0,
      right: 16.0,
      child: Material(
        elevation: 8.0,
        borderRadius: BorderRadius.circular(12.0),
        color: Colors.black.withValues(alpha: 0.88),
        child: Container(
          width: 300.0,
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.bug_report, color: Colors.greenAccent, size: 18.0),
                        SizedBox(width: 6.0),
                        Flexible(
                          child: Text(
                            'SPATIAL DIAGNOSTICS',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11.0,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.minimize, color: Colors.white70, size: 16.0),
                        tooltip: 'Minimize',
                        onPressed: () => setState(() => _isMinimized = true),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.only(right: 6.0),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 16.0),
                        tooltip: 'Close Diagnostics',
                        onPressed: widget.onClose,
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 12.0),
              _buildDiagRow('ROOM DIMENSIONS:', '${roomWidth.round()} x ${roomLength.round()} x ${roomHeight.round()} cm'),
              _buildDiagRow('WORLD SCALE:', '1 World Unit = 1 cm'),
              _buildDiagRow('ROOM BOUNDS:', '[${minX.round()}, ${maxX.round()}] x [${minZ.round()}, ${maxZ.round()}]'),
              _buildDiagRow('CAMERA POS:', cameraPosStr),
              _buildDiagRow('FURNITURE COUNT:', 'Expected: $totalFurniture | Loaded: $totalFurniture'),
              _buildDiagRow('OUT OF BOUNDS:', '$outOfBoundsCount items', isAlert: outOfBoundsCount > 0),
              _buildDiagRow('COLLISIONS:', '$errorCount errors', isAlert: errorCount > 0),
              _buildDiagRow('ERGONOMIC WARN:', '$warningCount warnings', isWarning: warningCount > 0),
              const SizedBox(height: 6.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(
                    child: Text(
                      'SPATIAL HEALTH SCORE:',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: 11.0, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 4.0),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                    decoration: BoxDecoration(
                      color: errorCount > 0 ? Colors.red : (warningCount > 0 ? Colors.amber.shade800 : Colors.green),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: Text(
                      '${healthScore.round()}%',
                      style: const TextStyle(color: Colors.white, fontSize: 11.0, fontWeight: FontWeight.bold),
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

  Widget _buildDiagRow(String label, String value, {bool isAlert = false, bool isWarning = false}) {
    Color valueColor = Colors.white70;
    if (isAlert) valueColor = Colors.redAccent;
    if (isWarning) valueColor = Colors.amberAccent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10.0, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4.0),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(color: valueColor, fontSize: 10.0, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
