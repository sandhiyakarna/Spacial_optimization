import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/themes/app_theme.dart';

import '../providers/project_provider.dart';
import '../../room/providers/room_provider.dart';
import '../../room/presentation/room_dialogs.dart';
import '../../analytics/providers/analytics_provider.dart';
import '../providers/export_provider.dart';

class ProjectWorkspaceScreen extends ConsumerStatefulWidget {
  final String projectId;

  const ProjectWorkspaceScreen({
    super.key,
    required this.projectId,
  });

  @override
  ConsumerState<ProjectWorkspaceScreen> createState() => _ProjectWorkspaceScreenState();
}

class _ProjectWorkspaceScreenState extends ConsumerState<ProjectWorkspaceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedRoomId;
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabChange);

    Future.microtask(() {
      ref.read(projectProvider.notifier).fetchProjects();
      ref.read(roomListProvider.notifier).fetchRooms(widget.projectId);
      ref.read(exportProvider.notifier).fetchReportHistory(widget.projectId);
    });
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _getProject(List<dynamic> projects) {
    try {
      return projects.firstWhere((p) => p['id'] == widget.projectId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _duplicateRoom(String roomId) async {
    final success = await ref.read(roomListProvider.notifier).duplicateRoom(widget.projectId, roomId);
    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room duplicated successfully.')),
      );
    }
  }

  void _showAddRoomDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateRoomDialog(projectId: widget.projectId),
    ).then((val) {
      ref.read(roomListProvider.notifier).fetchRooms(widget.projectId);
    });
  }

  void _showEditRoomDialog(Map<String, dynamic> room) {
    showDialog(
      context: context,
      builder: (context) => EditRoomDialog(room: room, projectId: widget.projectId),
    ).then((val) {
      ref.read(roomListProvider.notifier).fetchRooms(widget.projectId);
    });
  }

  void _showDeleteRoomDialog(Map<String, dynamic> room) {
    showDialog(
      context: context,
      builder: (context) => DeleteRoomDialog(room: room, projectId: widget.projectId),
    ).then((val) {
      ref.read(roomListProvider.notifier).fetchRooms(widget.projectId);
    });
  }

  Future<void> _restoreVersion(int versionNumber) async {
    final activeRoomId = _selectedRoomId;
    if (activeRoomId == null) return;
    
    setState(() {
      _isRestoring = true;
    });

    final success = await ref
        .read(analyticsProvider.notifier)
        .restoreVersion(activeRoomId, versionNumber);
        
    setState(() {
      _isRestoring = false;
    });

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored room layout to Version $versionNumber!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to restore layout version.'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectState = ref.watch(projectProvider);
    final roomState = ref.watch(roomListProvider);
    final analyticsState = ref.watch(analyticsProvider);
    final exportState = ref.watch(exportProvider);

    final currentProject = _getProject(projectState.projects);
    final projectName = currentProject?['project_name'] ?? 'Project Workspace';
    final rooms = roomState.rooms;

    // Auto-select first room and fetch details safely
    if (rooms.isNotEmpty) {
      final activeRoomId = _selectedRoomId ?? rooms.first['id'];
      if (_selectedRoomId != activeRoomId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _selectedRoomId = activeRoomId;
          });
          ref.read(analyticsProvider.notifier).fetchRoomAnalytics(activeRoomId);
        });
      }
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Build History Timeline Events
    final timelineEvents = _getTimelineEvents(rooms, analyticsState.history, exportState.reportHistory);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              projectName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'Total Rooms: ${rooms.length}',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/projects'), // Navigates back to Project List
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: isDark ? Colors.grey[400] : Colors.grey[600],
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.meeting_room_outlined), text: 'Rooms'),
            Tab(icon: Icon(Icons.architecture_outlined), text: 'Designer'),
            Tab(icon: Icon(Icons.analytics_outlined), text: 'Analysis'),
            Tab(icon: Icon(Icons.history_outlined), text: 'History'),
          ],
        ),
      ),
      body: roomState.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(), // Prevent swipe for smoother canvas control
              children: [
                _buildRoomsTab(context, rooms),
                _buildDesignerTab(context, rooms),
                _buildAnalysisTab(context, rooms, analyticsState),
                _buildHistoryTab(context, rooms, timelineEvents),
              ],
            ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _showAddRoomDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Room'),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  // --- Rooms Tab ---
  Widget _buildRoomsTab(BuildContext context, List<dynamic> rooms) {
    if (rooms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.meeting_room_outlined, size: 72, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No Rooms Added Yet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Start by adding a room to this project workspace.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _showAddRoomDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add First Room'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 600 ? 2 : 1);
        return GridView.builder(
          padding: const EdgeInsets.all(16.0),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.45,
          ),
          itemCount: rooms.length,
          itemBuilder: (context, index) {
            final room = rooms[index] as Map<String, dynamic>;
            return _buildRoomCard(context, room);
          },
        );
      },
    );
  }

  Widget _buildRoomCard(BuildContext context, Map<String, dynamic> room) {
    Color roomThemeColor = AppTheme.primary;
    try {
      final hex = (room['room_color'] ?? '#FFFFFF').toString().replaceAll('#', '');
      roomThemeColor = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {}

    final m = room['measurements'] as Map<String, dynamic>? ?? {};
    final double length = (m['length'] ?? 0.0).toDouble();
    final double width = (m['width'] ?? 0.0).toDouble();
    final sizeText = length > 0 && width > 0
        ? '${(length / 100).toStringAsFixed(1)}m × ${(width / 100).toStringAsFixed(1)}m'
        : 'No dimensions set';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 8,
            color: roomThemeColor,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: roomThemeColor.withValues(alpha: 0.15),
                        child: Icon(
                          _getRoomIcon(room['room_type']),
                          color: roomThemeColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          room['room_name'] ?? 'Unnamed Room',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (val) {
                          if (val == 'duplicate') {
                            _duplicateRoom(room['id']);
                          } else if (val == 'settings') {
                            _showEditRoomDialog(room);
                          } else if (val == 'delete') {
                            _showDeleteRoomDialog(room);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'duplicate',
                            child: Row(
                              children: [
                                Icon(Icons.copy, size: 16),
                                SizedBox(width: 8),
                                Text('Duplicate'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'settings',
                            child: Row(
                              children: [
                                Icon(Icons.settings, size: 16),
                                SizedBox(width: 8),
                                Text('Settings'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red, size: 16),
                                SizedBox(width: 8),
                                Text('Delete', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Type: ${room['room_type']} • Floor: ${room['floor_number']}',
                    style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.straighten, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        sizeText,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => context.go('/designer/${room['id']}'),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open Room'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getRoomIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'living room':
        return Icons.chair_outlined;
      case 'bedroom':
        return Icons.bed_outlined;
      case 'kitchen':
        return Icons.kitchen_outlined;
      case 'dining room':
        return Icons.restaurant;
      case 'office':
        return Icons.desktop_mac_outlined;
      case 'bathroom':
        return Icons.bathtub_outlined;
      default:
        return Icons.meeting_room_outlined;
    }
  }

  // --- Designer Tab ---
  Widget _buildDesignerTab(BuildContext context, List<dynamic> rooms) {
    if (rooms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.architecture_outlined, size: 72, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No Rooms Created Yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please add a room in the "Rooms" tab first to start designing spatial layouts.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _tabController.animateTo(0),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                child: const Text('Go to Rooms Tab'),
              ),
            ],
          ),
        ),
      );
    }

    final activeRoomId = _selectedRoomId ?? rooms.first['id'];
    final selectedRoom = rooms.firstWhere((r) => r['id'] == activeRoomId, orElse: () => rooms.first);

    Color roomThemeColor = AppTheme.primary;
    try {
      final hex = (selectedRoom['room_color'] ?? '#FFFFFF').toString().replaceAll('#', '');
      roomThemeColor = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {}

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  const Icon(Icons.meeting_room, color: AppTheme.primary),
                  const SizedBox(width: 12),
                  const Text(
                    'Select Room to Design:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: activeRoomId,
                        isDense: true,
                        items: rooms.map<DropdownMenuItem<String>>((r) {
                          return DropdownMenuItem<String>(
                            value: r['id'],
                            child: Text('${r['room_name']} (${r['room_type']})'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedRoomId = val;
                            });
                            ref.read(analyticsProvider.notifier).fetchRoomAnalytics(val);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 750;

              final blueprintPreviewCard = Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: 300,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: BlueprintPainter(
                            gridColor: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.05),
                            gridSpacing: 20,
                          ),
                        ),
                      ),
                      Center(
                        child: Opacity(
                          opacity: 0.3,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.architecture_rounded, size: 64, color: roomThemeColor),
                              const SizedBox(height: 8),
                              const Text(
                                'INTERACTIVE LAYOUT CANVAS',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 16,
                        left: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            selectedRoom['room_name'] ?? 'Active Room',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );

              final designerOptionsCard = Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.brush_outlined, color: AppTheme.primary, size: 28),
                          SizedBox(width: 12),
                          Text(
                            'Design Studio',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Arrange layout items, configure architectural clearances, and check style themes directly on the 2D canvas & 3D real-time renderer.',
                        style: TextStyle(color: Theme.of(context).hintColor, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: () => context.go('/designer/$activeRoomId'),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text(
                            'Continue Designing',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: () => context.go('/designer/$activeRoomId'),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text(
                            'Open existing Designer',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: const BorderSide(color: AppTheme.primary, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: blueprintPreviewCard),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: designerOptionsCard),
                  ],
                );
              } else {
                return Column(
                  children: [
                    blueprintPreviewCard,
                    const SizedBox(height: 20),
                    designerOptionsCard,
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  // --- Analysis Tab ---
  Widget _buildAnalysisTab(BuildContext context, List<dynamic> rooms, AnalyticsState analyticsState) {
    if (rooms.isEmpty) {
      return const Center(child: Text('No rooms available for analysis. Add a room first.'));
    }

    final activeRoomId = _selectedRoomId ?? rooms.first['id'];

    if (analyticsState.isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }

    final dashboard = analyticsState.dashboard;
    final insights = analyticsState.insights ?? [];

    if (dashboard == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.query_stats, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text('No Analysis Data Yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              const Text('Place furniture or run validation checks in the Designer to compute layout scores.', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/designer/$activeRoomId'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                child: const Text('Go to Designer'),
              )
            ],
          ),
        ),
      );
    }

    final overallScore = (dashboard['overall_score'] as num? ?? 0.0).toDouble();
    final accessibility = (dashboard['accessibility_score'] as num? ?? 0.0).toDouble();
    final lighting = (dashboard['lighting_score'] as num? ?? 0.0).toDouble();
    final comfort = (dashboard['comfort_score'] as num? ?? 0.0).toDouble();
    final balance = (dashboard['balance_score'] as num? ?? 0.0).toDouble();
    final spaceUtil = (dashboard['space_utilization'] as num? ?? 0.0).toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Design Analysis',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              DropdownButton<String>(
                value: activeRoomId,
                items: rooms.map<DropdownMenuItem<String>>((r) {
                  return DropdownMenuItem<String>(
                    value: r['id'],
                    child: Text(r['room_name']),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedRoomId = val;
                    });
                    ref.read(analyticsProvider.notifier).fetchRoomAnalytics(val);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 750;

              final scoreCard = Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Design Health Score',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 20),
                      _buildCircularScoreGauge(overallScore),
                      const SizedBox(height: 20),
                      Text(
                        overallScore >= 80 ? 'Excellent Layout' : (overallScore >= 60 ? 'Good Layout' : 'Needs Optimization'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: overallScore >= 80 ? Colors.green : (overallScore >= 60 ? Colors.orange : Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              );

              final breakdownCard = Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Performance Breakdown',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      _buildBreakdownProgressBar('Accessibility', accessibility, Colors.blue),
                      _buildBreakdownProgressBar('Lighting Angle & Glare', lighting, Colors.amber),
                      _buildBreakdownProgressBar('Ergonomics / Comfort', comfort, Colors.purple),
                      _buildBreakdownProgressBar('Space Utilization', spaceUtil, AppTheme.primary),
                      _buildBreakdownProgressBar('Balance & Symmetry', balance, Colors.indigo),
                    ],
                  ),
                ),
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: scoreCard),
                    const SizedBox(width: 20),
                    Expanded(flex: 3, child: breakdownCard),
                  ],
                );
              } else {
                return Column(
                  children: [
                    scoreCard,
                    const SizedBox(height: 20),
                    breakdownCard,
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'AI Summary & Recommendations',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (insights.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Center(
                  child: Text('AI analysis suggests a clean, well-spaced layout with no immediate warning flags.'),
                ),
              ),
            )
          else
            ...insights.map((insight) {
              final text = insight.toString();
              IconData icon = Icons.info_outline;
              Color color = AppTheme.primary;
              if (text.contains('excellent') || text.contains('well-spaced') || text.contains('Good')) {
                icon = Icons.check_circle_outline;
                color = Colors.green;
              } else if (text.contains('tight') || text.contains('overlap') || text.contains('warning') || text.contains('glare') || text.contains('obstruct')) {
                icon = Icons.warning_amber_outlined;
                color = Colors.orange;
              }
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.1),
                    child: Icon(icon, color: color),
                  ),
                  title: Text(
                    text,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.4),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildCircularScoreGauge(double score) {
    Color gaugeColor = score >= 80 ? Colors.green : (score >= 60 ? Colors.orange : Colors.red);
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: CircularProgressIndicator(
            value: score / 100.0,
            strokeWidth: 10,
            backgroundColor: gaugeColor.withValues(alpha: 0.1),
            color: gaugeColor,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${score.round()}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 32),
            ),
            const Text(
              'SCORE',
              style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildBreakdownProgressBar(String label, double val, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              Text('${val.round()}%', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: val / 100.0,
              color: color,
              backgroundColor: color.withValues(alpha: 0.1),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  // --- History Tab ---
  Widget _buildHistoryTab(BuildContext context, List<dynamic> rooms, List<ActivityEvent> events) {
    if (rooms.isEmpty) {
      return const Center(child: Text('No timeline history found. Create a room first.'));
    }

    final activeRoomId = _selectedRoomId ?? rooms.first['id'];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Activity Scope:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              DropdownButton<String>(
                value: activeRoomId,
                items: rooms.map<DropdownMenuItem<String>>((r) {
                  return DropdownMenuItem<String>(
                    value: r['id'],
                    child: Text(r['room_name']),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedRoomId = val;
                    });
                    ref.read(analyticsProvider.notifier).fetchRoomAnalytics(val);
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _isRestoring
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : events.isEmpty
                  ? const Center(child: Text('No activity timeline recorded yet.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(20.0),
                      itemCount: events.length,
                      itemBuilder: (context, index) {
                        final event = events[index];
                        return _buildTimelineItem(context, event, index == events.length - 1);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildTimelineItem(BuildContext context, ActivityEvent event, bool isLast) {
    final formattedTime = _formatEventTime(event.timestamp);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: event.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(event.icon, color: event.color, size: 16),
              ),
              Expanded(
                child: Container(
                  width: isLast ? 0 : 2,
                  color: Colors.grey.withValues(alpha: 0.25),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Card(
                margin: EdgeInsets.zero,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              event.description,
                              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              formattedTime,
                              style: const TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      if (event.trailing != null) ...[
                        const SizedBox(width: 8),
                        event.trailing!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatEventTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} mins ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hours ago';
    } else {
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }

  List<ActivityEvent> _getTimelineEvents(
    List<dynamic> rooms,
    List<dynamic>? roomVersions,
    List<dynamic> reports,
  ) {
    final List<ActivityEvent> events = [];

    // 1. Add Room creation and update events
    for (final r in rooms) {
      if (r['created_at'] != null) {
        try {
          events.add(ActivityEvent(
            title: 'Room Created',
            description: 'Room "${r['room_name']}" (${r['room_type']}) was added to the project.',
            timestamp: DateTime.parse(r['created_at'].toString()).toLocal(),
            icon: Icons.add_home_outlined,
            color: Colors.blue,
          ));
        } catch (_) {}
      }
      if (r['updated_at'] != null && r['created_at'] != r['updated_at']) {
        try {
          events.add(ActivityEvent(
            title: 'Room Config Updated',
            description: 'Room "${r['room_name']}" settings or measurements were modified.',
            timestamp: DateTime.parse(r['updated_at'].toString()).toLocal(),
            icon: Icons.edit_note,
            color: Colors.orange,
          ));
        } catch (_) {}
      }
    }

    // 2. Add Room Layout Version events
    if (roomVersions != null) {
      for (final v in roomVersions) {
        if (v['created_at'] != null) {
          try {
            final verNum = v['version_number'];
            final score = (v['overall_score'] as num? ?? 0).round();
            events.add(ActivityEvent(
              title: 'Layout Version V$verNum Saved',
              description: v['summary'] ?? 'Layout snapshot saved (Design Score: $score%).',
              timestamp: DateTime.parse(v['created_at'].toString()).toLocal(),
              icon: Icons.save_outlined,
              color: AppTheme.primary,
              trailing: TextButton.icon(
                icon: const Icon(Icons.restore, size: 14),
                label: const Text('Restore', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30)),
                onPressed: () => _restoreVersion(verNum),
              ),
            ));
          } catch (_) {}
        }
      }
    }

    // 3. Add Export report events
    for (final rep in reports) {
      if (rep['created_at'] != null) {
        try {
          final repType = rep['report_type'] ?? 'Report';
          final format = rep['format'] ?? 'PDF';
          final status = rep['status'] ?? 'Completed';
          events.add(ActivityEvent(
            title: 'Report Generated',
            description: '$repType ($format) - Status: $status',
            timestamp: DateTime.parse(rep['created_at'].toString()).toLocal(),
            icon: Icons.picture_as_pdf_outlined,
            color: status == 'Completed' ? Colors.green : Colors.red,
          ));
        } catch (_) {}
      }
    }

    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events;
  }
}

// Custom Classes for UI rendering
class ActivityEvent {
  final String title;
  final String description;
  final DateTime timestamp;
  final IconData icon;
  final Color color;
  final Widget? trailing;

  ActivityEvent({
    required this.title,
    required this.description,
    required this.timestamp,
    required this.icon,
    required this.color,
    this.trailing,
  });
}

class BlueprintPainter extends CustomPainter {
  final Color gridColor;
  final double gridSpacing;

  BlueprintPainter({
    required this.gridColor,
    this.gridSpacing = 20.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    for (double x = 0; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

