// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/designer_provider.dart';
import '../../providers/design_score_provider.dart';
import '../../providers/validation_provider.dart';
import '../../providers/camera_provider.dart';
import '../../../project/providers/project_provider.dart';
import '../../../room/providers/room_provider.dart';
import '../../../../app/themes/app_theme.dart';

// ─── Color palette (aligned with 04_COLOR_PALETTE.md) ──────────────────────────
const _kSurface = Color(0xFF111827); // Dark Theme Surface
const _kBorder = Color(0xFF334155); // Dark Theme Border
const _kAccent = Color(0xFF0F766E); // Brand Primary
const _kTextPrimary = Color(0xFFF8FAFC); // Dark Theme Primary Text
const _kTextSecondary = Color(0xFF94A3B8); // Dark Theme Secondary Text

/// Bottom status bar for the Designer screen.
///
/// Displays (left → center → right):
///   LEFT: Current Project | Current Room | Selected Object
///   CENTER: Camera Position | Zoom Level | Grid Status | Snap Status
///   RIGHT: Design Score | Validation Status | Auto Save Status | FPS (Developer Mode only)
class DesignerStatusBar extends ConsumerWidget {
  final String roomId;
  final DesignerLayoutState layout;
  final DesignScoreState scoreState;
  final ValidationState validationState;
  final double zoomLevel;
  final Offset? mouseCanvasPos;
  final VoidCallback? onScoreTap;
  final bool is3DMode;
  final bool showGrid;
  final String autoSaveStatus;
  final Offset translation2D;

  const DesignerStatusBar({
    super.key,
    required this.roomId,
    required this.layout,
    required this.scoreState,
    required this.validationState,
    required this.zoomLevel,
    this.mouseCanvasPos,
    this.onScoreTap,
    required this.is3DMode,
    required this.showGrid,
    required this.autoSaveStatus,
    required this.translation2D,
  });

  // ── helpers ─────────────────────────────────────────────────────────────────

  /// Friendly label for whatever is currently selected.
  String _selectedLabel() {
    if (layout.selectedFurnitureId != null) {
      try {
        final f = layout.furniture
            .firstWhere((f) => f.id == layout.selectedFurnitureId);
        return f.name;
      } catch (_) {}
    }
    if (layout.selectedOpeningId != null) {
      try {
        final op = layout.openings
            .firstWhere((o) => o.id == layout.selectedOpeningId);
        return '${op.type == 'door' ? 'Door' : 'Window'} #${op.id.substring(0, 4)}';
      } catch (_) {}
    }
    if (layout.selectedWallIndex != null) {
      return 'Wall #${layout.selectedWallIndex}';
    }
    return 'No Selection'; // Placeholder when nothing is selected
  }

  bool get _hasSelection =>
      layout.selectedFurnitureId != null ||
      layout.selectedOpeningId != null ||
      layout.selectedWallIndex != null;

  String _truncate(String str, int maxLen) {
    if (str.length <= maxLen) return str;
    return '${str.substring(0, maxLen)}…';
  }

  // ── validation summary ───────────────────────────────────────────────────────

