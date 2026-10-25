import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../app/themes/app_theme.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../../shared/widgets/snackbar_manager.dart';
import '../data/material_api_client.dart';
import '../models/material_model.dart';
import '../../admin/providers/admin_provider.dart';

class AdminMaterialUploadScreen extends ConsumerStatefulWidget {
  final MaterialModel? existingMaterial;
  final MaterialApiClient? apiClient;
  const AdminMaterialUploadScreen({super.key, this.existingMaterial, this.apiClient});

  @override
  ConsumerState<AdminMaterialUploadScreen> createState() => _AdminMaterialUploadScreenState();
}

class _AdminMaterialUploadScreenState extends ConsumerState<AdminMaterialUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  late final MaterialApiClient _apiClient;

  // Text Controllers
  final _nameController = TextEditingController();
  final _baseColorController = TextEditingController(text: '#FFFFFF');
  final _customCategoryController = TextEditingController();

  // PBR Slider Values
  double _opacity = 1.0;
  double _reflectivity = 0.0;
  double _defaultScale = 1.0;

  // Category Selection
  String? _selectedCategoryId;
  List<MaterialCategory> _categories = [];
  bool _isCustomCategory = false;
  bool _isLoadingCategories = true;

  // Picker states for textures and preview
  PlatformFile? _previewFile;
  Uint8List? _previewBytes;
  String? _previewValidationError;

  PlatformFile? _baseColorMapFile;
  Uint8List? _baseColorMapBytes;
  String? _baseColorMapValidationError;

  PlatformFile? _normalMapFile;
  Uint8List? _normalMapBytes;
  String? _normalMapValidationError;

  PlatformFile? _roughnessMapFile;
  Uint8List? _roughnessMapBytes;
  String? _roughnessMapValidationError;

  PlatformFile? _metallicMapFile;
  Uint8List? _metallicMapBytes;
  String? _metallicMapValidationError;

  // Upload progress state
  bool _isUploading = false;
  int _uploadStep = 0; // 0=metadata, 1=preview, 2=base_color, 3=normal, 4=roughness, 5=metallic, 6=done
  double _uploadProgress = 0.0;
  String _uploadStatusMessage = '';

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? MaterialApiClient();
    _fetchCategories();

    if (widget.existingMaterial != null) {
      _nameController.text = widget.existingMaterial!.name;
      _baseColorController.text = widget.existingMaterial!.baseColor ?? '#FFFFFF';
      _opacity = widget.existingMaterial!.opacity;
      _reflectivity = widget.existingMaterial!.reflectivity;
      _defaultScale = widget.existingMaterial!.defaultScale;
      _selectedCategoryId = widget.existingMaterial!.categoryId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseColorController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  Future<void> _fetchCategories() async {
    try {
      final cats = await _apiClient.getCategories();
      if (mounted) {
        setState(() {
          _categories = cats;
          _isLoadingCategories = false;
          
          if (widget.existingMaterial != null) {
            final exists = cats.any((c) => c.id == widget.existingMaterial!.categoryId);
            if (exists) {
              _selectedCategoryId = widget.existingMaterial!.categoryId;
              _isCustomCategory = false;
            } else {
              _isCustomCategory = true;
              _customCategoryController.text = widget.existingMaterial!.category.name;
            }
          } else if (cats.isNotEmpty) {
            _selectedCategoryId = cats.first.id;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCategories = false);
        SnackbarManager.showError(context, 'Failed to fetch categories: $e');
      }
    }
  }

  // --- Picker Helpers ---
  Future<void> _pickImageFile(String type) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      
      const maxImgSize = 5 * 1024 * 1024;
      String? error;
      if (file.size > maxImgSize) {
        error = 'Image exceeds 5MB size limit (${(file.size / (1024 * 1024)).toStringAsFixed(1)}MB)';
      }
      
      final ext = file.extension?.toLowerCase();
      if (ext != 'png' && ext != 'jpg' && ext != 'jpeg' && ext != 'webp') {
        error = 'Unsupported file format. Only png, jpg, jpeg, and webp are allowed.';
      }

      setState(() {
        if (type == 'preview') {
          _previewFile = error == null ? file : null;
          _previewBytes = error == null ? file.bytes : null;
          _previewValidationError = error;
        } else if (type == 'base_color') {
          _baseColorMapFile = error == null ? file : null;
          _baseColorMapBytes = error == null ? file.bytes : null;
          _baseColorMapValidationError = error;
        } else if (type == 'normal') {
          _normalMapFile = error == null ? file : null;
          _normalMapBytes = error == null ? file.bytes : null;
          _normalMapValidationError = error;
        } else if (type == 'roughness') {
          _roughnessMapFile = error == null ? file : null;
          _roughnessMapBytes = error == null ? file.bytes : null;
          _roughnessMapValidationError = error;
        } else if (type == 'metallic') {
          _metallicMapFile = error == null ? file : null;
          _metallicMapBytes = error == null ? file.bytes : null;
          _metallicMapValidationError = error;
        }
      });
    } catch (e) {
      SnackbarManager.showError(context, 'Error picking file: $e');
    }
  }

  // --- Save / Submission sequence ---
  Future<void> _saveMaterial() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isUploading = true;
      _uploadStep = 0;
      _uploadProgress = 0.1;
      _uploadStatusMessage = 'Processing material settings...';
    });

    try {
      String catId = _selectedCategoryId ?? '';
      
      // 1. Create custom category if chosen
      if (_isCustomCategory) {
        setState(() {
          _uploadStatusMessage = 'Creating custom category...';
          _uploadProgress = 0.2;
        });
        final newCat = await _apiClient.createMaterialCategory(_customCategoryController.text.trim());
        catId = newCat.id;
      }

      // 2. Prepare payload
      final payload = {
        'name': _nameController.text.trim(),
        'category_id': catId,
        'base_color': _baseColorController.text.trim(),
        'opacity': _opacity,
        'reflectivity': _reflectivity,
        'default_scale': _defaultScale,
      };

      MaterialModel material;
      if (widget.existingMaterial == null) {
        material = await _apiClient.createMaterial(payload);
      } else {
        material = await _apiClient.updateMaterial(widget.existingMaterial!.id, payload);
      }

      final matId = material.id;

      // 3. Upload Preview image
      if (_previewBytes != null) {
        setState(() {
          _uploadStep = 1;
          _uploadStatusMessage = 'Uploading preview image...';
          _uploadProgress = 0.4;
        });
        material = await _apiClient.uploadPreviewImage(matId, _previewBytes!, _previewFile!.name);
      }

      // 4. Upload Base Color Map
      if (_baseColorMapBytes != null) {
        setState(() {
          _uploadStep = 2;
          _uploadStatusMessage = 'Uploading base color map...';
          _uploadProgress = 0.6;
        });
        material = await _apiClient.uploadTextureFile(matId, 'base_color', _baseColorMapBytes!, _baseColorMapFile!.name);
      }

      // 5. Upload Normal Map
      if (_normalMapBytes != null) {
        setState(() {
          _uploadStep = 3;
          _uploadStatusMessage = 'Uploading normal map...';
          _uploadProgress = 0.75;
        });
        material = await _apiClient.uploadTextureFile(matId, 'normal', _normalMapBytes!, _normalMapFile!.name);
      }

      // 6. Upload Roughness Map
      if (_roughnessMapBytes != null) {
        setState(() {
          _uploadStep = 4;
          _uploadStatusMessage = 'Uploading roughness map...';
          _uploadProgress = 0.85;
        });
        material = await _apiClient.uploadTextureFile(matId, 'roughness', _roughnessMapBytes!, _roughnessMapFile!.name);
      }

      // 7. Upload Metallic Map
      if (_metallicMapBytes != null) {
        setState(() {
          _uploadStep = 5;
          _uploadStatusMessage = 'Uploading metallic map...';
          _uploadProgress = 0.95;
        });
        material = await _apiClient.uploadTextureFile(matId, 'metallic', _metallicMapBytes!, _metallicMapFile!.name);
      }

      setState(() {
        _uploadStep = 6;
        _uploadProgress = 1.0;
        _uploadStatusMessage = 'Material saved successfully!';
        _isUploading = false;
      });

      ref.read(adminProvider.notifier).fetchAdminDashboard();
      
      if (mounted) {
        SnackbarManager.showSuccess(context, 'Material successfully registered.');
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/admin');
        }
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        SnackbarManager.showError(context, 'Error saving material: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    if (_isLoadingCategories) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(title: const Text('Manage Material')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        title: Text(widget.existingMaterial == null ? 'Register New Material' : 'Edit Material Properties', style: TextStyle(color: textPrimary)),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Core Information', style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  
                  // Material Name
                  TextFormField(
                    controller: _nameController,
                    style: TextStyle(color: textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Material Name',
                      hintText: 'e.g. Polished Brass, Carrara Marble',
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Please enter material name' : null,
                  ),
                  const SizedBox(height: 20),

                  // Category Selector
                  Row(
                    children: [
                      Expanded(
                        child: _isCustomCategory
                            ? TextFormField(
                                controller: _customCategoryController,
                                style: TextStyle(color: textPrimary),
                                decoration: const InputDecoration(
                                  labelText: 'Custom Category Name',
                                ),
                                validator: (val) => val == null || val.trim().isEmpty ? 'Please enter category name' : null,
                              )
                            : DropdownButtonFormField<String>(
                                value: _selectedCategoryId,
                                dropdownColor: surfaceColor,
                                style: TextStyle(color: textPrimary),
                                decoration: const InputDecoration(labelText: 'Material Category'),
                                items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, style: TextStyle(color: textPrimary)))).toList(),
                                onChanged: (val) => setState(() => _selectedCategoryId = val),
                              ),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: () => setState(() => _isCustomCategory = !_isCustomCategory),
                        icon: Icon(_isCustomCategory ? Icons.list_rounded : Icons.add_rounded),
                        label: Text(_isCustomCategory ? 'Use Existing' : 'Create Custom'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // PBR Parameters Section
                  Text('PBR Rendering Settings', style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  
                  // Base Color Hex Code
                  TextFormField(
                    controller: _baseColorController,
                    style: TextStyle(color: textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Base Color Hex Code',
                      hintText: 'e.g. #FFFFFF or #D27D2D',
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return null;
                      final regExp = RegExp(r'^#[0-9A-Fa-f]{6}$');
                      if (!regExp.hasMatch(val)) return 'Invalid hex color code (use format #RRGGBB)';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Opacity Slider
                  Row(
                    children: [
                      Text('Opacity:', style: TextStyle(color: textPrimary)),
                      Expanded(
                        child: Slider(
                          value: _opacity,
                          min: 0.0,
                          max: 1.0,
                          divisions: 10,
                          label: _opacity.toStringAsFixed(1),
                          onChanged: (val) => setState(() => _opacity = val),
                        ),
                      ),
                      Text(_opacity.toStringAsFixed(1), style: TextStyle(color: textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Reflectivity Slider
                  Row(
                    children: [
                      Text('Reflectivity:', style: TextStyle(color: textPrimary)),
                      Expanded(
                        child: Slider(
                          value: _reflectivity,
                          min: 0.0,
                          max: 1.0,
                          divisions: 10,
                          label: _reflectivity.toStringAsFixed(1),
                          onChanged: (val) => setState(() => _reflectivity = val),
                        ),
                      ),
                      Text(_reflectivity.toStringAsFixed(1), style: TextStyle(color: textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Default Scale Slider
                  Row(
                    children: [
                      Text('Default Scale:', style: TextStyle(color: textPrimary)),
                      Expanded(
                        child: Slider(
                          value: _defaultScale,
                          min: 0.1,
                          max: 5.0,
                          divisions: 49,
                          label: _defaultScale.toStringAsFixed(2),
                          onChanged: (val) => setState(() => _defaultScale = val),
                        ),
                      ),
                      Text(_defaultScale.toStringAsFixed(2), style: TextStyle(color: textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // File Maps Section
                  Text('Texture Maps & Preview File', style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  
                  _buildFilePickerItem('Preview Image', _previewFile, _previewValidationError, () => _pickImageFile('preview')),
                  const SizedBox(height: 16),
                  _buildFilePickerItem('Albedo / Base Color Map', _baseColorMapFile, _baseColorMapValidationError, () => _pickImageFile('base_color')),
                  const SizedBox(height: 16),
                  _buildFilePickerItem('Normal Map', _normalMapFile, _normalMapValidationError, () => _pickImageFile('normal')),
                  const SizedBox(height: 16),
                  _buildFilePickerItem('Roughness Map', _roughnessMapFile, _roughnessMapValidationError, () => _pickImageFile('roughness')),
                  const SizedBox(height: 16),
                  _buildFilePickerItem('Metallic Map', _metallicMapFile, _metallicMapValidationError, () => _pickImageFile('metallic')),
                  
                  const SizedBox(height: 48),
                  
                  PrimaryButton(
                    key: const Key('save_material_btn'),
                    text: widget.existingMaterial == null ? 'Register Material' : 'Save Changes',
                    onPressed: _saveMaterial,
                  ),
                ],
              ),
            ),
          ),
          
          // Floating upload overlay
          if (_isUploading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(32),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 24),
                        Text(
                          _uploadStatusMessage,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: _uploadProgress),
                        const SizedBox(height: 8),
                        Text('${(_uploadProgress * 100).toInt()}% completed'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilePickerItem(String label, PlatformFile? file, String? validationError, VoidCallback onPick) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: validationError != null ? AppTheme.error : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
                ElevatedButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: Text(file == null ? 'Choose File' : 'Change'),
                ),
              ],
            ),
            if (file != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.insert_drive_file_outlined, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      file.name,
                      style: TextStyle(color: textPrimary, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${(file.size / 1024).toStringAsFixed(1)} KB',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ],
            if (validationError != null) ...[
              const SizedBox(height: 8),
              Text(
                validationError,
                style: const TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
