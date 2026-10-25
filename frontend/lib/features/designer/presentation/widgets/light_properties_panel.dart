import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/themes/app_theme.dart';

import '../../models/light_source.dart';
import '../../providers/lighting_provider.dart';

const _kSurface = Color(0xFF111827); 
const _kSurfaceElevated = Color(0xFF1E293B); 
const _kBorder = Color(0xFF334155); 
const _kAccent = Color(0xFF0F766E); 
const _kTextPrimary = Color(0xFFF8FAFC); 
const _kTextSecondary = Color(0xFF94A3B8);

class LightPropertiesPanel extends StatefulWidget {
  final LightSource light;
  final LightingNotifier notifier;
  final VoidCallback onDelete;

  const LightPropertiesPanel({
    super.key,
    required this.light,
    required this.notifier,
    required this.onDelete,
  });

  @override
  State<LightPropertiesPanel> createState() => _LightPropertiesPanelState();
}

class _LightPropertiesPanelState extends State<LightPropertiesPanel> {
  late TextEditingController _nameCtrl;
  late TextEditingController _xCtrl;
  late TextEditingController _yCtrl;
  late TextEditingController _zCtrl;
  late TextEditingController _rotXCtrl;
  late TextEditingController _rotYCtrl;
  late TextEditingController _rotZCtrl;

  @override
  void initState() {
    super.initState();
    _initControllers(widget.light);
  }

  void _initControllers(LightSource l) {
    _nameCtrl = TextEditingController(text: l.name);
    _xCtrl = TextEditingController(text: l.x.round().toString());
    _yCtrl = TextEditingController(text: l.y.round().toString());
    _zCtrl = TextEditingController(text: l.z.round().toString());
    _rotXCtrl = TextEditingController(text: (l.rotationX * 180 / pi).round().toString());
    _rotYCtrl = TextEditingController(text: (l.rotationY * 180 / pi).round().toString());
    _rotZCtrl = TextEditingController(text: (l.rotationZ * 180 / pi).round().toString());
  }

