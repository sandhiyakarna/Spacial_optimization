import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/snackbar_manager.dart';
import '../../providers/designer_provider.dart';
import '../../providers/camera_provider.dart';
import '../../../room/providers/room_provider.dart';
import '../../../project/providers/export_provider.dart';
import 'ai_design_requirements_dialog.dart';

// ─── Color tokens (aligned with 04_COLOR_PALETTE.md) ─────────────────────────────
const _kSurface = Color(0xFF111827); // Dark Theme Surface
const _kSurfaceElevated = Color(0xFF1E293B); // Dark Theme Card
const _kBorder = Color(0xFF334155); // Dark Theme Border
const _kAccent = Color(0xFF0F766E); // Brand Primary
const _kAccentLight = Color(0xFF5B5BD6); // Brand Secondary (AI)
const _kTextPrimary = Color(0xFFF8FAFC); // Dark Theme Primary Text
const _kTextSecondary = Color(0xFF94A3B8); // Dark Theme Secondary Text

// ═══════════════════════════════════════════════════════════════════════════════
//  Pulsing dot widget for Auto-save Status
// ═══════════════════════════════════════════════════════════════════════════════
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF10B981),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withOpacity(0.5 * _controller.value),
                blurRadius: 6 * _controller.value,
                spreadRadius: 2 * _controller.value,
              )
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Real Export Progress Dialog
// ═══════════════════════════════════════════════════════════════════════════════
class _RealExportProgressDialog extends ConsumerStatefulWidget {
  final String title;
  final String projectId;
  final String? roomId;
  final String reportType;
  final String format;
  final BuildContext parentContext;

  const _RealExportProgressDialog({
    required this.title,
    required this.projectId,
    required this.roomId,
    required this.reportType,
    required this.format,
    required this.parentContext,
  });

  @override
  ConsumerState<_RealExportProgressDialog> createState() => _RealExportProgressDialogState();
}

