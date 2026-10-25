import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/storage/token_storage.dart';
import '../../../core/api/api_client.dart';
import '../models/material_model.dart';

class MaterialApiClient {
  final ApiClient _apiClient = ApiClient();

  Future<List<MaterialCategory>> getCategories() async {
    final response = await _apiClient.get('/materials/categories');
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['success'] == true) {
        final list = decoded['data'] as List<dynamic>;
        return list.map((item) => MaterialCategory.fromJson(item as Map<String, dynamic>)).toList();
      }
    }
    throw Exception('Failed to load material categories: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> getMaterials({
    String? search,
    String? category,
    int page = 1,
    int limit = 20,
  }) async {
    String query = '?page=$page&limit=$limit';
    if (search != null && search.isNotEmpty) {
      query += '&search=${Uri.encodeComponent(search)}';
    }
    if (category != null && category.isNotEmpty) {
      query += '&category=${Uri.encodeComponent(category)}';
    }

    final response = await _apiClient.get('/materials$query');
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['success'] == true) {
        final list = decoded['data'] as List<dynamic>;
        final materials = list.map((item) => MaterialModel.fromJson(item as Map<String, dynamic>)).toList();
        return {
          'materials': materials,
          'total': decoded['total'] as int? ?? materials.length,
          'page': decoded['page'] as int? ?? page,
          'limit': decoded['limit'] as int? ?? limit,
        };
      }
    }
    throw Exception('Failed to load materials: ${response.statusCode}');
  }

  Future<MaterialModel> getMaterialDetails(String id) async {
    final response = await _apiClient.get('/materials/$id');
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['success'] == true) {
        return MaterialModel.fromJson(decoded['data'] as Map<String, dynamic>);
      }
    }
    throw Exception('Failed to load material details: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> applyMaterialToFurniture(String assetId, String materialId) async {
    final response = await _apiClient.post(
      '/furniture/$assetId/material',
      body: {'material_id': materialId},
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['success'] == true) {
        return decoded['data'] as Map<String, dynamic>;
      }
    }
    throw Exception('Failed to apply material: ${response.statusCode}');
  }

  Future<MaterialModel> createMaterial(Map<String, dynamic> data) async {
    final response = await _apiClient.post('/materials', body: data);
    if (response.statusCode == 201 || response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['success'] == true) {
        return MaterialModel.fromJson(decoded['data'] as Map<String, dynamic>);
      }
    }
    throw Exception(jsonDecode(response.body)?['detail'] ?? 'Failed to create material');
  }

  Future<MaterialModel> updateMaterial(String id, Map<String, dynamic> data) async {
    final response = await _apiClient.put('/materials/$id', body: data);
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['success'] == true) {
        return MaterialModel.fromJson(decoded['data'] as Map<String, dynamic>);
      }
    }
    throw Exception(jsonDecode(response.body)?['detail'] ?? 'Failed to update material');
  }

  Future<bool> deleteMaterial(String id) async {
    final response = await _apiClient.delete('/materials/$id');
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded['success'] == true;
    }
    throw Exception('Failed to delete material: ${response.statusCode}');
  }

  Future<MaterialModel> uploadPreviewImage(String materialId, List<int> bytes, String filename) async {
    final token = await TokenStorage().getAccessToken();
    final uri = Uri.parse('${ApiClient.baseUrl}/materials/$materialId/upload-preview');
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
      final decoded = jsonDecode(response.body);
      return MaterialModel.fromJson(decoded['data'] as Map<String, dynamic>);
    }
    throw Exception(jsonDecode(response.body)?['detail'] ?? 'Failed to upload preview image');
  }

  Future<MaterialModel> uploadTextureFile(String materialId, String textureType, List<int> bytes, String filename) async {
    final token = await TokenStorage().getAccessToken();
    final uri = Uri.parse('${ApiClient.baseUrl}/materials/$materialId/upload-texture?texture_type=$textureType');
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
      final decoded = jsonDecode(response.body);
      return MaterialModel.fromJson(decoded['data'] as Map<String, dynamic>);
    }
    throw Exception(jsonDecode(response.body)?['detail'] ?? 'Failed to upload texture file');
  }

  Future<MaterialCategory> createMaterialCategory(String name) async {
    final response = await _apiClient.post(
      '/materials/categories',
      body: {'name': name},
    );
    if (response.statusCode == 201 || response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['success'] == true) {
        final list = decoded['data'] as List<dynamic>;
        final item = list.firstWhere(
          (c) => c['name'] == name,
          orElse: () => list.last,
        );
        return MaterialCategory.fromJson(item as Map<String, dynamic>);
      }
    }
    throw Exception('Failed to create material category: ${response.statusCode}');
  }
}
