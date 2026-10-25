// ignore_for_file: deprecated_member_use


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/camera_provider.dart';
import '../../providers/designer_provider.dart';

// ─── Color tokens (mirror designer_screen.dart) ────────────────────────────
const _kSurface = Color(0xFF1A1D23);
const _kBorder = Color(0xFF2E3340);
const _kAccent = Color(0xFF00BFA5);
const _kTextSecondary = Color(0xFF8892A4);
const _kTextPrimary = Color(0xFFECEFF4);

/// Floating camera / viewport controls that overlay the central canvas.
///
/// In **2D mode** the [onZoomIn], [onZoomOut], [onResetView] callbacks
/// manipulate the [TransformationController] passed from [DesignerScreen].
/// In **3D mode** they drive the [CameraNotifier] via Riverpod.
///
/// [onFocusSelection] focuses the camera on the currently selected object.
/// [onToggleFullscreen] collapses/expands the side panels.
class FloatingControls extends ConsumerStatefulWidget {
  final bool is3DMode;

  // ── 2D callbacks (null in 3D mode) ──────────────────────────────────────
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onResetView;
  final VoidCallback? onFocusSelection2D;

  // ── Shared callbacks ────────────────────────────────────────────────────
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;

  const FloatingControls({
    super.key,
    required this.is3DMode,
    this.onZoomIn,
    this.onZoomOut,
    this.onResetView,
    this.onFocusSelection2D,
    this.onToggleFullscreen,
    this.isFullscreen = false,
  });

  @override
  ConsumerState<FloatingControls> createState() => _FloatingControlsState();
}

class _FloatingControlsState extends ConsumerState<FloatingControls>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animCtrl.forward();
    } else {
      _animCtrl.reverse();
    }
  }

  // ── 3D camera helpers ────────────────────────────────────────────────────

  void _zoom3DIn() {
    final mode = ref.read(viewModeProvider);
    ref.read(cameraProvider.notifier).zoom(-60.0, mode == ViewMode.free);
  }

  void _zoom3DOut() {
    final mode = ref.read(viewModeProvider);
    ref.read(cameraProvider.notifier).zoom(60.0, mode == ViewMode.free);
  }

  void _resetView3D() {
    final layout = ref.read(designerProvider);
    ref.read(cameraProvider.notifier).resetToRoom(layout);
  }

  void _focusSelection3D() {
    final layout = ref.read(designerProvider);
    if (layout.selectedFurnitureId != null) {
      try {
        final f = layout.furniture
            .firstWhere((f) => f.id == layout.selectedFurnitureId);
        ref.read(cameraProvider.notifier).focusFurniture(f);
      } catch (_) {}
    } else {
      // Fall back to room reset if nothing selected
      ref.read(cameraProvider.notifier).resetToRoom(layout);
    }
  }

  // ── Routing to 2D or 3D ──────────────────────────────────────────────────

  void _onZoomIn() {
    if (widget.is3DMode) {
      _zoom3DIn();
    } else {
      widget.onZoomIn?.call();
    }
  }

  void _onZoomOut() {
    if (widget.is3DMode) {
      _zoom3DOut();
    } else {
      widget.onZoomOut?.call();
    }
  }

  void _onResetView() {
    if (widget.is3DMode) {
      _resetView3D();
    } else {
      widget.onResetView?.call();
    }
  }

  void _onFocusSelection() {
    if (widget.is3DMode) {
      _focusSelection3D();
    } else {
      widget.onFocusSelection2D?.call();
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(designerProvider);
    final bool hasSelection = layout.selectedFurnitureId != null ||
        layout.selectedWallIndex != null ||
        layout.selectedOpeningId != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // ── Collapse toggle pill ─────────────────────────────────────────
        _CollapseToggle(
          expanded: _expanded,
          onTap: _toggleExpanded,
        ),
        const SizedBox(height: 6),

        // ── Main control panel ───────────────────────────────────────────
        ScaleTransition(
          scale: _scaleAnim,
          alignment: Alignment.bottomRight,
          child: AnimatedOpacity(
            opacity: _expanded ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            child: _expanded
                ? _ControlPanel(
                    onZoomIn: _onZoomIn,
                    onZoomOut: _onZoomOut,
                    onResetView: _onResetView,
                    onFocusSelection: _onFocusSelection,
                    onToggleFullscreen: widget.onToggleFullscreen,
                    isFullscreen: widget.isFullscreen,
                    hasSelection: hasSelection,
                    is3DMode: widget.is3DMode,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  Collapse toggle
// ────────────────────────────────────────────────────────────────────────────

class _CollapseToggle extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;
  const _CollapseToggle({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _kSurface.withOpacity(0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
            size: 13,
            color: _kTextSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            expanded ? 'Hide controls' : 'Show controls',
            style: const TextStyle(
              fontSize: 10,
              color: _kTextSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ]),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  Main control panel
// ────────────────────────────────────────────────────────────────────────────

class _ControlPanel extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetView;
  final VoidCallback onFocusSelection;
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;
  final bool hasSelection;
  final bool is3DMode;

  const _ControlPanel({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetView,
    required this.onFocusSelection,
    required this.onToggleFullscreen,
    required this.isFullscreen,
    required this.hasSelection,
    required this.is3DMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Zoom In ────────────────────────────────────────────────
              _FloatBtn(
                icon: Icons.add,
                tooltip: 'Zoom In',
                onTap: onZoomIn,
                label: '+',
              ),

              _Divider(),

              // ── Zoom Out ───────────────────────────────────────────────
              _FloatBtn(
                icon: Icons.remove,
                tooltip: 'Zoom Out',
                onTap: onZoomOut,
                label: '−',
              ),

              _Divider(),

              // ── Reset View ─────────────────────────────────────────────
              _FloatBtn(
                icon: is3DMode
                    ? Icons.home_outlined
                    : Icons.center_focus_strong_outlined,
                tooltip: 'Reset View',
                onTap: onResetView,
              ),

              _Divider(),

              // ── Focus Selection ─────────────────────────────────────────
              _FloatBtn(
                icon: Icons.my_location_outlined,
                tooltip: 'Focus Selection',
                onTap: onFocusSelection,
                accent: hasSelection,
              ),

              _Divider(),

              // ── Fullscreen ──────────────────────────────────────────────
              _FloatBtn(
                icon: isFullscreen
                    ? Icons.fullscreen_exit_outlined
                    : Icons.fullscreen_outlined,
                tooltip: isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
                onTap: onToggleFullscreen ?? () {},
                accent: isFullscreen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  Single button
// ────────────────────────────────────────────────────────────────────────────

class _FloatBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final String? label;
  final bool accent;

  const _FloatBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.label,
    this.accent = false,
  });

  @override
  State<_FloatBtn> createState() => _FloatBtnState();
}

class _FloatBtnState extends State<_FloatBtn> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.accent
        ? _kAccent
        : (_hovered ? _kTextPrimary : _kTextSecondary);

    final bgColor = _pressed
        ? _kAccent.withOpacity(0.18)
        : (_hovered ? Colors.white.withOpacity(0.05) : Colors.transparent);

    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 44,
            height: 40,
            color: bgColor,
            child: Center(
              child: Icon(widget.icon, size: 17, color: effectiveColor),
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  Thin divider between buttons
// ────────────────────────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: _kBorder.withOpacity(0.7));
}
