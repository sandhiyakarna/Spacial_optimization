import '../../../app/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/project_provider.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../../../shared/widgets/custom_dialog.dart';
import '../../../shared/widgets/snackbar_manager.dart';

class CreateProjectDialog extends ConsumerStatefulWidget {
  const CreateProjectDialog({super.key});

  @override
  ConsumerState<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends ConsumerState<CreateProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isSaving = false;

  // Selected states matching Screen 6
  String _selectedBuildingType = 'House';
  String _selectedUnit = 'Metric (cm)';

  final List<Map<String, dynamic>> _buildingTypes = const [
    {'name': 'House', 'icon': Icons.home_outlined, 'description': 'Residential single/multi-family home'},
    {'name': 'Apartment', 'icon': Icons.apartment_outlined, 'description': 'Flat or studio apartment layout'},
    {'name': 'Office', 'icon': Icons.work_outline, 'description': 'Productive commercial office space'},
    {'name': 'Other', 'icon': Icons.dashboard_customize_outlined, 'description': 'Custom commercial or retail design'},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      // Map building type to location and units to description to reuse backend without breaking schema
      final success = await ref.read(projectProvider.notifier).createProject(
            projectName: _nameController.text.trim(),
            location: _selectedBuildingType,
            description: 'Unit System: $_selectedUnit',
          );
      setState(() => _isSaving = false);

      if (mounted) {
        if (success) {
          SnackbarManager.showSuccess(context, 'Project created successfully.');
          Navigator.of(context).pop(true);
        } else {
          final error = ref.read(projectProvider).errorMessage ?? 'Failed to create project';
          SnackbarManager.showError(context, error);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 8,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Create New Project',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Project Name Input
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Project Name *',
                    hintText: 'e.g., My Sweet Home',
                    prefixIcon: const Icon(Icons.drive_file_rename_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Project name is required';
                    }
                    if (value.length > 120) {
                      return 'Name cannot exceed 120 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Building Type Title
                Text(
                  'Building Type',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),

                // Building Type Selection Grid
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.45,
                  ),
                  itemCount: _buildingTypes.length,
                  itemBuilder: (context, index) {
                    final type = _buildingTypes[index];
                    final isSelected = _selectedBuildingType == type['name'];
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedBuildingType = type['name'];
                        });
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primary.withValues(alpha: 0.1)
                              : (isDark ? Colors.white54.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02)),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? AppTheme.primary : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              type['icon'],
                              color: isSelected ? AppTheme.primary : (isDark ? Colors.white70 : Colors.black54),
                              size: 28,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              type['name'],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isSelected ? AppTheme.primary : (isDark ? Colors.white : Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Units Title
                Text(
                  'Units',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),

                // Units Row Selection
                Row(
                  children: [
                    // Metric Card
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _selectedUnit = 'Metric (cm)'),
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedUnit == 'Metric (cm)'
                                ? AppTheme.primary.withValues(alpha: 0.1)
                                : (isDark ? Colors.white54.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02)),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _selectedUnit == 'Metric (cm)' ? AppTheme.primary : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.straighten, size: 18, color: _selectedUnit == 'Metric (cm)' ? AppTheme.primary : Colors.grey),
                              const SizedBox(width: 8),
                              Text(
                                'Metric (cm)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _selectedUnit == 'Metric (cm)' ? AppTheme.primary : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Imperial Card
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _selectedUnit = 'Imperial (ft)'),
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedUnit == 'Imperial (ft)'
                                ? AppTheme.primary.withValues(alpha: 0.1)
                                : (isDark ? Colors.white54.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02)),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _selectedUnit == 'Imperial (ft)' ? AppTheme.primary : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.av_timer, size: 18, color: _selectedUnit == 'Imperial (ft)' ? AppTheme.primary : Colors.grey),
                              const SizedBox(width: 8),
                              Text(
                                'Imperial (ft)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _selectedUnit == 'Imperial (ft)' ? AppTheme.primary : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Next Button
                ElevatedButton(
                  onPressed: _isSaving ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Next',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EditProjectDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> project;

  const EditProjectDialog({super.key, required this.project});

  @override
  ConsumerState<EditProjectDialog> createState() => _EditProjectDialogState();
}

class _EditProjectDialogState extends ConsumerState<EditProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _locController = TextEditingController();
  String? _status;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.project['project_name'] ?? '';
    _descController.text = widget.project['description'] ?? '';
    _locController.text = widget.project['location'] ?? '';
    _status = widget.project['status'];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _locController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      final success = await ref.read(projectProvider.notifier).updateProject(
            widget.project['id'],
            projectName: _nameController.text.trim(),
            description: _descController.text.trim(),
            location: _locController.text.trim(),
            status: _status,
          );
      setState(() => _isSaving = false);

      if (mounted) {
        if (success) {
          SnackbarManager.showSuccess(context, 'Project updated successfully.');
          Navigator.of(context).pop(true);
        } else {
          final error = ref.read(projectProvider).errorMessage ?? 'Failed to update project';
          SnackbarManager.showError(context, error);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Project Details'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Project Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Project name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locController,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Draft', child: Text('Draft')),
                  DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                  DropdownMenuItem(value: 'Archived', child: Text('Archived')),
                ],
                onChanged: (val) => setState(() => _status = val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        SecondaryButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(width: 8),
        PrimaryButton(
          text: 'Save',
          isLoading: _isSaving,
          onPressed: _handleSave,
        ),
      ],
    );
  }
}

class DeleteProjectDialog extends ConsumerWidget {
  final Map<String, dynamic> project;

  const DeleteProjectDialog({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomDialog(
      title: 'Delete Project',
      content: 'Are you sure you want to delete "${project['project_name']}"? This action can be undone by restoring it from the archives.',
      confirmText: 'Delete',
      cancelText: 'Cancel',
      onConfirm: () async {
        final success = await ref.read(projectProvider.notifier).deleteProject(project['id']);
        if (context.mounted) {
          if (success) {
            SnackbarManager.showSuccess(context, 'Project deleted successfully.');
          } else {
            final error = ref.read(projectProvider).errorMessage ?? 'Failed to delete project';
            SnackbarManager.showError(context, error);
          }
        }
      },
    );
  }
}