  @override
  void didUpdateWidget(LightPropertiesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.light.id != widget.light.id) {
      _disposeControllers();
      _initControllers(widget.light);
    } else {
      if (_nameCtrl.text != widget.light.name) {
        _nameCtrl.text = widget.light.name;
      }
      // Update coordinates if changed from 3D viewport drag
      final lx = widget.light.x.round().toString();
      final ly = widget.light.y.round().toString();
      final lz = widget.light.z.round().toString();
      final rx = (widget.light.rotationX * 180 / pi).round().toString();
      final ry = (widget.light.rotationY * 180 / pi).round().toString();
      final rz = (widget.light.rotationZ * 180 / pi).round().toString();
      
      if (_xCtrl.text != lx) _xCtrl.text = lx;
      if (_yCtrl.text != ly) _yCtrl.text = ly;
      if (_zCtrl.text != lz) _zCtrl.text = lz;
      if (_rotXCtrl.text != rx) _rotXCtrl.text = rx;
      if (_rotYCtrl.text != ry) _rotYCtrl.text = ry;
      if (_rotZCtrl.text != rz) _rotZCtrl.text = rz;
    }
  }

  void _disposeControllers() {
    _nameCtrl.dispose();
    _xCtrl.dispose();
    _yCtrl.dispose();
    _zCtrl.dispose();
    _rotXCtrl.dispose();
    _rotYCtrl.dispose();
    _rotZCtrl.dispose();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.light;
    final showSpatial = l.type != LightType.ambient;
    final showRotation = l.type == LightType.directional || l.type == LightType.spot;
    final showRadius = l.type == LightType.point || l.type == LightType.spot;
    final showSpotAngle = l.type == LightType.spot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. General Info
        _CollapsibleCard(
          title: 'Light Information',
          icon: Icons.lightbulb_outline,
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Name', style: TextStyle(color: _kTextSecondary, fontSize: 10)),
              const SizedBox(height: 4),
              SizedBox(
                height: 38,
                child: TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: _kTextPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _kSurface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kAccent, width: 1.5),
                    ),
                  ),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) {
                      widget.notifier.updateLight(l.id, name: v.trim());
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              _buildReadOnlyInfoRow('Type', l.type.name.toUpperCase()),
            ],
          ),
        ),

        // 2. Spatial Transform (if not ambient)
        if (showSpatial)
          _CollapsibleCard(
            title: 'Transform',
            icon: Icons.transform,
            initiallyExpanded: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('POSITION (cm)'),
                const SizedBox(height: 8),
                _buildAxisControl(
                  label: 'X',
                  color: const Color(0xFFE57373),
                  value: l.x,
                  min: 0,
                  max: 2000,
                  controller: _xCtrl,
                  onSliderChanged: (v) {
                    widget.notifier.updateLight(l.id, x: v);
                    _xCtrl.text = v.round().toString();
                  },
                  onTextSubmitted: (v) {
                    final val = double.tryParse(v);
                    if (val != null) {
                      widget.notifier.updateLight(l.id, x: val.clamp(0, 2000));
                    }
                  },
                ),
                _buildAxisControl(
                  label: 'Y',
                  color: const Color(0xFF81C784),
                  value: l.y,
                  min: 0,
                  max: 1000,
                  controller: _yCtrl,
                  onSliderChanged: (v) {
                    widget.notifier.updateLight(l.id, y: v);
                    _yCtrl.text = v.round().toString();
                  },
                  onTextSubmitted: (v) {
                    final val = double.tryParse(v);
                    if (val != null) {
                      widget.notifier.updateLight(l.id, y: val.clamp(0, 1000));
                    }
                  },
                ),
                _buildAxisControl(
                  label: 'Z',
                  color: const Color(0xFF64B5F6),
                  value: l.z,
                  min: 0,
                  max: 2000,
                  controller: _zCtrl,
                  onSliderChanged: (v) {
                    widget.notifier.updateLight(l.id, z: v);
                    _zCtrl.text = v.round().toString();
                  },
                  onTextSubmitted: (v) {
                    final val = double.tryParse(v);
                    if (val != null) {
                      widget.notifier.updateLight(l.id, z: val.clamp(0, 2000));
                    }
                  },
                ),
                if (showRotation) ...[
                  const SizedBox(height: 12),
                  _sectionLabel('ROTATION (degrees)'),
                  const SizedBox(height: 8),
                  _buildAxisControl(
                    label: 'Pitch (X)',
                    color: _kTextSecondary.withOpacity(0.5),
                    value: l.rotationX * 180 / pi,
                    min: -90,
                    max: 90,
                    controller: _rotXCtrl,
                    suffix: '°',
                    onSliderChanged: (v) {
                      widget.notifier.updateLight(l.id, rotationX: v * pi / 180);
                      _rotXCtrl.text = v.round().toString();
                    },
                    onTextSubmitted: (v) {
                      final val = double.tryParse(v);
                      if (val != null) {
                        widget.notifier.updateLight(l.id, rotationX: val.clamp(-90, 90) * pi / 180);
                      }
                    },
                  ),
                  _buildAxisControl(
                    label: 'Yaw (Y)',
                    color: _kTextSecondary.withOpacity(0.5),
                    value: l.rotationY * 180 / pi,
                    min: 0,
                    max: 360,
                    controller: _rotYCtrl,
                    suffix: '°',
                    onSliderChanged: (v) {
                      widget.notifier.updateLight(l.id, rotationY: v * pi / 180);
                      _rotYCtrl.text = v.round().toString();
                    },
                    onTextSubmitted: (v) {
                      final val = double.tryParse(v);
                      if (val != null) {
                        widget.notifier.updateLight(l.id, rotationY: val.clamp(0, 360) * pi / 180);
                      }
                    },
                  ),
                ],
              ],
            ),
          ),

        // 3. Light Source Settings
        _CollapsibleCard(
          title: 'Light Controls',
          icon: Icons.tune,
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('INTENSITY'),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: l.intensity.clamp(0.0, 5.0),
                      min: 0.0,
                      max: 5.0,
                      activeColor: AppTheme.primary,
                      inactiveColor: _kBorder,
                      onChanged: (v) => widget.notifier.updateLight(l.id, intensity: v),
                    ),
                  ),
                  Text(l.intensity.toStringAsFixed(2), style: const TextStyle(color: _kTextPrimary, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 12),
              
              _sectionLabel('COLOR TEMPERATURE (Kelvin)'),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: l.temperature.clamp(1000.0, 12000.0),
                      min: 1000.0,
                      max: 12000.0,
                      activeColor: Colors.amber,
                      inactiveColor: _kBorder,
                      onChanged: (v) {
                        widget.notifier.updateLight(
                          l.id, 
                          temperature: v,
                          color: colorFromTemperature(v),
                        );
                      },
                    ),
                  ),
                  Text('${l.temperature.round()} K', style: const TextStyle(color: _kTextPrimary, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 12),

              _sectionLabel('LIGHT COLOR'),
              const SizedBox(height: 8),
              _buildColorPresets(l),
              const SizedBox(height: 8),

              // Shadow Cast Toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Cast Shadows', style: TextStyle(color: _kTextPrimary, fontSize: 12)),
                  Switch(
                    value: l.castShadow,
                    activeColor: AppTheme.primary,
                    onChanged: (v) => widget.notifier.updateLight(l.id, castShadow: v),
                  ),
                ],
              ),

              if (showRadius) ...[
                const SizedBox(height: 12),
                _sectionLabel('ATTENUATION RADIUS (cm)'),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: l.radius.clamp(50.0, 2000.0),
                        min: 50.0,
                        max: 2000.0,
                        activeColor: AppTheme.primary,
                        inactiveColor: _kBorder,
                        onChanged: (v) => widget.notifier.updateLight(l.id, radius: v),
                      ),
                    ),
                    Text('${l.radius.round()} cm', style: const TextStyle(color: _kTextPrimary, fontSize: 11)),
                  ],
                ),
              ],

              if (showSpotAngle) ...[
                const SizedBox(height: 12),
                _sectionLabel('SPOTLIGHT CONE ANGLE (degrees)'),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: (l.spotAngle * 180 / pi).clamp(10.0, 90.0),
                        min: 10.0,
                        max: 90.0,
                        activeColor: AppTheme.primary,
                        inactiveColor: _kBorder,
                        onChanged: (v) => widget.notifier.updateLight(l.id, spotAngle: v * pi / 180),
                      ),
                    ),
                    Text('${(l.spotAngle * 180 / pi).round()}°', style: const TextStyle(color: _kTextPrimary, fontSize: 11)),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),
        // Delete button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white),
            label: const Text('Delete Light', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: widget.onDelete,
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyInfoRow(String label, String val) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 11)),
        Text(val, style: const TextStyle(color: _kTextPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(color: _kTextSecondary, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
    );
  }

  Widget _buildAxisControl({
    required String label,
    required Color color,
    required double value,
    required double min,
    required double max,
    required TextEditingController controller,
    String suffix = '',
    required ValueChanged<double> onSliderChanged,
    required ValueChanged<String> onTextSubmitted,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              activeColor: color,
              inactiveColor: _kBorder,
              onChanged: onSliderChanged,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            height: 28,
            child: TextField(
              controller: controller,
              style: const TextStyle(color: _kTextPrimary, fontSize: 11),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*'))],
              decoration: InputDecoration(
                filled: true,
                fillColor: _kSurface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                suffixText: suffix,
                suffixStyle: const TextStyle(color: _kTextSecondary, fontSize: 9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _kBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _kBorder)),
              ),
              onSubmitted: onTextSubmitted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPresets(LightSource l) {
    final colorsList = [
      Colors.white,
      const Color(0xFFFFF6E0), // candlelight / warm
      const Color(0xFFFFE7C4), // very warm
      const Color(0xFFFFFDFA), // natural white
      const Color(0xFFE2F0FF), // cool daylight
      const Color(0xFFFFD2D2), // red tint
      const Color(0xFFD2FFD2), // green tint
      const Color(0xFFD2D2FF), // blue tint
      const Color(0xFFFFD2FF), // magenta tint
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: colorsList.map((c) {
        final isSel = l.color.value == c.value;
        return GestureDetector(
          onTap: () => widget.notifier.updateLight(l.id, color: c),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSel ? Colors.white : _kBorder,
                width: isSel ? 2 : 1,
              ),
              boxShadow: isSel ? [
                BoxShadow(color: c.withOpacity(0.5), blurRadius: 4, spreadRadius: 1),
              ] : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CollapsibleCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;

  const _CollapsibleCard({
    required this.title,
    required this.icon,
    required this.child,
    this.initiallyExpanded = false,
  });

  @override
  State<_CollapsibleCard> createState() => _CollapsibleCardState();
}

class _CollapsibleCardState extends State<_CollapsibleCard> with SingleTickerProviderStateMixin {
  late bool _expanded;
  late AnimationController _anim;
  late Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _anim = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: _expanded ? 1.0 : 0.0,
    );
    _curve = CurvedAnimation(parent: _anim, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _anim.forward();
      } else {
        _anim.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _kSurfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Icon(widget.icon, size: 16, color: _kAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(color: _kTextPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: _kTextSecondary,
                  ),
                ],
              ),
            ),
          ),
          SizeTransition(
            sizeFactor: _curve,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}
