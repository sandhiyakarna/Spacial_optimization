import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/storage/token_storage.dart';

class AuthState {
  final bool isLoading;
  final String? errorMessage;
  final Map<String, dynamic>? profile;

  bool get isAuthenticated => profile != null;

  const AuthState({
    this.isLoading = false,
    this.errorMessage,
    this.profile,
  });

  AuthState copyWith({
    bool? isLoading,
    String? errorMessage,
    Map<String, dynamic>? profile,
    bool clearProfile = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      profile: clearProfile ? null : (profile ?? this.profile),
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  final ApiClient _apiClient = ApiClient();
  final TokenStorage _tokenStorage = TokenStorage();

  @override
  AuthState build() {
    // Schedule tryAutoLogin after the current frame is processed to avoid state mutations during initialization
    Future.microtask(() => _tryAutoLogin());
    return const AuthState();
  }

  Future<void> _tryAutoLogin() async {
    final token = await _tokenStorage.getAccessToken();
    if (token != null) {
      await fetchProfile();
    }
  }

  String _getErrorMessage(Object error) {
    if (error is FormatException) {
      return 'Invalid server response. Please try again later.';
    }
    final errStr = error.toString();
    if (errStr.contains('SocketException') || errStr.contains('ClientException') || errStr.contains('Connection refused')) {
      return 'Connection error. Please check your internet connection and try again.';
    }
    return errStr;
  }

  String _extractErrorMessage(dynamic responseData, String defaultMessage) {
    if (responseData == null) return defaultMessage;
    final detail = responseData['detail'];
    if (detail == null) {
      return responseData['message'] ?? defaultMessage;
    }
    if (detail is String) {
      return detail;
    }
    if (detail is List) {
      try {
        final messages = detail.map((err) {
          final loc = err['loc'] as List?;
          final msg = err['msg'] ?? '';
          final field = loc != null && loc.length > 1 ? loc[1] : '';
          return field.isNotEmpty ? '$field: $msg' : '$msg';
        }).join(', ');
        return messages;
      } catch (_) {
        return detail.toString();
      }
    }
    return detail.toString();
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _apiClient.post(
        '/auth/register',
        body: {
          'full_name': fullName,
          'email': email,
          'password': password,
        },
        requireAuth: false,
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 && data['success'] == true) {
        state = state.copyWith(isLoading: false);
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: _extractErrorMessage(data, 'Registration failed'),
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _getErrorMessage(e));
      return false;
    }
  }

  Future<bool> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _apiClient.post(
        '/auth/login',
        body: {
          'email': email,
          'password': password,
          'remember_me': rememberMe,
        },
        requireAuth: false,
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final tokenData = data['data'];
        await _tokenStorage.saveTokens(
          accessToken: tokenData['access_token'],
          refreshToken: tokenData['refresh_token'],
          rememberMe: rememberMe,
        );
        await fetchProfile();
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: _extractErrorMessage(data, 'Login failed'),
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _getErrorMessage(e));
      return false;
    }
  }

  Future<void> fetchProfile() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _apiClient.get('/auth/profile');
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        state = state.copyWith(isLoading: false, profile: data['data']);
      } else {
        await _tokenStorage.clearTokens();
        state = state.copyWith(
          isLoading: false,
          clearProfile: true,
          errorMessage: _extractErrorMessage(data, 'Session expired'),
        );
      }
    } catch (e) {
      await _tokenStorage.clearTokens();
      state = state.copyWith(
        isLoading: false,
        clearProfile: true,
        errorMessage: _getErrorMessage(e),
      );
    }
  }

  Future<bool> updateProfile({
    required String fullName,
    String? profileImage,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _apiClient.put(
        '/auth/profile',
        body: {
          'full_name': fullName,
          'profile_image': profileImage,
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        await fetchProfile();
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: _extractErrorMessage(data, 'Failed to update profile'),
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _getErrorMessage(e));
      return false;
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _apiClient.put(
        '/auth/change-password',
        body: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        state = state.copyWith(isLoading: false);
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: _extractErrorMessage(data, 'Failed to change password'),
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _getErrorMessage(e));
      return false;
    }
  }

  Future<bool> forgotPassword({required String email}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _apiClient.post(
        '/auth/forgot-password',
        body: {'email': email},
        requireAuth: false,
      );

      final data = jsonDecode(response.body);
      state = state.copyWith(isLoading: false);
      if (response.statusCode == 200 && data['success'] == true) {
        return true;
      } else {
        state = state.copyWith(errorMessage: _extractErrorMessage(data, 'Request failed'));
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _getErrorMessage(e));
      return false;
    }
  }

  Future<bool> resetPassword({required String token, required String newPassword}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _apiClient.post(
        '/auth/reset-password',
        body: {
          'token': token,
          'new_password': newPassword,
        },
        requireAuth: false,
      );

      final data = jsonDecode(response.body);
      state = state.copyWith(isLoading: false);
      if (response.statusCode == 200 && data['success'] == true) {
        return true;
      } else {
        state = state.copyWith(errorMessage: _extractErrorMessage(data, 'Reset failed'));
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _getErrorMessage(e));
      return false;
    }
  }

  Future<String?> requestVerification() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _apiClient.post('/auth/request-verification');
      final data = jsonDecode(response.body);
      state = state.copyWith(isLoading: false);
      if (response.statusCode == 200 && data['success'] == true) {
        return data['data']?['token'];
      } else {
        state = state.copyWith(errorMessage: _extractErrorMessage(data, 'Failed to request verification token'));
        return null;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _getErrorMessage(e));
      return null;
    }
  }

  Future<bool> verifyEmail({required String token}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _apiClient.post(
        '/auth/verify-email',
        body: {'token': token},
        requireAuth: false,
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        await fetchProfile();
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: _extractErrorMessage(data, 'Verification failed'),
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _getErrorMessage(e));
      return false;
    }
  }

  Future<bool> logoutAllDevices() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _apiClient.post('/auth/logout-all');
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        await _tokenStorage.clearTokens();
        state = const AuthState();
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: _extractErrorMessage(data, 'Failed to logout from all devices'),
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _getErrorMessage(e));
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _apiClient.post('/auth/logout');
    } catch (_) {}
    await _tokenStorage.clearTokens();
    state = const AuthState();
  }

  Future<bool> deleteAccount({required String password}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _apiClient.delete(
        '/auth/account',
        body: {'password': password},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        await _tokenStorage.clearTokens();
        state = const AuthState();
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: _extractErrorMessage(data, 'Failed to delete account'),
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _getErrorMessage(e));
      return false;
    }
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
