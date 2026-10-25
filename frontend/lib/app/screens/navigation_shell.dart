import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../themes/app_theme.dart';

class NavigationShell extends ConsumerWidget {
  final Widget child;

  const NavigationShell({
    super.key,
    required this.child,
  });

  int _getSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/projects')) return 1;
    if (location.startsWith('/insights')) return 2;
    if (location.startsWith('/notifications')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0; // Default to /home
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/projects');
        break;
      case 2:
        context.go('/insights');
        break;
      case 3:
        context.go('/notifications');
        break;
      case 4:
        context.go('/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int selectedIndex = _getSelectedIndex(context);

    return Scaffold(
      body: SafeArea(
        child: ResponsiveLayout(
          mobileBody: _buildMobileTabletLayout(context, ref, selectedIndex),
          tabletBody: _buildMobileTabletLayout(context, ref, selectedIndex),
          desktopBody: _buildDesktopLayout(context, ref, selectedIndex),
        ),
      ),
    );
  }

  // Mobile & Tablet Layout (uses BottomNavigationBar)
  Widget _buildMobileTabletLayout(BuildContext context, WidgetRef ref, int selectedIndex) {
    return Column(
      children: [
        // App Bar
        _buildAppBar(context, ref),
        // Child screen content
        Expanded(child: child),
        // Bottom Navigation Bar
        BottomNavigationBar(
          currentIndex: selectedIndex,
          onTap: (index) => _onItemTapped(index, context),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_work_outlined),
              activeIcon: Icon(Icons.home_work),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.layers_outlined),
              activeIcon: Icon(Icons.layers),
              label: 'Projects',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.analytics_outlined),
              activeIcon: Icon(Icons.analytics),
              label: 'Insights',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications_none_outlined),
              activeIcon: Icon(Icons.notifications),
              label: 'Alerts',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ],
    );
  }

  // Desktop Layout (uses Sidebar NavigationRail)
  Widget _buildDesktopLayout(BuildContext context, WidgetRef ref, int selectedIndex) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Row(
      children: [
        // Left Navigation Rail
        NavigationRail(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) => _onItemTapped(index, context),
          labelType: NavigationRailLabelType.all,
          leading: const Padding(
            padding: EdgeInsets.symmetric(vertical: 24.0),
            child: Icon(Icons.architecture_rounded, size: 40, color: AppTheme.primary),
          ),
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.home_work_outlined),
              selectedIcon: Icon(Icons.home_work),
              label: Text('Home'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.layers_outlined),
              selectedIcon: Icon(Icons.layers),
              label: Text('Projects'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.analytics_outlined),
              selectedIcon: Icon(Icons.analytics),
              label: Text('Insights'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.notifications_none_outlined),
              selectedIcon: Icon(Icons.notifications),
              label: Text('Alerts'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: Text('Profile'),
            ),
          ],
        ),
        VerticalDivider(thickness: 1, width: 1, color: borderColor),
        // Content Area
        Expanded(
          child: Column(
            children: [
              _buildAppBar(context, ref),
              Expanded(child: child),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAppBar(BuildContext context, WidgetRef ref) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final Color borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    final profile = ref.watch(authProvider).profile;
    final roleName = profile != null ? (profile['role'] ?? 'Customer') : 'Guest';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(
          bottom: BorderSide(
            color: borderColor,
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.architecture_rounded, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                'FlowSpace',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
              ),
            ],
          ),
          // User role banner or state
          Row(
            children: [
              if (roleName.toString() == 'Administrator') ...[
                TextButton.icon(
                  key: const Key('admin_panel_button'),
                  onPressed: () => context.push('/admin'),
                  icon: const Icon(Icons.admin_panel_settings_rounded, color: AppTheme.primary, size: 18),
                  label: const Text(
                    'Admin Panel',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  roleName.toString().toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
