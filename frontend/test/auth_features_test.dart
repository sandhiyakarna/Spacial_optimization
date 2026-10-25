import 'package:flutter_test/flutter_test.dart';
import 'package:flowspace_frontend/core/storage/token_storage.dart';

void main() {
  group('TokenStorage - Remember Me & Session Persistence', () {
    setUp(() async {
      await TokenStorage().clearTokens();
    });

    test('Saving tokens with rememberMe = false saves in memory', () async {
      final storage = TokenStorage();
      await storage.saveTokens(
        accessToken: 'temp_access',
        refreshToken: 'temp_refresh',
        rememberMe: false,
      );

      expect(await storage.getAccessToken(), equals('temp_access'));
      expect(await storage.getRefreshToken(), equals('temp_refresh'));
    });

    test('Saving tokens with rememberMe = true saves correctly', () async {
      final storage = TokenStorage();
      await storage.saveTokens(
        accessToken: 'persist_access',
        refreshToken: 'persist_refresh',
        rememberMe: true,
      );

      expect(await storage.getAccessToken(), equals('persist_access'));
      expect(await storage.getRefreshToken(), equals('persist_refresh'));
    });

    test('Clearing tokens resets token states', () async {
      final storage = TokenStorage();
      await storage.saveTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        rememberMe: true,
      );
      await storage.clearTokens();

      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
    });
  });
}
