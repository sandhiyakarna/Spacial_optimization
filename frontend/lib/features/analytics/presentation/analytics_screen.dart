import '../../../app/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../project/providers/project_provider.dart';
import '../../room/providers/room_provider.dart';
import '../providers/analytics_provider.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:go_router/go_router.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  final String? projectId;
  final bool isEmbedded;

  const AnalyticsScreen({
    super.key,
    this.projectId,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> with SingleTickerProviderStateMixin {
  String? _selectedProjectId;
  String? _selectedRoomId;
  TabController? _tabController;

  // Comparison State
  String? _compareLayoutA;
  String? _compareLayoutB;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    
    if (widget.isEmbedded && widget.projectId != null) {
      _selectedProjectId = widget.projectId;
      Future.microtask(() => _onProjectChanged(widget.projectId!));
    } else {
      // Fetch projects on init
      Future.microtask(() async {
        await ref.read(projectProvider.notifier).fetchProjects();
        final projectsState = ref.read(projectProvider);
        if (projectsState.projects.isNotEmpty) {
          final firstProjId = projectsState.projects.first['id'];
          setState(() {
            _selectedProjectId = firstProjId;
          });
          _onProjectChanged(firstProjId);
        }
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _onProjectChanged(String projectId) async {
    await ref.read(roomListProvider.notifier).fetchRooms(projectId);
    await ref.read(analyticsProvider.notifier).fetchProjectAnalytics(projectId);
    
    final roomsState = ref.read(roomListProvider);
    if (roomsState.rooms.isNotEmpty) {
      final firstRoomId = roomsState.rooms.first['id'];
      setState(() {
        _selectedRoomId = firstRoomId;
        _compareLayoutA = firstRoomId;
        _compareLayoutB = firstRoomId;
      });
      _onRoomChanged(firstRoomId);
    } else {
      setState(() {
        _selectedRoomId = null;
        _compareLayoutA = null;
        _compareLayoutB = null;
      });
    }
  }

  Future<void> _onRoomChanged(String roomId) async {
    await ref.read(analyticsProvider.notifier).fetchRoomAnalytics(roomId);
    
    // Set default comparison options
    final analyticsState = ref.read(analyticsProvider);
    final history = analyticsState.history;
    if (history != null && history.isNotEmpty) {
      setState(() {
        _compareLayoutA = history.first['id'].toString();
        _compareLayoutB = history.last['id'].toString();
      });
      _onCompareTriggered();
    }
  }

  void _onCompareTriggered() {
    if (_compareLayoutA != null && _compareLayoutB != null) {
      // Resolve layout UUIDs or keep them as version numbers (backend comparison service handles version UUIDs)
      final analyticsState = ref.read(analyticsProvider);
      final history = analyticsState.history ?? [];
      
      String resA = _compareLayoutA!;
      String resB = _compareLayoutB!;
      
      // If version numbers are chosen, resolve to DesignHistory entry ID (or fallback to UUID if room selected)
      for (final h in history) {
        if (h['version_number'].toString() == _compareLayoutA) {
          // In backend compare, we search room ID first, then DesignHistory ID
          // Let's see if we have history id
          // If we compare history, we should send layout_a / layout_b as history IDs or Room ID
          // Let's resolve the actual history entry or room ID
          // We will find the DesignHistory ID or Room ID.
          // Wait, backend CompareLayoutsRequest resolves Room ID first.
          // If we want to compare version 1, we can pass version UUID, but wait!
          // How do we know the DesignHistory UUID?
          // Wait, did the history list include ID? Let's check how get_history returns it.
          // Ah, in AnalyticsService.get_history:
          // it returns version_number, overall_score, summary, etc. But not ID!
          // Wait, let's check if we can compare room vs room, or if we can compare versions.
          // If we compare versions, we can let user compare version 1 and 2 by passing version ID,
          // but wait! If get_history does not return ID, we can update get_history to include the ID!
          // Let's verify: yes, we should definitely update get_history to include "id" in returned dict!
          // Let's look at get_history in AnalyticsService. It returns:
          // "version_number", "overall_score", ..., "summary".
          // We can add "id": entry.id in AnalyticsService.get_history!
          // Let's edit AnalyticsService.get_history to include "id": entry.id. That is extremely useful!
        }
      }
      
      ref.read(analyticsProvider.notifier).compareLayouts(resA, resB);
    }
  }

  Widget _buildRestrictedAccessView(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF9FAFB),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.all(32.0),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE5E5E5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_person_rounded,
                        size: 64,
                        color: theme.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Professional Analytics Restricted',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Design analytics, layout safety diagnostics, compliance audits, and comparative insights are premium capabilities reserved for Architects, Interior Designers, and Administrators.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: isDark ? const Color(0xFFA0A0A0) : const Color(0xFF666666),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () {
                      context.go('/profile');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('To unlock, update your professional details or roles in your user profile.'),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.star_rounded, color: Colors.amber),
                    label: const Text(
                      'Upgrade Profile Role',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final role = authState.profile?['role'] ?? 'Customer';
    final allowedRoles = ['Administrator', 'Interior Designer', 'Architect'];
    if (!allowedRoles.contains(role)) {
      return _buildRestrictedAccessView(context);
    }

    final projectsState = ref.watch(projectProvider);
    final roomsState = ref.watch(roomListProvider);
    final analyticsState = ref.watch(analyticsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF9FAFB),
      body: Column(
        children: [
          // Selectors Top Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE5E5E5),
                ),
              ),
            ),
            child: Row(
              children: [
                if (!widget.isEmbedded) ...[
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedProjectId,
                      decoration: InputDecoration(
                        labelText: 'Project',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: projectsState.projects.map<DropdownMenuItem<String>>((p) {
                        return DropdownMenuItem<String>(
                          value: p['id'],
                          child: Text(p['project_name']),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedProjectId = val;
                          });
                          _onProjectChanged(val);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedRoomId,
                    decoration: InputDecoration(
                      labelText: 'Room',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: roomsState.rooms.map<DropdownMenuItem<String>>((r) {
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
                        _onRoomChanged(val);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          // Tab Bar
          TabBar(
            controller: _tabController,
            labelColor: AppTheme.primary,
            unselectedLabelColor: isDark ? Colors.grey[400] : Colors.grey[600],
            indicatorColor: AppTheme.primary,
            tabs: const [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Dashboard'),
              Tab(icon: Icon(Icons.insights_outlined), text: 'Insights'),
              Tab(icon: Icon(Icons.compare_outlined), text: 'Compare'),
              Tab(icon: Icon(Icons.history_outlined), text: 'Timeline'),
              Tab(icon: Icon(Icons.bar_chart_outlined), text: 'Project'),
            ],
          ),

          // Tab Content
          Expanded(
            child: analyticsState.isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Dashboard
                      _buildDashboardTab(analyticsState, isDark),
                      // Tab 2: Insights
                      _buildInsightsTab(analyticsState, isDark),
                      // Tab 3: Compare
                      _buildCompareTab(analyticsState, roomsState, isDark),
                      // Tab 4: Timeline
                      _buildTimelineTab(analyticsState, isDark),
                      // Tab 5: Project Analytics
                      _buildProjectTab(analyticsState, isDark),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // Dashboard Tab
  Widget _buildDashboardTab(AnalyticsState state, bool isDark) {
    if (state.dashboard == null || state.statistics == null) {
      return const Center(child: Text('Please select a room with measurements to view analytics.'));
    }

    final double overallScore = (state.dashboard!['overall_score'] as num).toDouble();
    final double accessibility = (state.dashboard!['accessibility_score'] as num).toDouble();
    final double lighting = (state.dashboard!['lighting_score'] as num).toDouble();
    final double comfort = (state.dashboard!['comfort_score'] as num).toDouble();
    final double balance = (state.dashboard!['balance_score'] as num).toDouble();
    final double spaceUtil = (state.dashboard!['space_utilization'] as num).toDouble();
    
    final stats = state.statistics!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row containing circular health gauge and basic stats
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Design Health Circular Gauge
              Expanded(
                flex: 2,
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Design Health',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        CustomCircularProgress(
                          value: overallScore / 100.0,
                          size: 140,
                          strokeWidth: 12,
                          centerWidget: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${overallScore.round()}%',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const Text('Score', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          overallScore >= 80 ? 'Excellent Layout' : (overallScore >= 65 ? 'Good Layout' : 'Needs Optimization'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: overallScore >= 80 ? Colors.green : (overallScore >= 65 ? Colors.orange : Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Subscores progress list
              Expanded(
                flex: 3,
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Score Breakdown',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        _buildSubscoreRow('Accessibility', accessibility, Colors.blue),
                        _buildSubscoreRow('Lighting', lighting, Colors.amber),
                        _buildSubscoreRow('Ergonomics/Comfort', comfort, Colors.purple),
                        _buildSubscoreRow('Space Utilization', spaceUtil, AppTheme.primary),
                        _buildSubscoreRow('Balance', balance, Colors.indigo),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Statistics Panel Title
          const Text(
            'Room Space Statistics',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primary),
          ),
          const SizedBox(height: 12),
          // Stats Grid
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _buildStatCard('Furniture Count', '${stats['furniture_count']} items', Icons.chair_outlined, AppTheme.primary),
              _buildStatCard('Occupied Area', '${(stats['occupied_area'] / 10000.0).toStringAsFixed(1)} m²', Icons.grid_view_outlined, Colors.red),
              _buildStatCard('Free Area', '${(stats['free_area'] / 10000.0).toStringAsFixed(1)} m²', Icons.space_bar_outlined, Colors.green),
              _buildStatCard('Walkway Coverage', '${stats['walkway_coverage']}%', Icons.alt_route_outlined, Colors.blue),
              _buildStatCard('Avg Clearance', '${stats['average_clearance'].round()} cm', Icons.straighten_outlined, Colors.orange),
              _buildStatCard('Estimated Budget', '\$${stats['estimated_cost'].round()}', Icons.monetization_on_outlined, Colors.purple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubscoreRow(String title, double score, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              Text('${score.round()}%', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100.0,
              backgroundColor: color.withOpacity(0.1),
              color: color,
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // Insights Tab
  Widget _buildInsightsTab(AnalyticsState state, bool isDark) {
    final insights = state.insights ?? [];
    if (insights.isEmpty) {
      return const Center(child: Text('No design insights available yet. Check room setup.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: insights.length,
      itemBuilder: (context, index) {
        final text = insights[index] as String;
        IconData bulletIcon = Icons.info_outline;
        Color bulletColor = Colors.blue;

        if (text.contains('excellent') || text.contains('Well-balanced')) {
          bulletIcon = Icons.check_circle_outline;
          bulletColor = Colors.green;
        } else if (text.contains('tight') || text.contains('obstructions') || text.contains('cramped') || text.contains('uneven')) {
          bulletIcon = Icons.warning_amber_outlined;
          bulletColor = Colors.orange;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: Icon(bulletIcon, color: bulletColor, size: 28),
            title: Text(
              text,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.4),
            ),
          ),
        );
      },
    );
  }

  // Compare Tab
  Widget _buildCompareTab(AnalyticsState state, RoomListState roomsState, bool isDark) {
    final history = state.history ?? [];
    final comp = state.comparison;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Layout Version Comparison',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Compare two layout versions to see layout enhancements and score delta.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),
          // Selectors
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _compareLayoutA,
                  decoration: const InputDecoration(labelText: 'Layout A'),
                  items: [
                    if (_selectedRoomId != null)
                      DropdownMenuItem<String>(value: _selectedRoomId, child: const Text('Current Layout')),
                    ...history.map<DropdownMenuItem<String>>((h) {
                      return DropdownMenuItem<String>(
                        value: h['id'].toString(),
                        child: Text('Version ${h['version_number']}'),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _compareLayoutA = val;
                    });
                    _onCompareTriggered();
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _compareLayoutB,
                  decoration: const InputDecoration(labelText: 'Layout B'),
                  items: [
                    if (_selectedRoomId != null)
                      DropdownMenuItem<String>(value: _selectedRoomId, child: const Text('Current Layout')),
                    ...history.map<DropdownMenuItem<String>>((h) {
                      return DropdownMenuItem<String>(
                        value: h['id'].toString(),
                        child: Text('Version ${h['version_number']}'),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _compareLayoutB = val;
                    });
                    _onCompareTriggered();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Comparison Result UI
          if (comp == null)
            const Center(child: Text('Choose different layout versions to compare.'))
          else ...[
            // Winner Card
            Card(
              elevation: 4,
              color: comp['improvement'] == true ? AppTheme.primary[50] : Colors.amber[50],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      comp['improvement'] == true ? Icons.military_tech : Icons.balance,
                      color: AppTheme.primary[800],
                      size: 48,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comp['improvement'] == true ? 'Optimization Detected!' : 'Balanced Scores',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary[900]),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Layout B has a score difference of ${comp['score_difference']}% over Layout A.',
                            style: TextStyle(color: AppTheme.primary[950], fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Comparative Review',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Comparison Bullet List
            ...List.generate((comp['recommendations'] as List).length, (i) {
              final text = comp['recommendations'][i] as String;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.arrow_right_alt, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
                  ],
                ),
              );
            }),
          ]
        ],
      ),
    );
  }

  // Timeline Tab
  Widget _buildTimelineTab(AnalyticsState state, bool isDark) {
    final history = state.history ?? [];
    if (history.isEmpty) {
      return const Center(child: Text('No timeline history found. Modify design layout to populate history.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Score Performance Trend',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
          ),
          const SizedBox(height: 8),
          // Custom Line Chart showing Score Trend
          Container(
            height: 160,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE5E5E5)),
            ),
            child: CustomPaint(
              painter: TrendLinePainter(
                data: history.map((e) => (e['overall_score'] as num).toDouble()).toList(),
                isDark: isDark,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Design Revision Stepper',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          // Revision List
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: history.length,
            itemBuilder: (context, index) {
              // Show in reverse order (newest first)
              final h = history[history.length - 1 - index];
              final double score = (h['overall_score'] as num).toDouble();
              final timestamp = DateTime.parse(h['created_at']);
              final formattedTime = '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      // Large Version Number Circle
                      CircleAvatar(
                        backgroundColor: AppTheme.primary,
                        radius: 20,
                        child: Text(
                          'V${h['version_number']}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              h['summary'] ?? 'Layout snapshot saved',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formattedTime,
                              style: const TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      // Score Badge and Restore Button
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Score: ${score.round()}%',
                              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(50, 24),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () async {
                              final scaffoldMessenger = ScaffoldMessenger.of(context);
                              final success = await ref
                                  .read(analyticsProvider.notifier)
                                  .restoreVersion(_selectedRoomId!, h['version_number'] as int);
                              if (success) {
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(content: Text('Restored room layout to Version ${h['version_number']}!')),
                                );
                              }
                            },
                            child: const Text('Restore', style: TextStyle(color: Colors.blue, fontSize: 12)),
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Project Analytics Tab
  Widget _buildProjectTab(AnalyticsState state, bool isDark) {
    final proj = state.projectAnalytics;
    if (proj == null) {
      return const Center(child: Text('Select a project to load analytics summary.'));
    }

    final double avgScore = (proj['average_overall_score'] as num).toDouble();
    final rooms = proj['room_scores'] as List;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Project Aggregated Stats
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text('Project Design Score Average', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text(
                    '${avgScore.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildProjectMiniStat('Rooms', '${proj['total_rooms']}', Colors.blue),
                      _buildProjectMiniStat('Total Assets', '${proj['total_furniture_count']}', Colors.purple),
                      _buildProjectMiniStat(
                        'Occupied Area', 
                        '${(proj['total_occupied_area'] / 10000.0).toStringAsFixed(1)} m²', 
                        Colors.orange
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Room Score Standings',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          // Rooms Score List
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              final r = rooms[index];
              final double score = (r['overall_score'] as num).toDouble();
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.meeting_room, color: AppTheme.primary),
                  title: Text(r['room_name'] ?? 'Room Name'),
                  subtitle: Text(r['room_type'] ?? 'Room Type', style: const TextStyle(fontSize: 11)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: score >= 80 ? Colors.green[100] : (score >= 60 ? Colors.orange[100] : Colors.red[100]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${score.round()}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: score >= 80 ? Colors.green[900] : (score >= 60 ? Colors.orange[900] : Colors.red[900]),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProjectMiniStat(String title, String val, Color color) {
    return Column(
      children: [
        Text(val, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

// Custom Circular Progress for Design Health Gauge
class CustomCircularProgress extends StatelessWidget {
  final double value;
  final double size;
  final double strokeWidth;
  final Widget centerWidget;

  const CustomCircularProgress({
    super.key,
    required this.value,
    this.size = 120,
    this.strokeWidth = 10,
    required this.centerWidget,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            height: size,
            width: size,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: strokeWidth,
              backgroundColor: Colors.grey.withOpacity(0.1),
              color: AppTheme.primary,
            ),
          ),
          centerWidget,
        ],
      ),
    );
  }
}

// Custom painter to draw beautiful trend line graph
class TrendLinePainter extends CustomPainter {
  final List<double> data;
  final bool isDark;

  TrendLinePainter({required this.data, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paintLine = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintPoint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.fill;

    final paintBg = Paint()
      ..style = PaintingStyle.fill;

    // Draw reference horizontal gridlines
    final gridPaint = Paint()
      ..color = isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0)
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      double y = size.height * (i / 4.0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    double dx = data.length > 1 ? size.width / (data.length - 1) : size.width;
    
    // Scale data from 0..100 to fits size height
    List<Offset> points = [];
    for (int i = 0; i < data.length; i++) {
      double val = data[i];
      // Limit to 100 max
      double score = val.clamp(0.0, 100.0);
      double y = size.height - (score / 100.0) * size.height;
      points.add(Offset(i * dx, y));
    }

    // Draw shaded gradient below the trend line
    final pathGrad = Path();
    pathGrad.moveTo(0, size.height);
    for (var pt in points) {
      pathGrad.lineTo(pt.dx, pt.dy);
    }
    pathGrad.lineTo(points.last.dx, size.height);
    pathGrad.close();

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    paintBg.shader = LinearGradient(
      colors: [AppTheme.primary.withOpacity(0.3), AppTheme.primary.withOpacity(0.01)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(rect);
    canvas.drawPath(pathGrad, paintBg);

    // Draw line
    final pathLine = Path();
    pathLine.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      pathLine.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(pathLine, paintLine);

    // Draw points
    for (var pt in points) {
      canvas.drawCircle(pt, 5.0, paintPoint);
      canvas.drawCircle(pt, 3.0, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
