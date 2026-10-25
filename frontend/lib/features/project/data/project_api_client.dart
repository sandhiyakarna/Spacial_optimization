import 'dart:convert';
import '../../../core/api/api_client.dart';

class ProjectApiClient {
  final ApiClient _apiClient = ApiClient();

  Future<Map<String, dynamic>> getDashboardSummary() async {
    final response = await _apiClient.get('/dashboard');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to load dashboard');
  }

  Future<List<dynamic>> getProjects({
    int page = 1,
    int limit = 20,
    String? status,
    String? search,
    String? sort = 'created_at',
    bool favorite = false,
  }) async {
    String query = '?page=$page&limit=$limit&favorite=$favorite';
    if (status != null) query += '&status=$status';
    if (search != null && search.isNotEmpty) query += '&search=${Uri.encodeComponent(search)}';
    if (sort != null) query += '&sort=$sort';

    final response = await _apiClient.get('/projects$query');
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return body['data'];
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to load projects');
  }

  Future<Map<String, dynamic>> getProjectDetails(String projectId) async {
    final response = await _apiClient.get('/projects/$projectId');
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['data'];
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to load project details');
  }

  Future<String> createProject({
    required String projectName,
    String? description,
    String? location,
  }) async {
    final response = await _apiClient.post(
      '/projects',
      body: {
        'project_name': projectName,
        'description': description,
        'location': location,
      },
    );

    final body = jsonDecode(response.body);
    if (response.statusCode == 201 && body['success'] == true) {
      return body['data']['project_id'];
    }
    throw Exception(body['detail'] ?? 'Failed to create project');
  }

  Future<void> updateProject(String projectId, {
    String? projectName,
    String? description,
    String? location,
    String? status,
    bool? isFavorite,
  }) async {
    final Map<String, dynamic> body = {};
    if (projectName != null) body['project_name'] = projectName;
    if (description != null) body['description'] = description;
    if (location != null) body['location'] = location;
    if (status != null) body['status'] = status;
    if (isFavorite != null) body['is_favorite'] = isFavorite;

    final response = await _apiClient.put('/projects/$projectId', body: body);
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to update project');
    }
  }

  Future<void> archiveProject(String projectId) async {
    final response = await _apiClient.patch('/projects/$projectId/archive');
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to archive project');
    }
  }

  Future<void> restoreProject(String projectId) async {
    final response = await _apiClient.patch('/projects/$projectId/restore');
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to restore project');
    }
  }

  Future<void> softDeleteProject(String projectId) async {
    final response = await _apiClient.delete('/projects/$projectId');
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to delete project');
    }
  }

  Future<String> duplicateProject(String projectId) async {
    final response = await _apiClient.post('/projects/$projectId/duplicate');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data']['project_id'];
    }
    throw Exception(body['detail'] ?? 'Failed to duplicate project');
  }

  Future<bool> toggleFavorite(String projectId) async {
    final response = await _apiClient.patch('/projects/$projectId/toggle-favorite');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data']['is_favorite'];
    }
    throw Exception(body['detail'] ?? 'Failed to toggle favorite');
  }
}
