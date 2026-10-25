import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flowspace_frontend/features/admin/providers/admin_provider.dart';
import 'package:flowspace_frontend/features/admin/presentation/widgets/admin_guard.dart';
import 'package:flowspace_frontend/features/admin/presentation/unauthorized_screen.dart';
import 'package:flowspace_frontend/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:flowspace_frontend/features/auth/providers/auth_provider.dart';

class MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return MockHttpClient();
  }
}

class MockHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    if (name.contains('Url') || name.contains('open') || name.contains('post') || name.contains('get')) {
      Uri? url;
      for (final arg in invocation.positionalArguments) {
        if (arg is Uri) {
          url = arg;
          break;
        }
      }
      return Future.value(MockHttpClientRequest(url));
    }
    return null;
  }
}

class MockHttpClientRequest implements HttpClientRequest {
  final Uri? url;
  MockHttpClientRequest(this.url);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #headers) {
      return MockHttpHeaders();
    }
    if (invocation.memberName == #close) {
      return Future.value(MockHttpClientResponse(url));
    }
    return Future.value();
  }
}

class MockHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockHttpClientResponse implements HttpClientResponse {
  final Uri? url;
  MockHttpClientResponse(this.url);

  List<int> get _bodyBytes {
    final path = url?.path ?? '';
    if (path.contains('/system/cache/purge')) {
      return utf8.encode(jsonEncode({'success': true, 'current_size': '0 B'}));
    }
    if (path.contains('/system/status')) {
      return utf8.encode(jsonEncode({
        'services': {
          'FastAPI Service': 'HEALTHY',
          'Database': 'CONNECTED',
          'Storage Service': 'HEALTHY',
        },
        'cache': {
          'size_formatted': '32 MB',
        }
      }));
    }
    return utf8.encode(jsonEncode({'success': true}));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #statusCode) return 200;
    if (invocation.memberName == #contentLength) return _bodyBytes.length;
    if (invocation.memberName == #headers) return MockHttpHeaders();
    if (invocation.memberName == #reasonPhrase) return "OK";
    if (invocation.memberName == #isRedirect) return false;
    if (invocation.memberName == #persistentConnection) return false;
    if (invocation.memberName == #redirects) return const <RedirectInfo>[];
    if (invocation.memberName == #cookies) return const <Cookie>[];
    if (invocation.memberName == #compressionState) return HttpClientResponseCompressionState.notCompressed;
    if (invocation.memberName == #listen) {
      final handler = invocation.positionalArguments[0] as void Function(List<int>);
      final onDone = invocation.namedArguments[#onDone] as void Function()?;
      final onError = invocation.namedArguments[#onError] as Function?;
      final cancelOnError = invocation.namedArguments[#cancelOnError] as bool?;
      return Stream<List<int>>.fromIterable([_bodyBytes]).listen(
        handler,
        onDone: onDone,
        onError: onError,
        cancelOnError: cancelOnError,
      );
    }
    return null;
  }
}

// Mock auth notifier to inject specific user profile states for testing RBAC
class MockAuthNotifier extends AuthNotifier {
  final AuthState mockState;
  MockAuthNotifier(this.mockState);

  @override
  AuthState build() => mockState;
}

// Mock admin notifier to inject stable state and block network requests during widget tests
class MockAdminNotifier extends AdminNotifier {
  final AdminState mockState;
  MockAdminNotifier(this.mockState);

  @override
  AdminState build() => mockState;

  @override
  Future<void> fetchAdminDashboard() async {
    // No-op to block real API client network requests
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = MockHttpOverrides();
  });
  group('AdminState & AdminNotifier Unit Tests', () {
    test('Default values of AdminState are initialized correctly', () {
      const state = AdminState();
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNull);
      expect(state.activeSection, equals(AdminSection.dashboard));
      expect(state.activeUsersCount, equals(142));
      expect(state.projectsCount, equals(84));
      expect(state.furnitureAssetsCount, equals(312));
      expect(state.materialsCount, equals(98));
      expect(state.systemHealth['Database'], equals('CONNECTED'));
      expect(state.systemConfig['Maintenance Mode'], isFalse);
      expect(state.selectedPeriod, equals('7d'));
      expect(state.telemetryData, isNull);
    });

    test('AdminState.copyWith overrides values correctly', () {
      const state = AdminState();
      final updated = state.copyWith(
        isLoading: true,
        errorMessage: 'Fail',
        activeSection: AdminSection.users,
        activeUsersCount: 200,
        selectedPeriod: '30d',
        telemetryData: {'active_users': {'active_users_count': 10}},
      );

      expect(updated.isLoading, isTrue);
      expect(updated.errorMessage, equals('Fail'));
      expect(updated.activeSection, equals(AdminSection.users));
      expect(updated.activeUsersCount, equals(200));
      expect(updated.selectedPeriod, equals('30d'));
      expect(updated.telemetryData?['active_users']?['active_users_count'], equals(10));
    });

    test('AdminNotifier changes sections successfully', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(adminProvider.notifier);
      await Future.delayed(Duration.zero); // Let background initialization fetch finish

      expect(container.read(adminProvider).activeSection, equals(AdminSection.dashboard));

      notifier.changeSection(AdminSection.system);
      expect(container.read(adminProvider).activeSection, equals(AdminSection.system));
    });

    test('AdminNotifier toggles configuration parameters', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(adminProvider.notifier);
      await Future.delayed(Duration.zero); // Wait for background fetch to avoid mutations after dispose

      expect(container.read(adminProvider).systemConfig['Maintenance Mode'], isFalse);

      notifier.toggleConfig('Maintenance Mode');
      expect(container.read(adminProvider).systemConfig['Maintenance Mode'], isTrue);
    });

    test('AdminNotifier suspends and activates users', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(adminProvider.notifier);
      await Future.delayed(Duration.zero); // Wait for background fetch to avoid mutations after dispose
      
      // Find David (who is Suspended by default in mock list)
      final davidIndex = container.read(adminProvider).users.indexWhere((u) => u['email'] == 'david@gmail.com');
      expect(container.read(adminProvider).users[davidIndex]['status'], equals('Suspended'));

      notifier.toggleUserStatus('david@gmail.com');
      expect(container.read(adminProvider).users[davidIndex]['status'], equals('Active'));
    });

    test('AdminNotifier cleans cache successfully', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(adminProvider.notifier);
      await Future.delayed(Duration.zero); // Wait for background fetch to avoid mutations after dispose

      expect(container.read(adminProvider).systemHealth['Cache Manager'], equals('32 MB'));

      await notifier.clearSystemCache();
      
      final state = container.read(adminProvider);
      expect(state.errorMessage, isNull);
      expect(state.systemHealth['Cache Manager'], equals('0 B'));
    });
  });

  group('AdminGuard RBAC Widget Tests', () {
    testWidgets('Unauthenticated user shows loading spinner & schedules redirect', (WidgetTester tester) async {
      final mockRouter = GoRouter(
        initialLocation: '/admin',
        routes: [
          GoRoute(
            path: '/admin',
            builder: (context, state) => const AdminGuard(
              child: Text('Admin View Active'),
            ),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) => const Scaffold(body: Text('Login Page')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => MockAuthNotifier(
                  const AuthState(profile: null),
                )),
          ],
          child: MaterialApp.router(
            routerConfig: mockRouter,
          ),
        ),
      );

      // Initially shows loading indicator because no profile is set
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Admin View Active'), findsNothing);

      // Allow microtask redirects to settle
      await tester.pumpAndSettle();
      expect(find.text('Login Page'), findsOneWidget);
    });

    testWidgets('Non-admin user (e.g. Customer) triggers access denied screen', (WidgetTester tester) async {
      final mockRouter = GoRouter(
        initialLocation: '/admin',
        routes: [
          GoRoute(
            path: '/admin',
            builder: (context, state) => const AdminGuard(
              child: Text('Admin View Active'),
            ),
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) => const Scaffold(body: Text('Home Page')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => MockAuthNotifier(
                  const AuthState(
                    profile: {'role': 'Customer', 'email': 'user@gmail.com'},
                  ),
                )),
          ],
          child: MaterialApp.router(
            routerConfig: mockRouter,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(UnauthorizedScreen), findsOneWidget);
      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.text('Admin View Active'), findsNothing);
    });

    testWidgets('Admin user bypasses guards successfully', (WidgetTester tester) async {
      final mockRouter = GoRouter(
        initialLocation: '/admin',
        routes: [
          GoRoute(
            path: '/admin',
            builder: (context, state) => const AdminGuard(
              child: Text('Admin View Active'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => MockAuthNotifier(
                  const AuthState(
                    profile: {'role': 'Administrator', 'email': 'admin@flowspace.com'},
                  ),
                )),
          ],
          child: MaterialApp.router(
            routerConfig: mockRouter,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(UnauthorizedScreen), findsNothing);
      expect(find.text('Admin View Active'), findsOneWidget);
    });
  });

  group('AdminDashboardScreen Navigation Widget Tests', () {
    testWidgets('Verify sections can be switched on Desktop sidebar layout', (WidgetTester tester) async {
      // Setup desktop dimensions
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      final mockRouter = GoRouter(
        initialLocation: '/admin',
        routes: [
          GoRoute(
            path: '/admin',
            builder: (context, state) => const AdminDashboardScreen(),
          ),
          GoRoute(
            path: '/admin/upload-furniture',
            builder: (context, state) => const Scaffold(body: Text('Upload Screen')),
          ),
        ],
      );

      final stableAdminState = AdminState(
        isLoading: false,
        activeSection: AdminSection.dashboard,
        users: const [
          {
            'name': 'Alice Smith',
            'email': 'alice@flowspace.com',
            'role': 'Administrator',
            'status': 'Active',
          },
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => MockAuthNotifier(
                  const AuthState(
                    profile: {'role': 'Administrator', 'email': 'admin@flowspace.com'},
                  ),
                )),
            adminProvider.overrideWith(() => MockAdminNotifier(stableAdminState)),
          ],
          child: MaterialApp.router(
            routerConfig: mockRouter,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify defaults (Overview cards)
      expect(find.text('Active Users'), findsOneWidget);
      expect(find.text('Projects Created'), findsOneWidget);

      // Click "Users" in Sidebar
      final usersNavItem = find.byKey(const Key('sidebar_item_users'));
      expect(usersNavItem, findsOneWidget);
      await tester.tap(usersNavItem);
      await tester.pumpAndSettle();

      // Verify Users view is now displayed
      expect(find.text('System Users Management'), findsOneWidget);
      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.textContaining('alice@flowspace.com'), findsOneWidget);

      // Clear physical size adjustments
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });
  });
}
