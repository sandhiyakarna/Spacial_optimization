import '../../../app/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:math';
import '../providers/dashboard_provider.dart';
import '../providers/project_provider.dart';
import 'project_dialogs.dart';
import '../../../shared/widgets/custom_card.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/error_state.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../shared/widgets/snackbar_manager.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isCreatingFromTemplate = false;

  final List<Map<String, dynamic>> _popularTemplates = [
    {
      'title': 'Ergonomic Home Office',
      'description': 'Designed for high focus with posture-optimized desk placement and glare control.',
      'icon': Icons.desk_outlined,
      'tag': 'Ergonomic Check',
      'rating': '4.9',
      'views': '140+ layouts',
    },
    {
      'title': 'Scandinavian Living Room',
      'description': 'Light wood aesthetics with minimal furniture clutter and maximum natural light.',
      'icon': Icons.chair_outlined,
      'tag': 'Space-Optimized',
      'rating': '4.8',
      'views': '98+ layouts',
    },
    {
      'title': 'Compact Studio Kitchen',
      'description': 'L-shaped workflow minimizing walking distance between fridge, sink, and stove.',
      'icon': Icons.kitchen_outlined,
      'tag': 'Golden Triangle',
      'rating': '4.7',
      'views': '64+ layouts',
    },
    {
      'title': 'Minimalist Bedroom',
      'description': 'A calming sanctuary focused on ventilation and quiet layouts.',
      'icon': Icons.bed_outlined,
      'tag': 'Acoustic-Friendly',
      'rating': '4.8',
      'views': '112+ layouts',
    },
  ];

  final List<Map<String, String>> _aiTips = [
    {
      'title': 'Optimize Lighting Angles',
      'text': 'Place task lights at 45-degree angles to your screens to completely eliminate screen glare and reduce eye strain.',
    },
    {
      'title': 'Pathway Clearance Rules',
      'text': 'Ensure a minimum of 75cm clearance between furniture pieces in active pathways to allow comfortable traffic flow.',
    },
    {
      'title': 'Plants Boost Focus',
      'text': 'Integrating biophilic elements like small desktop plants can increase productivity by up to 15% and lower cortisol.',
    },
    {
      'title': 'The Power of Mirrors',
      'text': 'Placing a mirror directly opposite a window will bounce light throughout the room, making small spaces feel larger.',
    },
    {
      'title': 'Ergonomic Desk Height',
      'text': 'Your elbows should form a 90-degree angle when typing. Adjust your chair height first, then support your feet if needed.',
    },
  ];

  Map<String, String> _getTipOfTheDay() {
    final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays;
    return _aiTips[dayOfYear % _aiTips.length];
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(dashboardProvider.notifier).fetchDashboard();
    });
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (context) => const CreateProjectDialog(),
    ).then((val) {
      if (val == true) {
        ref.read(dashboardProvider.notifier).fetchDashboard();
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(dashboardProvider);
    final userProfile = ref.watch(authProvider).profile;

    if (dashboardState.isLoading && dashboardState.data == null) {
      return const Scaffold(
        body: LoadingIndicator(message: 'Initializing your creative space...'),
      );
    }

    if (dashboardState.errorMessage != null && dashboardState.data == null) {
      return Scaffold(
        body: ErrorState(
          message: dashboardState.errorMessage!,
          onRetry: () => ref.read(dashboardProvider.notifier).fetchDashboard(),
        ),
      );
    }

    final data = dashboardState.data ?? {};
    final recentProjects = data['recent_projects'] as List<dynamic>? ?? [];
    final recentActivity = data['recent_activity'] as List<dynamic>? ?? [];
    final aiRecommendations = data['ai_recommendations'] as List<dynamic>? ?? [];
    final analyticsSummary = data['analytics_summary'] as Map<String, dynamic>? ?? {};
    final notifications = data['notifications'] as List<dynamic>? ?? [];

    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1100;
    final isTablet = width >= 650 && width < 1100;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.read(dashboardProvider.notifier).fetchDashboard(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 32.0 : 16.0,
              vertical: 24.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isCreatingFromTemplate)
                  const LinearProgressIndicator(minHeight: 3),
                
                // 1. GREETING & NOTIFICATION SHORTCUT
                _buildHeader(context, userProfile, notifications),
                const SizedBox(height: 20),

                // 2. AI TIP OF THE DAY
                _buildAiTipBanner(context),
                const SizedBox(height: 24),

                // 3. RESPONSIVE DASHBOARD LAYOUT
                if (isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildContinueProjectHero(context, recentProjects),
                            const SizedBox(height: 24),
                            _buildQuickStatsSection(context, data, analyticsSummary),
                            const SizedBox(height: 24),
                            _buildPopularTemplatesSection(context),
                          ],
                        ),
                      ),
                      const SizedBox(width: 28),
                      // Right Column
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildRecentProjectsSection(context, recentProjects),
                            const SizedBox(height: 24),
                            _buildActivityRecommendationsSection(context, recentActivity, aiRecommendations),
                          ],
                        ),
                      ),
                    ],
                  )
                else if (isTablet)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildContinueProjectHero(context, recentProjects),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildQuickStatsSection(context, data, analyticsSummary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildPopularTemplatesSection(context),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildRecentProjectsSection(context, recentProjects),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildActivityRecommendationsSection(context, recentActivity, aiRecommendations),
                          ),
                        ],
                      ),
                    ],
                  )
                else
                  // Mobile Layout
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildContinueProjectHero(context, recentProjects),
                      const SizedBox(height: 24),
                      _buildQuickStatsSection(context, data, analyticsSummary),
                      const SizedBox(height: 24),
                      _buildRecentProjectsSection(context, recentProjects),
                      const SizedBox(height: 24),
                      _buildPopularTemplatesSection(context),
                      const SizedBox(height: 24),
                      _buildActivityRecommendationsSection(context, recentActivity, aiRecommendations),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Map<String, dynamic>? userProfile, List<dynamic> notifications) {
    final String fullName = userProfile?['full_name'] ?? 'FlowSpace Designer';
    final unreadCount = notifications.where((n) => n['read'] == false).length;

    final hour = DateTime.now().hour;
    String greetingWord = 'Good morning';
    if (hour >= 12 && hour < 17) {
      greetingWord = 'Good afternoon';
    } else if (hour >= 17) {
      greetingWord = 'Good evening';
    }

    final formattedDate = _getFormattedDate();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$greetingWord, $fullName!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              formattedDate,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).hintColor,
                  ),
            ),
          ],
        ),
        // Notifications Shortcut with badge
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text('$unreadCount'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            textColor: Colors.white,
            alignment: const Alignment(0.6, -0.6),
            child: IconButton(
              icon: Icon(
                unreadCount > 0 ? Icons.notifications_active_outlined : Icons.notifications_none_outlined,
                color: unreadCount > 0 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () => _showNotificationsBottomSheet(context, notifications),
              tooltip: 'Notifications',
            ),
          ),
        ),
      ],
    );
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    return '${weekdays[now.weekday % 7]}, ${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  void _showNotificationsBottomSheet(BuildContext context, List<dynamic> notifications) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.6,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Notifications',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      '${notifications.length} Alerts',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),
              Expanded(
                child: notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_none, size: 48, color: Theme.of(context).hintColor),
                            const SizedBox(height: 8),
                            Text('All caught up!', style: TextStyle(color: Theme.of(context).hintColor)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: notifications.length,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemBuilder: (context, index) {
                          final n = notifications[index];
                          final unread = n['read'] == false;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: unread
                                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                                  : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                              child: Icon(
                                unread ? Icons.mark_chat_unread : Icons.chat_bubble_outline,
                                color: unread ? Theme.of(context).colorScheme.primary : Theme.of(context).hintColor,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              n['title'] ?? '',
                              style: TextStyle(
                                fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              n['message'] ?? '',
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: unread
                                ? Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAiTipBanner(BuildContext context) {
    final tip = _getTipOfTheDay();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  Theme.of(context).colorScheme.secondary.withValues(alpha: 0.05),
                ]
              : [
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.02),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            radius: 24,
            child: Icon(
              Icons.lightbulb_outline_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'AI Tip of the Day: ',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    Text(
                      tip['title'] ?? '',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  tip['text'] ?? '',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueProjectHero(BuildContext context, List<dynamic> recentProjects) {
    final hasProjects = recentProjects.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!hasProjects) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.architecture_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No Projects in Progress',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start creating your smart room layouts, optimize space utilization and generate structural interior design reports.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Start New Project'),
                onPressed: _showCreateDialog,
              ),
            ],
          ),
        ),
      );
    }

    final project = recentProjects.first;
    final String name = project['project_name'] ?? 'Unnamed Project';
    final String id = project['id'] ?? '';

    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: BlueprintPainter(
                  gridColor: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                  gridSpacing: 18.0,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    isDark ? Colors.black.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.85),
                    isDark ? Colors.black.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.4),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              padding: const EdgeInsets.all(20.0),
              child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Modern Style',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '92%',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Progress',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: const LinearProgressIndicator(
                      value: 0.92,
                      minHeight: 6,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.secondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            ElevatedButton(
              onPressed: () => context.go('/projects/$id/workspace'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                elevation: 4,
              ),
              child: const Text(
                'Continue',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStatsSection(BuildContext context, Map<String, dynamic> data, Map<String, dynamic> analyticsSummary) {
    final int totalProjects = data['total_projects'] ?? 0;
    final int totalRooms = data['total_rooms'] ?? 0;
    final String spaceUtil = analyticsSummary['average_room_utilization'] ?? '0%';
    final String compliance = analyticsSummary['ergonomic_compliance_rate'] ?? '0%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Statistics',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final double cardWidth = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildStatCard(
                  context: context,
                  width: cardWidth,
                  title: 'Active Projects',
                  value: '$totalProjects',
                  icon: Icons.folder_open_rounded,
                  color: Colors.blue,
                ),
                _buildStatCard(
                  context: context,
                  width: cardWidth,
                  title: 'Configured Rooms',
                  value: '$totalRooms',
                  icon: Icons.meeting_room_outlined,
                  color: AppTheme.primary,
                ),
                _buildStatCard(
                  context: context,
                  width: cardWidth,
                  title: 'Space Utilization',
                  value: spaceUtil,
                  icon: Icons.space_dashboard_outlined,
                  color: Colors.orange,
                  progressValue: _parsePercentage(spaceUtil),
                ),
                _buildStatCard(
                  context: context,
                  width: cardWidth,
                  title: 'Ergonomic Score',
                  value: compliance,
                  icon: Icons.health_and_safety_outlined,
                  color: Colors.green,
                  progressValue: _parsePercentage(compliance),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  double? _parsePercentage(String percentageString) {
    try {
      final cleaned = percentageString.replaceAll('%', '').trim();
      return double.parse(cleaned) / 100.0;
    } catch (_) {
      return null;
    }
  }

  Widget _buildStatCard({
    required BuildContext context,
    required double width,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    double? progressValue,
  }) {
    return CustomCard(
      width: width,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              if (progressValue != null)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    value: progressValue,
                    strokeWidth: 3,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).hintColor,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopularTemplatesSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Popular Layout Templates',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              'Quick Start',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 155,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _popularTemplates.length,
            itemBuilder: (context, index) {
              final template = _popularTemplates[index];
              return Container(
                width: 240,
                margin: const EdgeInsets.only(right: 16.0),
                child: CustomCard(
                  onTap: () => _handleTemplateSelection(context, template),
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(
                            template['icon'] as IconData,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              template['tag'] as String,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        template['title'] as String,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          template['description'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                height: 1.25,
                              ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 12),
                          const SizedBox(width: 2),
                          Text(
                            template['rating'] as String,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.history_edu, color: Theme.of(context).hintColor, size: 12),
                          const SizedBox(width: 2),
                          Text(
                            template['views'] as String,
                            style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _handleTemplateSelection(BuildContext context, Map<String, dynamic> template) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Use "${template['title']}"?'),
          content: Text(
            'Would you like to start a new project based on the pre-optimized ${template['title'].toLowerCase()} design?\n\n'
            'This sets up your project with structural rules, space parameters, and item libraries ready for customized editing.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                setState(() => _isCreatingFromTemplate = true);
                
                final success = await ref.read(projectProvider.notifier).createProject(
                  projectName: '${template['title']} Project',
                  description: template['description'],
                  location: 'Design Studio',
                );
                
                setState(() => _isCreatingFromTemplate = false);
                
                if (context.mounted) {
                  if (success) {
                    SnackbarManager.showSuccess(context, 'Template initialized! Project created.');
                    ref.read(dashboardProvider.notifier).fetchDashboard();
                  } else {
                    final error = ref.read(projectProvider).errorMessage ?? 'Failed to initialize template';
                    SnackbarManager.showError(context, error);
                  }
                }
              },
              child: const Text('Use Template'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecentProjectsSection(BuildContext context, List<dynamic> recentProjects) {
    final displayProjects = recentProjects.length > 1
        ? recentProjects.skip(1).toList()
        : recentProjects;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Other Recent Projects',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            TextButton(
              onPressed: () => context.go('/projects'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              child: Row(
                children: [
                  const Text('View All'),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 14, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (displayProjects.isEmpty)
          CustomCard(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Center(
              child: Text(
                'No other projects found.',
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: min(3, displayProjects.length),
            itemBuilder: (context, index) {
              final project = displayProjects[index] as Map<String, dynamic>;
              final String name = project['project_name'] ?? 'Unnamed';
              final String location = project['location'] ?? 'Unknown';
              final String status = project['status'] ?? 'Draft';
              final bool isFavorite = project['is_favorite'] == true;
              final String id = project['id'];

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: CustomCard(
                  onTap: () => context.go('/projects/$id/workspace'),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.architecture_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$location • $status',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: isFavorite ? Colors.amber : Theme.of(context).hintColor,
                        ),
                        onPressed: () async {
                          await ref.read(projectProvider.notifier).toggleFavorite(id);
                          ref.read(dashboardProvider.notifier).fetchDashboard();
                        },
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Theme.of(context).hintColor,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildActivityRecommendationsSection(
    BuildContext context,
    List<dynamic> recentActivity,
    List<dynamic> recommendations,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI Workspace Audit & Activity',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'AI Audits'),
                  Tab(text: 'Activity Log'),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: TabBarView(
                  children: [
                    recommendations.isEmpty
                        ? const Center(child: Text('No workspace audits run.'))
                        : ListView.builder(
                            itemCount: min(3, recommendations.length),
                            itemBuilder: (context, index) {
                              final rec = recommendations[index];
                              return Card(
                                elevation: 0,
                                margin: const EdgeInsets.only(bottom: 8),
                                color: Theme.of(context).colorScheme.surfaceContainerLow,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.psychology, color: Colors.purpleAccent, size: 20),
                                  title: Text(
                                    rec['title'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    rec['description'] ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              );
                            },
                          ),
                    recentActivity.isEmpty
                        ? const Center(child: Text('No recent activity.'))
                        : ListView.builder(
                            itemCount: min(3, recentActivity.length),
                            itemBuilder: (context, index) {
                              final act = recentActivity[index];
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
                                  child: Icon(Icons.history, size: 12, color: Theme.of(context).colorScheme.secondary),
                                ),
                                title: Text(act['description'] ?? ''),
                                subtitle: const Text('Just now'),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
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

