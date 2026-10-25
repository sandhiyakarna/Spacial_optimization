import '../../../../app/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/furniture_provider.dart';

class FurnitureFilterPanel extends ConsumerStatefulWidget {
  const FurnitureFilterPanel({super.key});

  @override
  ConsumerState<FurnitureFilterPanel> createState() => _FurnitureFilterPanelState();
}

class _FurnitureFilterPanelState extends ConsumerState<FurnitureFilterPanel> {
  final TextEditingController _searchController = TextEditingController();

  final List<String> _styles = [
    'All Styles',
    'Modern',
    'Scandinavian',
    'Minimal',
    'Industrial',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(furnitureProvider);
    final notifier = ref.read(furnitureProvider.notifier);

    // Keep controller text sync'd with state in case of resets
    if (_searchController.text != state.search) {
      _searchController.text = state.search;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Load categories dynamically from state, falling back to static list if empty
    final dynamicCategories = state.categories.map((c) => c.name).toList();
    final List<String> categories = [
      'All',
      if (dynamicCategories.isNotEmpty) ...dynamicCategories
      else ...['Living Room', 'Bedroom', 'Office', 'Kitchen']
    ];

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE5E5E5),
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row for Search and Style Filter
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 450;
              final searchWidget = TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search furniture (e.g. sofa, desk, chair)...',
                  prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            notifier.updateSearch('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (val) {
                  notifier.updateSearch(val);
                },
              );

              final styleDropdown = DropdownButtonFormField<String>(
                value: state.styleFilter ?? 'All Styles',
                decoration: InputDecoration(
                  labelText: 'Style',
                  labelStyle: const TextStyle(color: AppTheme.primary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: _styles.map((style) {
                  return DropdownMenuItem<String>(
                    value: style,
                    child: Text(style),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val == 'All Styles') {
                    notifier.updateStyleFilter(null);
                  } else {
                    notifier.updateStyleFilter(val);
                  }
                },
              );

              if (isNarrow) {
                return Column(
                  children: [
                    searchWidget,
                    const SizedBox(height: 12),
                    styleDropdown,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: searchWidget,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: styleDropdown,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          // Category Selector Row
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Categories',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: categories.map((cat) {
                    final isSelected = (cat == 'All' && state.categoryFilter == null) ||
                        (state.categoryFilter == cat);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                        ),
                        backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[200],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            if (cat == 'All') {
                              notifier.updateCategoryFilter(null);
                            } else {
                              notifier.updateCategoryFilter(cat);
                            }
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
