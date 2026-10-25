import '../../../../app/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/furniture_provider.dart';
import 'widgets/furniture_filter_panel.dart';
import 'widgets/furniture_grid_item.dart';
import 'widgets/glb_info_dialog.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/loading_indicator.dart';

class FurnitureLibraryScreen extends ConsumerStatefulWidget {
  const FurnitureLibraryScreen({super.key});

  @override
  ConsumerState<FurnitureLibraryScreen> createState() => _FurnitureLibraryScreenState();
}

class _FurnitureLibraryScreenState extends ConsumerState<FurnitureLibraryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(furnitureProvider.notifier).fetchAssets();
    });
  }

  void _showGlbDetails(BuildContext context, dynamic asset) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => GlbInfoDialog(asset: asset),
    ).then((_) {
      // Reload recently used list if we close the dialog, as it logs usage
      if (ref.read(furnitureProvider).catalogMode == CatalogMode.recent) {
        ref.read(furnitureProvider.notifier).fetchAssets();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(furnitureProvider);
    final notifier = ref.read(furnitureProvider.notifier);
    final profile = ref.watch(authProvider).profile;
    final bool isAdmin = profile != null && profile['role'] == 'Administrator';
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Calculate cross axis count responsively
    final width = MediaQuery.of(context).size.width;
    final double cardWidth = 160.0;
    int crossAxisCount = (width / cardWidth).floor();
    if (crossAxisCount < 1) crossAxisCount = 1;

    double childAspectRatio = 0.85;
    if (crossAxisCount == 1) {
      childAspectRatio = 1.3;
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF6F8F8),
      appBar: AppBar(
        title: const Text('Furniture Asset Library'),
        actions: [
          // Cache status icon & clear cache
          IconButton(
            icon: Badge(
              label: Text('${notifier.cacheSize}'),
              isLabelVisible: notifier.cacheSize > 0,
              backgroundColor: AppTheme.primary,
              child: const Icon(Icons.cached),
            ),
            tooltip: 'Asset Cache Info / Clear Cache',
            onPressed: () {
              final size = notifier.cacheSize;
              if (size == 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Asset cache is currently empty.')),
                );
              } else {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Asset Cache Manager'),
                    content: Text('The local asset cache contains $size GLB model(s). Do you want to clear it?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          notifier.clearCache();
                          Navigator.of(context).pop();
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Asset cache cleared successfully.')),
                          );
                        },
                        child: const Text('Clear Cache', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => notifier.fetchAssets(),
            tooltip: 'Refresh Library',
          ),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/admin/upload-furniture'),
              label: const Text('Upload Furniture'),
              icon: const Icon(Icons.upload_file),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
      body: Column(
        children: [
          // Premium Mode Switcher (Segmented Button)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<CatalogMode>(
                segments: const [
                  ButtonSegment<CatalogMode>(
                    value: CatalogMode.all,
                    label: Text('All Items'),
                    icon: Icon(Icons.grid_view),
                  ),
                  ButtonSegment<CatalogMode>(
                    value: CatalogMode.favorites,
                    label: Text('Favorites'),
                    icon: Icon(Icons.favorite),
                  ),
                  ButtonSegment<CatalogMode>(
                    value: CatalogMode.recent,
                    label: Text('Recent'),
                    icon: Icon(Icons.history),
                  ),
                ],
                selected: {state.catalogMode},
                onSelectionChanged: (Set<CatalogMode> newSelection) {
                  notifier.setCatalogMode(newSelection.first);
                },
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppTheme.primary,
                  selectedForegroundColor: Colors.white,
                ),
              ),
            ),
          ),

          // Filter & Search Panel (Only show for All Items)
          if (state.catalogMode == CatalogMode.all) const FurnitureFilterPanel(),

          // List Grid Content
          Expanded(
            child: _buildGridContent(state, notifier, crossAxisCount, childAspectRatio),
          ),

          // Pagination Bar (Only show for All Items or Favorites)
          if ((state.catalogMode == CatalogMode.all || state.catalogMode == CatalogMode.favorites) && state.assets.isNotEmpty)
            _buildPaginationBar(state, notifier),
        ],
      ),
    );
  }

  Widget _buildGridContent(FurnitureListState state, FurnitureNotifier notifier, int crossAxisCount, double childAspectRatio) {
    if (state.isLoading && state.assets.isEmpty) {
      return const Center(
        child: LoadingIndicator(message: 'Loading asset library...'),
      );
    }

    if (state.errorMessage != null && state.assets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ErrorState(
            message: 'Failed to connect to asset database.\n${state.errorMessage}',
            onRetry: () => notifier.fetchAssets(),
          ),
        ),
      );
    }

    if (state.assets.isEmpty) {
      IconData emptyIcon = Icons.chair_alt_outlined;
      String emptyTitle = 'No furniture assets found';
      String emptySubtitle = 'Try adjusting your search query or category filters.';

      if (state.catalogMode == CatalogMode.favorites) {
        emptyIcon = Icons.favorite_border;
        emptyTitle = 'No favorites added';
        emptySubtitle = 'Tap the heart icon on any asset to add it to your favorites.';
      } else if (state.catalogMode == CatalogMode.recent) {
        emptyIcon = Icons.history_toggle_off;
        emptyTitle = 'No recently used assets';
        emptySubtitle = 'Open detailed preview of any asset to log its usage here.';
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(emptyIcon, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              emptyTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              emptySubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16.0,
        mainAxisSpacing: 16.0,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: state.assets.length,
      itemBuilder: (context, index) {
        final asset = state.assets[index];
        return FurnitureGridItem(
          asset: asset,
          onTap: () => _showGlbDetails(context, asset),
        );
      },
    );
  }

  Widget _buildPaginationBar(FurnitureListState state, FurnitureNotifier notifier) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 16),
              onPressed: state.page > 1 && !state.isLoading ? () => notifier.previousPage() : null,
              tooltip: 'Previous Page',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Page ${state.page}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 16),
              onPressed: state.hasMore && !state.isLoading ? () => notifier.nextPage() : null,
              tooltip: 'Next Page',
            ),
          ],
        ),
      ),
    );
  }
}
