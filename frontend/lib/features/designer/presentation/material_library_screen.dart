import '../../../app/themes/app_theme.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/material_provider.dart';
import '../providers/selection_provider.dart';
import '../providers/designer_provider.dart';
import '../providers/texture_provider.dart';
import '../models/material_model.dart';
import '../../../shared/widgets/snackbar_manager.dart';
import 'widgets/material_drag_overlay.dart';
import 'widgets/material_editor_panel.dart';

class MaterialLibraryScreen extends ConsumerStatefulWidget {
  final String? targetElementType; // 'furniture', 'floor', 'wall'
  final String? targetElementId;

  const MaterialLibraryScreen({
    super.key,
    this.targetElementType,
    this.targetElementId,
  });

  @override
  ConsumerState<MaterialLibraryScreen> createState() => _MaterialLibraryScreenState();
}

class _MaterialLibraryScreenState extends ConsumerState<MaterialLibraryScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  
  // Custom filters
  double _minOpacity = 0.0;
  double _minReflectivity = 0.0;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      ref.read(materialProvider.notifier).updateSearch(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  IconData _getCategoryIcon(String categoryName) {
    switch (categoryName.toLowerCase()) {
      case 'wood':
        return Icons.forest_outlined;
      case 'marble':
      case 'granite':
      case 'concrete':
        return Icons.foundation_outlined;
      case 'metal':
        return Icons.precision_manufacturing_outlined;
      case 'glass':
        return Icons.wb_iridescent_outlined;
      case 'leather':
        return Icons.backpack_outlined;
      case 'fabric':
        return Icons.texture_outlined;
      case 'ceramic':
        return Icons.grid_view_outlined;
      case 'paint':
        return Icons.format_paint_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  Color _parseHexColor(String? hexString, {Color fallback = AppTheme.primary}) {
    if (hexString == null) return fallback;
    try {
      final hex = hexString.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    final matState = ref.watch(materialProvider);
    final matNotifier = ref.read(materialProvider.notifier);
    
    // Apply filters locally for advanced sliders (opacity/reflectivity)
    final filteredMaterials = matState.materials.where((m) {
      if (m.opacity < _minOpacity) return false;
      if (m.reflectivity < _minReflectivity) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.targetElementType != null 
          ? 'Apply Material to ${widget.targetElementType![0].toUpperCase()}${widget.targetElementType!.substring(1)}'
          : 'Material & Texture Library'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Browse'),
            Tab(icon: Icon(Icons.favorite), text: 'Favorites'),
            Tab(icon: Icon(Icons.history), text: 'Recently Used'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // BROWSE TAB
          Column(
            children: [
              // Search & Filters Panel
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search materials...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey.withOpacity(0.05),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      icon: Icon(_showFilters ? Icons.filter_alt_off : Icons.filter_alt),
                      onPressed: () {
                        setState(() {
                          _showFilters = !_showFilters;
                        });
                      },
                    ),
                  ],
                ),
              ),

              // Expandable Slider Filters
              if (_showFilters)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  color: Theme.of(context).cardColor,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text('Min Opacity: ', style: TextStyle(fontSize: 12)),
                          Expanded(
                            child: Slider(
                              value: _minOpacity,
                              min: 0.0,
                              max: 1.0,
                              divisions: 10,
                              label: _minOpacity.toStringAsFixed(1),
                              onChanged: (v) => setState(() => _minOpacity = v),
                            ),
                          ),
                          Text(_minOpacity.toStringAsFixed(1)),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('Min Reflectivity: ', style: TextStyle(fontSize: 12)),
                          Expanded(
                            child: Slider(
                              value: _minReflectivity,
                              min: 0.0,
                              max: 1.0,
                              divisions: 10,
                              label: _minReflectivity.toStringAsFixed(1),
                              onChanged: (v) => setState(() => _minReflectivity = v),
                            ),
                          ),
                          Text(_minReflectivity.toStringAsFixed(1)),
                        ],
                      ),
                    ],
                  ),
                ),

              // Categories Selector Row
              Container(
                height: 48,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: matState.categories.length + 1,
                  itemBuilder: (context, index) {
                    final isAll = index == 0;
                    final cat = isAll ? null : matState.categories[index - 1];
                    final isSelected = isAll 
                        ? matState.selectedCategory == null 
                        : matState.selectedCategory == cat!.name;
                    final label = isAll ? 'All Categories' : cat!.name;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ChoiceChip(
                        avatar: isAll ? null : Icon(_getCategoryIcon(cat!.name), size: 16, color: isSelected ? Colors.white : AppTheme.primary),
                        label: Text(label),
                        selected: isSelected,
                        onSelected: (selected) {
                          matNotifier.selectCategory(isAll ? null : cat!.name);
                        },
                        selectedColor: AppTheme.primary.shade700,
                        backgroundColor: AppTheme.primary.withOpacity(0.05),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Materials Grid View
              Expanded(
                child: matState.isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : matState.errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Colors.red),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                                child: Text(
                                  matState.errorMessage!,
                                  style: const TextStyle(color: Colors.red),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () => matNotifier.fetchMaterials(),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : filteredMaterials.isEmpty
                        ? const Center(child: Text('No materials match criteria'))
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth;
                              int crossAxisCount = 2;
                              if (width > 900) {
                                crossAxisCount = 5;
                              } else if (width > 600) {
                                crossAxisCount = 3;
                              }
                              return GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: 0.85,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                                itemCount: filteredMaterials.length,
                                itemBuilder: (context, index) {
                                  final material = filteredMaterials[index];
                                  final isFavorite = matState.favorites.contains(material.id);
                                  return _buildMaterialCard(material, isFavorite);
                                },
                              );
                            },
                          ),
              ),
            ],
          ),

          // FAVORITES TAB
          Builder(
            builder: (context) {
              final favs = matState.materials.where((m) => matState.favorites.contains(m.id)).toList();
              if (favs.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_border, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('No favorite materials added yet'),
                    ],
                  ),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  int crossAxisCount = 2;
                  if (width > 900) {
                    crossAxisCount = 5;
                  } else if (width > 600) {
                    crossAxisCount = 3;
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: favs.length,
                    itemBuilder: (context, index) {
                      final material = favs[index];
                      return _buildMaterialCard(material, true);
                    },
                  );
                },
              );
            },
          ),

          // RECENTLY USED TAB
          Builder(
            builder: (context) {
              final recents = matState.materials.where((m) => matState.recentlyUsed.contains(m.id)).toList();
              if (recents.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('No recently used materials'),
                    ],
                  ),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  int crossAxisCount = 2;
                  if (width > 900) {
                    crossAxisCount = 5;
                  } else if (width > 600) {
                    crossAxisCount = 3;
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: recents.length,
                    itemBuilder: (context, index) {
                      final material = recents[index];
                      final isFav = matState.favorites.contains(material.id);
                      return _buildMaterialCard(material, isFav);
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialCard(MaterialModel material, bool isFavorite) {
    final matColor = _parseHexColor(material.baseColor);

    return Draggable<MaterialModel>(
      data: material,
      feedback: MaterialDragFeedback(material: material),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: _buildCardContent(material, isFavorite, matColor),
      ),
      onDragStarted: () {
        ref.read(materialDragActiveProvider.notifier).setDragActive(true);
        Navigator.of(context).pop(); // instant close to reveal viewport
      },
      onDragEnd: (details) {
        ref.read(materialDragActiveProvider.notifier).setDragActive(false);
      },
      child: InkWell(
        onTap: () => _showMaterialDetailDialog(material),
        child: _buildCardContent(material, isFavorite, matColor),
      ),
    );
  }

  Widget _buildCardContent(MaterialModel material, bool isFavorite, Color matColor) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Preview Image or solid color block
          Expanded(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: matColor,
                    gradient: LinearGradient(
                      colors: [matColor, matColor.withOpacity(0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      _getCategoryIcon(material.category.name),
                      size: 40,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ),
                // Favorite icon button
                Positioned(
                  top: 4,
                  right: 4,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white.withOpacity(0.8),
                    child: IconButton(
                      icon: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        size: 16,
                        color: isFavorite ? Colors.red : Colors.grey,
                      ),
                      onPressed: () {
                        ref.read(materialProvider.notifier).toggleFavorite(material.id);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Material Info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  material.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      material.category.name,
                      style: TextStyle(fontSize: 11, color: AppTheme.primary.shade800, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'Scale: ${material.defaultScale}x',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMaterialDetailDialog(MaterialModel material) {
    // Lazy load textures for the preview
    for (final tex in material.textures) {
      ref.read(textureProvider.notifier).loadTexture(tex.filePath);
    }

    final textureState = ref.watch(textureProvider);
    final previewColor = _parseHexColor(material.baseColor);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: min(MediaQuery.of(context).size.width * 0.9, 400.0),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        material.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const Divider(),

                  // Preview sphere/box simulation
                  Container(
                    height: 180,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: previewColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                      gradient: RadialGradient(
                        colors: [Colors.white.withOpacity(0.3), Colors.black.withOpacity(0.3)],
                        center: const Alignment(-0.3, -0.3),
                        radius: 0.8,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Preview Sphere\nRoughness: ${material.reflectivity > 0.5 ? 'Glossy' : 'Rough'}\nOpacity: ${material.opacity.toStringAsFixed(1)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ),

                  // Material Properties
                  const Text('Properties', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  _buildPropertyRow('Category', material.category.name),
                  _buildPropertyRow('Base Color', material.baseColor ?? 'None'),
                  _buildPropertyRow('Opacity', material.opacity.toStringAsFixed(2)),
                  _buildPropertyRow('Reflectivity', material.reflectivity.toStringAsFixed(2)),
                  _buildPropertyRow('Default Scale', material.defaultScale.toStringAsFixed(2)),
                  
                  const SizedBox(height: 12),
                  // Texture Maps listing
                  const Text('Texture Maps', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  if (material.textures.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('Procedural Shader (No custom maps)', style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
                    )
                  else
                    ...material.textures.map((t) {
                      final status = textureState[t.filePath] ?? 'not_loaded';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              t.textureType.toUpperCase(),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              status == 'loaded' ? '✓ Cached WebP' : '⌛ Loading...',
                              style: TextStyle(fontSize: 10, color: status == 'loaded' ? Colors.green : Colors.orange),
                            ),
                          ],
                        ),
                      );
                    }),

                  const SizedBox(height: 24),
                  // Apply Button
                  ElevatedButton(
                    onPressed: () async {
                      if (widget.targetElementType != null && widget.targetElementId != null) {
                        Navigator.of(context).pop(); // Close dialog first

                        // Perform real-time application in Riverpod designer state
                        if (widget.targetElementType == 'furniture') {
                          // Apply to specific furniture instance
                          ref.read(designerProvider.notifier).updateSelectedFurnitureMaterial(
                            color: material.baseColor?.replaceAll('#', ''),
                            metallic: material.reflectivity,
                            roughness: 1.0 - material.reflectivity,
                            materialType: material.category.name.toLowerCase(),
                          );

                          // Also perform backend apply endpoint trigger
                          final success = await ref.read(materialProvider.notifier).applyMaterial(
                            widget.targetElementId!, // Placed furniture ID
                            material.id,
                          );

                          if (success && context.mounted) {
                            SnackbarManager.showSuccess(
                              context, 
                              'Applied ${material.name} to furniture.',
                            );
                            Navigator.of(context).pop(material); // Close Library Screen
                          }
                        } else if (widget.targetElementType == 'floor') {
                          ref.read(designerProvider.notifier).updateRoomMaterials(
                            floorColor: material.baseColor?.replaceAll('#', ''),
                            floorType: material.category.name.toLowerCase(),
                          );
                          ref.read(materialProvider.notifier).addRecentlyUsed(material.id);
                          SnackbarManager.showSuccess(
                            context, 
                            'Applied ${material.name} to room floor.',
                          );
                          Navigator.of(context).pop(material); // Close Library Screen
                        } else if (widget.targetElementType == 'wall') {
                          ref.read(designerProvider.notifier).updateRoomMaterials(
                            wallColor: material.baseColor?.replaceAll('#', ''),
                            wallType: material.category.name.toLowerCase(),
                          );
                          ref.read(materialProvider.notifier).addRecentlyUsed(material.id);
                          SnackbarManager.showSuccess(
                            context, 
                            'Applied ${material.name} to room walls.',
                          );
                          Navigator.of(context).pop(material); // Close Library Screen
                        }
                      } else {
                        // General preview only, no target
                        ref.read(selectionProvider.notifier).setPreviewMaterial(material);
                        Navigator.of(context).pop();
                        SnackbarManager.showInfo(context, 'Material selected as preview.');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Apply Material', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPropertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
