import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../../../shared/widgets/custom_card.dart';
import '../../../shared/widgets/snackbar_manager.dart';
import '../../../app/constants/app_constants.dart';
import '../../../core/validation/validators.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String? emailHint;

  const ResetPasswordScreen({
    super.key,
    this.emailHint,
  });

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.emailHint != null) {
      _tokenController.text = widget.emailHint!;
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (_formKey.currentState!.validate()) {
      final success = await ref.read(authProvider.notifier).resetPassword(
            token: _tokenController.text.trim(),
            newPassword: _passwordController.text,
          );

      if (mounted) {
        if (success) {
          SnackbarManager.showSuccess(context, 'Password reset successful. Please login.');
          context.go('/login');
        } else {
          final error = ref.read(authProvider).errorMessage ?? 'Reset failed';
          SnackbarManager.showError(context, error);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Reset Password'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        shape: const Border(),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/login');
            }
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.space24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CustomCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Enter New Password',
                          style: theme.textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppConstants.space24),
                        TextFormField(
                          controller: _tokenController,
                          decoration: const InputDecoration(
                            labelText: 'Reset Token or Email',
                            prefixIcon: Icon(Icons.vpn_key_outlined),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Reset token is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppConstants.space16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'New Password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: validatePassword,
                        ),
                        const SizedBox(height: AppConstants.space24),
                        PrimaryButton(
                          text: 'Reset Password',
                          isLoading: authState.isLoading,
                          onPressed: _handleResetPassword,
                        ),
                        const SizedBox(height: AppConstants.space16),
                        SecondaryButton(
                          text: 'Back to Login',
                          onPressed: () => context.go('/login'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
