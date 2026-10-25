import '../../../app/themes/app_theme.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/room_provider.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../../../shared/widgets/custom_dialog.dart';
import '../../../shared/widgets/snackbar_manager.dart';
import 'panorama_capture_step.dart';
import 'measurements_step.dart';
import 'style_selection_step.dart';
import 'ai_planning_step.dart';
import 'review_step.dart';

class CreateRoomDialog extends ConsumerStatefulWidget {
  final String projectId;

  const CreateRoomDialog({super.key, required this.projectId});

  @override
  ConsumerState<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends ConsumerState<CreateRoomDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  // Wizard state
  int _currentStep = 1;
  String? _roomId;
  String? _panoramaUrl;
  bool _panoramaSkipped = false;

  // Step 4: Style State
  String? _selectedStyle;

  // Step 5: AI Planning State
  // (AIPlanningStep manages its own internal state)
  String? _aiSummary; // surfaced to Step 6 review

  // Step 1: Details State
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _colorController = TextEditingController(text: '#14B8A6');
  String _roomType = 'Living Room';
  String _customType = '';
  int _floorNumber = 1;

  // Step 3: Measurements State
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  final _doorsController = TextEditingController();
  final _windowsController = TextEditingController();
  bool _isMetric = true;

  final List<Map<String, dynamic>> _presetColors = const [
    {'name': 'Teal', 'hex': '#14B8A6', 'color': Color(0xFF14B8A6)},
    {'name': 'Indigo', 'hex': '#6366F1', 'color': Color(0xFF6366F1)},
    {'name': 'Emerald', 'hex': '#10B981', 'color': Color(0xFF10B981)},
    {'name': 'Amber', 'hex': '#F59E0B', 'color': Color(0xFFF59E0B)},
    {'name': 'Rose', 'hex': '#F43F5E', 'color': Color(0xFFF43F5E)},
    {'name': 'Sky', 'hex': '#0EA5E9', 'color': Color(0xFF0EA5E9)},
    {'name': 'Purple', 'hex': '#A855F7', 'color': Color(0xFFA855F7)},
    {'name': 'Slate', 'hex': '#64748B', 'color': Color(0xFF64748B)},
  ];

  final List<Map<String, dynamic>> _roomTypes = const [
    {'name': 'Living Room', 'icon': Icons.weekend_outlined, 'desc': 'Family gatherings, lounging, and entertainment'},
    {'name': 'Bedroom', 'icon': Icons.bed_outlined, 'desc': 'Rest, sleep, and personal space'},
    {'name': 'Kitchen', 'icon': Icons.kitchen_outlined, 'desc': 'Cooking, food prep, and storage'},
    {'name': 'Dining Room', 'icon': Icons.restaurant_outlined, 'desc': 'Meals and dining setup'},
    {'name': 'Office', 'icon': Icons.work_outline, 'desc': 'Work, study, and productivity space'},
    {'name': 'Bathroom', 'icon': Icons.bathtub_outlined, 'desc': 'Hygiene and relaxation'},
    {'name': 'Custom', 'icon': Icons.dashboard_customize_outlined, 'desc': 'Any other unique room configuration'},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _colorController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _doorsController.dispose();
    _windowsController.dispose();
    super.dispose();
  }

  String _getMergedPropertiesJson(Map<String, dynamic> newUpdates) {
    final Map<String, dynamic> merged = {};
    final details = ref.read(roomDetailsProvider).details;
    if (details != null && details['properties'] != null) {
      try {
        final String propsText = details['properties'];
        if (propsText.isNotEmpty) {
          merged.addAll(jsonDecode(propsText));
        }
      } catch (_) {}
    }
    merged.addAll(newUpdates);
    return jsonEncode(merged);
  }

