import '../../../app/themes/app_theme.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';

/// Step 6 – Review & Create
///
/// Displays a summary of all room configuration entered across steps 1–5,
/// then lets the user go back or finalise the room and navigate to the Designer.
class ReviewStep extends StatelessWidget {
  // ── Step 1 ─────────────────────────────────────────────────────────────────
  final String roomName;
  final String roomType;
  final int floorNumber;
  final String roomColor;
  final String notes;

  // ── Step 2 ─────────────────────────────────────────────────────────────────
  final String? panoramaUrl;
  final bool panoramaSkipped;

  // ── Step 3 ─────────────────────────────────────────────────────────────────
  final String length;
  final String width;
  final String height;
  final String doors;
  final String windows;
  final bool isMetric;

  // ── Step 4 ─────────────────────────────────────────────────────────────────
  final String? selectedStyle;

  // ── Step 5 AI summary ──────────────────────────────────────────────────────
  final String? aiSummary;

  // ── Actions ────────────────────────────────────────────────────────────────
  final VoidCallback onBack;
  final VoidCallback onCreateRoom;
  final bool isLoading;

  const ReviewStep({
    super.key,
    required this.roomName,
    required this.roomType,
    required this.floorNumber,
    required this.roomColor,
    required this.notes,
    this.panoramaUrl,
    required this.panoramaSkipped,
    required this.length,
    required this.width,
    required this.height,
    required this.doors,
    required this.windows,
    required this.isMetric,
    this.selectedStyle,
    this.aiSummary,
    required this.onBack,
    required this.onCreateRoom,
    this.isLoading = false,
  });

  // ── helpers ────────────────────────────────────────────────────────────────

  Color get _roomColorValue {
    try {
      final hex = roomColor.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppTheme.primary;
    }
  }

  String get _unit => isMetric ? 'm' : 'ft';

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primary.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '\u2014' : value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  // ── Sections ───────────────────────────────────────────────────────────────

  Widget _buildRoomDetails() {
    return _card([
      _sectionHeader('Room Details', Icons.meeting_room_outlined),
      const SizedBox(height: 16),
      _infoRow('Name', roomName),
      _infoRow('Type', roomType),
      _infoRow('Floor', floorNumber == 0 ? 'Ground Floor' : 'Floor $floorNumber'),
      if (notes.isNotEmpty) _infoRow('Notes', notes),
      const SizedBox(height: 12),
      Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              'Accent Color',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: _roomColorValue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade300),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            roomColor.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _buildPanorama() {
    return _card([
      _sectionHeader('Spatial Room Capture', Icons.explore_outlined),
      const SizedBox(height: 16),
      if (panoramaSkipped || panoramaUrl == null || panoramaUrl!.isEmpty) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 20, color: Colors.orange.shade600),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Panorama could not be reconstructed or was skipped.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'The room geometry will be generated procedurally from measurements (AI-Assisted Layout).',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ] else ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 120,
            width: double.infinity,
            color: Colors.grey.shade100,
            child: Image.network(
              panoramaUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, e, s) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.explore_outlined, size: 36, color: Colors.grey.shade400),
                    const SizedBox(height: 4),
                    Text(
                      'Spatial Room Model loaded',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          panoramaUrl!,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade500,
            overflow: TextOverflow.ellipsis,
          ),
          maxLines: 1,
        ),
      ],
    ]);
  }

  Widget _buildMeasurements() {
    final hasAny = length.isNotEmpty || width.isNotEmpty || height.isNotEmpty;
    return _card([
      _sectionHeader('Measurements', Icons.straighten_outlined),
      const SizedBox(height: 16),
      if (!hasAny)
        Text(
          'No measurements entered',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        )
      else ...[
        if (length.isNotEmpty) _infoRow('Length', '$length $_unit'),
        if (width.isNotEmpty) _infoRow('Width', '$width $_unit'),
        if (height.isNotEmpty) _infoRow('Height', '$height $_unit'),
        if (doors.isNotEmpty) _infoRow('Doors', doors),
        if (windows.isNotEmpty) _infoRow('Windows', windows),
        _infoRow('Unit System', isMetric ? 'Metric (m)' : 'Imperial (ft)'),
      ],
    ]);
  }

  Widget _buildStyle() {
    return _card([
      _sectionHeader('Interior Style', Icons.palette_outlined),
      const SizedBox(height: 16),
      if (selectedStyle == null)
        Text(
          'No style selected',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        )
      else
        Wrap(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primary.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 16, color: AppTheme.primary.shade700),
                  const SizedBox(width: 6),
                  Text(
                    selectedStyle!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
    ]);
  }

  Widget _buildAISummary() {
    final summary = (aiSummary != null && aiSummary!.isNotEmpty)
        ? aiSummary!
        : 'AI layout analysis will be applied when the room opens in the Designer.';

    return _card([
      _sectionHeader('AI Summary', Icons.auto_awesome_outlined),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primary.shade50.withValues(alpha: 0.6),
              Colors.indigo.shade50.withValues(alpha: 0.4),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary.shade100),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_awesome, size: 18, color: AppTheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                summary,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── scrollable body ────────────────────────────────────────────────
        Expanded(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 750),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero banner
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary.shade700,
                            AppTheme.primary.shade500,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.checklist_rtl_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Review Your Room',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Check your configuration before creating the room.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Section cards
                    _buildRoomDetails(),
                    const SizedBox(height: 14),
                    _buildPanorama(),
                    const SizedBox(height: 14),
                    _buildMeasurements(),
                    const SizedBox(height: 14),
                    _buildStyle(),
                    const SizedBox(height: 14),
                    _buildAISummary(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── sticky bottom action bar ───────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
            border: Border(
              top: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Row(
            children: [
              SecondaryButton(
                text: 'Back',
                onPressed: isLoading ? null : onBack,
              ),
              const Spacer(),
              PrimaryButton(
                text: 'Create Room',
                isLoading: isLoading,
                onPressed: onCreateRoom,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
