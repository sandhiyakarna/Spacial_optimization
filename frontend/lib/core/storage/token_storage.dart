import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

class TokenStorage {
  static final TokenStorage _instance = TokenStorage._internal();
  factory TokenStorage() => _instance;

  TokenStorage._internal() {
    bool isTest = false;
    if (!kIsWeb) {
      try {
        isTest = Platform.environment.containsKey('FLUTTER_TEST');
      } catch (_) {}
    }
    if (isTest) {
      _useInMemory = true;
    }
  }

  final _secureStorage = const FlutterSecureStorage();

  // In-memory fallback for tests/environments where secure storage is unavailable
  String? _accessToken;
  String? _refreshToken;
  bool _hasSeenOnboarding = false;
  bool _useInMemory = false;
  bool _rememberMe = false;

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    bool? rememberMe,
  }) async {
    if (rememberMe != null) {
      _rememberMe = rememberMe;
    }
    _accessToken = accessToken;
    _refreshToken = refreshToken;

    if (_useInMemory) {
      return;
    }

    if (!_rememberMe) {
      try {
        await _secureStorage.delete(key: 'access_token');
        await _secureStorage.delete(key: 'refresh_token');
      } catch (_) {}
      return;
    }
    try {
      await _secureStorage.write(key: 'access_token', value: accessToken);
      await _secureStorage.write(key: 'refresh_token', value: refreshToken);
    } catch (e) {
      _useInMemory = true;
    }
  }

  Future<String?> getAccessToken() async {
    if (_useInMemory) {
      return _accessToken;
    }
    try {
      final token = await _secureStorage.read(key: 'access_token');
      if (token != null) {
        _rememberMe = true;
        _accessToken = token;
      }
      return token;
    } catch (e) {
      _useInMemory = true;
      return _accessToken;
    }
  }

  Future<String?> getRefreshToken() async {
    if (_useInMemory) {
      return _refreshToken;
    }
    try {
      final token = await _secureStorage.read(key: 'refresh_token');
      if (token != null) {
        _rememberMe = true;
        _refreshToken = token;
      }
      return token;
    } catch (e) {
      _useInMemory = true;
      return _refreshToken;
    }
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _rememberMe = false;
    if (!_useInMemory) {
      try {
        await _secureStorage.delete(key: 'access_token');
        await _secureStorage.delete(key: 'refresh_token');
      } catch (e) {
        _useInMemory = true;
      }
    }
  }

  Future<bool> getHasSeenOnboarding() async {
    if (_useInMemory) {
      return _hasSeenOnboarding;
    }
    try {
      final value = await _secureStorage.read(key: 'has_seen_onboarding');
      return value == 'true';
    } catch (e) {
      _useInMemory = true;
      return _hasSeenOnboarding;
    }
  }

  Future<void> setHasSeenOnboarding(bool value) async {
    if (_useInMemory) {
      _hasSeenOnboarding = value;
      return;
    }
    try {
      await _secureStorage.write(key: 'has_seen_onboarding', value: value.toString());
    } catch (e) {
      _useInMemory = true;
      _hasSeenOnboarding = value;
    }
  }
}