  Future<void> _saveRoom({required bool isDraft}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final propertiesJson = _getMergedPropertiesJson({
        'is_draft': isDraft,
        'wizard_step': 1,
      });
      final finalRoomType = _roomType == 'Custom' ? _customType.trim() : _roomType;

      if (_roomId == null) {
        final roomId = await ref.read(roomListProvider.notifier).createRoom(
              widget.projectId,
              roomName: _nameController.text.trim(),
              roomType: finalRoomType,
              floorNumber: _floorNumber,
              notes: _notesController.text.trim(),
              roomColor: _colorController.text.trim(),
              properties: propertiesJson,
            );

        if (roomId == null) {
          final error = ref.read(roomListProvider).errorMessage ?? 'Failed to add room';
          throw Exception(error);
        }

        if (mounted) {
          setState(() => _isSaving = false);
          if (isDraft) {
            SnackbarManager.showSuccess(context, 'Draft room saved successfully.');
            Navigator.of(context).pop(true);
          } else {
            _roomId = roomId;
            _currentStep = 2;
            setState(() {});
            SnackbarManager.showSuccess(context, 'Room details saved. (Step 1 Completed)');
          }
        }
      } else {
        final success = await ref.read(roomDetailsProvider.notifier).updateRoom(
              _roomId!,
              roomName: _nameController.text.trim(),
              roomType: finalRoomType,
              floorNumber: _floorNumber,
              notes: _notesController.text.trim(),
              roomColor: _colorController.text.trim(),
              properties: propertiesJson,
            );

        if (!success) {
          final error = ref.read(roomDetailsProvider).errorMessage ?? 'Failed to update room details';
          throw Exception(error);
        }

        if (mounted) {
          setState(() => _isSaving = false);
          if (isDraft) {
            SnackbarManager.showSuccess(context, 'Draft room updated successfully.');
            Navigator.of(context).pop(true);
          } else {
            _currentStep = 2;
            setState(() {});
            SnackbarManager.showSuccess(context, 'Room details updated.');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        SnackbarManager.showError(context, e.toString());
      }
    }
  }

  Future<void> _savePanorama({required bool isSkipped, String? url}) async {
    if (_roomId == null) return;

    setState(() => _isSaving = true);
    try {
      final propertiesJson = _getMergedPropertiesJson({
        'is_draft': false,
        'wizard_step': 2,
        'panorama_url': url,
        'panorama_file': url,
        'panorama_skipped': isSkipped,
      });
      final finalRoomType = _roomType == 'Custom' ? _customType.trim() : _roomType;

      final success = await ref.read(roomDetailsProvider.notifier).updateRoom(
            _roomId!,
            roomName: _nameController.text.trim(),
            roomType: finalRoomType,
            floorNumber: _floorNumber,
            notes: _notesController.text.trim(),
            roomColor: _colorController.text.trim(),
            properties: propertiesJson,
          );

      if (!success) {
        final error = ref.read(roomDetailsProvider).errorMessage ?? 'Failed to save panorama details';
        throw Exception(error);
      }

      if (mounted) {
        setState(() => _isSaving = false);
        SnackbarManager.showSuccess(
          context,
          isSkipped
              ? 'Panorama saved (skipped). Proceed to measurements.'
              : 'Panorama saved successfully. Proceed to measurements.'
        );
        setState(() {
          _currentStep = 3;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        SnackbarManager.showError(context, e.toString());
      }
    }
  }

  Future<void> _saveMeasurements() async {
    if (_roomId == null) return;
    setState(() => _isSaving = true);
    try {
      double rawL = double.tryParse(_lengthController.text.trim()) ?? 0.0;
      double rawW = double.tryParse(_widthController.text.trim()) ?? 0.0;
      double rawH = double.tryParse(_heightController.text.trim()) ?? 0.0;

      if (rawL <= 0) rawL = _isMetric ? 6.0 : 19.685;
      if (rawW <= 0) rawW = _isMetric ? 4.5 : 14.764;
      if (rawH <= 0) rawH = _isMetric ? 3.0 : 9.843;

      final double factor = _isMetric ? 100.0 : 30.48;
      final double l = rawL * factor;
      final double w = rawW * factor;
      final double h = rawH * factor;

      // 1. Update measurements DB table
      final measureSuccess = await ref.read(roomDetailsProvider.notifier).updateMeasurements(
            _roomId!,
            length: l,
            width: w,
            height: h,
          );

      if (!measureSuccess) {
        throw Exception(ref.read(roomDetailsProvider).errorMessage ?? 'Failed to save room measurements to DB');
      }

      // 2. Update room properties with merge
      final propertiesJson = _getMergedPropertiesJson({
        'is_draft': false,
        'wizard_step': 3,
        'length': _lengthController.text,
        'width': _widthController.text,
        'height': _heightController.text,
        'doors': _doorsController.text,
        'windows': _windowsController.text,
        'is_metric': _isMetric,
      });
      final finalRoomType = _roomType == 'Custom' ? _customType.trim() : _roomType;

      final success = await ref.read(roomDetailsProvider.notifier).updateRoom(
            _roomId!,
            roomName: _nameController.text.trim(),
            roomType: finalRoomType,
            floorNumber: _floorNumber,
            notes: _notesController.text.trim(),
            roomColor: _colorController.text.trim(),
            properties: propertiesJson,
          );

      if (!success) throw Exception(ref.read(roomDetailsProvider).errorMessage ?? 'Failed to save measurements properties');

      if (mounted) {
        setState(() => _isSaving = false);
        SnackbarManager.showSuccess(context, 'Measurements saved. (Step 3 Completed)');
        setState(() => _currentStep = 4);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        SnackbarManager.showError(context, e.toString());
      }
    }
  }

  Future<void> _saveStyle() async {
    if (_selectedStyle == null) {
      SnackbarManager.showError(context, 'Please select an interior style.');
      return;
    }
    if (_roomId == null) return;
    setState(() => _isSaving = true);
    try {
      final propertiesJson = _getMergedPropertiesJson({
        'is_draft': false,
        'wizard_step': 4,
        'selected_style': _selectedStyle,
      });
      final finalRoomType = _roomType == 'Custom' ? _customType.trim() : _roomType;

      final success = await ref.read(roomDetailsProvider.notifier).updateRoom(
            _roomId!,
            roomName: _nameController.text.trim(),
            roomType: finalRoomType,
            floorNumber: _floorNumber,
            notes: _notesController.text.trim(),
            roomColor: _colorController.text.trim(),
            properties: propertiesJson,
          );

      if (!success) throw Exception(ref.read(roomDetailsProvider).errorMessage ?? 'Failed to save style');

      if (mounted) {
        setState(() {
          _isSaving = false;
          _currentStep = 5;
        });
        SnackbarManager.showSuccess(context, 'Style saved. (Step 4 Completed)');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        SnackbarManager.showError(context, e.toString());
      }
    }
  }

  Future<void> _finishAIStep({String? aiSummary}) async {
    if (_roomId == null) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(roomDetailsProvider.notifier).fetchDetails(_roomId!);

      final propertiesJson = _getMergedPropertiesJson({
        'is_draft': false,
        'wizard_step': 5,
        'selected_style': _selectedStyle,
      });
      final finalRoomType = _roomType == 'Custom' ? _customType.trim() : _roomType;

      final success = await ref.read(roomDetailsProvider.notifier).updateRoom(
            _roomId!,
            roomName: _nameController.text.trim(),
            roomType: finalRoomType,
            floorNumber: _floorNumber,
            notes: _notesController.text.trim(),
            roomColor: _colorController.text.trim(),
            properties: propertiesJson,
          );

      if (!success) throw Exception(ref.read(roomDetailsProvider).errorMessage ?? 'Failed to advance wizard');

      if (mounted) {
        setState(() {
          _isSaving = false;
          _aiSummary = aiSummary;
          _currentStep = 6;
        });
        SnackbarManager.showSuccess(context, 'AI Planning complete. (Step 5 Completed)');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        SnackbarManager.showError(context, e.toString());
      }
    }
  }

  Future<void> _createRoom() async {
    if (_roomId == null) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(roomDetailsProvider.notifier).fetchDetails(_roomId!);

      final propertiesJson = _getMergedPropertiesJson({
        'is_draft': false,
        'wizard_step': 6,
        'wizard_complete': true,
        'selected_style': _selectedStyle,
        'panorama_url': _panoramaUrl,
        'panorama_file': _panoramaUrl,
        'panorama_skipped': _panoramaSkipped,
      });
      final finalRoomType = _roomType == 'Custom' ? _customType.trim() : _roomType;

      final success = await ref.read(roomDetailsProvider.notifier).updateRoom(
            _roomId!,
            roomName: _nameController.text.trim(),
            roomType: finalRoomType,
            floorNumber: _floorNumber,
            notes: _notesController.text.trim(),
            roomColor: _colorController.text.trim(),
            properties: propertiesJson,
          );

      if (!success) throw Exception(ref.read(roomDetailsProvider).errorMessage ?? 'Failed to create room');

      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.of(context).pop(true);
        context.go('/designer/${_roomId!}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        SnackbarManager.showError(context, e.toString());
      }
    }
  }


  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.primary.shade50.withValues(alpha: 0.4),
        border: Border(
          bottom: BorderSide(color: AppTheme.primary.shade100, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _currentStep == 1
                    ? 'Room Details'
                    : _currentStep == 2
                        ? 'Spatial Room Capture'
                        : _currentStep == 3
                            ? 'Measurements'
                            : _currentStep == 4
                                ? 'Interior Style'
                                : _currentStep == 5
                                    ? 'AI Planning'
                                    : 'Review & Create',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: AppTheme.primary,
                ),
              ),
              Text(
                'Step $_currentStep of 6',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.primary.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _currentStep / 6,
              minHeight: 8,
              backgroundColor: const Color(0xFFE0F2F1),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStepIndicatorText('1. Details', isActive: _currentStep == 1),
                _buildStepSeparator(),
                _buildStepIndicatorText('2. Capture', isActive: _currentStep == 2),
                _buildStepSeparator(),
                _buildStepIndicatorText('3. Dimensions', isActive: _currentStep == 3),
                _buildStepSeparator(),
                _buildStepIndicatorText('4. Style', isActive: _currentStep == 4),
                _buildStepSeparator(),
                _buildStepIndicatorText('5. AI Plan', isActive: _currentStep == 5),
                _buildStepSeparator(),
                _buildStepIndicatorText('6. Review', isActive: _currentStep == 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepSeparator() {
    return Container(
      width: 16,
      height: 1.5,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.grey.shade300,
    );
  }

  Widget _buildStepIndicatorText(String text, {required bool isActive}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? AppTheme.primary : Colors.grey.shade200,
          ),
          child: Text(
            text.split('.').first,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.white : Colors.grey.shade600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text.split(' ').last,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? AppTheme.primary.shade800 : Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Widget _buildFloorSelector() {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primary.shade50.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.layers_outlined, color: AppTheme.primary, size: 28),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Floor Level',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'The level where this room is located',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: AppTheme.primary, size: 28),
                  onPressed: _floorNumber > 0
                      ? () => setState(() => _floorNumber--)
                      : null,
                ),
                Container(
                  width: 50,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _floorNumber.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primary),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary, size: 28),
                  onPressed: () => setState(() => _floorNumber++),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorSelector() {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.shade50.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.palette_outlined, color: AppTheme.primary, size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Accent Color Theme',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Visual identity and highlight color for the room',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _presetColors.map((colorMap) {
                final isSelected = _colorController.text.toUpperCase() == colorMap['hex'].toString().toUpperCase();
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _colorController.text = colorMap['hex'];
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorMap['color'],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.black : Colors.white.withValues(alpha: 0.6),
                        width: isSelected ? 3 : 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 22)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _colorController,
              decoration: const InputDecoration(
                labelText: 'Hex Color Code',
                prefixIcon: Icon(Icons.color_lens_outlined),
                border: OutlineInputBorder(),
                hintText: '#14B8A6',
              ),
              onChanged: (val) => setState(() {}),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Hex color is required';
                }
                final regExp = RegExp(r'^#([A-Fa-f0-9]{6})$');
                if (!regExp.hasMatch(value)) {
                  return 'Enter a valid hex color code (e.g. #14B8A6)';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesField() {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.shade50.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.description_outlined, color: AppTheme.primary, size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Additional Notes',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Design preferences, constraints, or layout guidelines',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Room Notes & Instructions',
                hintText: 'e.g., Bright and airy, layout should leave room for a piano, family-friendly materials...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
            tooltip: 'Cancel',
          ),
          title: const Text(
            'Room Creation Wizard',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
        ),
        body: Container(
          color: Colors.grey.shade50,
          child: Column(
            children: [
              _buildProgressIndicator(),
              Expanded(
                child: _currentStep == 1
                    ? Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 750),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Card(
                                    elevation: 0.5,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(color: Colors.grey.shade200),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primary.shade50.withValues(alpha: 0.5),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: const Icon(Icons.drive_file_rename_outline, color: AppTheme.primary, size: 28),
                                              ),
                                              const SizedBox(width: 16),
                                              const Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Room Identity',
                                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    SizedBox(height: 4),
                                                    Text(
                                                      'Give your room a name and select its main category',
                                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 20),
                                          TextFormField(
                                            controller: _nameController,
                                            decoration: const InputDecoration(
                                              labelText: 'Room Name *',
                                              prefixIcon: Icon(Icons.drive_file_rename_outline),
                                              border: OutlineInputBorder(),
                                              hintText: 'e.g., Master Bedroom, Sunny Kitchen',
                                            ),
                                            validator: (value) {
                                              if (value == null || value.trim().isEmpty) {
                                                return 'Room name is required';
                                              }
                                              return null;
                                            },
                                          ),
                                          const SizedBox(height: 24),
                                          const Text(
                                            'Select Room Type',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                                          ),
                                          const SizedBox(height: 12),
                                          LayoutBuilder(
                                            builder: (context, constraints) {
                                              final crossAxisCount = constraints.maxWidth > 550 ? 4 : 2;
                                              return GridView.builder(
                                                shrinkWrap: true,
                                                physics: const NeverScrollableScrollPhysics(),
                                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: crossAxisCount,
                                                  mainAxisSpacing: 10,
                                                  crossAxisSpacing: 10,
                                                  childAspectRatio: constraints.maxWidth > 550 ? 1.4 : 1.25,
                                                ),
                                                itemCount: _roomTypes.length,
                                                itemBuilder: (context, index) {
                                                  final type = _roomTypes[index];
                                                  final isSelected = _roomType == type['name'];
                                                  return InkWell(
                                                    onTap: () {
                                                      setState(() {
                                                        _roomType = type['name'];
                                                      });
                                                    },
                                                    borderRadius: BorderRadius.circular(12),
                                                    child: AnimatedContainer(
                                                      duration: const Duration(milliseconds: 200),
                                                      decoration: BoxDecoration(
                                                        color: isSelected ? AppTheme.primary.shade50.withValues(alpha: 0.4) : Colors.white,
                                                        border: Border.all(
                                                          color: isSelected ? AppTheme.primary : Colors.grey.shade300,
                                                          width: isSelected ? 2 : 1,
                                                        ),
                                                        borderRadius: BorderRadius.circular(12),
                                                        boxShadow: isSelected
                                                            ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))]
                                                            : null,
                                                      ),
                                                      child: Padding(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                                        child: Column(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            Icon(
                                                              type['icon'] as IconData,
                                                              color: isSelected ? AppTheme.primary : Colors.grey.shade700,
                                                              size: 26,
                                                            ),
                                                            const SizedBox(height: 6),
                                                            Text(
                                                              type['name'] as String,
                                                              textAlign: TextAlign.center,
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                                color: isSelected ? AppTheme.primary.shade900 : Colors.black87,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                          if (_roomType == 'Custom') ...[
                                            const SizedBox(height: 16),
                                            TextFormField(
                                              decoration: const InputDecoration(
                                                labelText: 'Enter Custom Room Type *',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(Icons.meeting_room_outlined),
                                                hintText: 'e.g., Sunroom, Library, Home Theater',
                                              ),
                                              onChanged: (val) => setState(() => _customType = val),
                                              validator: (val) {
                                                if (_roomType == 'Custom' && (val == null || val.trim().isEmpty)) {
                                                  return 'Please specify custom room type';
                                                }
                                                return null;
                                              },
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _buildFloorSelector(),
                                  const SizedBox(height: 16),
                                  _buildColorSelector(),
                                  const SizedBox(height: 16),
                                  _buildNotesField(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : _currentStep == 2
                        ? SpatialRoomCaptureStep(
                            roomType: _roomType,
                            initialPanoramaUrl: _panoramaUrl,
                            initialPanoramaSkipped: _panoramaSkipped,
                            onPanoramaSelected: (url) {
                              _panoramaUrl = url;
                              _panoramaSkipped = false;
                              _savePanorama(isSkipped: false, url: url);
                            },
                            onSkip: () {
                              _panoramaUrl = null;
                              _panoramaSkipped = true;
                              _savePanorama(isSkipped: true);
                            },
                            onBack: () {
                              setState(() {
                                _currentStep = 1;
                              });
                            },
                          )
                        : _currentStep == 3
                            ? MeasurementsStep(
                                onBack: () {
                                  setState(() {
                                    _currentStep = 2;
                                  });
                                },
                                onSave: _saveMeasurements,
                                isMetric: _isMetric,
                                onUnitToggle: (metric) {
                                  setState(() {
                                    _isMetric = metric;
                                  });
                                },
                                lengthController: _lengthController,
                                widthController: _widthController,
                                heightController: _heightController,
                                doorsController: _doorsController,
                                windowsController: _windowsController,
                              )
                            : _currentStep == 4
                                ? Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 750),
                                        child: SingleChildScrollView(
                                          child: StyleSelectionStep(
                                            onBack: () => setState(() => _currentStep = 3),
                                            onSave: _saveStyle,
                                            selectedStyle: _selectedStyle,
                                            onStyleSelected: (style) =>
                                                setState(() => _selectedStyle = style),
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                : _currentStep == 5
                                    ? AIPlanningStep(
                                        roomId: _roomId ?? '',
                                        roomType: _roomType == 'Custom'
                                            ? (_customType.isNotEmpty ? _customType : 'Room')
                                            : _roomType,
                                        selectedStyle: _selectedStyle,
                                        onBack: () => setState(() => _currentStep = 4),
                                        onContinue: () => _finishAIStep(),
                                      )
                                    : _currentStep == 6
                                        ? ReviewStep(
                                            roomName: _nameController.text.trim(),
                                            roomType: _roomType == 'Custom'
                                                ? (_customType.isNotEmpty ? _customType : 'Room')
                                                : _roomType,
                                            floorNumber: _floorNumber,
                                            roomColor: _colorController.text.trim(),
                                            notes: _notesController.text.trim(),
                                            panoramaUrl: _panoramaUrl,
                                            panoramaSkipped: _panoramaSkipped,
                                            length: _lengthController.text,
                                            width: _widthController.text,
                                            height: _heightController.text,
                                            doors: _doorsController.text,
                                            windows: _windowsController.text,
                                            isMetric: _isMetric,
                                            selectedStyle: _selectedStyle,
                                            aiSummary: _aiSummary,
                                            isLoading: _isSaving,
                                            onBack: () => setState(() => _currentStep = 5),
                                            onCreateRoom: _createRoom,
                                          )
                                        : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _currentStep == 1
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    const SecondaryButton(
                      text: 'Back',
                      onPressed: null,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _isSaving ? null : () => _saveRoom(isDraft: true),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                            )
                          : const Text(
                              'Save Draft',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                                fontSize: 15,
                              ),
                            ),
                    ),
                    const SizedBox(width: 16),
                    PrimaryButton(
                      text: 'Next',
                      isLoading: _isSaving,
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          await _saveRoom(isDraft: false);
                        }
                      },
                    ),
                  ],
                ),
              )
            : null,
      ),
    );
  }
}

class EditRoomDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> room;
  final String projectId;

  const EditRoomDialog({super.key, required this.room, required this.projectId});

  @override
  ConsumerState<EditRoomDialog> createState() => _EditRoomDialogState();
}

class _EditRoomDialogState extends ConsumerState<EditRoomDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _colorController = TextEditingController();
  String _roomType = 'Living Room';
  int _floorNumber = 1;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.room['room_name'] ?? '';
    _notesController.text = widget.room['notes'] ?? '';
    _colorController.text = widget.room['room_color'] ?? '#FFFFFF';
    _roomType = widget.room['room_type'] ?? 'Living Room';
    _floorNumber = widget.room['floor_number'] ?? 1;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      final success = await ref.read(roomDetailsProvider.notifier).updateRoom(
            widget.room['id'],
            roomName: _nameController.text.trim(),
            roomType: _roomType,
            floorNumber: _floorNumber,
            notes: _notesController.text.trim(),
            roomColor: _colorController.text.trim(),
          );
      setState(() => _isSaving = false);

      if (mounted) {
        if (success) {
          SnackbarManager.showSuccess(context, 'Room details updated.');
          ref.read(roomListProvider.notifier).fetchRooms(widget.projectId);
          Navigator.of(context).pop(true);
        } else {
          final error = ref.read(roomDetailsProvider).errorMessage ?? 'Failed to update';
          SnackbarManager.showError(context, error);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Room Settings'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Room Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Room name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _roomType,
                decoration: const InputDecoration(
                  labelText: 'Room Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Living Room', child: Text('Living Room')),
                  DropdownMenuItem(value: 'Bedroom', child: Text('Bedroom')),
                  DropdownMenuItem(value: 'Kitchen', child: Text('Kitchen')),
                  DropdownMenuItem(value: 'Dining Room', child: Text('Dining Room')),
                  DropdownMenuItem(value: 'Office', child: Text('Office')),
                  DropdownMenuItem(value: 'Bathroom', child: Text('Bathroom')),
                  DropdownMenuItem(value: 'Custom', child: Text('Custom')),
                ],
                onChanged: (val) => setState(() => _roomType = val ?? 'Living Room'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _floorNumber.toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Floor Number',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty || int.tryParse(value) == null) {
                    return 'Enter a valid floor number';
                  }
                  return null;
                },
                onChanged: (val) => _floorNumber = int.tryParse(val) ?? 1,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _colorController,
                decoration: const InputDecoration(
                  labelText: 'Room Color (Hex code)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Color is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
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

class DeleteRoomDialog extends ConsumerWidget {
  final Map<String, dynamic> room;
  final String projectId;

  const DeleteRoomDialog({super.key, required this.room, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomDialog(
      title: 'Delete Room',
      content: 'Are you sure you want to delete "${room['room_name']}"? All geometry, doors, windows, and furniture inside it will be permanently deleted.',
      confirmText: 'Delete',
      cancelText: 'Cancel',
      onConfirm: () async {
        final success = await ref.read(roomListProvider.notifier).deleteRoom(projectId, room['id']);
        if (context.mounted) {
          if (success) {
            SnackbarManager.showSuccess(context, 'Room deleted successfully.');
          } else {
            final error = ref.read(roomListProvider).errorMessage ?? 'Failed to delete room';
            SnackbarManager.showError(context, error);
          }
        }
      },
    );
  }
}
