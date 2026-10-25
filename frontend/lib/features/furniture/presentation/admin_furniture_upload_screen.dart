import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../app/themes/app_theme.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../../shared/widgets/snackbar_manager.dart';
import '../data/furniture_api_client.dart';
import '../providers/furniture_provider.dart';
import '../models/furniture_asset.dart';
import '../../admin/providers/admin_provider.dart';

class AdminFurnitureUploadScreen extends ConsumerStatefulWidget {
  final FurnitureAsset? existingAsset;
  const AdminFurnitureUploadScreen({super.key, this.existingAsset});

  @override
  ConsumerState<AdminFurnitureUploadScreen> createState() => _AdminFurnitureUploadScreenState();
}

class _AdminFurnitureUploadScreenState extends ConsumerState<AdminFurnitureUploadScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final FurnitureApiClient _apiClient = FurnitureApiClient();

  // Text Controllers
  final _nameController = TextEditingController();
  final _widthController = TextEditingController(text: '100');
  final _depthController = TextEditingController(text: '100');
  final _heightController = TextEditingController(text: '75');
  final _clearanceController = TextEditingController(text: '0');
  final _assemblyController = TextEditingController(text: '0');
  final _tagsController = TextEditingController();
  final _customCategoryController = TextEditingController();

  // Dropdowns / selections
  String _selectedStyle = 'Modern';
  String _selectedCategory = 'Living Room';
  bool _isCustomCategory = false;

  final List<String> _styles = ['Modern', 'Scandinavian', 'Minimal', 'Industrial', 'Classic', 'Minimalist'];

  // Upload Files State
  PlatformFile? _glbFile;
  Uint8List? _glbBytes;
  GlbMetadata? _glbMetadata;
  String? _glbValidationError;

  PlatformFile? _thumbnailFile;
  Uint8List? _thumbnailBytes;
  String? _thumbnailValidationError;

  PlatformFile? _previewFile;
  Uint8List? _previewBytes;
  String? _previewValidationError;

  // Animation controller for 3D simulated mesh rotating preview
  late AnimationController _rotationController;

  // Multi-step upload process state
  bool _isUploading = false;
  int _uploadStep = 0; // 0=Idle, 1=Duplicate check/Metadata, 2=Schema setup, 3=GLB, 4=Thumbnail, 5=Preview, 6=Finished
  String _uploadStatusMessage = '';
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    
    // Fetch categories dynamically on load
    Future.microtask(() async {
      await ref.read(furnitureProvider.notifier).fetchCategories();
      if (widget.existingAsset != null && mounted) {
        final cats = ref.read(furnitureProvider).categories.map((c) => c.name).toList();
        setState(() {
          _nameController.text = widget.existingAsset!.name;
          _widthController.text = widget.existingAsset!.width.toString();
          _depthController.text = widget.existingAsset!.depth.toString();
          _heightController.text = widget.existingAsset!.height.toString();
          _clearanceController.text = widget.existingAsset!.clearance.toString();
          _assemblyController.text = widget.existingAsset!.assemblyClearance.toString();
          _tagsController.text = widget.existingAsset!.tags ?? '';
          _selectedStyle = widget.existingAsset!.style;
          
          if (cats.contains(widget.existingAsset!.category)) {
            _selectedCategory = widget.existingAsset!.category;
            _isCustomCategory = false;
          } else {
            _isCustomCategory = true;
            _customCategoryController.text = widget.existingAsset!.category;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _widthController.dispose();
    _depthController.dispose();
    _heightController.dispose();
    _clearanceController.dispose();
    _assemblyController.dispose();
    _tagsController.dispose();
    _customCategoryController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  // --- File Picking & Local Parsing/Validation ---
  Future<void> _pickGlbFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['glb'],
        withData: true, // Need bytes for local web/parsing preview
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      
      // 1. Validation size limit (50MB)
      const maxGlbSize = 50 * 1024 * 1024;
      if (file.size > maxGlbSize) {
        setState(() {
          _glbValidationError = 'GLB file exceeds 50MB size limit (${(file.size / (1024 * 1024)).toStringAsFixed(1)}MB)';
          _glbFile = null;
          _glbBytes = null;
          _glbMetadata = null;
        });
        return;
      }

      // 2. Extension check
      if (file.extension?.toLowerCase() != 'glb') {
        setState(() {
          _glbValidationError = 'Invalid file extension. Only .glb files are supported.';
          _glbFile = null;
          _glbBytes = null;
          _glbMetadata = null;
        });
        return;
      }

      final bytes = file.bytes;
      if (bytes == null || bytes.length < 20) {
        setState(() {
          _glbValidationError = 'Unable to read file content or file is corrupt.';
          _glbFile = null;
          _glbBytes = null;
          _glbMetadata = null;
        });
        return;
      }

      // 3. Magic bytes check (must start with "glTF")
      final magicBytes = bytes.sublist(0, 4);
      final magic = ascii.decode(magicBytes);
      if (magic != 'glTF') {
        setState(() {
          _glbValidationError = 'Invalid GLB format. Binary headers do not start with "glTF".';
          _glbFile = null;
          _glbBytes = null;
          _glbMetadata = null;
        });
        return;
      }

      // 4. Try parsing GLB metadata using local parser
      try {
        final meta = GlbMetadata.parse(bytes);
        setState(() {
          _glbFile = file;
          _glbBytes = bytes;
          _glbMetadata = meta;
          _glbValidationError = null;
        });
      } catch (e) {
        setState(() {
          _glbValidationError = 'Metadata parsing failed: ${e.toString()}';
          _glbFile = null;
          _glbBytes = null;
          _glbMetadata = null;
        });
      }
    } catch (e) {
      setState(() {
        _glbValidationError = 'Error picking file: $e';
      });
    }
  }

  Future<void> _pickThumbnailFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;

      // 1. Size check: 5MB
      const maxThumbSize = 5 * 1024 * 1024;
      if (file.size > maxThumbSize) {
        setState(() {
          _thumbnailValidationError = 'Thumbnail file exceeds 5MB size limit';
          _thumbnailFile = null;
          _thumbnailBytes = null;
        });
        return;
      }

      // 2. Extension check
      final allowedExts = ['png', 'jpg', 'jpeg', 'webp'];
      if (!allowedExts.contains(file.extension?.toLowerCase())) {
        setState(() {
          _thumbnailValidationError = 'Only images (.png, .jpg, .jpeg, .webp) are allowed.';
          _thumbnailFile = null;
          _thumbnailBytes = null;
        });
        return;
      }

      setState(() {
        _thumbnailFile = file;
        _thumbnailBytes = file.bytes;
        _thumbnailValidationError = null;
      });
    } catch (e) {
      setState(() {
        _thumbnailValidationError = 'Error picking thumbnail: $e';
      });
    }
  }

  Future<void> _pickPreviewFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;

      // 1. Size check: 5MB
      const maxPreviewSize = 5 * 1024 * 1024;
      if (file.size > maxPreviewSize) {
        setState(() {
          _previewValidationError = 'Preview file exceeds 5MB size limit';
          _previewFile = null;
          _previewBytes = null;
        });
        return;
      }

      // 2. Extension check
      final allowedExts = ['png', 'jpg', 'jpeg', 'webp'];
      if (!allowedExts.contains(file.extension?.toLowerCase())) {
        setState(() {
          _previewValidationError = 'Only images (.png, .jpg, .jpeg, .webp) are allowed.';
          _previewFile = null;
          _previewBytes = null;
        });
        return;
      }

      setState(() {
        _previewFile = file;
        _previewBytes = file.bytes;
        _previewValidationError = null;
      });
    } catch (e) {
      setState(() {
        _previewValidationError = 'Error picking preview image: $e';
      });
    }
  }

  // --- Duplicate check/Create and upload handler ---
  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    final bool isEditMode = widget.existingAsset != null;

    if (!isEditMode) {
      if (_glbFile == null || _glbBytes == null) {
        setState(() {
          _glbValidationError = 'A 3D model (.glb) is required';
        });
        return;
      }

      if (_thumbnailFile == null || _thumbnailBytes == null) {
        setState(() {
          _thumbnailValidationError = 'A thumbnail image is required';
        });
        return;
      }
    }

    final String name = _nameController.text.trim();
    final String category = _isCustomCategory ? _customCategoryController.text.trim() : _selectedCategory;
    final String style = _selectedStyle;
    final double width = double.parse(_widthController.text);
    final double depth = double.parse(_depthController.text);
    final double height = double.parse(_heightController.text);
    final double clearance = double.parse(_clearanceController.text);
    final double assemblyClearance = double.parse(_assemblyController.text);
    final String tags = _tagsController.text.trim();

    if (category.isEmpty) {
      SnackbarManager.showError(context, 'Please specify a category');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStep = 1;
      _uploadProgress = 0.15;
      _uploadStatusMessage = isEditMode ? 'Updating furniture metadata...' : 'Checking for duplicate assets on server...';
    });

    try {
      String assetId;
      if (isEditMode) {
        assetId = widget.existingAsset!.id;
        // Step 1: PUT Metadata update
        await _apiClient.updateFurnitureAsset(assetId, {
          'name': name,
          'category': category,
          'style': style,
          'width': width,
          'depth': depth,
          'height': height,
          'clearance': clearance,
          'assembly_clearance': assemblyClearance,
          'tags': tags.isNotEmpty ? tags : null,
        });
      } else {
        // Step 1: Duplicate check
        final dupResult = await _apiClient.checkDuplicate({
          'name': name,
          'category': category,
          'style': style,
          'width': width,
          'depth': depth,
          'height': height,
        });

        if (dupResult['is_duplicate'] == true) {
          // Pause upload to ask user confirmation
          setState(() {
            _isUploading = false;
          });
          
          final proceed = await _showDuplicateWarningDialog(
            dupResult['duplicate_asset']?['name'] ?? 'Identical Asset',
            dupResult['reason'] ?? 'Dimensions match exactly.',
          );

          if (!proceed) return;

          setState(() {
            _isUploading = true;
            _uploadStep = 2;
            _uploadProgress = 0.3;
            _uploadStatusMessage = 'Creating furniture asset metadata...';
          });
        } else {
          setState(() {
            _uploadStep = 2;
            _uploadProgress = 0.3;
            _uploadStatusMessage = 'Creating furniture asset metadata...';
          });
        }

        // Step 2: Create metadata on server
        final asset = await _apiClient.createFurnitureAsset({
          'name': name,
          'category': category,
          'style': style,
          'width': width,
          'depth': depth,
          'height': height,
          'clearance': clearance,
          'assembly_clearance': assemblyClearance,
          'tags': tags.isNotEmpty ? tags : null,
        });
        assetId = asset.id;
      }

      // Step 3: Upload GLB model file if selected
      if (_glbBytes != null && _glbFile != null) {
        setState(() {
          _uploadStep = 3;
          _uploadProgress = 0.5;
          _uploadStatusMessage = 'Uploading 3D model (${(_glbBytes!.length / 1024).toStringAsFixed(0)} KB)...';
        });
        await _apiClient.uploadGlbFile(assetId, _glbBytes!, _glbFile!.name);
      }

      // Step 4: Upload thumbnail if selected
      if (_thumbnailBytes != null && _thumbnailFile != null) {
        setState(() {
          _uploadStep = 4;
          _uploadProgress = 0.7;
          _uploadStatusMessage = 'Uploading thumbnail image...';
        });
        await _apiClient.uploadThumbnailFile(assetId, _thumbnailBytes!, _thumbnailFile!.name);
      }

      // Step 5: Upload preview if selected
      if (_previewBytes != null && _previewFile != null) {
        setState(() {
          _uploadStep = 5;
          _uploadProgress = 0.85;
          _uploadStatusMessage = 'Uploading preview image...';
        });
        await _apiClient.uploadPreviewFile(assetId, _previewBytes!, _previewFile!.name);
      }

      // Step 6: Finished
      setState(() {
        _uploadStep = 6;
        _uploadProgress = 1.0;
        _uploadStatusMessage = isEditMode ? 'Asset updated successfully!' : 'Asset successfully uploaded!';
      });

      // Refresh parent lists
      ref.read(furnitureProvider.notifier).fetchAssets();
      ref.read(furnitureProvider.notifier).fetchCategories();
      ref.read(adminProvider.notifier).fetchAdminDashboard();

      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/admin');
        }
        SnackbarManager.showSuccess(context, isEditMode ? 'Successfully updated "$name"!' : 'Successfully uploaded "$name"!');
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
        _uploadStep = 0;
        _uploadStatusMessage = '';
      });
      if (mounted) {
        SnackbarManager.showError(context, '${isEditMode ? "Update" : "Upload"} failed: ${e.toString()}');
      }
    }
  }

  Future<bool> _showDuplicateWarningDialog(String assetName, String reason) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('Duplicate Detected'),
          ],
        ),
        content: Text(
          'An asset named "$assetName" or with matching dimensions already exists.\n\n'
          'Reason:\n$reason\n\n'
          'Are you sure you want to upload this duplicate asset anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel Upload'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Proceed Anyway'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // --- Layout Builders ---
  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isLargeScreen = width > 900;
    final isEditMode = widget.existingAsset != null;
    
    // Dynamic categories from Riverpod state
    final state = ref.watch(furnitureProvider);
    final dynamicCategories = state.categories.map((c) => c.name).toList();
    final categories = dynamicCategories.isNotEmpty 
        ? dynamicCategories 
        : ['Living Room', 'Bedroom', 'Office', 'Kitchen', 'Dining Room', 'Bathroom'];

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(isEditMode ? 'Edit Furniture Asset' : 'Upload Furniture Asset'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isUploading
              ? null
              : () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/admin');
                  }
                },
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isLargeScreen)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _buildFormFields(isDark, categories)),
                        const SizedBox(width: 28),
                        Expanded(flex: 2, child: _buildPreviewColumn(isDark)),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildFormFields(isDark, categories),
                        const SizedBox(height: 28),
                        _buildPreviewColumn(isDark),
                      ],
                    ),
                  const SizedBox(height: 32),
                  PrimaryButton(
                    text: isEditMode ? 'Save Furniture Changes' : 'Publish Furniture Asset',
                    onPressed: _isUploading ? null : _submitForm,
                  ),
                ],
              ),
            ),
          ),
          if (_isUploading) _buildUploadProgressOverlay(isDark, isEditMode),
        ],
      ),
    );
  }

  Widget _buildFormFields(bool isDark, List<String> categories) {
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB);

    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Furniture Metadata',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppTheme.primary[900],
              ),
            ),
            const SizedBox(height: 16),
            
            // Name
            TextFormField(
              controller: _nameController,
              enabled: !_isUploading,
              decoration: const InputDecoration(
                labelText: 'Furniture Name',
                prefixIcon: Icon(Icons.title),
                hintText: 'e.g. Ergonomic Office Chair',
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Name is required';
                if (val.trim().length < 3) return 'Name is too short';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Style & Category Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedStyle,
                    decoration: const InputDecoration(
                      labelText: 'Style Theme',
                      prefixIcon: Icon(Icons.style),
                    ),
                    items: _styles.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: _isUploading ? null : (val) => setState(() => _selectedStyle = val!),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _isCustomCategory ? 'CUSTOM' : _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category),
                    ),
                    items: [
                      ...categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                      const DropdownMenuItem(value: 'CUSTOM', child: Text('+ Custom Category')),
                    ],
                    onChanged: _isUploading 
                        ? null 
                        : (val) {
                            setState(() {
                              if (val == 'CUSTOM') {
                                _isCustomCategory = true;
                              } else {
                                _isCustomCategory = false;
                                _selectedCategory = val!;
                              }
                            });
                          },
                  ),
                ),
              ],
            ),
            if (_isCustomCategory) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _customCategoryController,
                enabled: !_isUploading,
                decoration: const InputDecoration(
                  labelText: 'Custom Category Name',
                  prefixIcon: Icon(Icons.add_box),
                  hintText: 'e.g. Patio, Outdoor, Gym',
                ),
                validator: (val) {
                  if (_isCustomCategory && (val == null || val.trim().isEmpty)) {
                    return 'Custom category name is required';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 24),

            Text(
              'Dimensions (in cm)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.grey[400] : Colors.grey[700],
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Width, Depth, Height Row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _widthController,
                    enabled: !_isUploading,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                    decoration: const InputDecoration(labelText: 'Width'),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Req';
                      final d = double.tryParse(val);
                      if (d == null || d <= 0) return '> 0';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _depthController,
                    enabled: !_isUploading,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                    decoration: const InputDecoration(labelText: 'Depth'),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Req';
                      final d = double.tryParse(val);
                      if (d == null || d <= 0) return '> 0';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _heightController,
                    enabled: !_isUploading,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                    decoration: const InputDecoration(labelText: 'Height'),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Req';
                      final d = double.tryParse(val);
                      if (d == null || d <= 0) return '> 0';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Text(
              'Clearance Tolerances (in cm)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.grey[400] : Colors.grey[700],
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Clearance and Assembly clearance
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _clearanceController,
                    enabled: !_isUploading,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                    decoration: const InputDecoration(
                      labelText: 'Passage Clearance',
                      hintText: 'e.g. 50',
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Required';
                      final d = double.tryParse(val);
                      if (d == null || d < 0) return 'Must be >= 0';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _assemblyController,
                    enabled: !_isUploading,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                    decoration: const InputDecoration(
                      labelText: 'Assembly Clearance',
                      hintText: 'e.g. 10',
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Required';
                      final d = double.tryParse(val);
                      if (d == null || d < 0) return 'Must be >= 0';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tags
            TextFormField(
              controller: _tagsController,
              enabled: !_isUploading,
              decoration: const InputDecoration(
                labelText: 'Search Tags (comma separated)',
                prefixIcon: Icon(Icons.tag),
                hintText: 'e.g. wood, ergonomic, heavy-duty',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewColumn(bool isDark) {
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // GLB Picker Card
        Card(
          color: cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '3D Model File (.glb)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.primary[900],
                      ),
                    ),
                    const Icon(Icons.view_in_ar, color: AppTheme.primary),
                  ],
                ),
                const SizedBox(height: 16),
                
                if (_glbFile != null && _glbMetadata != null) ...[
                  // File details
                  _buildFileIndicator(
                    name: _glbFile!.name,
                    size: _glbFile!.size,
                    onClear: () {
                      setState(() {
                        _glbFile = null;
                        _glbBytes = null;
                        _glbMetadata = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Simulated 3D rotating preview
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _rotationController,
                          builder: (context, child) {
                            return CustomPaint(
                              size: const Size(100, 100),
                              painter: _Mock3DWireframePainter(
                                rotationAngle: _rotationController.value * 2 * pi,
                                isDark: isDark,
                              ),
                            );
                          },
                        ),
                        Positioned(
                          bottom: 8,
                          left: 12,
                          child: Text(
                            'Simulated mesh bounding box',
                            style: TextStyle(fontSize: 10, color: Colors.grey[500], fontStyle: FontStyle.italic),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'VERIFIED',
                              style: TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Binary attributes
                  _buildPreviewRow('glTF version', 'v${_glbMetadata!.gltfVersion}'),
                  _buildPreviewRow('Generator Tool', _glbMetadata!.generator),
                  _buildPreviewRow('Meshes / Nodes', '${_glbMetadata!.meshesCount} mesh(es) / ${_glbMetadata!.nodesCount} node(s)'),
                  _buildPreviewRow('Materials / Textures', '${_glbMetadata!.materialsCount} / ${_glbMetadata!.texturesCount}'),
                ] else ...[
                  if (widget.existingAsset?.glbUrl != null && widget.existingAsset!.glbUrl.isNotEmpty && _glbFile == null) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        'Current GLB: ${widget.existingAsset!.glbUrl}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                  OutlinedButton.icon(
                    onPressed: _isUploading ? null : _pickGlbFile,
                    icon: const Icon(Icons.file_open),
                    label: const Text('Choose GLB File'),
                  ),
                  if (_glbValidationError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _glbValidationError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ]
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Thumbnail Picker Card
        Card(
          color: cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Thumbnail Image',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.primary[900],
                      ),
                    ),
                    const Icon(Icons.image_outlined, color: AppTheme.primary),
                  ],
                ),
                const SizedBox(height: 16),

                if (_thumbnailFile != null && _thumbnailBytes != null) ...[
                  _buildFileIndicator(
                    name: _thumbnailFile!.name,
                    size: _thumbnailFile!.size,
                    onClear: () {
                      setState(() {
                        _thumbnailFile = null;
                        _thumbnailBytes = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Local Image Preview
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 1.5,
                      child: Container(
                        color: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                        child: Image.memory(
                          _thumbnailBytes!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  if (widget.existingAsset?.thumbnailUrl != null && widget.existingAsset!.thumbnailUrl.isNotEmpty && _thumbnailFile == null) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        'Current Thumbnail: ${widget.existingAsset!.thumbnailUrl}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                  OutlinedButton.icon(
                    onPressed: _isUploading ? null : _pickThumbnailFile,
                    icon: const Icon(Icons.add_photo_alternate),
                    label: const Text('Choose Image File'),
                  ),
                  if (_thumbnailValidationError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _thumbnailValidationError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ]
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Preview Image Picker Card
        Card(
          color: cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Preview Image (Optional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.primary[900],
                      ),
                    ),
                    const Icon(Icons.preview_rounded, color: AppTheme.primary),
                  ],
                ),
                const SizedBox(height: 16),

                if (_previewFile != null && _previewBytes != null) ...[
                  _buildFileIndicator(
                    name: _previewFile!.name,
                    size: _previewFile!.size,
                    onClear: () {
                      setState(() {
                        _previewFile = null;
                        _previewBytes = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Local Image Preview
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 1.5,
                      child: Container(
                        color: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                        child: Image.memory(
                          _previewBytes!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  if (widget.existingAsset?.previewUrl != null && _previewFile == null) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        'Current Preview: ${widget.existingAsset!.previewUrl}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                  OutlinedButton.icon(
                    onPressed: _isUploading ? null : _pickPreviewFile,
                    icon: const Icon(Icons.add_photo_alternate),
                    label: const Text('Choose Preview Image'),
                  ),
                  if (_previewValidationError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _previewValidationError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ]
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileIndicator({required String name, required int size, required VoidCallback onClear}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  '${(size / 1024).toStringAsFixed(1)} KB',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            onPressed: _isUploading ? null : onClear,
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadProgressOverlay(bool isDark, bool isEditMode) {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 4),
              ),
              const SizedBox(height: 24),
              Text(
                isEditMode ? 'Updating Asset' : 'Publishing Asset',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.primary[900],
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _uploadProgress,
                backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.grey[200],
                color: AppTheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                _uploadStatusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              
              // Step Indicators
              _buildStepRow(1, isEditMode ? 'Update metadata' : 'Duplicate check', _uploadStep > 1, _uploadStep == 1),
              _buildStepRow(2, isEditMode ? 'Updated schema' : 'Create asset schema', _uploadStep > 2, _uploadStep == 2),
              _buildStepRow(3, 'Upload GLB model', _uploadStep > 3, _uploadStep == 3),
              _buildStepRow(4, 'Upload thumbnail image', _uploadStep > 4, _uploadStep == 4),
              _buildStepRow(5, 'Upload preview image', _uploadStep > 5, _uploadStep == 5),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow(int step, String label, bool isDone, bool isActive) {
    Color labelColor = Colors.grey;
    Widget icon = const Icon(Icons.circle_outlined, size: 16, color: Colors.grey);

    if (isDone) {
      labelColor = Colors.green;
      icon = const Icon(Icons.check_circle, size: 16, color: Colors.green);
    } else if (isActive) {
      labelColor = AppTheme.primary;
      icon = const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(width: 24, child: Center(child: icon)),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Painter to draw a rotating 3D wireframe box
class _Mock3DWireframePainter extends CustomPainter {
  final double rotationAngle;
  final bool isDark;

  _Mock3DWireframePainter({required this.rotationAngle, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double r = size.width * 0.25;

    // Define 8 vertices of a cube
    final vertices = [
      Offset3D(-1, -1, -1),
      Offset3D(1, -1, -1),
      Offset3D(1, 1, -1),
      Offset3D(-1, 1, -1),
      Offset3D(-1, -1, 1),
      Offset3D(1, -1, 1),
      Offset3D(1, 1, 1),
      Offset3D(-1, 1, 1),
    ];

    // Rotate vertices around Y axis and X axis (isometric angle)
    final rotated2D = vertices.map((v) {
      // Y-axis rotation
      double x = v.x * cos(rotationAngle) - v.z * sin(rotationAngle);
      double z = v.x * sin(rotationAngle) + v.z * cos(rotationAngle);
      double y = v.y;

      // X-axis rotation (pitch/isometric angle)
      final pitch = 0.5;
      double yRot = y * cos(pitch) - z * sin(pitch);
      
      // Project to 2D
      return Offset(cx + x * r, cy + yRot * r);
    }).toList();

    // Draw edges
    final edges = [
      [0, 1], [1, 2], [2, 3], [3, 0], // Back face
      [4, 5], [5, 6], [6, 7], [7, 4], // Front face
      [0, 4], [1, 5], [2, 6], [3, 7], // Connecting edges
    ];

    for (final edge in edges) {
      canvas.drawLine(rotated2D[edge[0]], rotated2D[edge[1]], paint);
    }

    // Draw little circles at vertices
    final vertexPaint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.fill;
      
    for (final pt in rotated2D) {
      canvas.drawCircle(pt, 3, vertexPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _Mock3DWireframePainter oldDelegate) {
    return oldDelegate.rotationAngle != rotationAngle || oldDelegate.isDark != isDark;
  }
}

class Offset3D {
  final double x;
  final double y;
  final double z;

  Offset3D(this.x, this.y, this.z);
}
