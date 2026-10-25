import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/providers/auth_provider.dart';
import '../unauthorized_screen.dart';

class AdminGuard extends ConsumerWidget {
  final Widget child;

  const AdminGuard({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    if (authState.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final profile = authState.profile;

    if (profile == null) {
      // User is not logged in. Redirect to login.
      Future.microtask(() {
        if (context.mounted) {
          context.go('/login');
        }
      });
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final role = profile['role'];
    final bool isAdmin = role == 'Administrator';

    if (!isAdmin) {
      // Logged in but not an admin. Render unauthorized access screen.
      return const UnauthorizedScreen();
    }

    // Authenticated and Authorized. Render the requested screen.
    return child;
  }
}
