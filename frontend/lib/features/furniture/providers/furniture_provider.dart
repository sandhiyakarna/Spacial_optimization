import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../core/utils/url_helper.dart';
import '../data/furniture_api_client.dart';
import '../models/furniture_asset.dart';

// --- IN-MEMORY ASSET CACHE ---
class AssetCache {
  static final AssetCache _instance = AssetCache._internal();
  factory AssetCache() => _instance;
  AssetCache._internal();

  final Map<String, Uint8List> _cache = {};

  void put(String url, Uint8List bytes) {
    _cache[url] = bytes;
  }

  Uint8List? get(String url) {
    return _cache[url];
  }

  bool has(String url) {
    return _cache.containsKey(url);
  }

  void clear() {
    _cache.clear();
  }

  int get size => _cache.length;
}

// --- GLB BINARY METADATA PARSER ---
class GlbMetadata {
  final String magic;
  final int version;
  final int totalLength;
  final int jsonChunkLength;
  final String jsonChunkType;
  final Map<String, dynamic> jsonContent;

  GlbMetadata({
    required this.magic,
    required this.version,
    required this.totalLength,
    required this.jsonChunkLength,
    required this.jsonChunkType,
    required this.jsonContent,
  });

  factory GlbMetadata.parse(Uint8List bytes) {
    if (bytes.length < 20) {
      throw const FormatException("Invalid GLB file: too short (less than 20 bytes).");
    }

    final byteData = ByteData.sublistView(bytes);

    // Read magic: 4 bytes (must be "glTF")
    final magicBytes = bytes.sublist(0, 4);
    final magic = ascii.decode(magicBytes);
    if (magic != "glTF") {
      throw FormatException("Invalid GLB: magic signature is '$magic', expected 'glTF'.");
    }

    // Read version: 4 bytes (uint32)
    final version = byteData.getUint32(4, Endian.little);
    if (version != 2) {
      throw FormatException("Unsupported GLB version: $version. Only version 2 is supported.");
    }

    // Read total length: 4 bytes (uint32)
    final totalLength = byteData.getUint32(8, Endian.little);

    // Read chunk 0 length: 4 bytes (uint32)
    final jsonChunkLength = byteData.getUint32(12, Endian.little);

    // Read chunk 0 type: 4 bytes (must be "JSON")
    final chunkTypeBytes = bytes.sublist(16, 20);
    final jsonChunkType = ascii.decode(chunkTypeBytes).trim();
    if (jsonChunkType != "JSON") {
      throw FormatException("Invalid GLB: first chunk must be JSON, got '$jsonChunkType'.");
    }

    if (20 + jsonChunkLength > bytes.length) {
      throw const FormatException("Invalid GLB: JSON chunk size exceeds file length.");
    }

    // Read JSON content
    final jsonBytes = bytes.sublist(20, 20 + jsonChunkLength);
    final jsonStr = utf8.decode(jsonBytes);
    
    try {
      final jsonContent = jsonDecode(jsonStr) as Map<String, dynamic>;
      return GlbMetadata(
        magic: magic,
        version: version,
        totalLength: totalLength,
        jsonChunkLength: jsonChunkLength,
        jsonChunkType: jsonChunkType,
        jsonContent: jsonContent,
      );
    } catch (e) {
      throw FormatException("Failed to decode GLB JSON content: $e");
    }
  }

  // Helper metadata fields
  String get gltfVersion => jsonContent['asset']?['version']?.toString() ?? '2.0';
  String get generator => jsonContent['asset']?['generator']?.toString() ?? 'Unknown';
  int get nodesCount => (jsonContent['nodes'] as List?)?.length ?? 0;
  int get meshesCount => (jsonContent['meshes'] as List?)?.length ?? 0;
  int get materialsCount => (jsonContent['materials'] as List?)?.length ?? 0;
  int get texturesCount => (jsonContent['textures'] as List?)?.length ?? 0;
  int get animationsCount => (jsonContent['animations'] as List?)?.length ?? 0;
}

// --- STATE MANAGEMENT ---
enum CatalogMode { all, favorites, recent }

class FurnitureListState {
  final bool isLoading;
  final String? errorMessage;
  final List<FurnitureAsset> assets;
  final String search;
  final String? categoryFilter;
  final String? styleFilter;
  final int page;
  final int limit;
  final bool hasMore;
  final CatalogMode catalogMode;
  final List<FurnitureCategory> categories;

  const FurnitureListState({
    this.isLoading = false,
    this.errorMessage,
    this.assets = const [],
    this.search = '',
    this.categoryFilter,
    this.styleFilter,
    this.page = 1,
    this.limit = 50,
    this.hasMore = true,
    this.catalogMode = CatalogMode.all,
    this.categories = const [],
  });

  FurnitureListState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<FurnitureAsset>? assets,
    String? search,
    String? categoryFilter,
    bool clearCategoryFilter = false,
    String? styleFilter,
    bool clearStyleFilter = false,
    int? page,
    int? limit,
    bool? hasMore,
    CatalogMode? catalogMode,
    List<FurnitureCategory>? categories,
  }) {
    return FurnitureListState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      assets: assets ?? this.assets,
      search: search ?? this.search,
      categoryFilter: clearCategoryFilter ? null : (categoryFilter ?? this.categoryFilter),
      styleFilter: clearStyleFilter ? null : (styleFilter ?? this.styleFilter),
      page: page ?? this.page,
      limit: limit ?? this.limit,
      hasMore: hasMore ?? this.hasMore,
      catalogMode: catalogMode ?? this.catalogMode,
      categories: categories ?? this.categories,
    );
  }
}

