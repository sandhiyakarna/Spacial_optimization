import 'dart:convert';
import 'package:http/http.dart' as http;
import '../storage/token_storage.dart';
import '../utils/url_helper.dart';

class ApiClient {
  static String get baseUrl => '${getBaseUrl()}/api/v1';
  final http.Client _client = http.Client();
  final TokenStorage _tokenStorage = TokenStorage();

  Future<Map<String, String>> _getHeaders({bool requireAuth = true}) async {
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (requireAuth) {
      final token = await _tokenStorage.getAccessToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  Future<bool> _refreshToken() async {
    final refreshToken = await _tokenStorage.getRefreshToken();
    if (refreshToken == null) return false;

    try {
      final url = Uri.parse('$baseUrl/auth/refresh');
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final newAccessToken = data['data']['access_token'];
          await _tokenStorage.saveTokens(
            accessToken: newAccessToken,
            refreshToken: refreshToken,
          );
          return true;
        }
      }
    } catch (e) {
      // Fail silently
    }
    return false;
  }

  Future<http.Response> _sendRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool requireAuth = true,
  }) async {
    final url = Uri.parse('$baseUrl$path');
    var headers = await _getHeaders(requireAuth: requireAuth);
    final encodedBody = body != null ? jsonEncode(body) : null;

    http.Response response;
    switch (method) {
      case 'GET':
        response = await _client.get(url, headers: headers);
        break;
      case 'POST':
        response = await _client.post(url, headers: headers, body: encodedBody);
        break;
      case 'PUT':
        response = await _client.put(url, headers: headers, body: encodedBody);
        break;
      case 'PATCH':
        response = await _client.patch(url, headers: headers, body: encodedBody);
        break;
      case 'DELETE':
        response = await _client.delete(url, headers: headers, body: encodedBody);
        break;
      default:
        throw UnsupportedError('Unsupported HTTP method: $method');
    }

    if (requireAuth && response.statusCode == 401) {
      final success = await _refreshToken();
      if (success) {
        // Retry request with new headers
        headers = await _getHeaders(requireAuth: requireAuth);
        switch (method) {
          case 'GET':
            return await _client.get(url, headers: headers);
          case 'POST':
            return await _client.post(url, headers: headers, body: encodedBody);
          case 'PUT':
            return await _client.put(url, headers: headers, body: encodedBody);
          case 'PATCH':
            return await _client.patch(url, headers: headers, body: encodedBody);
          case 'DELETE':
            return await _client.delete(url, headers: headers, body: encodedBody);
        }
      }
    }

    return response;
  }

  Future<http.Response> post(String path, {Map<String, dynamic>? body, bool requireAuth = true}) async {
    return await _sendRequest('POST', path, body: body, requireAuth: requireAuth);
  }

  Future<http.Response> get(String path, {bool requireAuth = true}) async {
    return await _sendRequest('GET', path, requireAuth: requireAuth);
  }

  Future<http.Response> put(String path, {Map<String, dynamic>? body, bool requireAuth = true}) async {
    return await _sendRequest('PUT', path, body: body, requireAuth: requireAuth);
  }

  Future<http.Response> patch(String path, {Map<String, dynamic>? body, bool requireAuth = true}) async {
    return await _sendRequest('PATCH', path, body: body, requireAuth: requireAuth);
  }

  Future<http.Response> delete(String path, {Map<String, dynamic>? body, bool requireAuth = true}) async {
    return await _sendRequest('DELETE', path, body: body, requireAuth: requireAuth);
  }
}
