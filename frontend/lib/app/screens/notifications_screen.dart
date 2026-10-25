import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/project/providers/dashboard_provider.dart';
import '../../shared/widgets/custom_card.dart';
import '../../shared/widgets/loading_indicator.dart';
import '../../shared/widgets/empty_state.dart';
import '../../app/constants/app_constants.dart';
import '../../app/themes/app_theme.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(dashboardProvider.notifier).fetchDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(dashboardProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (dashboardState.isLoading && dashboardState.data == null) {
      return const Scaffold(
        body: LoadingIndicator(message: 'Loading notifications...'),
      );
    }

    final data = dashboardState.data ?? {};
    final notifications = data['notifications'] as List<dynamic>? ?? [];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        shape: Border(bottom: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(dashboardProvider.notifier).fetchDashboard(),
        color: theme.primaryColor,
        child: notifications.isEmpty
            ? Center(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: EmptyState(
                    title: 'All Caught Up! 🎉',
                    message: 'No new design alerts or project comments at this time.',
                    onActionPressed: () => ref.read(dashboardProvider.notifier).fetchDashboard(),
                    actionText: 'Refresh',
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(AppConstants.space16),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final notif = notifications[index] as Map<String, dynamic>;
                final title = notif['title'] ?? 'Notification';
                final message = notif['message'] ?? '';
                final time = notif['created_at'] ?? 'Just now';
                final type = notif['type'] ?? 'info';

                IconData icon = Icons.info_outline;
                Color iconColor = AppTheme.info;
                if (type == 'success') {
                  icon = Icons.check_circle_outline_rounded;
                  iconColor = AppTheme.success;
                } else if (type == 'warning') {
                  icon = Icons.warning_amber_rounded;
                  iconColor = AppTheme.warning;
                } else if (type == 'error') {
                  icon = Icons.error_outline_rounded;
                  iconColor = AppTheme.error;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: AppConstants.space8),
                    child: CustomCard(
                      padding: const EdgeInsets.all(AppConstants.space16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, color: iconColor, size: 24),
                          const SizedBox(width: AppConstants.space16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: AppConstants.space4),
                                Text(
                                  message,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                  ),
                                ),
                                const SizedBox(height: AppConstants.space8),
                                Text(
                                  time.toString(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: isDark ? AppTheme.darkBorder : AppTheme.lightTextHint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
