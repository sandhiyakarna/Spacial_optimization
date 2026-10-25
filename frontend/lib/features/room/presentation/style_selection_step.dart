import '../../../app/themes/app_theme.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';

class StyleSelectionStep extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onSave;
  final String? selectedStyle;
  final ValueChanged<String> onStyleSelected;

  const StyleSelectionStep({
    super.key,
    required this.onBack,
    required this.onSave,
    required this.selectedStyle,
    required this.onStyleSelected,
  });

  @override
  State<StyleSelectionStep> createState() => _StyleSelectionStepState();
}

class _StyleSelectionStepState extends State<StyleSelectionStep> {
  final List<String> _styles = [
    'Modern',
    'Minimalist',
    'Scandinavian',
    'Luxury',
    'Industrial',
    'Contemporary',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Interior Style',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 3,
          ),
          itemCount: _styles.length,
          itemBuilder: (context, index) {
            final style = _styles[index];
            final isSelected = widget.selectedStyle == style;
            return InkWell(
              onTap: () => widget.onStyleSelected(style),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary.shade50.withValues(alpha: 0.4) : Colors.white,
                  border: Border.all(
                    color: isSelected ? AppTheme.primary : Colors.grey.shade300,
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  style,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? AppTheme.primary.shade900 : Colors.black87,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SecondaryButton(
              text: 'Back',
              onPressed: widget.onBack,
            ),
            PrimaryButton(
              text: 'Save & Continue',
              onPressed: widget.onSave,
            ),
          ],
        ),
      ],
    );
  }
}
