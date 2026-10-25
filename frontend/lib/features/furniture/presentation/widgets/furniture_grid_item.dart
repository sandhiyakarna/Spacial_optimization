import '../../../../app/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/furniture_asset.dart';
import '../../providers/furniture_provider.dart';
import '../../../../core/utils/url_helper.dart';

class FurnitureGridItem extends ConsumerWidget {
  final FurnitureAsset asset;
  final VoidCallback onTap;

  const FurnitureGridItem({
    super.key,
    required this.asset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String thumbnailUrl = asset.thumbnailUrl;
    final String resolvedUrl = (thumbnailUrl.contains('unsplash.com') || thumbnailUrl.isEmpty)
        ? '/uploads/furniture/thumbnails/${asset.id.replaceAll('model_', '')}.png'
        : thumbnailUrl;
    final String imageUrl = resolvedUrl.startsWith('http')
        ? resolvedUrl
        : '${getBaseUrl()}$resolvedUrl';

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail Image Area
            Expanded(
              child: Container(
                color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF0F5F5),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.chair_outlined,
                            size: 48,
                            color: AppTheme.primary.withValues(alpha: 0.5),
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                            ),
                          );
                        },
                      ),
                    ),
                    // Style Badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          asset.style,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    // Favorite Toggle Button
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.transparent,
                        child: IconButton(
                          icon: Icon(
                            asset.isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: asset.isFavorite ? Colors.redAccent : (isDark ? Colors.white70 : Colors.black54),
                            size: 20,
                          ),
                          tooltip: asset.isFavorite ? 'Remove from favorites' : 'Add to favorites',
                          onPressed: () {
                            ref.read(furnitureProvider.notifier).toggleFavorite(asset);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Info Area
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    asset.category,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.square_foot, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${asset.width.round()} × ${asset.depth.round()} × ${asset.height.round()} cm',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                                fontSize: 11,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