  _StatusData _validationChip() {
    final summary = validationState.summary;
    if (validationState.isLoading) {
      return _StatusData(
        label: 'Validation: Syncing…',
        color: AppTheme.warning,
        icon: Icons.sync,
      );
    }
    if (summary == null && validationState.errors.isEmpty && validationState.warnings.isEmpty) {
      return _StatusData(
        label: 'Validation: Unvalidated',
        color: _kTextSecondary,
        icon: Icons.help_outline,
      );
    }

    final hasErrors = validationState.errors.isNotEmpty || (summary?.errorCount ?? 0) > 0;
    final hasWarnings = validationState.warnings.isNotEmpty || (summary?.warningCount ?? 0) > 0;

    if (hasErrors) {
      // Check for specific error types
      final bool hasCollision = validationState.errors.any((e) =>
          e.ruleId == 'RULE_COLLISION' ||
          e.ruleName.toLowerCase() == 'collision detection' ||
          (e.ruleName.toLowerCase().contains('collision') && !e.ruleName.toLowerCase().contains('wall')));
      
      final bool hasWallCollision = validationState.errors.any((e) =>
          e.ruleId == 'RULE_WALL' ||
          e.ruleName.toLowerCase().contains('wall collision') ||
          (e.ruleName.toLowerCase().contains('wall') && e.category.toLowerCase() == 'safety'));

      final bool hasDoorError = validationState.errors.any((e) =>
          e.ruleId == 'RULE_DOOR' ||
          e.ruleName.toLowerCase().contains('door'));

      final bool hasFireEscapeError = validationState.errors.any((e) =>
          e.ruleId == 'RULE_FIRE_ESCAPE' ||
          e.ruleName.toLowerCase().contains('fire escape') ||
          e.ruleName.toLowerCase().contains('fire'));

      final bool hasWalkwayError = validationState.errors.any((e) =>
          e.ruleId == 'RULE_WALKWAY' ||
          e.ruleName.toLowerCase().contains('walkway'));

      String label;
      if (hasCollision) {
        label = '🔴 COLLISION';
      } else if (hasWallCollision) {
        label = '🔴 WALL COLLISION';
      } else if (hasDoorError) {
        label = '🔴 DOORWAY BLOCKED';
      } else if (hasFireEscapeError) {
        label = '🔴 FIRE ESCAPE BLOCKED';
      } else if (hasWalkwayError) {
        label = '🔴 WALKWAY BLOCKED';
      } else if (validationState.errors.isNotEmpty) {
        label = '🔴 ${validationState.errors.first.ruleName.toUpperCase()}';
      } else {
        label = '🔴 VALIDATION ERROR';
      }

      return _StatusData(
        label: label,
        color: AppTheme.error,
        icon: Icons.cancel_outlined,
      );
    } else if (hasWarnings) {
      final firstWarning = validationState.warnings.isNotEmpty ? validationState.warnings.first : null;
      String label = '🟡 ERGONOMIC WARNING';
      if (firstWarning != null) {
        if (firstWarning.category.toLowerCase() == 'circulation' || firstWarning.ruleName.toLowerCase().contains('walkway')) {
          label = '🟡 WALKWAY WARNING';
        } else if (firstWarning.category.toLowerCase() == 'accessibility' || firstWarning.ruleName.toLowerCase().contains('accessibility')) {
          label = '🟡 ACCESSIBILITY WARNING';
        } else if (firstWarning.category.toLowerCase() == 'safety' || firstWarning.ruleName.toLowerCase().contains('safety') || firstWarning.ruleName.toLowerCase().contains('fire')) {
          label = '🟡 SAFETY WARNING';
        } else if (firstWarning.ruleName.toLowerCase().contains('door')) {
          label = '🟡 DOORWAY WARNING';
        } else if (firstWarning.ruleName.isNotEmpty) {
          label = '🟡 ${firstWarning.ruleName.toUpperCase()}';
        }
      }

      return _StatusData(
        label: label,
        color: AppTheme.warning,
        icon: Icons.warning_amber_rounded,
      );
    } else {
      return _StatusData(
        label: '🟢 SAFE',
        color: AppTheme.success,
        icon: Icons.check_circle_outline,
      );
    }
  }

  // ── score ────────────────────────────────────────────────────────────────────

  Color _scoreColor(double score) {
    if (score >= 80) return AppTheme.success;
    if (score >= 50) return AppTheme.warning;
    return AppTheme.error;
  }

  // ── auto save ────────────────────────────────────────────────────────────────

  _StatusData _autoSaveChip() {
    switch (autoSaveStatus) {
      case 'Saving':
        return _StatusData(
          label: 'Auto Save: Saving…',
          color: AppTheme.warning,
          icon: Icons.cloud_sync_outlined,
        );
      case 'Error':
        return _StatusData(
          label: 'Auto Save: Error',
          color: AppTheme.error,
          icon: Icons.cloud_off_outlined,
        );
      case 'Saved':
      default:
        return _StatusData(
          label: 'Auto Save: Saved',
          color: AppTheme.success,
          icon: Icons.cloud_done_outlined,
        );
    }
  }

  // ── build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ── LEFT: Project & Room data retrieval
    final roomDetails = ref.watch(roomDetailsProvider).details;
    final String roomName = roomDetails?['room_name'] ?? '—';
    final String? projectId = roomDetails?['project_id'];

    final projectState = ref.watch(projectProvider);
    final dynamic project = projectState.projects.firstWhere(
      (p) => p['id'] == projectId,
      orElse: () => null,
    );
    final String projectName = project?['project_name'] ?? '—';

    // ── CENTER: Camera status retrieval
    final cameraState = ref.watch(cameraProvider);
    String cameraPosStr;
    String zoomStr;

    if (is3DMode) {
      cameraPosStr = 'Cam: X:${cameraState.position.x.round()} Y:${cameraState.position.y.round()} Z:${cameraState.position.z.round()}';
      zoomStr = 'Zoom: ${(90000 / cameraState.orbitRadius).round()}%';
    } else {
      cameraPosStr = 'Cam: X:${translation2D.dx.round()} Y:${translation2D.dy.round()}';
      zoomStr = 'Zoom: ${(zoomLevel * 100).round()}%';
    }

