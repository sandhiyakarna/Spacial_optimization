import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/material_api_client.dart';
import '../models/material_model.dart';

class MaterialState {
  final bool isLoading;
  final String? errorMessage;
  final List<MaterialCategory> categories;
  final List<MaterialModel> materials;
  final List<MaterialModel> customMaterials; // locally saved custom materials
  final String? selectedCategory;
  final String searchQuery;
  final int currentPage;
  final int pageSize;
  final int totalMaterials;
  final List<String> favorites;
  final List<String> recentlyUsed;

  const MaterialState({
    this.isLoading = false,
    this.errorMessage,
    this.categories = const [],
    this.materials = const [],
    this.customMaterials = const [],
    this.selectedCategory,
    this.searchQuery = '',
    this.currentPage = 1,
    this.pageSize = 20,
    this.totalMaterials = 0,
    this.favorites = const [],
    this.recentlyUsed = const [],
  });

  MaterialState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<MaterialCategory>? categories,
    List<MaterialModel>? materials,
    List<MaterialModel>? customMaterials,
    String? selectedCategory,
    bool clearCategory = false,
    String? searchQuery,
    int? currentPage,
    int? pageSize,
    int? totalMaterials,
    List<String>? favorites,
    List<String>? recentlyUsed,
  }) {
    return MaterialState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      categories: categories ?? this.categories,
      materials: materials ?? this.materials,
      customMaterials: customMaterials ?? this.customMaterials,
      selectedCategory: clearCategory ? null : (selectedCategory ?? this.selectedCategory),
      searchQuery: searchQuery ?? this.searchQuery,
      currentPage: currentPage ?? this.currentPage,
      pageSize: pageSize ?? this.pageSize,
      totalMaterials: totalMaterials ?? this.totalMaterials,
      favorites: favorites ?? this.favorites,
      recentlyUsed: recentlyUsed ?? this.recentlyUsed,
    );
  }
}

class MaterialNotifier extends Notifier<MaterialState> {
  final MaterialApiClient _apiClient = MaterialApiClient();

  @override
  MaterialState build() {
    // Initial fetch of categories and materials
    Future.microtask(() {
      fetchCategories();
      fetchMaterials();
    });
    return const MaterialState();
  }

  Future<void> fetchCategories() async {
    try {
      final list = await _apiClient.getCategories();
      state = state.copyWith(categories: list);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load categories: $e');
    }
  }

  Future<void> fetchMaterials({int? page}) async {
    final targetPage = page ?? state.currentPage;
    state = state.copyWith(isLoading: true, errorMessage: null, currentPage: targetPage);
    try {
      final result = await _apiClient.getMaterials(
        search: state.searchQuery,
        category: state.selectedCategory,
        page: targetPage,
        limit: state.pageSize,
      );
      state = state.copyWith(
        isLoading: false,
        materials: result['materials'] as List<MaterialModel>,
        totalMaterials: result['total'] as int,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to load materials: $e');
    }
  }

  void updateSearch(String query) {
    state = state.copyWith(searchQuery: query, currentPage: 1);
    fetchMaterials();
  }

  void selectCategory(String? category) {
    if (category == null || category.isEmpty) {
      state = state.copyWith(clearCategory: true, currentPage: 1);
    } else {
      state = state.copyWith(selectedCategory: category, currentPage: 1);
    }
    fetchMaterials();
  }

  void changePage(int page) {
    if (page < 1) return;
    fetchMaterials(page: page);
  }

  void toggleFavorite(String id) {
    final updated = List<String>.from(state.favorites);
    if (updated.contains(id)) {
      updated.remove(id);
    } else {
      updated.add(id);
    }
    state = state.copyWith(favorites: updated);
  }

  void addRecentlyUsed(String id) {
    final updated = List<String>.from(state.recentlyUsed);
    updated.remove(id); // Remove if already exists to push to front
    updated.insert(0, id);
    if (updated.length > 10) {
      updated.removeLast(); // Cap at 10 items
    }
    state = state.copyWith(recentlyUsed: updated);
  }

  Future<bool> applyMaterial(String assetId, String materialId) async {
    try {
      await _apiClient.applyMaterialToFurniture(assetId, materialId);
      addRecentlyUsed(materialId);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to apply material: $e');
      return false;
    }
  }

  /// Save a custom material locally (client-side only, not persisted to backend).
  void saveCustomMaterial({
    required String name,
    String? colorHex,
    String? materialType,
    double metallic = 0.0,
    double roughness = 0.5,
    double opacity = 1.0,
    double reflection = 0.0,
    double scale = 1.0,
    double rotation = 0.0,
  }) {
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final cat = MaterialCategory(
      id: 'custom',
      name: materialType ?? 'Custom',
      createdAt: DateTime.now(),
    );
    final model = MaterialModel(
      id: id,
      name: name,
      categoryId: 'custom',
      baseColor: colorHex,
      previewImage: null,
      opacity: opacity,
      reflectivity: reflection,
      defaultScale: scale,
      createdAt: DateTime.now(),
      category: cat,
      textures: const [],
    );
    final updated = [...state.customMaterials, model];
    // Also inject into the main materials list for visibility in the library
    final allMats = [...state.materials, model];
    state = state.copyWith(customMaterials: updated, materials: allMats);
  }

  /// Remove a material from the custom list and main list.
  void removeCustomMaterial(String id) {
    final updatedCustom = state.customMaterials.where((m) => m.id != id).toList();
    final updatedAll = state.materials.where((m) => m.id != id).toList();
    state = state.copyWith(customMaterials: updatedCustom, materials: updatedAll);
  }

  /// Duplicate a custom material.
  void duplicateCustomMaterial(String id) {
    try {
      final original = state.materials.firstWhere((m) => m.id == id);
      saveCustomMaterial(
        name: '${original.name} (Copy)',
        colorHex: original.baseColor,
        materialType: original.category.name.toLowerCase(),
        opacity: original.opacity,
        reflection: original.reflectivity,
        scale: original.defaultScale,
      );
    } catch (_) {}
  }
}

final materialProvider = NotifierProvider<MaterialNotifier, MaterialState>(() {
  return MaterialNotifier();
});
