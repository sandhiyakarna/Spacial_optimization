import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/project_provider.dart';
import '../data/project_sync_repository.dart';
import 'project_dialogs.dart';
import 'import_export_dialogs.dart';
import '../../../shared/widgets/search_bar.dart';
import '../../../shared/widgets/snackbar_manager.dart';
import '../../../app/themes/app_theme.dart';

class ProjectListScreen extends ConsumerStatefulWidget {
  const ProjectListScreen({super.key});

  @override
  ConsumerState<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends ConsumerState<ProjectListScreen> {
  final _searchController = TextEditingController();
  bool _isGridView = true;

  // List of high-quality interior stock photos for project thumbnails
  static const List<String> _unsplashImages = [
    '',
    '',
    '',
    '',
    '',
    '',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(projectProvider.notifier).fetchProjects());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (context) => const CreateProjectDialog(),
    );
  }

  void _showEditDialog(Map<String, dynamic> project) {
    showDialog(
      context: context,
      builder: (context) => EditProjectDialog(project: project),
    );
  }

  void _showDeleteDialog(Map<String, dynamic> project) {
    showDialog(
      context: context,
      builder: (context) => DeleteProjectDialog(project: project),
    );
  }

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (context) => const ImportProjectDialog(),
    );
  }

  void _showRestoreDialog() {
    showDialog(
      context: context,
      builder: (context) => const RestoreProjectDialog(),
    );
  }

  void _showExportDialog(Map<String, dynamic> project) {
    showDialog(
      context: context,
      builder: (context) => ExportProjectDialog(
        projectId: project['id'],
        projectName: project['project_name'] ?? 'Project',
      ),
    );
  }

  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return 'Unknown date';
    try {
      DateTime parsed;
      if (dateVal is DateTime) {
        parsed = dateVal.toLocal();
      } else {
        parsed = DateTime.parse(dateVal.toString()).toLocal();
      }
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
    } catch (_) {
      return dateVal.toString();
    }
  }

  String _getSortLabel(String sortBy) {
    switch (sortBy) {
      case 'project_name':
        return 'Name (A-Z)';
      case 'project_name_desc':
        return 'Name (Z-A)';
      case 'updated_at':
        return 'Recently Modified';
      case 'created_at':
      default:
        return 'Newest First';
    }
  }

  double _calculateProgress(Map<String, dynamic> project) {
    final status = project['status'] ?? 'Draft';
    if (status == 'Completed' || status == 'Archived') {
      return 1.0;
    }
    // If draft, compute based on room count
    final rooms = project['rooms'] ?? 0;
    if (rooms == 0) return 0.15;
    if (rooms == 1) return 0.40;
    if (rooms == 2) return 0.65;
    return 0.85;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Completed':
        return Colors.green;
      case 'Archived':
        return Colors.blueGrey;
      default:
        return AppTheme.primary;
    }
  }

  Widget _buildStatusFilters(BuildContext context, ProjectListState listState, ProjectNotifier notifier) {
    final statuses = [
      {'value': null, 'label': 'All Projects'},
      {'value': 'Draft', 'label': 'Drafts'},
      {'value': 'Completed', 'label': 'Completed'},
      {'value': 'Archived', 'label': 'Archived'},
    ];

    return Row(
      children: statuses.map((status) {
        final isSelected = listState.statusFilter == status['value'];
        return Padding(
          padding: const EdgeInsets.only(right: 6.0),
          child: ChoiceChip(
            selected: isSelected,
            label: Text(status['label'] as String),
            onSelected: (selected) {
              if (selected) {
                notifier.updateStatusFilter(status['value']);
              }
            },
            selectedColor: AppTheme.primary.withValues(alpha: 0.15),
            labelStyle: TextStyle(
              color: isSelected ? AppTheme.primary : Theme.of(context).textTheme.bodyMedium?.color,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
            side: BorderSide(
              color: isSelected ? AppTheme.primary : Colors.grey.withValues(alpha: 0.3),
              width: 1,
            ),
            backgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFavoritesFilter(BuildContext context, ProjectListState listState, ProjectNotifier notifier) {
    final isSelected = listState.favoriteOnly;
    return FilterChip(
      selected: isSelected,
      avatar: Icon(
        isSelected ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: isSelected ? Colors.red : Colors.grey,
        size: 14,
      ),
      label: const Text('Favorites Only'),
      onSelected: (selected) {
        notifier.updateFavoriteOnly(selected);
      },
      selectedColor: Colors.red.withValues(alpha: 0.1),
      labelStyle: TextStyle(
        color: isSelected ? Colors.red : Theme.of(context).textTheme.bodyMedium?.color,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? Colors.red : Colors.grey.withValues(alpha: 0.3),
        width: 1,
      ),
      backgroundColor: Colors.transparent,
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _buildSortSelector(BuildContext context, ProjectListState listState, ProjectNotifier notifier) {
    return PopupMenuButton<String>(
      initialValue: listState.sortBy,
      onSelected: (val) => notifier.updateSortBy(val),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'created_at', child: Text('Newest First')),
        const PopupMenuItem(value: 'project_name', child: Text('Name (A-Z)')),
        const PopupMenuItem(value: 'project_name_desc', child: Text('Name (Z-A)')),
        const PopupMenuItem(value: 'updated_at', child: Text('Recently Modified')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 16, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(
              _getSortLabel(listState.sortBy),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildGridListToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              Icons.grid_view_rounded,
              color: _isGridView ? AppTheme.primary : Theme.of(context).hintColor,
              size: 18,
            ),
            style: IconButton.styleFrom(
              backgroundColor: _isGridView
                  ? (Theme.of(context).brightness == Brightness.dark ? AppTheme.primary.withValues(alpha: 0.2) : Colors.white)
                  : Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.all(8),
            ),
            onPressed: () => setState(() => _isGridView = true),
            tooltip: 'Grid view',
          ),
          IconButton(
            icon: Icon(
              Icons.list_rounded,
              color: !_isGridView ? AppTheme.primary : Theme.of(context).hintColor,
              size: 18,
            ),
            style: IconButton.styleFrom(
              backgroundColor: !_isGridView
                  ? (Theme.of(context).brightness == Brightness.dark ? AppTheme.primary.withValues(alpha: 0.2) : Colors.white)
                  : Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.all(8),
            ),
            onPressed: () => setState(() => _isGridView = false),
            tooltip: 'List view',
          ),
        ],
      ),
    );
  }

  Widget _buildBlueprintPlaceholder(bool isDark) {
    final gridColor = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06);
    
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: BlueprintPainter(
              gridColor: gridColor,
              gridSpacing: 18.0,
            ),
          ),
        ),
        Center(
          child: Opacity(
            opacity: 0.25,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.architecture_rounded,
                  size: 40,
                  color: isDark ? Colors.white70 : AppTheme.primary,
                ),
                const SizedBox(height: 6),
                Text(
                  'FLOWSPACE ARCHITECTURE',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : AppTheme.primary,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderPanel(BuildContext context, ProjectListState listState, ProjectNotifier notifier) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search, Toggle and Sort
          if (isMobile) ...[
            CustomSearchBar(
              controller: _searchController,
              hintText: 'Search projects...',
              onChanged: (val) => notifier.updateSearch(val),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildGridListToggle(),
                _buildSortSelector(context, listState, notifier),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: CustomSearchBar(
                    controller: _searchController,
                    hintText: 'Search by project name or location...',
                    onChanged: (val) => notifier.updateSearch(val),
                  ),
                ),
                const SizedBox(width: 16),
                _buildGridListToggle(),
                const SizedBox(width: 12),
                _buildSortSelector(context, listState, notifier),
              ],
            ),
          ],
          const SizedBox(height: 12),
          // Filter Chips Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildStatusFilters(context, listState, notifier),
                const SizedBox(width: 8),
                _buildFavoritesFilter(context, listState, notifier),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (_isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: width < 600 ? double.infinity : 400,
          mainAxisSpacing: 20,
          crossAxisSpacing: 20,
          childAspectRatio: 0.72,
        ),
        itemCount: 6,
        itemBuilder: (context, index) => _buildSkeletonCard(context),
      );
    } else {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: 4,
        itemBuilder: (context, index) => _buildSkeletonListCard(context),
      );
    }
  }

  Widget _buildSkeletonCard(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF151D30) : Colors.white,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerPlaceholder(width: double.infinity, height: 180, borderRadius: 0),
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerPlaceholder(width: 150, height: 20),
                SizedBox(height: 8),
                ShimmerPlaceholder(width: double.infinity, height: 14),
                SizedBox(height: 4),
                ShimmerPlaceholder(width: 200, height: 14),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ShimmerPlaceholder(width: 80, height: 12),
                    ShimmerPlaceholder(width: 60, height: 12),
                  ],
                ),
                SizedBox(height: 16),
                ShimmerPlaceholder(width: double.infinity, height: 38, borderRadius: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonListCard(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;
    
    if (isMobile) return _buildSkeletonCard(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF151D30) : Colors.white,
      child: const SizedBox(
        height: 180,
        child: Row(
          children: [
            ShimmerPlaceholder(width: 220, height: 180, borderRadius: 0),
            SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ShimmerPlaceholder(width: 200, height: 22),
                        ShimmerPlaceholder(width: 24, height: 24),
                      ],
                    ),
                    SizedBox(height: 8),
                    ShimmerPlaceholder(width: double.infinity, height: 14),
                    SizedBox(height: 4),
                    ShimmerPlaceholder(width: 150, height: 14),
                    Spacer(),
                    Row(
                      children: [
                        ShimmerPlaceholder(width: 120, height: 14),
                        SizedBox(width: 24),
                        ShimmerPlaceholder(width: 80, height: 14),
                        Spacer(),
                        ShimmerPlaceholder(width: 180, height: 38, borderRadius: 10),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message, ProjectNotifier notifier) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.redAccent,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Unable to load projects',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).hintColor,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => notifier.fetchProjects(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ProjectListState listState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSearchActive = _searchController.text.isNotEmpty || listState.statusFilter != null || listState.favoriteOnly;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 200,
              width: 200,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.01),
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: ClipOval(
                      child: CustomPaint(
                        painter: BlueprintPainter(
                          gridColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                          gridSpacing: 16.0,
                        ),
                      ),
                    ),
                  ),
                  Icon(
                    isSearchActive ? Icons.search_off_rounded : Icons.architecture_rounded,
                    size: 72,
                    color: AppTheme.primary.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isSearchActive ? 'No Projects Found' : 'Start Your First Interior Project',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                isSearchActive
                    ? 'No design projects match your search query or filter selections. Try resetting them.'
                    : 'Design interactive spatial layouts, arrange furniture assets, and construct your interior workspace today.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).hintColor,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (isSearchActive)
              FilledButton.icon(
                onPressed: () {
                  _searchController.clear();
                  ref.read(projectProvider.notifier).updateSearch('');
                  ref.read(projectProvider.notifier).updateStatusFilter(null);
                  ref.read(projectProvider.notifier).updateFavoriteOnly(false);
                },
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text('Clear Filters'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )
            else
              FilledButton.icon(
                onPressed: _showCreateDialog,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create New Project'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridProjectCard(BuildContext context, Map<String, dynamic> project, ProjectNotifier notifier) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF151D30) : Colors.white;
    final imageIndex = project['id'].hashCode.abs() % _unsplashImages.length;
    final imageUrl = _unsplashImages[imageIndex];
    final status = project['status'] ?? 'Draft';
    final progressVal = _calculateProgress(project);

    Color statusColor = _getStatusColor(status);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      color: cardColor,
      child: InkWell(
        onTap: () => context.go('/projects/${project['id']}/workspace'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail Header
            Stack(
              children: [
                Container(
                  height: 180,
                  width: double.infinity,
                  color: isDark ? const Color(0xFF0C101B) : const Color(0xFFF1F5F9),
                  child: imageUrl.isEmpty
                      ? _buildBlueprintPlaceholder(isDark)
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return _buildBlueprintPlaceholder(isDark);
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return _buildBlueprintPlaceholder(isDark);
                          },
                        ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.4),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),
                // Favorite Button (Glassmorphic)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                        child: IconButton(
                          icon: Icon(
                            project['is_favorite'] == true
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: project['is_favorite'] == true ? Colors.redAccent : Colors.white,
                            size: 18,
                          ),
                          onPressed: () => notifier.toggleFavorite(project['id']),
                          style: IconButton.styleFrom(padding: const EdgeInsets.all(8)),
                        ),
                      ),
                    ),
                  ),
                ),
                // Status Chip
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
                // Room Count Badge
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.meeting_room_outlined, color: Colors.white, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          '${project['rooms'] ?? 0} ${project['rooms'] == 1 ? "Room" : "Rooms"}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            // Card Details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Hero(
                            tag: 'project-title-${project['id']}',
                            child: Material(
                              color: Colors.transparent,
                              child: Text(
                                project['project_name'] ?? 'Unnamed Project',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                    ),
                              ),
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert_rounded, size: 20, color: Theme.of(context).hintColor),
                          onSelected: (action) async {
                            if (action == 'edit') {
                              _showEditDialog(project);
                            } else if (action == 'delete') {
                              _showDeleteDialog(project);
                            } else if (action == 'duplicate') {
                              final success = await notifier.duplicateProject(project['id']);
                              if (context.mounted && success) {
                                SnackbarManager.showSuccess(context, 'Project duplicated.');
                              }
                            } else if (action == 'export') {
                              _showExportDialog(project);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, size: 18),
                                  SizedBox(width: 8),
                                  Text('Edit Details'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'duplicate',
                              child: Row(
                                children: [
                                  Icon(Icons.copy_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Duplicate'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'export',
                              child: Row(
                                children: [
                                  Icon(Icons.download_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Export/Backup'),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Text(
                        (project['description'] != null && project['description'].toString().isNotEmpty)
                            ? project['description']
                            : 'No description provided.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).hintColor,
                              fontSize: 12,
                            ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Location & Last Modified
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            project['location'] ?? 'Unknown Location',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).hintColor,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 14, color: AppTheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Updated ${_formatDate(project['updated_at'])}',
                          style: TextStyle(
                            color: Theme.of(context).hintColor.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Design Progress
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Progress',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                            Text(
                              '${(progressVal * 100).toInt()}%',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progressVal,
                            minHeight: 5,
                            backgroundColor: isDark ? Colors.white10 : Colors.black12,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Continue Designing Button
                    SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => context.go('/projects/${project['id']}/workspace'),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                        label: const Text(
                          'Continue Designing',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListProjectCard(BuildContext context, Map<String, dynamic> project, ProjectNotifier notifier) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF151D30) : Colors.white;
    final imageIndex = project['id'].hashCode.abs() % _unsplashImages.length;
    final imageUrl = _unsplashImages[imageIndex];
    final status = project['status'] ?? 'Draft';
    final progressVal = _calculateProgress(project);

    Color statusColor = _getStatusColor(status);
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;

    // Mobile list cards display vertically (fallback)
    if (isMobile) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 420,
        child: _buildGridProjectCard(context, project, notifier),
      );
    }

    // Tablet/Desktop list cards display horizontally
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      margin: const EdgeInsets.only(bottom: 16),
      color: cardColor,
      child: InkWell(
        onTap: () => context.go('/projects/${project['id']}/workspace'),
        child: SizedBox(
          height: 180,
          child: Row(
            children: [
              // Left Image
              Stack(
                children: [
                  Container(
                    width: 220,
                    height: double.infinity,
                    color: isDark ? const Color(0xFF0C101B) : const Color(0xFFF1F5F9),
                    child: imageUrl.isEmpty
                        ? _buildBlueprintPlaceholder(isDark)
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return _buildBlueprintPlaceholder(isDark);
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return _buildBlueprintPlaceholder(isDark);
                            },
                          ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.15),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.35),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  // Status Chip
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                  // Room Count Badge
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.meeting_room_outlined, color: Colors.white, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            '${project['rooms'] ?? 0} ${project['rooms'] == 1 ? "Room" : "Rooms"}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              
              // Right Details
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Hero(
                              tag: 'project-title-${project['id']}',
                              child: Material(
                                color: Colors.transparent,
                                child: Text(
                                  project['project_name'] ?? 'Unnamed Project',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  project['is_favorite'] == true
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: project['is_favorite'] == true ? Colors.redAccent : Theme.of(context).hintColor,
                                  size: 20,
                                ),
                                onPressed: () => notifier.toggleFavorite(project['id']),
                              ),
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert_rounded, size: 20, color: Theme.of(context).hintColor),
                                onSelected: (action) async {
                                  if (action == 'edit') {
                                    _showEditDialog(project);
                                  } else if (action == 'delete') {
                                    _showDeleteDialog(project);
                                  } else if (action == 'duplicate') {
                                    final success = await notifier.duplicateProject(project['id']);
                                    if (context.mounted && success) {
                                      SnackbarManager.showSuccess(context, 'Project duplicated.');
                                    }
                                  } else if (action == 'export') {
                                    _showExportDialog(project);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_outlined, size: 18),
                                        SizedBox(width: 8),
                                        Text('Edit Details'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'duplicate',
                                    child: Row(
                                      children: [
                                        Icon(Icons.copy_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text('Duplicate'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'export',
                                    child: Row(
                                      children: [
                                        Icon(Icons.download_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text('Export/Backup'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Expanded(
                        child: Text(
                          (project['description'] != null && project['description'].toString().isNotEmpty)
                              ? project['description']
                              : 'No description provided.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).hintColor,
                                fontSize: 13,
                              ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Meta location
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            project['location'] ?? 'Unknown Location',
                            style: TextStyle(
                              color: Theme.of(context).hintColor,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 20),
                          const Icon(Icons.schedule_rounded, size: 14, color: AppTheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Updated ${_formatDate(project['updated_at'])}',
                            style: TextStyle(
                              color: Theme.of(context).hintColor.withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Progress and Button Row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Design Progress',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                    ),
                                    Text(
                                      '${(progressVal * 100).toInt()}%',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: progressVal,
                                    minHeight: 4,
                                    backgroundColor: isDark ? Colors.white10 : Colors.black12,
                                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 32),
                          SizedBox(
                            width: 180,
                            height: 38,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () => context.go('/projects/${project['id']}/workspace'),
                              icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                              label: const Text(
                                'Continue Designing',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(projectProvider);
    final notifier = ref.read(projectProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget contentWidget;

    if (listState.errorMessage != null) {
      contentWidget = KeyedSubtree(
        key: const ValueKey('error'),
        child: _buildErrorState(context, listState.errorMessage!, notifier),
      );
    } else if (listState.isLoading) {
      contentWidget = KeyedSubtree(
        key: const ValueKey('loading'),
        child: _buildLoadingState(context),
      );
    } else if (listState.projects.isEmpty) {
      contentWidget = KeyedSubtree(
        key: const ValueKey('empty'),
        child: _buildEmptyState(context, listState),
      );
    } else {
      contentWidget = KeyedSubtree(
        key: const ValueKey('content'),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_isGridView) {
              return GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                itemCount: listState.projects.length,
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: constraints.maxWidth < 600 ? double.infinity : 400,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.72,
                ),
                itemBuilder: (context, index) {
                  final project = listState.projects[index] as Map<String, dynamic>;
                  return _buildGridProjectCard(context, project, notifier);
                },
              );
            } else {
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                itemCount: listState.projects.length,
                itemBuilder: (context, index) {
                  final project = listState.projects[index] as Map<String, dynamic>;
                  return _buildListProjectCard(context, project, notifier);
                },
              );
            }
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Design Projects',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: listState.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                  )
                : const Icon(Icons.sync_rounded),
            onPressed: listState.isSyncing ? null : notifier.manualSync,
            tooltip: 'Sync Projects',
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _showImportDialog,
            tooltip: 'Import Project JSON',
          ),
          IconButton(
            icon: const Icon(Icons.settings_backup_restore_outlined),
            onPressed: _showRestoreDialog,
            tooltip: 'Restore Backup JSON',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Background subtle architectural grid lines
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: isDark ? 0.015 : 0.025,
                child: CustomPaint(
                  painter: BlueprintPainter(
                    gridColor: isDark ? Colors.white : Colors.black,
                    gridSpacing: 24.0,
                  ),
                ),
              ),
            ),
          ),
          // Main Body
          Column(
            children: [
              _buildSyncIndicatorBar(context, listState, notifier),
              _buildHeaderPanel(context, listState, notifier),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: contentWidget,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Project', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildSyncIndicatorBar(BuildContext context, ProjectListState listState, ProjectNotifier notifier) {
    if (listState.conflicts.isNotEmpty) {
      return Container(
        color: Colors.red.shade100,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.sync_problem_rounded, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Sync Conflict: ${listState.conflicts.length} project(s) have conflicting changes.',
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () => _showConflictDialog(context, listState.conflicts.first, notifier),
              style: TextButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Resolve', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
      );
    }

    if (listState.isSyncing) {
      return Container(
        color: AppTheme.primary.withValues(alpha: 0.1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
            ),
            SizedBox(width: 10),
            Text(
              'Syncing with cloud...',
              style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (listState.isOffline) {
      return Container(
        color: Colors.orange.shade50,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 16),
            SizedBox(width: 8),
            Text(
              'Offline Mode - Working from local cache',
              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  void _showConflictDialog(BuildContext context, ProjectConflict conflict, ProjectNotifier notifier) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber),
            SizedBox(width: 10),
            Text('Resolve Sync Conflict'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A conflict was detected for project "${conflict.projectName}".'),
            const SizedBox(height: 12),
            const Text('This project has been updated both locally and in the cloud since your last sync.', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Option 1: Keep Local Version', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    const SizedBox(height: 4),
                    Text('Last modified locally: ${_formatDate(conflict.localUpdatedAt)}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Option 2: Use Cloud Version', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 4),
                    Text('Last modified in cloud: ${_formatDate(conflict.remoteUpdatedAt)}'),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              notifier.resolveConflict(conflict.projectId, true);
            },
            child: const Text('Keep Local'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              notifier.resolveConflict(conflict.projectId, false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            child: const Text('Use Cloud'),
          ),
        ],
      ),
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

class ShimmerPlaceholder extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerPlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<ShimmerPlaceholder> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.35, end: 0.75).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}