class _RealExportProgressDialogState extends ConsumerState<_RealExportProgressDialog> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(exportProvider.notifier).generateAndPollReport(
        projectId: widget.projectId,
        roomId: widget.roomId,
        reportType: widget.reportType,
        format: widget.format,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(exportProvider);

    ref.listen<ExportState>(exportProvider, (previous, next) {
      if (!next.isLoading && previous?.isLoading == true) {
        if (context.mounted) {
          Navigator.of(context).pop();
          if (next.errorMessage != null) {
            SnackbarManager.showError(widget.parentContext, 'Export failed: ${next.errorMessage}');
          } else if (next.downloadedBytes != null) {
            SnackbarManager.showSuccess(
              widget.parentContext,
              '${widget.format} exported successfully! (${next.downloadedBytes!.length} bytes)',
            );
          }
        }
      }
    });

    return AlertDialog(
      backgroundColor: _kSurfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _kBorder),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const CircularProgressIndicator(
              strokeWidth: 4,
              color: _kAccent,
              backgroundColor: _kBorder,
            ),
            const SizedBox(height: 24),
            Text(
              widget.title,
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              state.reportStatus ?? 'Initiating export...',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _kTextSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DesignerToolbar
// ═══════════════════════════════════════════════════════════════════════════════
class DesignerToolbar extends ConsumerWidget implements PreferredSizeWidget {
  final String roomId;
  final bool isEmbedded;
  final bool is3DMode;
  final bool showGrid;
  final bool leftSidebarOpen;
  final ViewMode viewMode;

  final DesignerLayoutState layout;
  final DesignerNotifier notifier;

  final VoidCallback onSave;
  final VoidCallback onToggle3D;
  final VoidCallback onToggleGrid;
  final VoidCallback onToggleLeftSidebar;
  final VoidCallback onBack;

  final bool isWalkthroughMode;
  final VoidCallback onToggleWalkthrough;

  // Connected workspaces fields
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final bool measurementsEnabled;
  final VoidCallback onToggleMeasurements;
  final bool showFurnitureLabels;
  final VoidCallback onToggleFurnitureLabels;
  final bool showDoors;
  final VoidCallback onToggleDoors;
  final bool showWindows;
  final VoidCallback onToggleWindows;
  final bool showDiagnostics;
  final VoidCallback onToggleDiagnostics;
  final String activeTransformTool;
  final ValueChanged<String> onChangeTransformTool;
  final String activeRightTab;
  final bool rightPanelOpen;
  final Function(String tab, bool open) onToggleRightPanel;

  const DesignerToolbar({
    super.key,
    required this.roomId,
    required this.isEmbedded,
    required this.is3DMode,
    required this.showGrid,
    required this.leftSidebarOpen,
    required this.viewMode,
    required this.layout,
    required this.notifier,
    required this.isWalkthroughMode,
    required this.onToggleWalkthrough,
    required this.onSave,
    required this.onToggle3D,
    required this.onToggleGrid,
    required this.onToggleLeftSidebar,
    required this.onBack,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    required this.measurementsEnabled,
    required this.onToggleMeasurements,
    required this.showFurnitureLabels,
    required this.onToggleFurnitureLabels,
    required this.showDoors,
    required this.onToggleDoors,
    required this.showWindows,
    required this.onToggleWindows,
    this.showDiagnostics = false,
    required this.onToggleDiagnostics,
    required this.activeTransformTool,
    required this.onChangeTransformTool,
    required this.activeRightTab,
    required this.rightPanelOpen,
    required this.onToggleRightPanel,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  // ─── Action Button builders ──────────────────────────────────────────────────
  Widget _buildCapsule({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: _kSurfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildCapsuleButton({
    required IconData icon,
    required String label,
    required String tooltip,
    required bool isActive,
    required VoidCallback onTap,
    Color? activeBgColor,
    Color? activeFgColor,
    bool isEnabled = true,
  }) {
    final activeBg = activeBgColor ?? _kAccent;
    final activeFg = activeFgColor ?? Colors.white;

    final displayLabel = isActive ? '$label ✓' : label;

    return Tooltip(
      message: tooltip,
      textStyle: const TextStyle(fontSize: 10, color: Colors.white),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: isEnabled ? 1.0 : 0.35,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isActive ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isActive ? activeFg : _kTextSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  displayLabel,
                  style: TextStyle(
                    color: isActive ? activeFg : _kTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Dropdowns & Presets ─────────────────────────────────────────────────────
  Widget _buildCameraPresetsMenu(BuildContext context, WidgetRef ref) {
    IconData activeIcon = Icons.videocam;
    switch (viewMode) {
      case ViewMode.perspective: activeIcon = Icons.streetview; break;
      case ViewMode.top: activeIcon = Icons.vertical_align_bottom; break;
      case ViewMode.front: activeIcon = Icons.crop_original; break;
      case ViewMode.left: activeIcon = Icons.subdirectory_arrow_left; break;
      default: activeIcon = Icons.videocam;
    }

    return PopupMenuButton<ViewMode>(
      enabled: is3DMode,
      tooltip: is3DMode ? 'Select Camera Preset Angle' : 'Camera controls only available in 3D Mode',
      color: _kSurfaceElevated,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kBorder),
      ),
      offset: const Offset(0, 40),
      child: Opacity(
        opacity: is3DMode ? 1.0 : 0.35,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(activeIcon, size: 16, color: _kTextPrimary),
              const SizedBox(width: 5),
              Text(
                _getViewModeLabel(viewMode),
                style: const TextStyle(
                  color: _kTextPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 14, color: _kTextSecondary),
            ],
          ),
        ),
      ),
      onSelected: (val) {
        ref.read(viewModeProvider.notifier).setMode(val);
        SnackbarManager.showSuccess(context, 'Camera Mode: ${_getViewModeLabel(val)}');
      },
      itemBuilder: (ctx) {
        return [
          _buildCameraMenuItem(ViewMode.perspective, 'Perspective View', Icons.streetview),
          _buildCameraMenuItem(ViewMode.top, 'Top View (Plan)', Icons.vertical_align_bottom),
          _buildCameraMenuItem(ViewMode.front, 'Front View (Elevation)', Icons.crop_original),
          _buildCameraMenuItem(ViewMode.left, 'Left View (Elevation)', Icons.subdirectory_arrow_left),
        ];
      },
    );
  }

  PopupMenuItem<ViewMode> _buildCameraMenuItem(ViewMode mode, String title, IconData icon) {
    final isSel = viewMode == mode;
    return PopupMenuItem<ViewMode>(
      value: mode,
      child: Row(
        children: [
          Icon(icon, size: 16, color: isSel ? _kAccent : _kTextSecondary),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              color: isSel ? _kTextPrimary : _kTextSecondary,
              fontSize: 12,
              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  String _getViewModeLabel(ViewMode mode) {
    switch (mode) {
      case ViewMode.perspective: return 'Perspective';
      case ViewMode.top:         return 'Top View';
      case ViewMode.front:       return 'Front View';
      case ViewMode.left:        return 'Left View';
      default:                   return 'Camera View';
    }
  }

  // ─── Screenshot / Export / Help Dialog Simulators ────────────────────────────
  void _simulateScreenshot(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.white.withOpacity(0.95), // White flash shutter animation
      barrierDismissible: false,
      builder: (ctx) {
        Future.delayed(const Duration(milliseconds: 180), () {
          if (ctx.mounted) {
            Navigator.of(ctx).pop();
            if (context.mounted) {
              SnackbarManager.showSuccess(context, 'Viewport snapshot saved to gallery!');
            }
          }
        });
        return const SizedBox.expand();
      },
    );
  }

  void _showExportImageDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _kSurfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: _kBorder),
          ),
          title: const Row(
            children: [
              Icon(Icons.image_outlined, color: _kAccent),
              SizedBox(width: 8),
              Text('Export Design Image', style: TextStyle(color: _kTextPrimary, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Resolution Ratio', style: TextStyle(color: _kTextSecondary, fontSize: 11)),
              const SizedBox(height: 8),
              Row(
                children: ['Standard (1080p)', 'HD (2K)', 'UHD (4K)'].map((res) {
                  final isSel = res.startsWith('Standard');
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: isSel ? _kAccent : Colors.transparent,
                          side: BorderSide(color: isSel ? _kAccent : _kBorder),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {},
                        child: Text(
                          res.split(' ').first,
                          style: TextStyle(color: isSel ? Colors.white : _kTextSecondary, fontSize: 11),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text('Format', style: TextStyle(color: _kTextSecondary, fontSize: 11)),
              const SizedBox(height: 8),
              Row(
                children: ['PNG (Lossless)', 'JPG (Standard)'].map((fmt) {
                  final isSel = fmt.startsWith('PNG');
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: isSel ? _kAccent : Colors.transparent,
                          side: BorderSide(color: isSel ? _kAccent : _kBorder),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {},
                        child: Text(
                          fmt.split(' ').first,
                          style: TextStyle(color: isSel ? Colors.white : _kTextSecondary, fontSize: 11),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: _kTextSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                final roomDetails = ref.read(roomDetailsProvider).details;
                final projectId = roomDetails?['project_id'];
                if (projectId == null) {
                  SnackbarManager.showError(context, 'Project context not found');
                  return;
                }
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialogCtx) => _RealExportProgressDialog(
                    title: 'Exporting Image',
                    projectId: projectId,
                    roomId: roomId,
                    reportType: 'Design Report',
                    format: 'PNG',
                    parentContext: context,
                  ),
                );
              },
              child: const Text('Export', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showExportPDFDialog(BuildContext context, WidgetRef ref) {
    final roomDetails = ref.read(roomDetailsProvider).details;
    final projectId = roomDetails?['project_id'];
    if (projectId == null) {
      SnackbarManager.showError(context, 'Project context not found');
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _RealExportProgressDialog(
        title: 'Generating Blueprint PDF Report',
        projectId: projectId,
        roomId: roomId,
        reportType: 'Design Report',
        format: 'PDF',
        parentContext: context,
      ),
    );
  }

  void _showShortcutsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final list = [
          {'key': 'Ctrl + Z', 'desc': 'Undo last modification'},
          {'key': 'Ctrl + Y', 'desc': 'Redo last undone action'},
          {'key': 'V', 'desc': 'Select / Translate Tool'},
          {'key': 'W', 'desc': 'Draw Wall Tool (2D)'},
          {'key': 'D', 'desc': 'Place Door Tool (2D)'},
          {'key': 'N', 'desc': 'Place Window Tool (2D)'},
          {'key': 'H', 'desc': 'Pan Canvas Tool (2D)'},
          {'key': 'F', 'desc': 'Toggle Fullscreen view'},
          {'key': 'G', 'desc': 'Toggle Background Grid'},
          {'key': 'M', 'desc': 'Toggle Measurement Lines'},
          {'key': 'Esc', 'desc': 'Clear Selection / Cancel Tool'},
        ];

        return AlertDialog(
          backgroundColor: _kSurfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: _kBorder),
          ),
          title: const Row(
            children: [
              Icon(Icons.keyboard_outlined, color: _kAccent),
              SizedBox(width: 8),
              Text('Keyboard Shortcuts', style: TextStyle(color: _kTextPrimary, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: list.length,
              separatorBuilder: (_, index) => const Divider(color: _kBorder, height: 1),
              itemBuilder: (context, index) {
                final item = list[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Text(
                          item['key']!,
                          style: const TextStyle(
                            color: _kAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item['desc']!,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: _kTextSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close', style: TextStyle(color: _kAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showTutorialsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final pages = [
          {
            'title': '1. Room Drafting (2D)',
            'desc': 'Draft rooms easily. Select the Draw Wall tool (W) and click on the canvas to place wall endpoints. Select the Place Door (D) or Window (N) tool to align openings onto existing walls.',
            'icon': Icons.architecture,
          },
          {
            'title': '2. Furnishing the Space',
            'desc': 'Open the Left Asset Library to explore catalog items. Drag and drop items directly onto the canvas. Use the Properties Inspector Panel on the right to customize dimensions, materials, color, metallic textures, and coordinates.',
            'icon': Icons.chair,
          },
          {
            'title': '3. 3D Spatial Walkthrough',
            'desc': 'Toggle into 3D Mode to experience your design in high fidelity. Switch view modes (Perspective, Top, Front) or select Walkthrough Mode (Free Flight) to explore the room manually using virtual joysticks or WASD keyboard controls.',
            'icon': Icons.view_in_ar,
          },
          {
            'title': '4. AI Suggestions & Rules',
            'desc': 'Access AI Features to calculate design optimization scores or generate room furnishing suggestions. Click "Validate Design" to run strict spatial rules validation (e.g. check for overlapping assets, walkway blocks, safety clearances).',
            'icon': Icons.auto_awesome,
          },
        ];

        return AlertDialog(
          backgroundColor: _kSurfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: _kBorder),
          ),
          title: const Row(
            children: [
              Icon(Icons.school, color: _kAccent),
              SizedBox(width: 8),
              Text('FlowSpace Tutorials', style: TextStyle(color: _kTextPrimary, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 400,
            height: 250,
            child: PageView.builder(
              itemCount: pages.length,
              itemBuilder: (context, index) {
                final page = pages[index];
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(page['icon'] as IconData, size: 44, color: _kAccent),
                    const SizedBox(height: 12),
                    Text(
                      page['title'] as String,
                      style: const TextStyle(color: _kTextPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Text(
                        page['desc'] as String,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _kTextSecondary, fontSize: 11.5, height: 1.35),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close', style: TextStyle(color: _kTextSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Get Started', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // ─── Build Method ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomDetails = ref.watch(roomDetailsProvider);
    final roomName = roomDetails.details?['room_name'] ?? 'Loading...';
    final roomType = roomDetails.details?['room_type'] ?? 'Room';

    return Container(
      height: preferredSize.height,
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 750;

          // Project Info Widget
          final projectWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isEmbedded) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 16, color: _kTextSecondary),
                  tooltip: 'Back to projects',
                  onPressed: onBack,
                ),
                const SizedBox(width: 4),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        roomName,
                        style: const TextStyle(
                          color: _kTextPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: _kBorder,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          roomType.toUpperCase(),
                          style: const TextStyle(
                            color: _kTextSecondary,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PulsingDot(),
                      SizedBox(width: 6),
                      Text(
                        'Synced to cloud',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );

          // Save / Sidebar triggers Right Section
          final rightActionWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCapsuleButton(
                icon: Icons.save_outlined,
                label: 'Save',
                tooltip: 'Commit manual save (Ctrl+S)',
                isActive: false,
                onTap: onSave,
              ),
            ],
          );

          // Build all tool capsules list
          final toolCapsules = [
            // 1. Edit capsule
            _buildCapsule(
              children: [
                _buildCapsuleButton(
                  icon: Icons.undo,
                  label: 'Undo',
                  tooltip: 'Undo changes (Ctrl+Z)',
                  isActive: false,
                  onTap: notifier.undo,
                ),
                _buildCapsuleButton(
                  icon: Icons.redo,
                  label: 'Redo',
                  tooltip: 'Redo changes (Ctrl+Y)',
                  isActive: false,
                  onTap: notifier.redo,
                ),
              ],
            ),
            // 1.5. AI Generate / Regenerate Design Capsule
            _buildCapsule(
              children: [
                _buildCapsuleButton(
                  icon: layout.furniture.isEmpty ? Icons.auto_awesome : Icons.restart_alt,
                  label: layout.furniture.isEmpty ? 'AI Generate' : 'Regenerate Design',
                  tooltip: layout.furniture.isEmpty
                      ? 'Generate intelligent room layout with local AI'
                      : 'Regenerate alternative room layout candidates with local AI',
                  isActive: true,
                  activeBgColor: const Color(0xFF5B5BD6),
                  activeFgColor: Colors.white,
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AiDesignRequirementsDialog(
                        roomId: roomId,
                        layout: layout,
                        notifier: notifier,
                      ),
                    );
                  },
                ),
              ],
            ),
            // 2. View Mode & Tools
            _buildCapsule(
              children: [
                _buildCapsuleButton(
                  icon: Icons.view_in_ar,
                  label: '3D View',
                  tooltip: 'Switch to 3D room environment',
                  isActive: is3DMode && !isWalkthroughMode,
                  onTap: () { if (!is3DMode) onToggle3D(); },
                ),
                _buildCapsuleButton(
                  icon: Icons.grid_on,
                  label: '2D View',
                  tooltip: 'Switch to 2D blueprint layout',
                  isActive: !is3DMode,
                  onTap: () { if (is3DMode) onToggle3D(); },
                ),
                _buildCapsuleButton(
                  icon: Icons.directions_walk,
                  label: 'Walkthrough',
                  tooltip: 'Start first-person room walkthrough',
                  isActive: isWalkthroughMode,
                  onTap: onToggleWalkthrough,
                ),
                _buildCapsuleButton(
                  icon: isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  label: 'Fullscreen',
                  tooltip: 'Maximize layout workspace (F)',
                  isActive: isFullscreen,
                  onTap: onToggleFullscreen,
                ),
                _buildCapsuleButton(
                  icon: showGrid ? Icons.grid_3x3 : Icons.grid_off,
                  label: 'Grid',
                  tooltip: 'Toggle canvas reference grid (G)',
                  isActive: showGrid,
                  onTap: onToggleGrid,
                ),
                _buildCapsuleButton(
                  icon: measurementsEnabled ? Icons.straighten : Icons.square_foot,
                  label: 'Measurements',
                  tooltip: 'Toggle layout boundary measurement numbers (M)',
                  isActive: measurementsEnabled,
                  onTap: onToggleMeasurements,
                ),
                _buildCapsuleButton(
                  icon: showFurnitureLabels ? Icons.label : Icons.label_off,
                  label: 'Labels',
                  tooltip: 'Toggle furniture text labels',
                  isActive: showFurnitureLabels,
                  onTap: onToggleFurnitureLabels,
                ),
                _buildCapsuleButton(
                  icon: showDoors ? Icons.meeting_room : Icons.no_meeting_room,
                  label: 'Doors',
                  tooltip: 'Toggle door visibility',
                  isActive: showDoors,
                  onTap: onToggleDoors,
                ),
                _buildCapsuleButton(
                  icon: showWindows ? Icons.window : Icons.window_outlined,
                  label: 'Windows',
                  tooltip: 'Toggle window visibility',
                  isActive: showWindows,
                  onTap: onToggleWindows,
                ),
                _buildCapsuleButton(
                  icon: Icons.bug_report_outlined,
                  label: 'Diagnostics',
                  tooltip: 'Toggle Spatial Diagnostics overlay',
                  isActive: showDiagnostics,
                  onTap: onToggleDiagnostics,
                ),
              ],
            ),
            // 3. Camera Controls (Only in 3D Mode)
            _buildCapsule(
              children: [
                _buildCapsuleButton(
                  icon: Icons.refresh,
                  label: 'Reset Camera',
                  tooltip: 'Reset camera view orientation',
                  isActive: false,
                  onTap: () => ref.read(cameraProvider.notifier).resetToRoom(layout, snap: true),
                  isEnabled: is3DMode,
                ),
                const SizedBox(width: 4),
                _buildCameraPresetsMenu(context, ref),
              ],
            ),
            // 4. Interaction transform tools
            _buildCapsule(
              children: [
                _buildCapsuleButton(
                  icon: Icons.near_me_outlined,
                  label: 'Select',
                  tooltip: 'Select object (Esc to clear)',
                  isActive: activeTransformTool == 'select',
                  onTap: () => onChangeTransformTool('select'),
                ),
                _buildCapsuleButton(
                  icon: Icons.open_with,
                  label: 'Move',
                  tooltip: 'Translate placed furniture (V)',
                  isActive: activeTransformTool == 'move',
                  onTap: () => onChangeTransformTool('move'),
                ),
                _buildCapsuleButton(
                  icon: Icons.rotate_right,
                  label: 'Rotate',
                  tooltip: 'Rotate placed assets (R)',
                  isActive: activeTransformTool == 'rotate',
                  onTap: () => onChangeTransformTool('rotate'),
                ),
                _buildCapsuleButton(
                  icon: Icons.zoom_out_map,
                  label: 'Scale',
                  tooltip: 'Scale dimension ratios (S)',
                  isActive: activeTransformTool == 'scale',
                  onTap: () => onChangeTransformTool('scale'),
                ),
                _buildCapsuleButton(
                  icon: Icons.copy_outlined,
                  label: 'Duplicate',
                  tooltip: 'Duplicate selected furniture (+30cm offset)',
                  isActive: false,
                  onTap: () => notifier.duplicateSelectedFurniture(),
                  isEnabled: layout.selectedFurnitureId != null,
                ),
                _buildCapsuleButton(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  tooltip: 'Delete selected furniture (Delete/Backspace)',
                  isActive: false,
                  activeFgColor: const Color(0xFFEF4444),
                  onTap: () => notifier.deleteSelected(),
                  isEnabled: layout.selectedFurnitureId != null,
                ),
              ],
            ),
            // 5. AI assistant & validation
            _buildCapsule(
              children: [
                _buildCapsuleButton(
                  icon: Icons.psychology,
                  label: 'AI Studio',
                  tooltip: 'Launch AI Layout Studio (Requirements & 3 Design Candidates)',
                  isActive: false,
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AiDesignRequirementsDialog(
                        roomId: roomId,
                        layout: layout,
                        notifier: notifier,
                      ),
                    );
                  },
                  activeBgColor: _kAccent,
                ),
                _buildCapsuleButton(
                  icon: Icons.auto_awesome,
                  label: 'Suggestions',
                  tooltip: 'Generate intelligent furniture layouts',
                  isActive: rightPanelOpen && activeRightTab == 'ai',
                  onTap: () => onToggleRightPanel('ai', !rightPanelOpen || activeRightTab != 'ai'),
                  activeBgColor: _kAccentLight,
                ),
                _buildCapsuleButton(
                  icon: Icons.analytics_outlined,
                  label: 'Design Score',
                  tooltip: 'Audit design metrics scorecard',
                  isActive: rightPanelOpen && activeRightTab == 'ai',
                  onTap: () => onToggleRightPanel('ai', !rightPanelOpen || activeRightTab != 'ai'),
                  activeBgColor: _kAccentLight,
                ),
                _buildCapsuleButton(
                  icon: Icons.check_circle_outline,
                  label: 'Validate Design',
                  tooltip: 'Run clearance & overlapping layout rules audit',
                  isActive: rightPanelOpen && activeRightTab == 'validation',
                  onTap: () => onToggleRightPanel('validation', !rightPanelOpen || activeRightTab != 'validation'),
                  activeBgColor: _kAccentLight,
                ),
              ],
            ),
            // 6. Export tools
            _buildCapsule(
              children: [
                _buildCapsuleButton(
                  icon: Icons.camera_alt_outlined,
                  label: 'Screenshot',
                  tooltip: 'Take standard viewport snapshot',
                  isActive: false,
                  onTap: () => _simulateScreenshot(context),
                ),
                _buildCapsuleButton(
                  icon: Icons.image_outlined,
                  label: 'Export Image',
                  tooltip: 'Render design to PNG/JPG asset',
                  isActive: false,
                  onTap: () => _showExportImageDialog(context, ref),
                ),
                _buildCapsuleButton(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'Export PDF',
                  tooltip: 'Export architectural blueprint PDF scorecard',
                  isActive: false,
                  onTap: () => _showExportPDFDialog(context, ref),
                ),
              ],
            ),
            // 7. Help tools
            _buildCapsule(
              children: [
                _buildCapsuleButton(
                  icon: Icons.school_outlined,
                  label: 'Tutorials',
                  tooltip: 'Browse design instructions booklet',
                  isActive: false,
                  onTap: () => _showTutorialsDialog(context),
                ),
                _buildCapsuleButton(
                  icon: Icons.keyboard_outlined,
                  label: 'Shortcuts',
                  tooltip: 'List quick keyboard command keys',
                  isActive: false,
                  onTap: () => _showShortcutsDialog(context),
                ),
              ],
            ),
          ];

          if (isMobile) {
            // Mobile layout: Project on left, Scrollable capsules, Save on right
            return Row(
              children: [
                projectWidget,
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: toolCapsules,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                rightActionWidget,
              ],
            );
          } else {
            // Desktop/Tablet layout: Project left, Scrollable middle, Save right
            return Row(
              children: [
                projectWidget,
                const SizedBox(width: 12),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: toolCapsules,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                rightActionWidget,
              ],
            );
          }
        },
      ),
    );
  }
}
