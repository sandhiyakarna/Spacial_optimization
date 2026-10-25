import 'dart:convert';
import '../../../core/api/api_client.dart';

class AiApiClient {
  final ApiClient _apiClient = ApiClient();

  Future<String> generateLayout(
    String roomId, {
    String style = "Modern",
    List<String>? preferences,
    String? mode,
    List<String>? lockedFurnitureIds,
    String? command,
  }) async {
    final response = await _apiClient.post(
      '/ai/layout',
      body: {
        'room_id': roomId,
        'style': style,
        'preferences': preferences ?? [],
        if (mode != null) 'mode': mode,
        if (lockedFurnitureIds != null && lockedFurnitureIds.isNotEmpty)
          'locked_furniture_ids': lockedFurnitureIds,
        if (command != null && command.isNotEmpty) 'command': command,
      },
    );
    final body = jsonDecode(response.body);
    if (response.statusCode == 201 && body['success'] == true) {
      return body['data']['job_id'];
    }
    throw Exception(body['detail'] ?? 'Failed to start AI layout generation');
  }

  Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final response = await _apiClient.get('/ai/jobs/$jobId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to get job status');
  }

  Future<Map<String, dynamic>> getJobResult(String jobId) async {
    final response = await _apiClient.get('/ai/results/$jobId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to get job result');
  }

  Future<Map<String, dynamic>> optimizeLayout(String roomId) async {
    final response = await _apiClient.post(
      '/ai/optimize',
      body: {'room_id': roomId},
    );
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to optimize room layout');
  }

  Future<List<dynamic>> getRecommendations(String roomId) async {
    final response = await _apiClient.get('/ai/recommendations/$roomId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to load recommendations');
  }

  Future<Map<String, dynamic>> explainRecommendation(String recId) async {
    final response = await _apiClient.get('/ai/explain/$recId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to explain recommendation');
  }

  Future<List<dynamic>> getHistory(String roomId) async {
    final response = await _apiClient.get('/ai/history/$roomId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to load AI history');
  }

  Future<Map<String, dynamic>> applyRecommendation(String recId) async {
    final response = await _apiClient.post('/ai/apply/$recId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body;
    }
    throw Exception(body['detail'] ?? 'Failed to apply recommendation');
  }

  Future<Map<String, dynamic>> getRoomScores(String roomId) async {
    final response = await _apiClient.get('/ai/scores/$roomId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to load design scores');
  }
}
