import 'dart:convert';
import '../../../core/api/api_client.dart';

class RoomApiClient {
  final ApiClient _apiClient = ApiClient();

  Future<List<dynamic>> getRooms(String projectId) async {
    final response = await _apiClient.get('/projects/$projectId/rooms');
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return body['data'];
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to load rooms');
  }

  Future<Map<String, dynamic>> getRoomDetails(String roomId) async {
    final response = await _apiClient.get('/rooms/$roomId');
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['data'];
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to load room details');
  }

  Future<String> createRoom(String projectId, {
    required String roomName,
    required String roomType,
    int floorNumber = 1,
    String? notes,
    String roomColor = '#FFFFFF',
    String? properties,
  }) async {
    final response = await _apiClient.post(
      '/projects/$projectId/rooms',
      body: {
        'room_name': roomName,
        'room_type': roomType,
        'floor_number': floorNumber,
        'notes': notes,
        'room_color': roomColor,
        'properties': properties,
      },
    );

    final body = jsonDecode(response.body);
    if (response.statusCode == 201 && body['success'] == true) {
      return body['data']['room_id'];
    }
    throw Exception(body['detail'] ?? 'Failed to create room');
  }

  Future<void> updateRoom(String roomId, {
    String? roomName,
    String? roomType,
    int? floorNumber,
    String? notes,
    String? roomColor,
    String? properties,
  }) async {
    final Map<String, dynamic> body = {};
    if (roomName != null) body['room_name'] = roomName;
    if (roomType != null) body['room_type'] = roomType;
    if (floorNumber != null) body['floor_number'] = floorNumber;
    if (notes != null) body['notes'] = notes;
    if (roomColor != null) body['room_color'] = roomColor;
    if (properties != null) body['properties'] = properties;

    final response = await _apiClient.put('/rooms/$roomId', body: body);
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to update room');
    }
  }

  Future<void> deleteRoom(String roomId) async {
    final response = await _apiClient.delete('/rooms/$roomId');
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to delete room');
    }
  }

  Future<String> duplicateRoom(String roomId) async {
    final response = await _apiClient.post('/rooms/$roomId/duplicate');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return body['data']['room_id'];
    }
    throw Exception(body['detail'] ?? 'Failed to duplicate room');
  }

  Future<Map<String, dynamic>> getMeasurements(String roomId) async {
    final response = await _apiClient.get('/rooms/$roomId/measurements');
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['data'];
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to load measurements');
  }

  Future<void> updateMeasurements(String roomId, {
    required double length,
    required double width,
    required double height,
    double? floorThickness,
    double? wallThickness,
    double? ceilingHeight,
  }) async {
    final response = await _apiClient.put(
      '/rooms/$roomId/measurements',
      body: {
        'length': length,
        'width': width,
        'height': height,
        'floor_thickness': floorThickness ?? 30.0,
        'wall_thickness': wallThickness ?? 20.0,
        'ceiling_height': ceilingHeight ?? height,
      },
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to update measurements');
    }
  }

  Future<String?> getRoomLayout(String roomId) async {
    final response = await _apiClient.get('/rooms/$roomId/layout');
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return body['layout_data'] as String?;
    }
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to load room layout');
  }

  Future<void> saveRoomLayout(String roomId, String layoutJson) async {
    final response = await _apiClient.put(
      '/rooms/$roomId/layout',
      body: {
        'success': true,
        'layout_data': layoutJson,
      },
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to save room layout');
    }
  }
}

