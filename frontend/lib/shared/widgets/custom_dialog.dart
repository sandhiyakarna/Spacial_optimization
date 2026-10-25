import 'package:flutter/material.dart';
import '../../app/constants/app_constants.dart';
import 'primary_button.dart';
import 'secondary_button.dart';

class CustomDialog extends StatelessWidget {
  final String title;
  final String content;
  final String confirmText;
  final String cancelText;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  const CustomDialog({
    super.key,
    required this.title,
    required this.content,
    required this.confirmText,
    required this.cancelText,
    required this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return AlertDialog(
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
      ),
      content: Text(
        content,
        style: const TextStyle(fontSize: 15, height: 1.4),
      ),
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.3 : 0.12),
      elevation: 16,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusDialog),
      ),
      actionsPadding: const EdgeInsets.only(right: 16.0, bottom: 16.0, left: 16.0),
      actions: [
        SecondaryButton(
          text: cancelText,
          onPressed: () {
            Navigator.of(context).pop();
            if (onCancel != null) onCancel!();
          },
        ),
        const SizedBox(width: 8),
        PrimaryButton(
          text: confirmText,
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm();
          },
        ),
      ],
    );
  }
}
