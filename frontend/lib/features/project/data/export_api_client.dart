import 'dart:convert';
import 'dart:typed_data';
import '../../../core/api/api_client.dart';

class ExportApiClient {
  final ApiClient _apiClient = ApiClient();

  Future<String> generateReport({
    required String projectId,
    String? roomId,
    required String reportType,
    String format = 'PDF',
  }) async {
    final response = await _apiClient.post(
      '/reports/generate',
      body: {
        'project_id': projectId,
        'room_id': roomId,
        'report_type': reportType,
        'format': format,
      },
    );

    final body = jsonDecode(response.body);
    if ((response.statusCode == 200 || response.statusCode == 201) && body['success'] == true) {
      return body['data']['report_id'];
    }
    throw Exception(body['detail'] ?? 'Failed to initiate report generation');
  }

  Future<String> getReportStatus(String reportId) async {
    final response = await _apiClient.get('/reports/$reportId/status');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data']['status'];
    }
    throw Exception(body['detail'] ?? 'Failed to get report status');
  }

  Future<Uint8List> downloadReport(String reportId) async {
    final response = await _apiClient.get('/reports/$reportId/download');
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    throw Exception('Failed to download report');
  }

  Future<List<dynamic>> getReportHistory(String projectId) async {
    final response = await _apiClient.get('/reports/history/$projectId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to load report history');
  }

  Future<Map<String, dynamic>> exportProjectJson(String projectId) async {
    final response = await _apiClient.post(
      '/export/project',
      body: {
        'project_id': projectId,
        'format': 'JSON',
      },
    );
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to export project');
  }

  Future<Uint8List> exportProjectFile(String projectId, String format) async {
    final response = await _apiClient.post(
      '/export/project',
      body: {
        'project_id': projectId,
        'format': format,
      },
    );
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    throw Exception('Failed to export project in $format format');
  }

  Future<Map<String, dynamic>> exportRoomJson(String roomId) async {
    final response = await _apiClient.post(
      '/export/room',
      body: {
        'room_id': roomId,
        'format': 'JSON',
      },
    );
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to export room');
  }

  Future<Uint8List> exportRoomFile(String roomId, String format) async {
    final response = await _apiClient.post(
      '/export/room',
      body: {
        'room_id': roomId,
        'format': format,
      },
    );
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    throw Exception('Failed to export room in $format format');
  }

  Future<Uint8List> exportSceneImage(String roomId) async {
    final response = await _apiClient.post(
      '/export/image',
      body: {
        'room_id': roomId,
        'format': 'PNG',
      },
    );
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    throw Exception('Failed to export scene image');
  }

  Future<Map<String, dynamic>> exportAnalytics(String roomId) async {
    final response = await _apiClient.post(
      '/export/analytics',
      body: {
        'room_id': roomId,
        'format': 'JSON',
      },
    );
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to export room analytics');
  }

  Future<void> importProject(Map<String, dynamic> projectData) async {
    final response = await _apiClient.post(
      '/projects/import',
      body: projectData,
    );
    final body = jsonDecode(response.body);
    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['detail'] ?? 'Failed to import project');
    }
  }

  Future<Map<String, dynamic>> backupProject(String projectId) async {
    final response = await _apiClient.post('/projects/$projectId/backup');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to backup project');
  }

  Future<void> restoreProject(Map<String, dynamic> backupData) async {
    final response = await _apiClient.post(
      '/projects/restore',
      body: backupData,
    );
    final body = jsonDecode(response.body);
    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['detail'] ?? 'Failed to restore project');
    }
  }
}
