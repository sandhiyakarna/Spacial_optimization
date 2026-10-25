import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowspace_frontend/app/app.dart';
import 'package:flowspace_frontend/core/storage/token_storage.dart';
import 'package:flowspace_frontend/features/auth/providers/auth_provider.dart';
import 'package:flowspace_frontend/features/project/providers/dashboard_provider.dart';

class MockDashboardNotifier extends DashboardNotifier {
  @override
  DashboardState build() {
    return const DashboardState(
      isLoading: false,
      data: <String, dynamic>{
        'welcome_message': 'Welcome back, Project Tester!',
        'total_projects': 2,
        'total_rooms': 5,
        'recent_projects': <dynamic>[],
        'favorite_projects': <dynamic>[],
        'recent_activity': <dynamic>[],
        'ai_recommendations': <dynamic>[],
        'analytics_summary': <String, dynamic>{},
        'notifications': <dynamic>[]
      },
    );
  }
}

class MockAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState(
      profile: <String, dynamic>{
        'email': 'project@example.com',
        'role': 'Customer',
        'full_name': 'Project Tester'
      }
    );
  }
}

void main() {
  setUp(() async {
    await TokenStorage().clearTokens();
    await TokenStorage().setHasSeenOnboarding(true);
  });

  testWidgets('Smoke test - Verify App initializes on Splash and redirects to Login when not authenticated', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: FlowSpaceApp(),
      ),
    );

    // Verify Splash Screen renders
    await tester.pump();
    expect(find.text('FlowSpace'), findsOneWidget);

    // Wait for the splash delay and route guarding redirect
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 500));

    // Should redirect to Login screen
    expect(find.text('Welcome Back 👋'), findsOneWidget);
  });

  testWidgets('Verify App routes to Dashboard when already authenticated', (WidgetTester tester) async {
    // Save fake tokens to simulate authenticated state
    await TokenStorage().saveTokens(accessToken: 'mock_jwt', refreshToken: 'mock_refresh');

    // Set a tablet/desktop screen size to avoid overflows in responsive layout
    tester.view.physicalSize = const Size(1620, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => MockAuthNotifier()),
          dashboardProvider.overrideWith(() => MockDashboardNotifier()),
        ],
        child: const FlowSpaceApp(),
      ),
    );

    // Settle splash routing
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 500));

    // Verify Dashboard is reached by finding the "Popular Layout Templates" widget header
    expect(find.text('Popular Layout Templates'), findsOneWidget);
  });
}
