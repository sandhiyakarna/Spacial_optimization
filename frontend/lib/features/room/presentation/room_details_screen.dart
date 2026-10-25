import '../../../app/themes/app_theme.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/room_provider.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/snackbar_manager.dart';
import 'panorama_capture_screen.dart';

class RoomDetailsScreen extends ConsumerStatefulWidget {
  final String roomId;

  const RoomDetailsScreen({super.key, required this.roomId});

  @override
  ConsumerState<RoomDetailsScreen> createState() => _RoomDetailsScreenState();
}

class _RoomDetailsScreenState extends ConsumerState<RoomDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  final _floorThickController = TextEditingController();
  final _wallThickController = TextEditingController();
  final _ceilHeightController = TextEditingController();
  final _propertiesController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(roomDetailsProvider.notifier).fetchDetails(widget.roomId);
    });
  }

  @override
  void dispose() {
    _lengthController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _floorThickController.dispose();
    _wallThickController.dispose();
    _ceilHeightController.dispose();
    _propertiesController.dispose();
    super.dispose();
  }

  void _populateControllers(Map<String, dynamic> data) {
    final m = data['measurements'] as Map<String, dynamic>? ?? {};
    if (_lengthController.text.isEmpty) {
      _lengthController.text = (m['length'] ?? 600.0).toString();
      _widthController.text = (m['width'] ?? 450.0).toString();
      _heightController.text = (m['height'] ?? 300.0).toString();
      _floorThickController.text = (m['floor_thickness'] ?? 30.0).toString();
      _wallThickController.text = (m['wall_thickness'] ?? 20.0).toString();
      _ceilHeightController.text = (m['ceiling_height'] ?? 300.0).toString();
      _propertiesController.text = data['properties'] ?? '';
    }
  }

  Future<void> _handleSave() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      
      final l = double.parse(_lengthController.text.trim());
      final w = double.parse(_widthController.text.trim());
      final h = double.parse(_heightController.text.trim());
      final ft = double.tryParse(_floorThickController.text.trim());
      final wt = double.tryParse(_wallThickController.text.trim());
      final ch = double.tryParse(_ceilHeightController.text.trim());

      // Update measurements
      final success = await ref.read(roomDetailsProvider.notifier).updateMeasurements(
            widget.roomId,
            length: l,
            width: w,
            height: h,
            floorThickness: ft,
            wallThickness: wt,
            ceilingHeight: ch,
          );

      // Save properties
      await ref.read(roomDetailsProvider.notifier).updateRoom(
            widget.roomId,
            roomName: ref.read(roomDetailsProvider).details?['room_name'] ?? '',
            roomType: ref.read(roomDetailsProvider).details?['room_type'] ?? '',
            floorNumber: ref.read(roomDetailsProvider).details?['floor_number'] ?? 1,
            roomColor: ref.read(roomDetailsProvider).details?['room_color'] ?? '#FFFFFF',
            notes: ref.read(roomDetailsProvider).details?['notes'],
            properties: _propertiesController.text.trim(),
          );

      setState(() => _isSaving = false);

      if (mounted) {
        if (success) {
          SnackbarManager.showSuccess(context, 'Measurements & properties updated.');
        } else {
          final error = ref.read(roomDetailsProvider).errorMessage ?? 'Failed to update';
          SnackbarManager.showError(context, error);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailState = ref.watch(roomDetailsProvider);

    if (detailState.isLoading && detailState.details == null) {
      return const Scaffold(
        body: LoadingIndicator(message: 'Loading room configuration...'),
      );
    }

    if (detailState.errorMessage != null && detailState.details == null) {
      return Scaffold(
        body: ErrorState(
          message: detailState.errorMessage!,
          onRetry: () => ref.read(roomDetailsProvider.notifier).fetchDetails(widget.roomId),
        ),
      );
    }

    final data = detailState.details ?? {};
    _populateControllers(data);

    Color parsedColor = Colors.grey;
    try {
      final hex = (data['room_color'] ?? '#FFFFFF').toString().replaceAll('#', '');
      parsedColor = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {}

    return Scaffold(
      appBar: AppBar(
        title: Text(data['room_name'] ?? 'Room Geometry'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Room Quick Summary Info card
              Card(
                elevation: 1,
                color: AppTheme.primary.withValues(alpha: 0.05),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: parsedColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Type: ${data['room_type']}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text('Floor Level: ${data['floor_number']}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Room Panorama Section
              Builder(
                builder: (context) {
                  String? panoramaFile;
                  try {
                    final String propsText = data['properties'] ?? '';
                    if (propsText.isNotEmpty) {
                      final props = jsonDecode(propsText);
                      panoramaFile = props['panorama_file'] ?? props['panorama_url'];
                    }
                  } catch (_) {}

                  final roomType = data['room_type'] ?? 'Living Room';

                  return Card(
                    elevation: 1,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          color: AppTheme.primary.withAlpha(12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.explore_outlined, color: AppTheme.primary, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Spatial Room Capture (360° Preview)',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              TextButton.icon(
                                icon: Icon(panoramaFile != null ? Icons.refresh : Icons.camera_alt, size: 16, color: AppTheme.primary),
                                label: Text(
                                  panoramaFile != null ? 'Recapture' : 'Capture New',
                                  style: const TextStyle(color: AppTheme.primary, fontSize: 13),
                                ),
                                onPressed: () async {
                                  final result = await Navigator.push<String>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SpatialRoomCaptureScreen(
                                        roomType: roomType,
                                        roomId: widget.roomId,
                                      ),
                                    ),
                                  );
                                  if (result != null) {
                                    final Map<String, dynamic> currentProps = {};
                                    try {
                                      if (_propertiesController.text.isNotEmpty) {
                                        currentProps.addAll(jsonDecode(_propertiesController.text));
                                      }
                                    } catch (_) {}
                                    if (result == 'ai_fallback') {
                                      currentProps['panorama_file'] = null;
                                      currentProps['panorama_skipped'] = true;
                                    } else {
                                      currentProps['panorama_file'] = result;
                                      currentProps['panorama_skipped'] = false;
                                    }
                                    
                                    setState(() {
                                      _propertiesController.text = jsonEncode(currentProps);
                                    });
 
                                    setState(() => _isSaving = true);
                                    await ref.read(roomDetailsProvider.notifier).updateRoom(
                                          widget.roomId,
                                          roomName: data['room_name'] ?? '',
                                          roomType: data['room_type'] ?? '',
                                          floorNumber: data['floor_number'] ?? 1,
                                          roomColor: data['room_color'] ?? '#FFFFFF',
                                          notes: data['notes'],
                                          properties: _propertiesController.text,
                                        );
                                    setState(() => _isSaving = false);
                                    
                                    if (context.mounted) {
                                      SnackbarManager.showSuccess(context, 'Spatial Room Capture updated successfully.');
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        if (panoramaFile != null)
                          SizedBox(
                            height: 200,
                            child: Stack(
                              children: [
                                InteractivePanoramaViewer(
                                  roomType: roomType,
                                  isInteractive: true,
                                  lightMode: Theme.of(context).brightness == Brightness.light,
                                  panoramaUrl: panoramaFile,
                                ),
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.swipe, color: Colors.white, size: 12),
                                        SizedBox(width: 4),
                                        Text('Drag to pan', style: TextStyle(color: Colors.white, fontSize: 9)),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.shade700,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      panoramaFile,
                                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                            child: Column(
                              children: [
                                Icon(Icons.explore_outlined, size: 36, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text(
                                  'No Spatial Room Model Captured',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Perform a spatial room capture to visualize the digital model in 3D.',
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // Dimensions Heading
              Text(
                'Space Geometry & Dimensions (Centimeters)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _lengthController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Length *',
                        border: OutlineInputBorder(),
                        suffixText: 'cm',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'Length required';
                        final val = double.tryParse(value);
                        if (val == null || val <= 0) return 'Must be > 0';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _widthController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Width *',
                        border: OutlineInputBorder(),
                        suffixText: 'cm',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'Width required';
                        final val = double.tryParse(value);
                        if (val == null || val <= 0) return 'Must be > 0';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _heightController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Height *',
                        border: OutlineInputBorder(),
                        suffixText: 'cm',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'Height required';
                        final val = double.tryParse(value);
                        if (val == null || val <= 0) return 'Must be > 0';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _ceilHeightController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Ceiling Height',
                        border: OutlineInputBorder(),
                        suffixText: 'cm',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _wallThickController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Wall Thickness',
                        border: OutlineInputBorder(),
                        suffixText: 'cm',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _floorThickController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Floor Thickness',
                        border: OutlineInputBorder(),
                        suffixText: 'cm',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Room Properties Heading
              Text(
                'Extra Attributes / Properties',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _propertiesController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Custom Room Properties (e.g. JSON metadata)',
                  hintText: '{\n  "window_orientation": "North",\n  "flooring_material": "Oak Wood"\n}',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 32),

              PrimaryButton(
                text: 'Save Space Configuration',
                isLoading: _isSaving,
                onPressed: _handleSave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