class FurnitureNotifier extends Notifier<FurnitureListState> {
  final FurnitureApiClient _apiClient = FurnitureApiClient();
  final AssetCache _assetCache = AssetCache();

  @override
  FurnitureListState build() {
    Future.microtask(() => fetchCategories());
    return const FurnitureListState();
  }

  Future<void> fetchCategories() async {
    try {
      final cats = await _apiClient.getCategories();
      state = state.copyWith(categories: cats);
    } catch (_) {
      // Fail silently, falls back to default filters
    }
  }

  Future<void> fetchAssets() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      List<FurnitureAsset> list = [];
      
      switch (state.catalogMode) {
        case CatalogMode.all:
          list = await _apiClient.getFurnitureAssets(
            search: state.search,
            category: state.categoryFilter,
            style: state.styleFilter,
            page: state.page,
            limit: state.limit,
          );
          break;
        case CatalogMode.favorites:
          list = await _apiClient.getFavorites(
            page: state.page,
            limit: state.limit,
          );
          break;
        case CatalogMode.recent:
          list = await _apiClient.getRecentlyUsed(
            limit: state.limit,
          );
          break;
      }

      final mutableList = List<FurnitureAsset>.from(list);
      
      if (state.catalogMode == CatalogMode.all && 
          (state.categoryFilter == null || state.categoryFilter == 'Furniture' || state.categoryFilter!.isEmpty)) {
        final hasStairs = mutableList.any((a) => a.id == 'STAIRS_001');
        if (!hasStairs && state.search.isEmpty) {
          mutableList.add(FurnitureAsset(
            id: 'STAIRS_001',
            name: 'Modular Stairs',
            category: 'Furniture',
            style: 'Modern',
            width: 100.0,
            depth: 150.0,
            height: 120.0,
            clearance: 0.0,
            assemblyClearance: 0.0,
            glbUrl: '',
            thumbnailUrl: '',
            createdAt: DateTime.now(),
          ));
        }
      }

      final bool hasMore = list.length >= state.limit;
      state = state.copyWith(
        isLoading: false,
        assets: mutableList,
        hasMore: hasMore,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  void updateSearch(String search) {
    state = state.copyWith(search: search, page: 1);
    fetchAssets();
  }

  void updateCategoryFilter(String? category) {
    if (category == null || category.isEmpty) {
      state = state.copyWith(clearCategoryFilter: true, page: 1);
    } else {
      state = state.copyWith(categoryFilter: category, page: 1);
    }
    fetchAssets();
  }

  void updateStyleFilter(String? style) {
    if (style == null || style.isEmpty) {
      state = state.copyWith(clearStyleFilter: true, page: 1);
    } else {
      state = state.copyWith(styleFilter: style, page: 1);
    }
    fetchAssets();
  }

  void setCatalogMode(CatalogMode mode) {
    state = state.copyWith(catalogMode: mode, page: 1, assets: []);
    fetchAssets();
  }

  void nextPage() {
    if (state.hasMore && !state.isLoading) {
      state = state.copyWith(page: state.page + 1);
      fetchAssets();
    }
  }

  void previousPage() {
    if (state.page > 1 && !state.isLoading) {
      state = state.copyWith(page: state.page - 1);
      fetchAssets();
    }
  }

  void setPage(int page) {
    if (page >= 1 && !state.isLoading) {
      state = state.copyWith(page: page);
      fetchAssets();
    }
  }

  Future<void> toggleFavorite(FurnitureAsset asset) async {
    final originalState = state;
    final updatedAssets = state.assets.map((a) {
      if (a.id == asset.id) {
        return a.copyWith(isFavorite: !a.isFavorite);
      }
      return a;
    }).toList();
    
    state = state.copyWith(assets: updatedAssets);

    try {
      if (asset.isFavorite) {
        await _apiClient.unfavoriteAsset(asset.id);
      } else {
        await _apiClient.favoriteAsset(asset.id);
      }
      if (state.catalogMode == CatalogMode.favorites) {
        fetchAssets();
      }
    } catch (e) {
      state = originalState.copyWith(errorMessage: 'Failed to update favorite: $e');
    }
  }

  // GLB Loader & Parser with In-Memory Caching
  Future<GlbMetadata> loadAndParseGlb(String relativeUrl) async {
    final absoluteUrl = relativeUrl.startsWith('http') 
        ? relativeUrl 
        : '${getBaseUrl()}$relativeUrl';
        
    // Check Cache First
    if (_assetCache.has(absoluteUrl)) {
      final cachedBytes = _assetCache.get(absoluteUrl)!;
      return GlbMetadata.parse(cachedBytes);
    }

    // Otherwise Download
    final response = await http.get(Uri.parse(absoluteUrl));
    if (response.statusCode == 200) {
      final bytes = response.bodyBytes;
      // Save to Cache
      _assetCache.put(absoluteUrl, bytes);
      return GlbMetadata.parse(bytes);
    } else {
      throw Exception("Failed to download GLB model: Server returned status code ${response.statusCode}");
    }
  }

  void addCustomAsset(FurnitureAsset asset) {
    state = state.copyWith(assets: [asset, ...state.assets]);
  }

  Future<void> deleteAsset(String id) async {
    try {
      await _apiClient.deleteFurnitureAsset(id);
      fetchAssets();
      fetchCategories();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete asset: $e');
    }
  }

  void clearCache() {
    _assetCache.clear();
  }
  
  int get cacheSize => _assetCache.size;
}

final furnitureProvider = NotifierProvider<FurnitureNotifier, FurnitureListState>(() {
  return FurnitureNotifier();
});
