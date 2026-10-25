import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/themes/app_theme.dart';
import '../../../core/utils/url_helper.dart';
import '../../../shared/widgets/custom_card.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../providers/admin_provider.dart';
import '../../../features/furniture/models/furniture_asset.dart';
import '../../designer/models/material_model.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminProvider);
    final notifier = ref.read(adminProvider.notifier);
    
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final textPrimaryColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondaryColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    final width = MediaQuery.of(context).size.width;
    final bool isDesktop = width > 900;

    // Sidebar/Drawer Destination definitions
    final List<Map<String, dynamic>> destinations = [
      {'section': AdminSection.dashboard, 'label': 'Dashboard', 'icon': Icons.dashboard_rounded},
      {'section': AdminSection.furniture, 'label': 'Furniture', 'icon': Icons.chair_rounded},
      {'section': AdminSection.materials, 'label': 'Materials', 'icon': Icons.texture_rounded},
      {'section': AdminSection.categories, 'label': 'Categories', 'icon': Icons.category_rounded},
      {'section': AdminSection.users, 'label': 'Users', 'icon': Icons.people_alt_rounded},
      {'section': AdminSection.analytics, 'label': 'Analytics', 'icon': Icons.analytics_rounded},
      {'section': AdminSection.system, 'label': 'System', 'icon': Icons.dns_rounded},
    ];

    // Helper to get active view widget
    Widget buildBody() {
      if (state.isLoading) {
        return const Center(child: LoadingIndicator());
      }
      
      switch (state.activeSection) {
        case AdminSection.dashboard:
          return _buildDashboardView(context, ref, state, notifier, isDark);
        case AdminSection.furniture:
          return _buildFurnitureView(context, ref, state, notifier, isDark);
        case AdminSection.materials:
          return _buildMaterialsView(context, ref, state, notifier, isDark);
        case AdminSection.categories:
          return _buildCategoriesView(context, ref, state, notifier, isDark);
        case AdminSection.users:
          return _buildUsersView(context, ref, state, notifier, isDark);
        case AdminSection.analytics:
          return _buildAnalyticsView(context, ref, state, notifier, isDark);
        case AdminSection.system:
          return _buildSystemView(context, ref, state, notifier, isDark);
      }
    }

    // Left Navigation Sidebar (Desktop)
    Widget buildSidebar() {
      return Container(
        width: 260,
        decoration: BoxDecoration(
          color: surfaceColor,
          border: Border(right: BorderSide(color: borderColor, width: 1.0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Row(
                children: [
                  const Icon(Icons.admin_panel_settings_rounded, color: AppTheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'FlowSpace Admin',
                      style: TextStyle(
                        color: textPrimaryColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                itemCount: destinations.length,
                itemBuilder: (context, index) {
                  final dest = destinations[index];
                  final isSelected = state.activeSection == dest['section'];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Material(
                      color: Colors.transparent,
                      child: ListTile(
                        key: Key('sidebar_item_${dest['label'].toLowerCase()}'),
                        selected: isSelected,
                        leading: Icon(dest['icon'], color: isSelected ? Colors.white : textSecondaryColor),
                        title: Text(
                          dest['label'],
                          style: TextStyle(
                            color: isSelected ? Colors.white : textPrimaryColor,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                        selectedTileColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        onTap: () => notifier.changeSection(dest['section'] as AdminSection),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: TextButton.icon(
                onPressed: () => context.go('/home'),
                icon: const Icon(Icons.logout_rounded, color: AppTheme.error),
                label: const Text('Exit Panel', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      );
    }

    // Mobile Drawer
    Widget buildDrawer() {
      return Drawer(
        backgroundColor: surfaceColor,
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.admin_panel_settings_rounded, color: AppTheme.primary, size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'FlowSpace Admin',
                      style: TextStyle(
                        color: textPrimaryColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                itemCount: destinations.length,
                itemBuilder: (context, index) {
                  final dest = destinations[index];
                  final isSelected = state.activeSection == dest['section'];
                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                      key: Key('drawer_item_${dest['label'].toLowerCase()}'),
                      selected: isSelected,
                      leading: Icon(dest['icon'], color: isSelected ? Colors.white : textSecondaryColor),
                      title: Text(
                        dest['label'],
                        style: TextStyle(
                          color: isSelected ? Colors.white : textPrimaryColor,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selectedTileColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      onTap: () {
                        notifier.changeSection(dest['section'] as AdminSection);
                        Navigator.pop(context); // Close drawer
                      },
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const Icon(Icons.logout_rounded, color: AppTheme.error),
                title: const Text('Exit Panel', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context);
                  context.go('/home');
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      drawer: isDesktop ? null : buildDrawer(),
      appBar: isDesktop
          ? null
          : AppBar(
              backgroundColor: surfaceColor,
              elevation: 0,
              iconTheme: IconThemeData(color: textPrimaryColor),
              title: Text(
                destinations.firstWhere((d) => d['section'] == state.activeSection)['label'],
                style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => notifier.fetchAdminDashboard(),
                ),
              ],
            ),
      body: Row(
        children: [
          if (isDesktop) buildSidebar(),
          Expanded(
            child: Column(
              children: [
                if (isDesktop)
                  Container(
                    height: 70,
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      border: Border(bottom: BorderSide(color: borderColor)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          destinations.firstWhere((d) => d['section'] == state.activeSection)['label'],
                          style: TextStyle(
                            color: textPrimaryColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          onPressed: () => notifier.fetchAdminDashboard(),
                          tooltip: 'Refresh system metrics',
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: state.errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  'Error loading metrics',
                                  style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  state.errorMessage!,
                                  style: TextStyle(color: textSecondaryColor),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () => notifier.fetchAdminDashboard(),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : buildBody(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Sub-View: Dashboard ---
  Widget _buildDashboardView(BuildContext context, WidgetRef ref, AdminState state, AdminNotifier notifier, bool isDark) {
    final textPrimaryColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondaryColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stat Cards Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth > 1200 ? 4 : (constraints.maxWidth > 700 ? 2 : 1);
              return GridView.count(
                crossAxisCount: cols,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: cols == 4 ? 1.5 : 2.0,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStatCard(
                    context,
                    title: 'Active Users',
                    value: '${state.activeUsersCount}',
                    trend: '▲ 12% vs last week',
                    icon: Icons.people_alt_rounded,
                    colors: [const Color(0xFF0F766E), const Color(0xFF14B8A6)],
                  ),
                  _buildStatCard(
                    context,
                    title: 'Projects Created',
                    value: '${state.projectsCount}',
                    trend: '▲ 8% vs last week',
                    icon: Icons.layers_rounded,
                    colors: [const Color(0xFF5B5BD6), const Color(0xFF818CF8)],
                  ),
                  _buildStatCard(
                    context,
                    title: 'Furniture Assets',
                    value: '${state.furnitureAssetsCount}',
                    trend: '▲ 24 uploaded recently',
                    icon: Icons.chair_rounded,
                    colors: [const Color(0xFFEA580C), const Color(0xFFF97316)],
                  ),
                  _buildStatCard(
                    context,
                    title: 'Materials Registered',
                    value: '${state.materialsCount}',
                    trend: '▲ 5 added this week',
                    icon: Icons.texture_rounded,
                    colors: [const Color(0xFF0284C7), const Color(0xFF38BDF8)],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          
          // Storage Usage & Activity Card
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Storage card
              Expanded(
                flex: 3,
                child: CustomCard(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Storage Usage', style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 16)),
                          const Icon(Icons.storage_rounded, color: AppTheme.primary),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '${(state.storageUsedBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB used of ${(state.storageTotalBytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB limit',
                        style: TextStyle(color: textPrimaryColor, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: state.storageUsedBytes / state.storageTotalBytes,
                          backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                          color: AppTheme.primary,
                          minHeight: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Using ${(state.storageUsedBytes / state.storageTotalBytes * 100).toStringAsFixed(1)}% of total allocated quota.',
                        style: TextStyle(color: textSecondaryColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Recent Activity Log
          Text('Recent Activity Log', style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 12),
          CustomCard(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: state.recentActivities.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final act = state.recentActivities[index];
                IconData actIcon = Icons.info_rounded;
                if (act['icon'] == 'upload_file') actIcon = Icons.upload_file_rounded;
                if (act['icon'] == 'add_circle') actIcon = Icons.add_circle_outline_rounded;
                if (act['icon'] == 'texture') actIcon = Icons.texture_rounded;
                if (act['icon'] == 'dns') actIcon = Icons.dns_rounded;
                if (act['icon'] == 'block') actIcon = Icons.block_flipped;
                if (act['icon'] == 'admin_panel_settings') actIcon = Icons.admin_panel_settings_rounded;
                if (act['icon'] == 'delete_sweep') actIcon = Icons.delete_sweep_rounded;

                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                      child: Icon(actIcon, color: AppTheme.primary, size: 20),
                    ),
                    title: Text(act['action'], style: TextStyle(color: textPrimaryColor, fontSize: 14)),
                    subtitle: Text('${act['user']} • ${act['time']}', style: TextStyle(color: textSecondaryColor, fontSize: 12)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- Sub-View: Furniture ---
  Widget _buildFurnitureView(BuildContext context, WidgetRef ref, AdminState state, AdminNotifier notifier, bool isDark) {
    final textPrimaryColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondaryColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    final searchController = TextEditingController(text: state.furnitureSearch);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Asset Administration', style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
              FloatingActionButton.extended(
                onPressed: () => context.push('/admin/upload-furniture'),
                label: const Text('Upload Asset'),
                icon: const Icon(Icons.add_rounded),
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Search and Filters Row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search furniture by name, style, or tag...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              searchController.clear();
                              notifier.updateSearch('');
                            },
                          )
                        : null,
                  ),
                  onSubmitted: (val) => notifier.updateSearch(val.trim()),
                ),
              ),
              const SizedBox(width: 16),
              DropdownButton<String>(
                value: state.furnitureCategoryFilter,
                hint: const Text('All Categories'),
                dropdownColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                items: [
                  const DropdownMenuItem(value: '', child: Text('All Categories')),
                  ...state.categories.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))),
                ],
                onChanged: (val) => notifier.updateCategoryFilter(val),
              ),
              const SizedBox(width: 16),
              DropdownButton<String>(
                value: state.furnitureStyleFilter,
                hint: const Text('All Styles'),
                dropdownColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                items: [
                  const DropdownMenuItem(value: '', child: Text('All Styles')),
                  ...['Modern', 'Scandinavian', 'Minimal', 'Industrial', 'Classic', 'Minimalist', 'Biophilic'].map((s) => DropdownMenuItem(value: s, child: Text(s))),
                ],
                onChanged: (val) => notifier.updateStyleFilter(val),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Bulk Actions Bar
          if (state.selectedFurnitureIds.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Text(
                    '${state.selectedFurnitureIds.length} assets selected',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _showBulkChangeCategoryDialog(context, notifier, state.categories),
                    icon: const Icon(Icons.category_rounded, color: AppTheme.primary, size: 20),
                    label: const Text('Change Category', style: TextStyle(color: AppTheme.primary)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showBulkDeleteConfirmDialog(context, notifier, state.selectedFurnitureIds.length),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error, foregroundColor: Colors.white),
                    icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                    label: const Text('Delete Selected'),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => notifier.clearSelection(),
                    icon: const Icon(Icons.close_rounded, color: Colors.grey),
                    tooltip: 'Deselect all',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (state.furnitureAssets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Row(
                children: [
                  Checkbox(
                    value: state.selectedFurnitureIds.length == state.furnitureAssets.length && state.furnitureAssets.isNotEmpty,
                    onChanged: (val) {
                      if (val == true) {
                        notifier.selectAll();
                      } else {
                        notifier.clearSelection();
                      }
                    },
                  ),
                  const Text('Select All On This Page', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),

          Expanded(
            child: state.furnitureAssets.isEmpty
                ? Center(
                    child: Text('No furniture assets found in database.', style: TextStyle(color: textSecondaryColor)),
                  )
                : ListView.builder(
                    itemCount: state.furnitureAssets.length,
                    itemBuilder: (context, index) {
                      final asset = state.furnitureAssets[index];
                      final isSelected = state.selectedFurnitureIds.contains(asset.id);
                      final String thumbnailUrl = asset.thumbnailUrl;
                      final String resolvedUrl = (thumbnailUrl.contains('unsplash.com') || thumbnailUrl.isEmpty)
                          ? '/uploads/furniture/thumbnails/${asset.id.replaceAll('model_', '')}.png'
                          : thumbnailUrl;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: isSelected,
                                  onChanged: (val) => notifier.toggleSelection(asset.id),
                                ),
                                const SizedBox(width: 8),
                                resolvedUrl.isNotEmpty
                                    ? Image.network(
                                        resolvedUrl.startsWith('http')
                                            ? resolvedUrl
                                            : '${getBaseUrl()}$resolvedUrl',
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.chair_rounded, size: 36),
                                      )
                                    : const Icon(Icons.chair_rounded, size: 36),
                              ],
                            ),
                            title: Text(asset.name, style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold)),
                            subtitle: Text('${asset.category} • ${asset.style} • Dimensions: ${asset.width}x${asset.depth}x${asset.height}cm', style: TextStyle(color: textSecondaryColor)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded, color: AppTheme.primary),
                                  onPressed: () => context.push('/admin/upload-furniture', extra: asset),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
                                  onPressed: () => _showDeleteConfirmDialog(context, notifier, asset),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          if (state.furnitureAssets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: state.furniturePage > 1 ? () => notifier.previousPage() : null,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Page ${state.furniturePage}',
                    style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: state.furnitureHasMore ? () => notifier.nextPage() : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirmDialog(BuildContext context, AdminNotifier notifier, FurnitureAsset asset) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text(
          'Are you sure you want to delete "${asset.name}"?\n\n'
          'This action is permanent and will delete the asset metadata and physical files (GLB, thumbnail, preview) from the server storage.'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error, foregroundColor: Colors.white),
            onPressed: () {
              notifier.deleteFurnitureAsset(asset.id);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBulkDeleteConfirmDialog(BuildContext context, AdminNotifier notifier, int count) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Bulk Deletion'),
        content: Text(
          'Are you sure you want to delete the $count selected furniture assets?\n\n'
          'This action is permanent and will delete the metadata and physical files for ALL selected assets from the server storage.'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error, foregroundColor: Colors.white),
            onPressed: () {
              notifier.bulkDeleteFurnitureAssets();
              Navigator.pop(context);
            },
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBulkChangeCategoryDialog(BuildContext context, AdminNotifier notifier, List<FurnitureCategory> categories) async {
    String? selectedCategoryName = categories.isNotEmpty ? categories.first.name : null;
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Bulk Change Category'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Select target category to apply to all selected furniture assets:'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedCategoryName,
                  items: categories.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
                  onChanged: (val) => setState(() => selectedCategoryName = val),
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (selectedCategoryName != null) {
                  notifier.bulkUpdateFurnitureCategory(selectedCategoryName!);
                  Navigator.pop(context);
                }
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  // --- Sub-View: Materials ---
  Widget _buildMaterialsView(BuildContext context, WidgetRef ref, AdminState state, AdminNotifier notifier, bool isDark) {
    return AdminMaterialsSection(
      materials: state.materials,
      notifier: notifier,
      isDark: isDark,
    );
  }

  // --- Sub-View: Categories ---
  Widget _buildCategoriesView(BuildContext context, WidgetRef ref, AdminState state, AdminNotifier notifier, bool isDark) {
    final textPrimaryColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondaryColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Product Categories Breakdown', style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
              FloatingActionButton.extended(
                onPressed: () => _showCategoryDialog(context, ref, notifier),
                label: const Text('Add Category'),
                icon: const Icon(Icons.add_rounded),
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          Expanded(
            child: state.categories.isEmpty
                ? Center(
                    child: Text('No categories registered.', style: TextStyle(color: textSecondaryColor)),
                  )
                : ListView.separated(
                    itemCount: state.categories.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final cat = state.categories[index];
                      final count = state.categoriesBreakdown[cat.name] ?? 0;
                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                            child: const Icon(Icons.category_rounded, color: AppTheme.primary, size: 20),
                          ),
                          title: Text(cat.name, style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold)),
                          subtitle: cat.description != null ? Text(cat.description!, style: TextStyle(color: textSecondaryColor, fontSize: 12)) : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$count Items',
                                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, color: AppTheme.primary),
                                onPressed: () => _showCategoryDialog(context, ref, notifier, category: cat),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
                                onPressed: () => _showDeleteCategoryConfirmDialog(context, notifier, cat),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCategoryDialog(BuildContext context, WidgetRef ref, AdminNotifier notifier, {FurnitureCategory? category}) async {
    final nameController = TextEditingController(text: category?.name);
    final descController = TextEditingController(text: category?.description);
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(category == null ? 'Add Category' : 'Edit Category'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Category Name'),
                validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'Description (Optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                if (category == null) {
                  notifier.createCategory(nameController.text.trim(), descController.text.trim());
                } else {
                  notifier.updateCategory(category.id, nameController.text.trim(), descController.text.trim());
                }
                Navigator.pop(context);
              }
            },
            child: Text(category == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteCategoryConfirmDialog(BuildContext context, AdminNotifier notifier, FurnitureCategory category) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Category Deletion'),
        content: Text(
          'Are you sure you want to delete the category "${category.name}"?\n\n'
          'All furniture assets currently assigned to this category will be reassigned to "Uncategorized".'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error, foregroundColor: Colors.white),
            onPressed: () {
              notifier.deleteCategory(category.id);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // --- Sub-View: Users ---
  Widget _buildUsersView(BuildContext context, WidgetRef ref, AdminState state, AdminNotifier notifier, bool isDark) {
    final textPrimaryColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondaryColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('System Users Management', style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            const TabBar(
              isScrollable: true,
              labelColor: AppTheme.primary,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppTheme.primary,
              tabs: [
                Tab(text: 'Users List'),
                Tab(text: 'Roles & Permissions'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                children: [
                  // Tab 1: Users List
                  Column(
                    children: [
                      Expanded(
                        child: CustomCard(
                          child: state.users.isEmpty
                              ? Center(child: Text('No users registered in system.', style: TextStyle(color: textSecondaryColor)))
                              : ListView.separated(
                                  itemCount: state.users.length,
                                  separatorBuilder: (context, index) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final user = state.users[index];
                                    final bool isSuspended = user['status'] == 'Suspended';
                                    return Material(
                                      color: Colors.transparent,
                                      child: ListTile(
                                        key: Key('user_row_${user['email']}'),
                                        leading: CircleAvatar(
                                          backgroundColor: isSuspended ? Colors.red.withValues(alpha: 0.1) : AppTheme.primary.withValues(alpha: 0.1),
                                          child: Icon(
                                            user['role'] == 'Administrator' ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                                            color: isSuspended ? Colors.red : AppTheme.primary,
                                          ),
                                        ),
                                        title: Text(user['name'], style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold)),
                                        subtitle: Text(
                                          '${user['email']} • Role: ${user['role']}\nLast Login: ${user['last_login']}',
                                          style: TextStyle(color: textSecondaryColor, fontSize: 12),
                                        ),
                                        isThreeLine: true,
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: isSuspended ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                user['status'],
                                                style: TextStyle(
                                                  color: isSuspended ? Colors.red : Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(Icons.edit_rounded, color: AppTheme.primary, size: 20),
                                              tooltip: 'Change User Role',
                                              onPressed: () => _showChangeRoleDialog(context, notifier, state.roles, user),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.vpn_key_rounded, color: AppTheme.secondary, size: 20),
                                              tooltip: 'Manage Sessions',
                                              onPressed: () => _showSessionsDialog(context, notifier, state, user),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error, size: 20),
                                              tooltip: 'Delete User',
                                              onPressed: () => _showDeleteUserDialog(context, notifier, user),
                                            ),
                                            Switch(
                                              value: !isSuspended,
                                              activeColor: AppTheme.primary,
                                              onChanged: (val) {
                                                if (user['role'] == 'Administrator' && ref.read(adminProvider).users.where((u) => u['role'] == 'Administrator' && u['status'] == 'Active').length <= 1 && !isSuspended) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('Cannot suspend the last active Administrator.')),
                                                  );
                                                } else {
                                                  notifier.toggleUserStatus(user['id'], user['status']);
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                  // Tab 2: Roles & Permissions
                  CustomCard(
                    child: state.roles.isEmpty
                        ? Center(child: Text('No roles defined.', style: TextStyle(color: textSecondaryColor)))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16.0),
                            itemCount: state.roles.length,
                            separatorBuilder: (context, index) => const Divider(height: 24),
                            itemBuilder: (context, index) {
                              final role = state.roles[index];
                              final List perms = role['permissions'] ?? [];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            role['name'] ?? '',
                                            style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            role['description'] ?? 'No description provided',
                                            style: TextStyle(color: textSecondaryColor, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.security_rounded, color: AppTheme.primary),
                                        tooltip: 'Modify Role Permissions',
                                        onPressed: () => _showModifyPermissionsDialog(context, notifier, state.permissions, role),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: perms.map<Widget>((p) {
                                      return Chip(
                                        label: Text(
                                          p['name'] ?? '',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                        backgroundColor: AppTheme.primary.withOpacity(0.1),
                                        side: BorderSide.none,
                                      );
                                    }).toList(),
                                  ),
                                ],
                              );
                            },
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

  // --- Sub-View: Analytics ---
  // --- Sub-View: Analytics ---
  Widget _buildAnalyticsView(BuildContext context, WidgetRef ref, AdminState state, AdminNotifier notifier, bool isDark) {
    final textPrimaryColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondaryColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    final telemetry = state.telemetryData;
    if (telemetry == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40.0),
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    final activeUsers = telemetry['active_users'] ?? {};
    final furnitureUsage = telemetry['furniture_usage'] ?? {};
    final projectStats = telemetry['project_statistics'] ?? {};
    final aiUsage = telemetry['ai_usage'] ?? {};
    final storageUsage = telemetry['storage_usage'] ?? {};
    final exportStats = telemetry['export_statistics'] ?? {};
    final charts = telemetry['charts'] ?? {};

    final List dauTrend = charts['dau_trend'] ?? [];
    final List projectsTrend = charts['projects_trend'] ?? [];
    final List aiJobsTrend = charts['ai_jobs_trend'] ?? [];

    // Find maximum count in trends to scale bar heights
    double maxCount = 1.0;
    for (var pt in dauTrend) {
      final val = (pt['count'] as num).toDouble();
      if (val > maxCount) maxCount = val;
    }
    for (var pt in aiJobsTrend) {
      final val = (pt['count'] as num).toDouble();
      if (val > maxCount) maxCount = val;
    }

    final List mostUsedFurniture = furnitureUsage['most_used'] ?? [];
    final Map<String, dynamic> categoriesBreakdown = furnitureUsage['categories_breakdown'] ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Time Filters
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'System Telemetry & Analytics',
                style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF252525) : const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: ['7d', '30d', '90d', 'all'].map((period) {
                    final isSelected = state.selectedPeriod == period;
                    final label = period == 'all' ? 'All Time' : 'Last $period';
                    return GestureDetector(
                      onTap: () => notifier.updateSelectedPeriod(period),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: isSelected ? Colors.white : textPrimaryColor.withOpacity(0.7),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // KPI Cards Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth > 900 ? 4 : (constraints.maxWidth > 500 ? 2 : 1);
              return GridView.count(
                crossAxisCount: cols,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: cols == 4 ? 1.5 : 2.0,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildTelemetryKpiCard(
                    context,
                    title: 'Active Users',
                    value: '${activeUsers['active_users_count'] ?? 0}',
                    subtext: 'Total Registered: ${activeUsers['total_users'] ?? 0}',
                    trendText: '${activeUsers['trend_percentage'] >= 0 ? '▲' : '▼'} ${activeUsers['trend_percentage']?.toStringAsFixed(1) ?? '0.0'}%',
                    trendColor: activeUsers['trend_percentage'] >= 0 ? Colors.greenAccent : Colors.redAccent,
                    icon: Icons.people_rounded,
                    colors: [const Color(0xFF0F766E), const Color(0xFF14B8A6)],
                  ),
                  _buildTelemetryKpiCard(
                    context,
                    title: 'AI Success Rate',
                    value: '${aiUsage['success_rate']?.toStringAsFixed(1) ?? '100.0'}%',
                    subtext: 'Avg Latency: ${aiUsage['avg_latency_seconds']?.toStringAsFixed(1) ?? '0.0'}s',
                    trendText: '${aiUsage['total_jobs'] ?? 0} jobs run',
                    trendColor: Colors.white70,
                    icon: Icons.psychology_rounded,
                    colors: [const Color(0xFF6B21A8), const Color(0xFF9333EA)],
                  ),
                  _buildTelemetryKpiCard(
                    context,
                    title: 'Storage Used',
                    value: '${((storageUsage['total_used_bytes'] ?? 0) / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB',
                    subtext: 'Limit: ${((storageUsage['limit_bytes'] ?? 5.0 * 1024 * 1024 * 1024) / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB',
                    trendText: '${(((storageUsage['total_used_bytes'] ?? 0) / (storageUsage['limit_bytes'] ?? 5.0 * 1024 * 1024 * 1024)) * 100.0).toStringAsFixed(1)}% full',
                    trendColor: Colors.amberAccent,
                    icon: Icons.storage_rounded,
                    colors: [const Color(0xFFEA580C), const Color(0xFFF97316)],
                  ),
                  _buildTelemetryKpiCard(
                    context,
                    title: 'Reports Exported',
                    value: '${exportStats['total_exports'] ?? 0}',
                    subtext: 'Formats: ${exportStats['exports_by_format']?.keys?.join(', ') ?? 'PDF'}',
                    trendText: 'Files generated',
                    trendColor: Colors.white70,
                    icon: Icons.download_rounded,
                    colors: [const Color(0xFF0369A1), const Color(0xFF0EA5E9)],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // Chart: Scrollable Dual Bar Chart (DAU & AI Request Trends)
          CustomCard(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Daily Active Users (DAU) & AI Jobs Trend',
                      style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(width: 4),
                        Text('DAU', style: TextStyle(color: textSecondaryColor, fontSize: 11)),
                        const SizedBox(width: 16),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(color: AppTheme.secondary, borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(width: 4),
                        Text('AI Jobs', style: TextStyle(color: textSecondaryColor, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 160,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(dauTrend.length, (index) {
                        final ptDau = dauTrend[index];
                        final ptAi = aiJobsTrend[index];
                        final dateLabel = ptDau['date'] as String;
                        final dauVal = (ptDau['count'] as num).toDouble();
                        final aiVal = (ptAi['count'] as num).toDouble();
                        return _buildDailyDualBar(dateLabel, dauVal, aiVal, maxCount, isDark);
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Bottom Detail Breakdowns
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left side: Furniture Asset & Catalog Breakdowns
              Expanded(
                flex: 4,
                child: CustomCard(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Furniture Usage Breakdown', style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 16),
                      Text('Popular Models (Placed in Rooms):', style: TextStyle(color: textSecondaryColor, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (mostUsedFurniture.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20.0),
                          child: Center(child: Text('No furniture items used in layouts yet.', style: TextStyle(color: textSecondaryColor, fontSize: 13))),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: mostUsedFurniture.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = mostUsedFurniture[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primary.withOpacity(0.1),
                                child: const Icon(Icons.chair_rounded, color: AppTheme.primary, size: 20),
                              ),
                              title: Text(item['name'] ?? 'Unknown Item', style: TextStyle(color: textPrimaryColor, fontSize: 13, fontWeight: FontWeight.bold)),
                              subtitle: Text(item['category'] ?? 'Furniture', style: TextStyle(color: textSecondaryColor, fontSize: 11)),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Used ${item['count'] ?? 0}x',
                                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 20),
                      Text('Rooms Catalog Categories Distribution:', style: TextStyle(color: textSecondaryColor, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: categoriesBreakdown.entries.map((e) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF202020) : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.folder_open_rounded, size: 14, color: textSecondaryColor),
                                const SizedBox(width: 6),
                                Text(e.key, style: TextStyle(color: textPrimaryColor, fontSize: 12, fontWeight: FontWeight.w500)),
                                const SizedBox(width: 4),
                                Text(
                                  '(${e.value})',
                                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              
              // Right side: Project Statistics
              Expanded(
                flex: 3,
                child: CustomCard(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Workspace Project Stats', style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 20),
                      _buildWorkspaceRow('Total Projects', '${projectStats['total_projects'] ?? 0}', Icons.folder_copy_rounded, isDark),
                      _buildWorkspaceRow('Total Rooms Plotted', '${projectStats['total_rooms'] ?? 0}', Icons.roofing_rounded, isDark),
                      _buildWorkspaceRow('Rooms / Project Avg', '${projectStats['average_rooms_per_project'] ?? 0.0}', Icons.analytics_rounded, isDark),
                      _buildWorkspaceRow('Average Design Score', '${projectStats['average_design_score']?.toStringAsFixed(1) ?? '75.0'}%', Icons.star_half_rounded, isDark),
                      const SizedBox(height: 24),
                      Text('Export Formats Distribution:', style: TextStyle(color: textSecondaryColor, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      if (exportStats['exports_by_format'] == null || (exportStats['exports_by_format'] as Map).isEmpty)
                        Text('No exports generated in this period.', style: TextStyle(color: textSecondaryColor, fontSize: 12))
                      else
                        ...(exportStats['exports_by_format'] as Map).entries.map((e) {
                          final double value = (e.value as num).toDouble();
                          final double total = (exportStats['total_exports'] as num).toDouble();
                          final double ratio = total > 0 ? value / total : 0.0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(e.key.toString(), style: TextStyle(color: textPrimaryColor, fontSize: 12, fontWeight: FontWeight.w500)),
                                    Text('${value.toInt()} files (${(ratio * 100).toStringAsFixed(0)}%)', style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: ratio,
                                    color: AppTheme.primary,
                                    backgroundColor: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE5E7EB),
                                    minHeight: 4,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryKpiCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtext,
    required String trendText,
    required Color trendColor,
    required IconData icon,
    required List<Color> colors,
  }) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Icon(icon, color: Colors.white70, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  subtext,
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                trendText,
                style: TextStyle(color: trendColor, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDailyDualBar(String dateLabel, double dauVal, double aiVal, double maxCount, bool isDark) {
    final double heightDau = maxCount > 0 ? (dauVal / maxCount) * 110.0 : 0.0;
    final double heightAi = maxCount > 0 ? (aiVal / maxCount) * 110.0 : 0.0;
    final labelColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    
    String displayLabel = dateLabel;
    try {
      final dateObj = DateTime.parse(dateLabel);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      displayLabel = '${dateObj.day} ${months[dateObj.month - 1]}';
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 12,
                height: heightDau + 4,
                decoration: const BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 12,
                height: heightAi + 4,
                decoration: const BoxDecoration(
                  color: AppTheme.secondary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(displayLabel, style: TextStyle(color: labelColor, fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildWorkspaceRow(String label, String value, IconData icon, bool isDark) {
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final subColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final borderCol = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderCol, width: 0.5))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: subColor),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
          Text(value, style: const TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }


  // --- Sub-View: System ---
  Widget _buildSystemView(BuildContext context, WidgetRef ref, AdminState state, AdminNotifier notifier, bool isDark) {
    final textPrimaryColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondaryColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Infrastructure Status Diagnostics', style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          
          // Diagnostic health lists
          CustomCard(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: state.systemHealth.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final key = state.systemHealth.keys.elementAt(index);
                final val = state.systemHealth[key]!;
                final bool isHealthy = val == 'HEALTHY' || val == 'CONNECTED' || !val.contains('FAIL');
                
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: Icon(
                      isHealthy ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
                      color: isHealthy ? Colors.green : Colors.red,
                    ),
                    title: Text(key, style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold)),
                    trailing: Text(
                      val,
                      style: TextStyle(
                        color: isHealthy ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // Settings/Configuration
          Text('Global System Settings Toggles', style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 12),
          CustomCard(
            child: Column(
              children: state.systemConfig.keys.map((key) {
                final isEnabled = state.systemConfig[key]!;
                return ListTile(
                  title: Text(key, style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    key == 'Maintenance Mode'
                        ? 'Restricts user access. Only Administrators can connect to backend API.'
                        : (key == 'Verbose Logging' ? 'Enables detailed request/response tracking in logger.' : 'Enables AI planning recommendations.'),
                    style: TextStyle(color: textSecondaryColor, fontSize: 12),
                  ),
                  trailing: Switch(
                    value: isEnabled,
                    activeColor: AppTheme.primary,
                    onChanged: (val) => notifier.toggleConfig(key),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 32),

          // Quick System Commands
          Text('Quick Admin Maintenance Tools', style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 12),
          CustomCard(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('System log & optimization cache', style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Purge local database locks and GLB cached assets from system store.', style: TextStyle(color: textSecondaryColor, fontSize: 12)),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    notifier.clearSystemCache();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('System logs and GLB optimize cache purged successfully.')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.error,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.delete_sweep_rounded),
                  label: const Text('Purge Cache'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Widget helper: Statistics Card ---
  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required String trend,
    required IconData icon,
    required List<Color> colors,
  }) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Icon(icon, color: Colors.white, size: 24),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            trend,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangeRoleDialog(BuildContext context, AdminNotifier notifier, List<dynamic> roles, Map<String, dynamic> user) async {
    String selectedRole = user['role'];
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Change Role for ${user['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select new system role:'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedRole,
                items: roles.map<DropdownMenuItem<String>>((r) {
                  final name = r['name'] as String;
                  return DropdownMenuItem(value: name, child: Text(name));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => selectedRole = val);
                },
                decoration: const InputDecoration(labelText: 'Role'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                notifier.changeUserRole(user['id'], selectedRole);
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteUserDialog(BuildContext context, AdminNotifier notifier, Map<String, dynamic> user) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete User'),
        content: Text(
          'Are you sure you want to permanently delete user "${user['name']}" (${user['email']})?\n\n'
          'This action is irreversible and will delete all user preferences, sessions, and design projects from the database.'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error, foregroundColor: Colors.white),
            onPressed: () {
              notifier.deleteUser(user['id']);
              Navigator.pop(context);
            },
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  Future<void> _showModifyPermissionsDialog(BuildContext context, AdminNotifier notifier, List<dynamic> allPermissions, Map<String, dynamic> role) async {
    final List rolePerms = role['permissions'] ?? [];
    final List<String> selectedPermissions = rolePerms.map<String>((p) => p['name'] as String).toList();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Edit Permissions for ${role['name']}'),
          content: SizedBox(
            width: 400,
            height: 300,
            child: ListView.builder(
              itemCount: allPermissions.length,
              itemBuilder: (context, index) {
                final perm = allPermissions[index];
                final name = perm['name'] as String;
                final bool isChecked = selectedPermissions.contains(name);
                return CheckboxListTile(
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(perm['description'] ?? '', style: const TextStyle(fontSize: 11)),
                  value: isChecked,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        selectedPermissions.add(name);
                      } else {
                        selectedPermissions.remove(name);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                notifier.updateRolePermissions(role['id'], selectedPermissions);
                Navigator.pop(context);
              },
              child: const Text('Save Permissions'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSessionsDialog(BuildContext context, AdminNotifier notifier, AdminState state, Map<String, dynamic> user) async {
    await notifier.fetchUserSessions(user['id']);
    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, child) {
          final currentState = ref.watch(adminProvider);
          final sessions = currentState.userSessions;

          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('Active Sessions: ${user['name']}', overflow: TextOverflow.ellipsis),
                ),
                if (sessions.isNotEmpty)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.power_settings_new_rounded, size: 16),
                    label: const Text('Revoke All', style: TextStyle(fontSize: 12)),
                    onPressed: () async {
                      await notifier.revokeAllUserSessions(user['id']);
                    },
                  ),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 350,
              child: currentState.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : sessions.isEmpty
                      ? const Center(child: Text('No active sessions found for this user.'))
                      : ListView.separated(
                          itemCount: sessions.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) {
                            final sess = sessions[index];
                            final bool isActive = sess['is_active'] == true;
                            return ListTile(
                              leading: Icon(
                                isActive ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                color: isActive ? Colors.green : Colors.grey,
                              ),
                              title: Text('Session ID: ${sess['id'].substring(0, 8)}...'),
                              subtitle: Text(
                                'Token: ${sess['access_token_masked']}\nCreated: ${sess['created_at'].substring(0, 16)}\nExpires: ${sess['expires_at'].substring(0, 16)}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              isThreeLine: true,
                              trailing: isActive
                                  ? IconButton(
                                      icon: const Icon(Icons.cancel_outlined, color: AppTheme.error),
                                      tooltip: 'Revoke Session',
                                      onPressed: () => notifier.revokeUserSession(sess['id'], user['id']),
                                    )
                                  : const Text('Revoked', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            );
                          },
                        ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }
}

class AdminMaterialsSection extends StatefulWidget {
  final List<dynamic> materials;
  final AdminNotifier notifier;
  final bool isDark;

  const AdminMaterialsSection({
    super.key,
    required this.materials,
    required this.notifier,
    required this.isDark,
  });

  @override
  State<AdminMaterialsSection> createState() => _AdminMaterialsSectionState();
}

class _AdminMaterialsSectionState extends State<AdminMaterialsSection> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textPrimaryColor = widget.isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondaryColor = widget.isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final surfaceColor = widget.isDark ? AppTheme.darkSurface : AppTheme.lightSurface;

    // Get unique categories from materials list for filter
    final categories = widget.materials
        .map((m) => m.category?.name as String? ?? 'General')
        .toSet()
        .toList();

    // Filter materials list
    final filtered = widget.materials.where((m) {
      final name = (m.name as String? ?? '').toLowerCase();
      final cat = (m.category?.name as String? ?? 'General').toLowerCase();
      
      final matchesSearch = name.contains(_searchQuery.toLowerCase());
      final matchesCategory = _selectedCategory == null || 
          _selectedCategory!.isEmpty || 
          cat == _selectedCategory!.toLowerCase();
          
      return matchesSearch && matchesCategory;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Material Library Management', style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
              FloatingActionButton.extended(
                key: const Key('add_material_fab'),
                onPressed: () => context.push('/admin/upload-material'),
                label: const Text('Add Material'),
                icon: const Icon(Icons.add_rounded),
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Search & Filter Row
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('material_search_input'),
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search materials by name...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.trim();
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              DropdownButton<String>(
                key: const Key('material_category_dropdown'),
                value: _selectedCategory,
                hint: const Text('All Categories'),
                dropdownColor: surfaceColor,
                style: TextStyle(color: textPrimaryColor),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All Categories')),
                  ...categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedCategory = val;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text('No material items found matching your filters.', style: TextStyle(color: textSecondaryColor)),
                  )
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 240,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final mat = filtered[index];
                      
                      // Preview widget logic
                      Widget previewWidget;
                      if (mat.previewImage != null && mat.previewImage!.isNotEmpty) {
                        previewWidget = Image.network(
                          mat.previewImage!.startsWith('http')
                              ? mat.previewImage!
                              : '${getBaseUrl()}${mat.previewImage}',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.texture_rounded, color: AppTheme.primary, size: 40),
                        );
                      } else if (mat.baseColor != null && mat.baseColor!.isNotEmpty) {
                        Color? color;
                        try {
                          final hex = mat.baseColor!.replaceAll('#', '');
                          color = Color(int.parse('FF$hex', radix: 16));
                        } catch (_) {
                          color = Colors.grey;
                        }
                        previewWidget = Container(color: color);
                      } else {
                        previewWidget = const Icon(Icons.texture_rounded, color: AppTheme.primary, size: 40);
                      }

                      return CustomCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  Positioned.fill(child: previewWidget),
                                  // Edit/Delete buttons overlay
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: Colors.black.withOpacity(0.6),
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 16),
                                            onPressed: () => context.push('/admin/upload-material', extra: mat),
                                            tooltip: 'Edit properties',
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: Colors.black.withOpacity(0.6),
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                                            onPressed: () => _showDeleteConfirmDialog(context, widget.notifier, mat),
                                            tooltip: 'Delete material',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mat.name ?? 'Unnamed Material',
                                    style: TextStyle(color: textPrimaryColor, fontWeight: FontWeight.bold, fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    mat.category?.name ?? 'General',
                                    style: TextStyle(color: textSecondaryColor, fontSize: 11),
                                  ),
                                  const SizedBox(height: 6),
                                  // Render PBR info chips
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      _buildPbrChip('Op: ${mat.opacity.toStringAsFixed(1)}'),
                                      _buildPbrChip('Ref: ${mat.reflectivity.toStringAsFixed(1)}'),
                                      _buildPbrChip('Sc: ${mat.defaultScale.toStringAsFixed(1)}'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPbrChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(color: AppTheme.primary, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _showDeleteConfirmDialog(BuildContext context, AdminNotifier notifier, dynamic mat) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text(
          'Are you sure you want to delete material "${mat.name}"?\n\n'
          'This action is permanent and will delete the material properties and physical textures/previews from disk storage.'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error, foregroundColor: Colors.white),
            onPressed: () {
              notifier.deleteMaterial(mat.id);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
