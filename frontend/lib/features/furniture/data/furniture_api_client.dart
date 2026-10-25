import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/api/api_client.dart';
import '../../../core/storage/token_storage.dart';
import '../models/furniture_asset.dart';

class FurnitureApiClient {
  final ApiClient _apiClient = ApiClient();

  Future<List<FurnitureAsset>> getFurnitureAssets({
    String? search,
    String? category,
    String? style,
    bool favoritesOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    final List<String> params = [];
    if (search != null && search.isNotEmpty) {
      params.add('search=${Uri.encodeComponent(search)}');
    }
    if (category != null && category.isNotEmpty) {
      params.add('category=${Uri.encodeComponent(category)}');
    }
    if (style != null && style.isNotEmpty) {
      params.add('style=${Uri.encodeComponent(style)}');
    }
    if (favoritesOnly) {
      params.add('favorites_only=true');
    }
    params.add('page=$page');
    params.add('limit=$limit');

    final String query = params.isEmpty ? '' : '?${params.join('&')}';
    final response = await _apiClient.get('/furniture$query');

    if (response.statusCode == 200) {
      final List<dynamic> body = jsonDecode(response.body);
      return body.map((item) => FurnitureAsset.fromJson(item)).toList();
    }
    
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to load furniture assets');
  }

  Future<FurnitureAsset> getFurnitureAssetDetails(String assetId) async {
    final response = await _apiClient.get('/furniture/$assetId');

    if (response.statusCode == 200) {
      final dynamic body = jsonDecode(response.body);
      return FurnitureAsset.fromJson(body);
    }

    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to load furniture asset details');
  }

  Future<List<FurnitureAsset>> getFavorites({
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _apiClient.get('/furniture/favorites?page=$page&limit=$limit');
    if (response.statusCode == 200) {
      final List<dynamic> body = jsonDecode(response.body);
      return body.map((item) => FurnitureAsset.fromJson(item)).toList();
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to load favorite assets');
  }

  Future<List<FurnitureAsset>> getRecentlyUsed({
    int limit = 10,
  }) async {
    final response = await _apiClient.get('/furniture/recent?limit=$limit');
    if (response.statusCode == 200) {
      final List<dynamic> body = jsonDecode(response.body);
      return body.map((item) => FurnitureAsset.fromJson(item)).toList();
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to load recently used assets');
  }

  Future<void> favoriteAsset(String assetId) async {
    final response = await _apiClient.post('/furniture/$assetId/favorite');
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to favorite asset');
    }
  }

  Future<void> unfavoriteAsset(String assetId) async {
    final response = await _apiClient.delete('/furniture/$assetId/favorite');
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to unfavorite asset');
    }
  }

  Future<List<FurnitureCategory>> getCategories() async {
    final response = await _apiClient.get('/furniture/categories');
    if (response.statusCode == 200) {
      final List<dynamic> body = jsonDecode(response.body);
      return body.map((item) => FurnitureCategory.fromJson(item)).toList();
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to load categories');
  }

  Future<FurnitureAsset> createFurnitureAsset(Map<String, dynamic> data) async {
    final response = await _apiClient.post('/furniture', body: data);
    if (response.statusCode == 201) {
      return FurnitureAsset.fromJson(jsonDecode(response.body));
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to create furniture asset');
  }

  Future<FurnitureAsset> uploadGlbFile(String assetId, List<int> bytes, String filename) async {
    final token = await TokenStorage().getAccessToken();
    final uri = Uri.parse('${ApiClient.baseUrl}/furniture/$assetId/upload-model');
    final request = http.MultipartRequest('POST', uri);
    
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.headers['Accept'] = 'application/json';
    
    final multipartFile = http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
    );
    request.files.add(multipartFile);
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 200) {
      return FurnitureAsset.fromJson(jsonDecode(response.body));
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to upload GLB model');
  }

  Future<FurnitureAsset> uploadThumbnailFile(String assetId, List<int> bytes, String filename) async {
    final token = await TokenStorage().getAccessToken();
    final uri = Uri.parse('${ApiClient.baseUrl}/furniture/$assetId/upload-thumbnail');
    final request = http.MultipartRequest('POST', uri);
    
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.headers['Accept'] = 'application/json';
    
    final multipartFile = http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
    );
    request.files.add(multipartFile);
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 200) {
      return FurnitureAsset.fromJson(jsonDecode(response.body));
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to upload thumbnail');
  }

  Future<Map<String, dynamic>> checkDuplicate(Map<String, dynamic> data) async {
    final response = await _apiClient.post('/furniture/check-duplicate', body: data);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to check duplicates');
  }

  Future<FurnitureAsset> updateFurnitureAsset(String assetId, Map<String, dynamic> data) async {
    final response = await _apiClient.put('/furniture/$assetId', body: data);
    if (response.statusCode == 200) {
      return FurnitureAsset.fromJson(jsonDecode(response.body));
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to update furniture asset');
  }

  Future<void> deleteFurnitureAsset(String assetId) async {
    final response = await _apiClient.delete('/furniture/$assetId');
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to delete furniture asset');
    }
  }

  Future<FurnitureAsset> uploadPreviewFile(String assetId, List<int> bytes, String filename) async {
    final token = await TokenStorage().getAccessToken();
    final uri = Uri.parse('${ApiClient.baseUrl}/furniture/$assetId/upload-preview');
    final request = http.MultipartRequest('POST', uri);
    
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.headers['Accept'] = 'application/json';
    
    final multipartFile = http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
    );
    request.files.add(multipartFile);
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 200) {
      return FurnitureAsset.fromJson(jsonDecode(response.body));
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to upload preview image');
  }

  Future<void> bulkDeleteFurniture(List<String> assetIds) async {
    final response = await _apiClient.post('/furniture/bulk-delete', body: {'asset_ids': assetIds});
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed bulk deletion');
    }
  }

  Future<void> bulkUpdateCategory(List<String> assetIds, String category) async {
    final response = await _apiClient.post('/furniture/bulk-update-category', body: {
      'asset_ids': assetIds,
      'category': category,
    });
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed bulk category update');
    }
  }

  Future<FurnitureCategory> createCategory(String name, String? description) async {
    final response = await _apiClient.post('/furniture/categories', body: {
      'name': name,
      'description': description,
    });
    if (response.statusCode == 201) {
      return FurnitureCategory.fromJson(jsonDecode(response.body));
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to create category');
  }

  Future<FurnitureCategory> updateCategory(String id, String name, String? description) async {
    final response = await _apiClient.put('/furniture/categories/$id', body: {
      'name': name,
      'description': description,
    });
    if (response.statusCode == 200) {
      return FurnitureCategory.fromJson(jsonDecode(response.body));
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to update category');
  }

  Future<void> deleteCategory(String id) async {
    final response = await _apiClient.delete('/furniture/categories/$id');
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to delete category');
    }
  }
}