    // ── RIGHT: Design Score, Validation, Auto Save, FPS
    final score = scoreState.scores?.overallScore;
    final scoreColor = score != null ? _scoreColor(score) : _kTextSecondary;
    final valData = _validationChip();
    final autoSaveData = _autoSaveChip();

    final isDevMode = ref.watch(developerModeProvider);
    final fps = ref.watch(designerFpsProvider);
    final fpsColor = fps >= 55 ? AppTheme.success : (fps >= 30 ? AppTheme.warning : AppTheme.error);

    return GestureDetector(
      onDoubleTap: () {
        final newMode = !ref.read(developerModeProvider);
        ref.read(developerModeProvider.notifier).setMode(newMode);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newMode
                  ? 'Developer Mode Enabled (FPS Counter visible)'
                  : 'Developer Mode Disabled',
            ),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Container(
        height: 36,
        decoration: const BoxDecoration(
          color: _kSurface,
          border: Border(top: BorderSide(color: _kBorder, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // ─── LEFT COLUMN: Project, Room, Selection ─────────────────────
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusChip(
                        icon: Icons.folder_open_outlined,
                        label: 'Project: ',
                        value: _truncate(projectName, 15),
                        color: _kTextSecondary,
                      ),
                      _StatusDivider(),
                      _StatusChip(
                        icon: Icons.meeting_room_outlined,
                        label: 'Room: ',
                        value: _truncate(roomName, 15),
                        color: _kTextSecondary,
                      ),
                      _StatusDivider(),
                      _StatusChip(
                        icon: _hasSelection
                            ? Icons.category_outlined
                            : Icons.check_box_outline_blank,
                        label: 'Selected: ',
                        value: _truncate(_selectedLabel(), 15),
                        color: _hasSelection ? AppTheme.success : _kTextSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ─── CENTER COLUMN: Camera, Zoom, Grid, Snap ───────────────────
            Expanded(
              flex: 4,
              child: Align(
                alignment: Alignment.center,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusChip(
                        icon: Icons.videocam_outlined,
                        label: cameraPosStr,
                        color: _kTextSecondary,
                        monospace: true,
                      ),
                      _StatusDivider(),
                      _StatusChip(
                        icon: Icons.zoom_in,
                        label: zoomStr,
                        color: _kTextSecondary,
                      ),
                      _StatusDivider(),
                      _StatusChip(
                        icon: showGrid ? Icons.grid_on : Icons.grid_off,
                        label: 'Grid: ${showGrid ? "On" : "Off"}',
                        color: showGrid ? AppTheme.success : _kTextSecondary,
                      ),
                      _StatusDivider(),
                      _StatusChip(
                        icon: layout.snapToGrid ? Icons.electric_bolt_outlined : Icons.flash_off_outlined,
                        label: 'Snap: ${layout.snapToGrid ? "On" : "Off"}',
                        color: layout.snapToGrid ? AppTheme.success : _kTextSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ─── RIGHT COLUMN: Score, Validation, Auto Save, FPS ───────────
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      scoreState.isLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: _kAccent,
                              ),
                            )
                          : _StatusChip(
                              icon: Icons.auto_awesome,
                              label: score != null
                                  ? 'Score: ${score.round()}/100'
                                  : 'Score: —',
                              color: scoreColor,
                              onTap: onScoreTap,
                            ),
                      _StatusDivider(),
                      _StatusChip(
                        icon: valData.icon,
                        label: valData.label,
                        color: valData.color,
                      ),
                      _StatusDivider(),
                      _StatusChip(
                        icon: autoSaveData.icon,
                        label: autoSaveData.label,
                        color: autoSaveData.color,
                      ),
                      if (isDevMode) ...[
                        _StatusDivider(),
                        _StatusChip(
                          icon: Icons.speed_outlined,
                          label: 'FPS: $fps',
                          color: fpsColor,
                          monospace: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Small internal widgets ───────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final Color color;
  final bool monospace;
  final VoidCallback? onTap;

  const _StatusChip({
    required this.icon,
    required this.label,
    this.value,
    required this.color,
    this.monospace = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: color,
            fontWeight: FontWeight.w500,
            fontFamily: monospace ? 'monospace' : null,
          ),
        ),
        if (value != null)
          Text(
            value!,
            style: TextStyle(
              fontSize: 10.5,
              color: color == _kTextSecondary ? _kTextPrimary : color,
              fontWeight: FontWeight.bold,
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: content,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: content,
    );
  }
}

class _StatusDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 14,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: _kBorder,
      );
}

// ── Helper Data Class ─────────────────────────────────────────────────────────

class _StatusData {
  final String label;
  final Color color;
  final IconData icon;

  _StatusData({
    required this.label,
    required this.color,
    required this.icon,
  });
}
