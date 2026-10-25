import 'dart:convert';
import '../../../core/api/api_client.dart';

class ValidationApiClient {
  final ApiClient _apiClient = ApiClient();

  Future<Map<String, dynamic>> runValidation(
    String roomId, {
    double? minWalkwayClearance,
    bool? requireBothSidesBedAccess,
  }) async {
    final Map<String, dynamic> payload = {'room_id': roomId};
    if (minWalkwayClearance != null) {
      payload['min_walkway_clearance'] = minWalkwayClearance;
    }
    if (requireBothSidesBedAccess != null) {
      payload['require_both_sides_bed_access'] = requireBothSidesBedAccess;
    }

    final response = await _apiClient.post(
      '/validation/run',
      body: payload,
    );
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to run validation');
  }

  Future<Map<String, dynamic>> getFixCandidate({
    required String roomId,
    required String ruleId,
    required String issueType,
    required String furnitureId,
    double? minWalkwayClearance,
    bool? requireBothSidesBedAccess,
  }) async {
    final Map<String, dynamic> payload = {
      'room_id': roomId,
      'rule_id': ruleId,
      'issue_type': issueType,
      'furniture_id': furnitureId,
    };
    if (minWalkwayClearance != null) {
      payload['min_walkway_clearance'] = minWalkwayClearance;
    }
    if (requireBothSidesBedAccess != null) {
      payload['require_both_sides_bed_access'] = requireBothSidesBedAccess;
    }

    final response = await _apiClient.post(
      '/validation/fix-candidate',
      body: payload,
    );
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to evaluate fix candidate');
  }

  Future<Map<String, dynamic>> applyFix({
    required String roomId,
    required String furnitureId,
    required double proposedX,
    required double proposedZ,
    required double proposedRotation,
  }) async {
    final response = await _apiClient.post(
      '/validation/apply-fix',
      body: {
        'room_id': roomId,
        'furniture_id': furnitureId,
        'proposed_x': proposedX,
        'proposed_z': proposedZ,
        'proposed_rotation': proposedRotation,
      },
    );
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to apply layout correction');
  }

  Future<Map<String, dynamic>> getValidationResults(String roomId) async {
    final response = await _apiClient.get('/validation/$roomId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to get validation results');
  }

  Future<Map<String, dynamic>> getValidationChecklist(String roomId) async {
    final response = await _apiClient.get('/validation/checklist/$roomId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to get validation checklist');
  }

  Future<Map<String, dynamic>> getValidationSummary(String roomId) async {
    final response = await _apiClient.get('/validation/summary/$roomId');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['detail'] ?? 'Failed to get validation summary');
  }
}
