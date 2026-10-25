import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/themes/app_theme.dart';
import '../providers/designer_provider.dart';
import '../providers/camera_provider.dart';
import 'three_d_designer_view.dart';
import 'designer_painter.dart';

class FullFloorView extends ConsumerStatefulWidget {
  final String projectId;
  final List<dynamic> rooms;
  final List<dynamic> furnitureAssets;
  final VoidCallback? onBackToSingleRoom;

  const FullFloorView({
    super.key,
    required this.projectId,
    required this.rooms,
    required this.furnitureAssets,
    this.onBackToSingleRoom,
  });

  @override
  ConsumerState<FullFloorView> createState() => _FullFloorViewState();
}

class _FullFloorViewState extends ConsumerState<FullFloorView> {
  bool _is3DMode = true;
  bool _showWalls = true;
  bool _showFloor = true;
  bool _showFurniture = true;
  bool _showDoors = true;
  bool _showWindows = true;

  @override
  Widget build(BuildContext context) {
    final double totalArea = widget.rooms.fold(0.0, (sum, r) {
      final w = (r['measurements']?['length'] ?? 450.0) as double;
      final l = (r['measurements']?['width'] ?? 390.0) as double;
      return sum + (w * l) / 10000.0;
    });

    int totalFurniture = 0;
    final List<PlacedFurniture> allFurniture = [];
    final List<Wall> allWalls = [];
    final List<Opening> allOpenings = [];

    double currentOffsetX = 0.0;
    double currentOffsetZ = 0.0;
    double maxRowHeight = 0.0;
    int colIndex = 0;
    const int columns = 2;
    const double gap = 60.0;

    for (final room in widget.rooms) {
      final w = (room['measurements']?['length'] ?? 450.0) as double;
      final l = (room['measurements']?['width'] ?? 390.0) as double;

      final offX = currentOffsetX;
      final offZ = currentOffsetZ;

      // Extract room furniture if available
      final props = room['properties'];
      if (props != null && props is Map<String, dynamic>) {
        final rawFurn = props['furniture'] as List? ?? [];
        totalFurniture += rawFurn.length;
        for (final f in rawFurn) {
          allFurniture.add(PlacedFurniture(
            id: '${room['id']}_${f['id'] ?? Random().nextInt(10000)}',
            assetId: f['assetId'] ?? 'BED_001',
            name: f['name'] ?? 'Furniture',
            x: (f['x'] as num? ?? 0.0).toDouble() + offX,
            y: (f['y'] as num? ?? 0.0).toDouble(),
            z: (f['z'] as num? ?? 0.0).toDouble() + offZ,
            width: (f['width'] as num? ?? 100.0).toDouble(),
            depth: (f['depth'] as num? ?? 100.0).toDouble(),
            height: (f['height'] as num? ?? 100.0).toDouble(),
            rotationY: (f['rotationY'] as num? ?? 0.0).toDouble(),
          ));
        }

        final rawWalls = props['walls'] as List? ?? [];
        for (final wall in rawWalls) {
          allWalls.add(Wall(
            start: Offset((wall['x1'] as num).toDouble() + offX, (wall['y1'] as num).toDouble() + offZ),
            end: Offset((wall['x2'] as num).toDouble() + offX, (wall['y2'] as num).toDouble() + offZ),
            thickness: (wall['thickness'] as num? ?? 15.0).toDouble(),
          ));
        }

        final rawOpenings = props['openings'] as List? ?? [];
        for (final op in rawOpenings) {
          allOpenings.add(Opening(
            id: '${room['id']}_${op['id'] ?? 'op'}',
            type: op['type'] ?? 'door',
            position: Offset((op['x'] as num).toDouble() + offX, (op['y'] as num).toDouble() + offZ),
            width: (op['width'] as num? ?? 90.0).toDouble(),
            angle: (op['angle'] as num? ?? 0.0).toDouble(),
          ));
        }
      }

      if (allWalls.isEmpty) {
        allWalls.add(Wall(start: Offset(offX, offZ), end: Offset(offX + w, offZ), thickness: 15.0));
        allWalls.add(Wall(start: Offset(offX + w, offZ), end: Offset(offX + w, offZ + l), thickness: 15.0));
        allWalls.add(Wall(start: Offset(offX + w, offZ + l), end: Offset(offX, offZ + l), thickness: 15.0));
        allWalls.add(Wall(start: Offset(offX, offZ + l), end: Offset(offX, offZ), thickness: 15.0));
      }

      colIndex++;
      maxRowHeight = max(maxRowHeight, l);
      if (colIndex >= columns) {
        currentOffsetX = 0.0;
        currentOffsetZ += maxRowHeight + gap;
        maxRowHeight = 0.0;
        colIndex = 0;
      } else {
        currentOffsetX += w + gap;
      }
    }

    final layoutState = DesignerLayoutState(
      walls: allWalls,
      openings: allOpenings,
      furniture: allFurniture,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      body: Column(
        children: [
          // ─── TOP BAR ────────────────────────────────────────────────────────
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF111827),
              border: Border(bottom: BorderSide(color: Color(0xFF1F2937))),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                  onPressed: widget.onBackToSingleRoom ?? () => Navigator.of(context).pop(),
                  tooltip: 'Back to Single Room',
                ),
                const SizedBox(width: 8),
                const Icon(Icons.home, color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'My Home  ›  Ground Floor',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _is3DMode = true),
                  icon: const Icon(Icons.view_in_ar, size: 16),
                  label: const Text('3D View'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _is3DMode ? AppTheme.primary : const Color(0xFF1F2937),
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _is3DMode = false),
                  icon: const Icon(Icons.map, size: 16),
                  label: const Text('2D View'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !_is3DMode ? AppTheme.primary : const Color(0xFF1F2937),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // ─── MAIN CONTENT BODY ─────────────────────────────────────────────
          Expanded(
            child: Row(
              children: [
                // ─── LEFT PANEL: WORKFLOW & ROOMS LIST ───────────────────────
                Container(
                  width: 280,
                  decoration: const BoxDecoration(
                    color: Color(0xFF111827),
                    border: Border(right: BorderSide(color: Color(0xFF1F2937))),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DESIGN WORKFLOW',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                      ),
                      const SizedBox(height: 12),
                      _buildWorkflowStep('1', 'Create Rooms', '${widget.rooms.length}/${widget.rooms.length} rooms created', true),
                      _buildWorkflowStep('2', 'Design Each Room', 'All rooms designed', true),
                      _buildWorkflowStep('3', 'Review & Optimize', 'Score: 78/100', true),
                      _buildWorkflowStep('4', 'Generate Full Floor', 'Combine all rooms', true, active: true),

                      const SizedBox(height: 20),
                      Text(
                        'ROOMS (${widget.rooms.length})',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          itemCount: widget.rooms.length,
                          itemBuilder: (context, index) {
                            final r = widget.rooms[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF334155)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.meeting_room, color: AppTheme.primary, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r['room_name'] ?? 'Room ${index + 1}',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        const Text('Designed', style: TextStyle(color: Colors.green, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.auto_awesome, size: 16),
                          label: const Text('Generate Full Floor Plan'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ─── CENTER VIEWPORT ─────────────────────────────────────────
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _is3DMode
                            ? ThreeDDesignerView(
                                roomId: widget.projectId,
                                furnitureAssets: widget.furnitureAssets,
                              )
                            : Container(
                                color: const Color(0xFF0F172A),
                                child: CustomPaint(
                                  painter: DesignerPainter(
                                    layout: layoutState,
                                    showGrid: true,
                                    showMeasurements: true,
                                    showFurnitureLabels: true,
                                    showDoors: _showDoors,
                                    showWindows: _showWindows,
                                  ),
                                ),
                              ),
                      ),
                      Positioned(
                        top: 16,
                        left: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B).withOpacity(0.85),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'FINAL FLOOR PLAN',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                              ),
                              Text(
                                'All rooms combined',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ─── RIGHT PANEL: SCENE PROPERTIES ────────────────────────────
                Container(
                  width: 260,
                  decoration: const BoxDecoration(
                    color: Color(0xFF111827),
                    border: Border(left: BorderSide(color: Color(0xFF1F2937))),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: ListView(
                    children: [
                      Text(
                        'SCENE PROPERTIES',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Text('Room Settings', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white)),
                      const SizedBox(height: 8),
                      _buildTextField('Room Name', 'Ground Floor'),
                      const SizedBox(height: 8),
                      _buildTextField('Wall Height (cm)', '280'),
                      const SizedBox(height: 8),
                      _buildTextField('Floor Height (cm)', '0'),
                      const SizedBox(height: 8),
                      _buildTextField('Wall Thickness (cm)', '15'),

                      const SizedBox(height: 20),
                      Text('View Controls', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white)),
                      const SizedBox(height: 8),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        childAspectRatio: 2.5,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        children: [
                          _buildViewButton('Top View', () => ref.read(cameraProvider.notifier).onViewModeChanged(ViewMode.top)),
                          _buildViewButton('Front View', () => ref.read(cameraProvider.notifier).onViewModeChanged(ViewMode.front)),
                          _buildViewButton('Left View', () => ref.read(cameraProvider.notifier).onViewModeChanged(ViewMode.left)),
                          _buildViewButton('Right View', () => ref.read(cameraProvider.notifier).onViewModeChanged(ViewMode.right)),
                          _buildViewButton('Reset View', () => ref.read(cameraProvider.notifier).onViewModeChanged(ViewMode.orbit)),
                          _buildViewButton('Isometric', () => ref.read(cameraProvider.notifier).onViewModeChanged(ViewMode.isometric), active: true),
                        ],
                      ),

                      const SizedBox(height: 20),
                      Text('Display Options', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white)),
                      const SizedBox(height: 8),
                      _buildSwitch('Show Walls', _showWalls, (v) => setState(() => _showWalls = v)),
                      _buildSwitch('Show Floor', _showFloor, (v) => setState(() => _showFloor = v)),
                      _buildSwitch('Show Furniture', _showFurniture, (v) => setState(() => _showFurniture = v)),
                      _buildSwitch('Show Doors', _showDoors, (v) => setState(() => _showDoors = v)),
                      _buildSwitch('Show Windows', _showWindows, (v) => setState(() => _showWindows = v)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ─── BOTTOM PANEL: PROJECT SUMMARY ─────────────────────────────────
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF111827),
              border: Border(top: BorderSide(color: Color(0xFF1F2937))),
            ),
            child: Row(
              children: [
                _buildSummaryStat('Total Rooms', '${widget.rooms.length}'),
                const SizedBox(width: 24),
                _buildSummaryStat('Total Area', '${totalArea.toStringAsFixed(1)} m²'),
                const SizedBox(width: 24),
                _buildSummaryStat('Total Furniture', '$totalFurniture'),
                const SizedBox(width: 24),
                _buildSummaryStat('Design Score', '78/100', color: Colors.amber),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield, color: Colors.green, size: 14),
                      SizedBox(width: 4),
                      Text('SAFE', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Export 2D Plan'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('Export 3D View'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('Save Project'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowStep(String num, String title, String subtitle, bool completed, {bool active = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: active ? AppTheme.primary : (completed ? Colors.green : Colors.grey.shade800),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: completed && !active
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : Text(num, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: active ? Colors.white : Colors.grey.shade300, fontWeight: FontWeight.bold, fontSize: 12)),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
        const SizedBox(height: 4),
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _buildViewButton(String label, VoidCallback onPressed, {bool active = false}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? AppTheme.primary : const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  Widget _buildSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppTheme.primary,
        ),
      ],
    );
  }

  Widget _buildSummaryStat(String label, String value, {Color? color}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 10)),
        Text(value, style: TextStyle(color: color ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}
