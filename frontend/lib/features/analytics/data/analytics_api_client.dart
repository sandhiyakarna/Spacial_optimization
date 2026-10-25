import 'dart:convert';
import '../../../core/api/api_client.dart';

class AnalyticsApiClient {
  final ApiClient _apiClient = ApiClient();

  Future<Map<String, dynamic>> getAnalyticsDashboard(String roomId) async {
    final response = await _apiClient.get('/analytics/$roomId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to load analytics dashboard');
  }

  Future<Map<String, dynamic>> getDetailedScores(String roomId) async {
    final response = await _apiClient.get('/analytics/$roomId/scores');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to load detailed scores');
  }

  Future<Map<String, dynamic>> compareLayouts(String layoutA, String layoutB) async {
    final response = await _apiClient.post(
      '/analytics/compare',
      body: {
        'layout_a': layoutA,
        'layout_b': layoutB,
      },
    );
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to compare room layouts');
  }

  Future<List<dynamic>> getHistory(String roomId) async {
    final response = await _apiClient.get('/analytics/history/$roomId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to load layout history');
  }

  Future<Map<String, dynamic>> getStatistics(String roomId) async {
    final response = await _apiClient.get('/analytics/statistics/$roomId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to load room statistics');
  }

  Future<List<dynamic>> getInsights(String roomId) async {
    final response = await _apiClient.get('/analytics/insights/$roomId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to load design insights');
  }

  Future<Map<String, dynamic>> getProjectAnalytics(String projectId) async {
    final response = await _apiClient.get('/analytics/project/$projectId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to load project analytics');
  }

  Future<Map<String, dynamic>> restoreHistory(String roomId, int versionNumber) async {
    final response = await _apiClient.post(
      '/analytics/history/restore',
      body: {
        'room_id': roomId,
        'version_number': versionNumber,
      },
    );
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to restore design version');
  }

  Future<Map<String, dynamic>> getSystemTelemetry(String period) async {
    final response = await _apiClient.get('/analytics/admin/system?period=$period');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to load system telemetry');
  }
}

