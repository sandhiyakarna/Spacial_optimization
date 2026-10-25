import '../../../app/themes/app_theme.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';

class MeasurementsStep extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onSave;
  final bool isMetric;
  final ValueChanged<bool> onUnitToggle;
  final TextEditingController lengthController;
  final TextEditingController widthController;
  final TextEditingController heightController;
  final TextEditingController doorsController;
  final TextEditingController windowsController;

  const MeasurementsStep({
    super.key,
    required this.onBack,
    required this.onSave,
    required this.isMetric,
    required this.onUnitToggle,
    required this.lengthController,
    required this.widthController,
    required this.heightController,
    required this.doorsController,
    required this.windowsController,
  });

  @override
  State<MeasurementsStep> createState() => _MeasurementsStepState();
}

class _MeasurementsStepState extends State<MeasurementsStep> {
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 750),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Room Measurements',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter the dimensions of the room and count of doors/windows.',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 24),
                // Unit toggle
                Row(
                  children: [
                    const Text('Units:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('Metric'),
                      selected: widget.isMetric,
                      onSelected: (selected) => widget.onUnitToggle(true),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Imperial'),
                      selected: !widget.isMetric,
                      onSelected: (selected) => widget.onUnitToggle(false),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Length, Width, Height
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: widget.lengthController,
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Length',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Required';
                          final d = double.tryParse(value);
                          if (d == null || d <= 0) return 'Enter positive number';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: widget.widthController,
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Width',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Required';
                          final d = double.tryParse(value);
                          if (d == null || d <= 0) return 'Enter positive number';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: widget.heightController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Height',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Required';
                    final d = double.tryParse(value);
                    if (d == null || d <= 0) return 'Enter positive number';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                // Doors and Windows
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: widget.doorsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Doors',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Required';
                          final i = int.tryParse(value);
                          if (i == null || i < 0) return 'Enter non‑negative integer';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: widget.windowsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Windows',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Required';
                          final i = int.tryParse(value);
                          if (i == null || i < 0) return 'Enter non‑negative integer';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SecondaryButton(
                      text: 'Back',
                      onPressed: widget.onBack,
                    ),
                    PrimaryButton(
                      text: 'Save & Finish',
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          widget.onSave();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
