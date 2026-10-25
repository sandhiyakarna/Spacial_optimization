import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/storage/token_storage.dart';
import 'screens/splash_screen.dart';
import 'screens/navigation_shell.dart';
import 'screens/notifications_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/auth/presentation/profile_screen.dart';
import '../features/auth/presentation/onboarding_screen.dart';
import '../features/project/presentation/dashboard_screen.dart';
import '../features/project/presentation/project_list_screen.dart';
import '../features/room/presentation/room_list_screen.dart';
import '../features/room/presentation/room_details_screen.dart';
import '../features/designer/presentation/designer_screen.dart';
import '../features/furniture/presentation/furniture_library_screen.dart';
import '../features/furniture/presentation/admin_furniture_upload_screen.dart';
import '../features/furniture/models/furniture_asset.dart';
import '../features/analytics/presentation/analytics_screen.dart';
import '../features/project/presentation/reports_screen.dart';
import '../features/project/presentation/project_workspace_screen.dart';
import '../features/admin/presentation/widgets/admin_guard.dart';
import '../features/admin/presentation/admin_dashboard_screen.dart';
import '../features/designer/presentation/admin_material_upload_screen.dart';
import '../features/designer/models/material_model.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  navigatorKey: _rootNavigatorKey,
  redirect: (BuildContext context, GoRouterState state) async {
    final token = await TokenStorage().getAccessToken();
    final loggedIn = token != null;
    final hasSeenOnboarding = await TokenStorage().getHasSeenOnboarding();
    
    final isAuthRoute = state.uri.path == '/login' ||
        state.uri.path == '/register' ||
        state.uri.path == '/forgot-password' ||
        state.uri.path == '/reset-password';
    
    final isSplash = state.uri.path == '/splash';
    final isOnboarding = state.uri.path == '/onboarding';

    if (!hasSeenOnboarding) {
      if (!isOnboarding && !isSplash) {
        return '/onboarding';
      }
      return null;
    }

    if (!loggedIn) {
      if (!isAuthRoute && !isSplash && !isOnboarding) {
        return '/login';
      }
    } else {
      if (isAuthRoute || isSplash || isOnboarding) {
        return '/home';
      }
    }
    return null;
  },
  routes: [
    // Splash Route (outside shell)
    GoRoute(
      path: '/splash',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) => const SplashScreen(),
    ),

    // Onboarding Route (outside shell)
    GoRoute(
      path: '/onboarding',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) => const OnboardingScreen(),
    ),
    
    // Auth Routes (outside shell)
    GoRoute(
      path: '/login',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/forgot-password',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/reset-password',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final emailHint = state.extra as String?;
        return ResetPasswordScreen(emailHint: emailHint);
      },
    ),

    // standalone project routes (outside shell to prevent mixing global and project navigations)
    GoRoute(
      path: '/projects/:projectId/rooms',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final projectId = state.pathParameters['projectId']!;
        return RoomListScreen(projectId: projectId);
      },
    ),
    GoRoute(
      path: '/projects/:projectId/workspace',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final projectId = state.pathParameters['projectId']!;
        return ProjectWorkspaceScreen(projectId: projectId);
      },
    ),
    GoRoute(
      path: '/rooms/:roomId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final roomId = state.pathParameters['roomId']!;
        return RoomDetailsScreen(roomId: roomId);
      },
    ),
    GoRoute(
      path: '/designer/:roomId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final roomId = state.pathParameters['roomId']!;
        return DesignerScreen(roomId: roomId);
      },
    ),
    GoRoute(
      path: '/furniture-library',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) => const FurnitureLibraryScreen(),
    ),
    GoRoute(
      path: '/admin',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) => const AdminGuard(
        child: AdminDashboardScreen(),
      ),
    ),
    GoRoute(
      path: '/admin/upload-furniture',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final existingAsset = state.extra as FurnitureAsset?;
        return AdminGuard(
          child: AdminFurnitureUploadScreen(existingAsset: existingAsset),
        );
      },
    ),
    GoRoute(
      path: '/admin/upload-material',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final existingMaterial = state.extra as MaterialModel?;
        return AdminGuard(
          child: AdminMaterialUploadScreen(existingMaterial: existingMaterial),
        );
      },
    ),
    GoRoute(
      path: '/reports',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) => const ReportsScreen(),
    ),

    // Shell Route wrapping application main views
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (BuildContext context, GoRouterState state, Widget child) {
        return NavigationShell(child: child);
      },
      routes: [
        GoRoute(
          path: '/home',
          parentNavigatorKey: _shellNavigatorKey,
          builder: (BuildContext context, GoRouterState state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/projects',
          parentNavigatorKey: _shellNavigatorKey,
          builder: (BuildContext context, GoRouterState state) => const ProjectListScreen(),
        ),
        GoRoute(
          path: '/insights',
          parentNavigatorKey: _shellNavigatorKey,
          builder: (BuildContext context, GoRouterState state) => const AnalyticsScreen(),
        ),
        GoRoute(
          path: '/notifications',
          parentNavigatorKey: _shellNavigatorKey,
          builder: (BuildContext context, GoRouterState state) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/profile',
          parentNavigatorKey: _shellNavigatorKey,
          builder: (BuildContext context, GoRouterState state) => const ProfileScreen(),
        ),
      ],
    ),
  ],
);
