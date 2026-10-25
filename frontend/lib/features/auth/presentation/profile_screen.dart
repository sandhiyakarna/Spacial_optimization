import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../../../shared/widgets/custom_card.dart';
import '../../../shared/widgets/custom_dialog.dart';
import '../../../shared/widgets/snackbar_manager.dart';
import '../../../app/constants/app_constants.dart';
import '../../../app/themes/app_theme.dart';
import '../../../core/validation/validators.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final profile = ref.read(authProvider).profile;
    if (profile != null) {
      _nameController.text = profile['full_name'] ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleUpdateProfile() async {
    final nameError = validateFullName(_nameController.text);
    if (nameError != null) {
      SnackbarManager.showError(context, nameError);
      return;
    }

    final success = await ref.read(authProvider.notifier).updateProfile(
          fullName: _nameController.text.trim(),
        );

    if (mounted) {
      if (success) {
        SnackbarManager.showSuccess(context, 'Profile updated successfully.');
      } else {
        final error = ref.read(authProvider).errorMessage ?? 'Failed to update';
        SnackbarManager.showError(context, error);
      }
    }
  }

  Future<void> _handleChangePassword() async {
    if (_formKey.currentState!.validate()) {
      final success = await ref.read(authProvider.notifier).changePassword(
            currentPassword: _currentPasswordController.text,
            newPassword: _newPasswordController.text,
          );

      if (mounted) {
        if (success) {
          _currentPasswordController.clear();
          _newPasswordController.clear();
          SnackbarManager.showSuccess(context, 'Password updated successfully.');
        } else {
          final error = ref.read(authProvider).errorMessage ?? 'Failed to change password';
          SnackbarManager.showError(context, error);
        }
      }
    }
  }

  void _handleLogout() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final authState = ref.watch(authProvider);
          return AlertDialog(
            title: const Text('Logout'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Select your logout preference below:'),
                if (authState.isLoading) ...[
                  const SizedBox(height: AppConstants.space16),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusDialog),
            ),
            actionsPadding: const EdgeInsets.all(AppConstants.space16),
            actionsOverflowButtonSpacing: 8,
            actions: [
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      text: 'Cancel',
                      onPressed: authState.isLoading ? null : () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                        foregroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppConstants.radiusButton),
                        ),
                      ),
                      onPressed: authState.isLoading ? null : () async {
                        final navigator = GoRouter.of(context);
                        await ref.read(authProvider.notifier).logout();
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          navigator.go('/login');
                          SnackbarManager.showSuccess(context, 'Logged out from current device.');
                        }
                      },
                      child: const Text('Logout Current Device', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppConstants.radiusButton),
                        ),
                      ),
                      onPressed: authState.isLoading ? null : () async {
                        final navigator = GoRouter.of(context);
                        final success = await ref.read(authProvider.notifier).logoutAllDevices();
                        if (success) {
                          if (context.mounted) {
                            Navigator.of(context).pop();
                            navigator.go('/login');
                            SnackbarManager.showSuccess(context, 'Logged out from all devices.');
                          }
                        } else {
                          if (context.mounted) {
                            final error = ref.read(authProvider).errorMessage ?? 'Failed to logout';
                            SnackbarManager.showError(context, error);
                          }
                        }
                      },
                      child: const Text('Logout All Devices', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _showVerificationDialog() async {
    final tokenController = TextEditingController();
    final token = await ref.read(authProvider.notifier).requestVerification();
    
    if (!mounted) return;
    
    if (token != null) {
      SnackbarManager.showSuccess(context, 'Verification token generated: ${token.substring(0, 8)}...');
      tokenController.text = token;
    } else {
      final error = ref.read(authProvider).errorMessage ?? 'Failed to request verification token';
      SnackbarManager.showError(context, error);
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final authState = ref.watch(authProvider);
          return AlertDialog(
            title: const Text('Verify Email'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'A verification token has been generated. Enter the token below to verify your email address:',
                  style: TextStyle(fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: AppConstants.space16),
                TextField(
                  controller: tokenController,
                  decoration: const InputDecoration(
                    labelText: 'Verification Token',
                    hintText: 'Enter JWT verification token',
                  ),
                ),
                if (authState.isLoading) ...[
                  const SizedBox(height: AppConstants.space16),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusDialog),
            ),
            actions: [
              SecondaryButton(
                text: 'Cancel',
                onPressed: authState.isLoading ? null : () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusButton),
                  ),
                ),
                onPressed: authState.isLoading ? null : () async {
                  final tok = tokenController.text.trim();
                  if (tok.isEmpty) {
                    SnackbarManager.showError(context, 'Verification token is required');
                    return;
                  }
                  final success = await ref.read(authProvider.notifier).verifyEmail(token: tok);
                  if (success) {
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      SnackbarManager.showSuccess(context, 'Email verified successfully!');
                    }
                  } else {
                    if (context.mounted) {
                      final error = ref.read(authProvider).errorMessage ?? 'Verification failed';
                      SnackbarManager.showError(context, error);
                    }
                  }
                },
                child: const Text('Verify', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _handleDeleteAccount() {
    final passwordConfirmController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final authState = ref.watch(authProvider);
          return AlertDialog(
            title: const Text('Delete Account'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'WARNING: This action is permanent and will soft-delete your account and deactivate active sessions.',
                  style: TextStyle(color: Colors.red, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: AppConstants.space16),
                TextField(
                  controller: passwordConfirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Enter Password to Confirm',
                  ),
                ),
                if (authState.isLoading) ...[
                  const SizedBox(height: AppConstants.space16),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusDialog),
            ),
            actions: [
              SecondaryButton(
                text: 'Cancel',
                onPressed: authState.isLoading ? null : () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusButton),
                  ),
                ),
                onPressed: authState.isLoading ? null : () async {
                  final pwd = passwordConfirmController.text;
                  if (pwd.isEmpty) {
                    SnackbarManager.showError(context, 'Password is required');
                    return;
                  }
                  final navigator = GoRouter.of(context);
                  final success = await ref.read(authProvider.notifier).deleteAccount(password: pwd);
                  if (success) {
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      SnackbarManager.showSuccess(context, 'Account deleted successfully.');
                      navigator.go('/login');
                    }
                  } else {
                    if (context.mounted) {
                      final error = ref.read(authProvider).errorMessage ?? 'Failed to delete account';
                      SnackbarManager.showError(context, error);
                    }
                  }
                },
                child: const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final profile = authState.profile;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (profile == null) {
      return const Scaffold(
        body: Center(
          child: Text('Not authenticated. Please login.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!(profile['is_verified'] ?? false)) ...[
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                    width: 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Email Verification Required',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.orange[200] : Colors.orange[800],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Verify your email to secure your account and enable full access.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.space16),
                    PrimaryButton(
                      text: 'Verify Email Now',
                      onPressed: _showVerificationDialog,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.space16),
            ],
            // User Header
            CustomCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                    child: const Icon(Icons.person_rounded, size: 40, color: AppTheme.primary),
                  ),
                  const SizedBox(width: AppConstants.space16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile['full_name'] ?? 'User Profile',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profile['email'] ?? '',
                          style: TextStyle(
                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: AppConstants.space8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                (profile['role'] ?? 'Customer').toString().toUpperCase(),
                                style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (profile['is_verified'] ?? false)
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    (profile['is_verified'] ?? false)
                                        ? Icons.verified_user_rounded
                                        : Icons.warning_amber_rounded,
                                    size: 12,
                                    color: (profile['is_verified'] ?? false)
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    (profile['is_verified'] ?? false) ? 'VERIFIED' : 'UNVERIFIED',
                                    style: TextStyle(
                                      color: (profile['is_verified'] ?? false)
                                          ? Colors.green
                                          : Colors.orange,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.space16),

            // Profile Edit Form
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Edit Profile Details',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppConstants.space16),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                    ),
                  ),
                  const SizedBox(height: AppConstants.space16),
                  PrimaryButton(
                    text: 'Save Details',
                    isLoading: authState.isLoading,
                    onPressed: _handleUpdateProfile,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.space16),

            // Change Password Form
            CustomCard(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Change Account Password',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppConstants.space16),
                    TextFormField(
                      controller: _currentPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Current Password',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Current password is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppConstants.space16),
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                      ),
                      validator: validatePassword,
                    ),
                    const SizedBox(height: AppConstants.space16),
                    PrimaryButton(
                      text: 'Change Password',
                      isLoading: authState.isLoading,
                      onPressed: _handleChangePassword,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppConstants.space24),

            // Actions (Logout & Delete)
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    text: 'Logout',
                    onPressed: _handleLogout,
                  ),
                ),
                const SizedBox(width: AppConstants.space16),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _handleDeleteAccount,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: AppTheme.error,
                      side: const BorderSide(color: AppTheme.error, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusButton),
                      ),
                    ),
                    child: const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
