import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/themes/app_theme.dart';
import '../../../../shared/widgets/snackbar_manager.dart';
import '../../../room/providers/room_provider.dart';
import '../../data/ai_api_client.dart';
import '../../providers/designer_provider.dart';
import 'ai_candidates_comparison_dialog.dart';

// ─── Dark Theme Color Tokens ──────────────────────────────────────────────────
const _kSurface = Color(0xFF111827);
const _kSurfaceElevated = Color(0xFF1E293B);
const _kBorder = Color(0xFF334155);
const _kAccent = Color(0xFF0F766E);
const _kAccentLight = Color(0xFF5B5BD6);
const _kTextPrimary = Color(0xFFF8FAFC);
const _kTextSecondary = Color(0xFF94A3B8);

class AiDesignRequirementsDialog extends ConsumerStatefulWidget {
  final String roomId;
  final DesignerLayoutState layout;
  final DesignerNotifier notifier;

  const AiDesignRequirementsDialog({
    super.key,
    required this.roomId,
    required this.layout,
    required this.notifier,
  });

  @override
  ConsumerState<AiDesignRequirementsDialog> createState() =>
      _AiDesignRequirementsDialogState();
}

class _AiDesignRequirementsDialogState
    extends ConsumerState<AiDesignRequirementsDialog> {
  final AiApiClient _apiClient = AiApiClient();

  late String _roomType;
  late double _roomWidth;
  late double _roomLength;
  String _selectedStyle = 'Modern';
  String _colorPalette = 'Warm Woods';
  String _accessibilityProfile = 'Standard';
  String _regenerationMode = 'redesign'; // 'redesign', 'improve_layout', 'optimize_space', 'improve_style'
  bool _preserveLockedOnly = true;

  bool _isGenerating = false;
  String _generationStatus = 'Understanding your room';
  int _progressStep = 1;
  Timer? _pollingTimer;

  final List<String> _roomTypes = [
    'Kitchen',
    'Bedroom',
    'Living Room',
    'Dining Room',
    'Office',
    'Manager\'s Office',
    'Study',
    'Bathroom',
  ];

  final List<String> _styles = [
    'Modern',
    'Minimalist',
    'Scandinavian',
    'Contemporary',
    'Industrial',
    'Luxury',
  ];

  final List<String> _palettes = [
    'Warm Woods',
    'Neutral & Cream',
    'Dark Monochromatic',
    'Scandinavian Light',
    'Coastal Blue',
    'Earthy & Botanical',
  ];

  final List<Map<String, String>> _regenerationModes = [
    {
      'id': 'redesign',
      'title': 'Redesign Entire Room',
      'desc': 'Generates a fresh, optimal layout based on room type rules and constraints.'
    },
    {
      'id': 'improve_layout',
      'title': 'Improve Current Layout',
      'desc': 'Preserves suitable furniture and refines positions to improve ergonomics.'
    },
    {
      'id': 'optimize_space',
      'title': 'Optimize Space',
      'desc': 'Prioritizes maximum walkway circulation and efficient open floor area.'
    },
    {
      'id': 'improve_style',
      'title': 'Improve Style',
      'desc': 'Focuses on visual balance, focal point grouping, and aesthetic harmony.'
    },
  ];

  final List<String> _progressMessages = [
    'Understanding your room',
    'Selecting suitable furniture',
    'Designing the layout',
    'Checking clearances and collisions',
    'Preparing your design',
  ];

  @override
  void initState() {
    super.initState();
    // Read actual room type from project state - never infer or hardcode Living Room
    final roomDetails = ref.read(roomDetailsProvider).details;
    final rType = roomDetails?['room_type']?.toString().trim();
    if (rType != null && rType.isNotEmpty) {
      _roomType = rType;
    } else {
      _roomType = 'Kitchen';
    }

    _roomWidth = 600.0;
    _roomLength = 450.0;

    if (widget.layout.walls.isNotEmpty) {
      double maxX = 0;
      double maxY = 0;
      for (final w in widget.layout.walls) {
        if (w.start.dx > maxX) maxX = w.start.dx;
        if (w.end.dx > maxX) maxX = w.end.dx;
        if (w.start.dy > maxY) maxY = w.start.dy;
        if (w.end.dy > maxY) maxY = w.end.dy;
      }
      if (maxX > 100) _roomWidth = maxX;
      if (maxY > 100) _roomLength = maxY;
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _startGeneration() async {
    setState(() {
      _isGenerating = true;
      _progressStep = 1;
      _generationStatus = _progressMessages[0];
    });

    final preferences = <String>[];
    if (_accessibilityProfile == 'Spacious') preferences.add('more_spacious');
    if (_accessibilityProfile == 'Wheelchair') preferences.add('wheelchair_accessible');
    preferences.add('palette_$_colorPalette');

    final lockedFurnitureIds = widget.layout.furniture
        .where((f) => f.isLocked)
        .map((f) => f.id)
        .toList();

    try {
      final jobId = await _apiClient.generateLayout(
        widget.roomId,
        style: _selectedStyle,
        preferences: preferences,
        mode: _regenerationMode,
        lockedFurnitureIds: lockedFurnitureIds,
      );

      _pollJob(jobId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      SnackbarManager.showError(context, 'Failed to launch AI layout generation: $e');
    }
  }

  void _pollJob(String jobId) {
    int attempts = 0;
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      attempts++;
      if (attempts > 50) {
        timer.cancel();
        if (mounted) {
          setState(() => _isGenerating = false);
          SnackbarManager.showError(context, 'AI generation timed out. Please try again.');
        }
        return;
      }

      // Progress through user-facing stage messages
      if (attempts <= 5) {
        final msgIdx = attempts - 1;
        if (msgIdx < _progressMessages.length) {
          setState(() {
            _progressStep = msgIdx + 1;
            _generationStatus = _progressMessages[msgIdx];
          });
        }
      }

      try {
        final statusData = await _apiClient.getJobStatus(jobId);
        final status = (statusData['status'] as String?)?.toLowerCase() ?? '';

        if (!mounted) return;

        if (status == 'completed') {
          timer.cancel();
          final resultData = await _apiClient.getJobResult(jobId);
          if (!mounted) return;
          setState(() => _isGenerating = false);

          Navigator.of(context).pop(); // Close requirements modal

          // Open comparison dialog
          _showComparisonDialog(resultData);
        } else if (status == 'failed') {
          timer.cancel();
          setState(() => _isGenerating = false);
          final errorMsg = statusData['error'] ?? 'Layout generation failed.';
          SnackbarManager.showError(context, 'AI generation failed: $errorMsg');
        }
      } catch (e) {
        // Continue polling unless error repeats
      }
    });
  }

  void _showComparisonDialog(Map<String, dynamic> resultData) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AiCandidatesComparisonDialog(
        resultData: resultData,
        layout: widget.layout,
        notifier: widget.notifier,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _isGenerating ? _buildLoadingState() : _buildFormState(),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kAccentLight.withOpacity(0.15),
            border: Border.all(color: _kAccentLight, width: 2),
          ),
          child: const Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: _kAccentLight,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Generating Interior Design',
          style: TextStyle(
            color: _kTextPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _kSurfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: _kAccentLight),
              ),
              const SizedBox(width: 10),
              Text(
                '$_generationStatus...',
                style: const TextStyle(
                  color: _kTextPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Progress steps indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_progressMessages.length, (idx) {
            final isDone = idx < _progressStep;
            final isCurrent = idx == (_progressStep - 1);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isCurrent ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: isDone
                    ? _kAccentLight
                    : _kBorder,
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildFormState() {
    final lockedCount = widget.layout.furniture.where((f) => f.isLocked).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kAccentLight.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome, color: _kAccentLight, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.layout.furniture.isEmpty ? 'AI Interior Design Generation' : 'AI Design Regeneration',
                        style: const TextStyle(
                          color: _kTextPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _kAccent),
                        ),
                        child: Text(
                          _roomType.toUpperCase(),
                          style: const TextStyle(
                            color: _kAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Local Llama/Qwen reasoning engine with deterministic spatial validation',
                    style: TextStyle(color: _kTextSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: _kTextSecondary, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Divider(color: _kBorder, height: 1),
        const SizedBox(height: 14),

        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Locked furniture notice banner
                if (lockedCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kAccent),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock, color: _kAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$lockedCount locked furniture item(s) detected. Their coordinates and rotations will be strictly preserved.',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Regeneration Mode Selection
                _buildSectionHeader('GENERATION / REGENERATION MODE'),
                const SizedBox(height: 8),
                Column(
                  children: _regenerationModes.map((mode) {
                    final isSel = _regenerationMode == mode['id'];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: isSel ? _kAccentLight.withOpacity(0.15) : _kSurfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSel ? _kAccentLight : _kBorder,
                          width: isSel ? 1.5 : 1.0,
                        ),
                      ),
                      child: RadioListTile<String>(
                        value: mode['id']!,
                        groupValue: _regenerationMode,
                        onChanged: (val) => setState(() => _regenerationMode = val!),
                        activeColor: _kAccentLight,
                        dense: true,
                        title: Text(
                          mode['title']!,
                          style: TextStyle(
                            color: isSel ? Colors.white : _kTextPrimary,
                            fontSize: 12,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          mode['desc']!,
                          style: const TextStyle(color: _kTextSecondary, fontSize: 10.5),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // Room Type & Dimensions
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildDropdown(
                        label: 'Room Type (Hard Constraint)',
                        value: _roomTypes.contains(_roomType) ? _roomType : _roomTypes.first,
                        items: _roomTypes,
                        onChanged: (val) => setState(() => _roomType = val!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _buildReadOnlyField(
                        label: 'Dimensions',
                        value: '${_roomWidth.round()} × ${_roomLength.round()} cm',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Interior Style
                _buildSectionHeader('INTERIOR STYLE'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _styles.map((style) {
                    final isSelected = _selectedStyle == style;
                    return ChoiceChip(
                      label: Text(style),
                      selected: isSelected,
                      selectedColor: _kAccent,
                      backgroundColor: _kSurfaceElevated,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : _kTextSecondary,
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color: isSelected ? _kAccent : _kBorder,
                      ),
                      onSelected: (_) => setState(() => _selectedStyle = style),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Palette & Materials
                _buildSectionHeader('PALETTE & MATERIALS'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _palettes.map((p) {
                    final isSelected = _colorPalette == p;
                    return ChoiceChip(
                      label: Text(p),
                      selected: isSelected,
                      selectedColor: _kAccentLight,
                      backgroundColor: _kSurfaceElevated,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : _kTextSecondary,
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color: isSelected ? _kAccentLight : _kBorder,
                      ),
                      onSelected: (_) => setState(() => _colorPalette = p),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Usage & Accessibility Profile
                _buildSectionHeader('CIRCULATION & ACCESSIBILITY PROFILE'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildProfileCard(
                      'Standard',
                      'Normal living clearances (60cm+ pathways)',
                      Icons.accessibility_new,
                      _accessibilityProfile == 'Standard',
                      () => setState(() => _accessibilityProfile = 'Standard'),
                    ),
                    const SizedBox(width: 8),
                    _buildProfileCard(
                      'Spacious',
                      'Generous open floor & wide corridors (90cm+)',
                      Icons.open_in_full,
                      _accessibilityProfile == 'Spacious',
                      () => setState(() => _accessibilityProfile = 'Spacious'),
                    ),
                    const SizedBox(width: 8),
                    _buildProfileCard(
                      'Wheelchair',
                      'ADA compliant: 150cm turning & 90cm door flow',
                      Icons.accessible,
                      _accessibilityProfile == 'Wheelchair',
                      () => setState(() => _accessibilityProfile = 'Wheelchair'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        const Divider(color: _kBorder, height: 1),
        const SizedBox(height: 16),

        // Action Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: _kTextSecondary)),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              icon: Icon(
                widget.layout.furniture.isEmpty ? Icons.auto_awesome : Icons.restart_alt,
                size: 16,
              ),
              label: Text(
                widget.layout.furniture.isEmpty ? 'Generate Layout' : 'Regenerate Design',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccentLight,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _startGeneration,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: _kTextSecondary,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(label.toUpperCase()),
        const SizedBox(height: 6),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _kSurfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: _kSurfaceElevated,
              style: const TextStyle(color: _kTextPrimary, fontSize: 12),
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(label.toUpperCase()),
        const SizedBox(height: 6),
        Container(
          height: 48,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _kSurfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorder),
          ),
          child: Text(
            value,
            style: const TextStyle(color: _kTextPrimary, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard(String title, String desc, IconData icon, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected ? _kAccent.withOpacity(0.15) : _kSurfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? _kAccent : _kBorder, width: isSelected ? 1.5 : 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: isSelected ? _kAccent : _kTextSecondary),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : _kTextPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _kTextSecondary, fontSize: 9.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
