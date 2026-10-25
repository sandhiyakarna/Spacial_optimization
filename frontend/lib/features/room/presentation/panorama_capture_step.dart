import '../../../app/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../data/panorama_service.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import 'panorama_capture_screen.dart';

class SpatialRoomCaptureStep extends StatefulWidget {
  final Function(String url) onPanoramaSelected;
  final VoidCallback onSkip;
  final VoidCallback onBack;
  final String? initialPanoramaUrl;
  final bool initialPanoramaSkipped;
  final String roomType;

  const SpatialRoomCaptureStep({
    super.key,
    required this.onPanoramaSelected,
    required this.onSkip,
    required this.onBack,
    this.initialPanoramaUrl,
    this.initialPanoramaSkipped = false,
    this.roomType = 'Living Room',
  });


  @override
  State<SpatialRoomCaptureStep> createState() => _SpatialRoomCaptureStepState();
}

class _SpatialRoomCaptureStepState extends State<SpatialRoomCaptureStep>
    with SingleTickerProviderStateMixin {
  // States: 'select', 'capturing', 'preview'
  String _mode = 'select';

  // Simulated capture state
  late AnimationController _captureAnimationController;
  double _captureProgress = 0.0;
  bool _isCapturing = false;
  String _captureInstruction = 'Align with the starting marker to begin';

  // Preview state
  String? _selectedUrl;
  final ScrollController _scrollController = ScrollController();

  final TextEditingController _urlController = TextEditingController();

  // High-res room panorama presets
  final List<Map<String, String>> _presets = const [
    {
      'name': 'Scandi Living Room',
      'desc': 'Bright, neutral tones with wood accents',
      'url': 'https://images.unsplash.com/photo-1600210492486-724fe5c67fb0?auto=format&fit=crop&q=80&w=1600',
      'thumb': 'https://images.unsplash.com/photo-1600210492486-724fe5c67fb0?auto=format&fit=crop&q=80&w=200',
    },
    {
      'name': 'Industrial Loft Kitchen',
      'desc': 'Exposed brick, dark metals, steel appliances',
      'url': 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&q=80&w=1600',
      'thumb': 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&q=80&w=200',
    },
    {
      'name': 'Modern Smart Bedroom',
      'desc': 'Minimalist styling, ambient led highlights',
      'url': 'https://images.unsplash.com/photo-1616594039964-ae9021a400a0?auto=format&fit=crop&q=80&w=1600',
      'thumb': 'https://images.unsplash.com/photo-1616594039964-ae9021a400a0?auto=format&fit=crop&q=80&w=200',
    },
  ];

  // Default image used when captured
  final String _defaultCapturedUrl =
      'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&q=80&w=1600';

  @override
  void initState() {
    super.initState();
    if (widget.initialPanoramaUrl != null) {
      _selectedUrl = widget.initialPanoramaUrl;
      _mode = 'preview';
    }
    _captureAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _captureAnimationController.addListener(() {
      setState(() {
        _captureProgress = _captureAnimationController.value;
        if (_captureProgress < 0.25) {
          _captureInstruction = 'Slowly sweep your phone to the right →';
        } else if (_captureProgress < 0.6) {
          _captureInstruction = 'Keep sweeping, maintain level line...';
        } else if (_captureProgress < 0.9) {
          _captureInstruction = 'Almost complete, hold steady...';
        } else {
          _captureInstruction = 'Processing panorama image...';
        }
      });
    });

    _captureAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _isCapturing = false;
          _selectedUrl = _defaultCapturedUrl;
          _mode = 'preview';
        });
      }
    });
  }

  @override
  void dispose() {
    _captureAnimationController.dispose();
    _scrollController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _triggerSimulatedCapture() {
    _captureAnimationController.forward(from: 0.0);
  }

  void _selectPreset(String url) {
    setState(() {
      _selectedUrl = url;
      _mode = 'preview';
    });
  }

  void _applyCustomUrl() {
    final url = _urlController.text.trim();
    if (url.isNotEmpty && url.startsWith('http')) {
      setState(() {
        _selectedUrl = url;
        _mode = 'preview';
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid HTTP(S) image URL.')),
      );
    }
  }

  void _retake() {
    setState(() {
      _mode = 'select';
      _selectedUrl = null;
      _urlController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade50,
      width: double.infinity,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 750),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        switchInCurve: Curves.easeInOutCubic,
                        switchOutCurve: Curves.easeInOutCubic,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.0, 0.05),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey<String>(_mode),
                          child: _mode == 'select'
                              ? _buildSelectModeView()
                              : _mode == 'capturing'
                                  ? _buildCapturingModeView()
                                  : _buildPreviewModeView(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _buildBottomActionButtons(),
        ],
      ),
    );
  }

  Widget _buildSelectModeView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Spatial Room Model Setup',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
        ),
        const SizedBox(height: 8),
        const Text(
          'Scan the room with your camera to capture spatial boundaries and build a digital 3D layout of the space.',
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final result = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SpatialRoomCaptureScreen(
                        roomType: widget.roomType,
                      ),
                    ),
                  );
                  if (result != null) {
                    if (result == 'ai_fallback') {
                      widget.onSkip();
                    } else {
                      setState(() {
                        _selectedUrl = result;
                        _mode = 'preview';
                      });
                    }
                  }
                },

                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.shade50.withValues(alpha: 0.3),
                    border: Border.all(color: AppTheme.primary.shade200, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.explore_outlined, color: AppTheme.primary, size: 36),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Spatial Room Capture',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary),
                      ),
                      const SizedBox(height: 6),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Calibrate sensors, scan room boundaries, and estimate spatial layout',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'OR CHOOSE A SAMPLE ROOM PRESET',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 20),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _presets.length,
          itemBuilder: (context, index) {
            final preset = _presets[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Card(
                elevation: 0.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      preset['thumb']!,
                      width: 70,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 70,
                        height: 50,
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.broken_image, size: 20, color: Colors.grey),
                      ),
                    ),
                  ),
                  title: Text(
                    preset['name']!,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  subtitle: Text(preset['desc']!, style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.primary),
                  onTap: () => _selectPreset(preset['url']!),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'OR ENTER IMAGE URL',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          elevation: 0.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      hintText: 'Enter panoramic image web link (http...)',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _applyCustomUrl,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCapturingModeView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Panorama Sweep Simulation',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
        ),
        const SizedBox(height: 16),
        // Simulated Viewfinder Box
        Container(
          height: 320,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.primary, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                // Simulated camera grid and visual scanning bars
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.4,
                    child: Column(
                      children: List.generate(
                        4,
                        (index) => Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: AppTheme.primary.shade200.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.4,
                    child: Row(
                      children: List.generate(
                        4,
                        (index) => Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                  color: AppTheme.primary.shade200.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Simulated panoramic panorama background sweep moving horizontally
                if (_isCapturing)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 100),
                    left: -200 * _captureProgress,
                    top: 0,
                    bottom: 0,
                    width: 1000,
                    child: Opacity(
                      opacity: 0.6,
                      child: Image.network(
                        _defaultCapturedUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: const Color(0xFF1E293B),
                          child: const Center(
                            child: Icon(Icons.photo_outlined, color: Colors.white24, size: 48),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_camera_front, size: 64, color: Colors.white24),
                        SizedBox(height: 12),
                        Text(
                          'Simulated 360 Camera Sensor ready.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                // Horizon Level Guide Line
                Center(
                  child: Container(
                    height: 2,
                    color: Colors.greenAccent.withValues(alpha: 0.7),
                    width: double.infinity,
                  ),
                ),
                // Level target indicator (moving slightly)
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: 44,
                    height: 44,
                    transform: Matrix4.translationValues(
                      _isCapturing ? (20 * _captureProgress % 10 - 5).toDouble() : 0.0,
                      _isCapturing ? (10 * _captureProgress % 6 - 3).toDouble() : 0.0,
                      0.0,
                    ),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.greenAccent, width: 2),
                    ),
                    child: Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
                // Visual level alignment line indicator on left/right
                Positioned(
                  left: 20,
                  top: 0,
                  bottom: 0,
                  child: Icon(Icons.unfold_more_sharp, color: Colors.greenAccent.withValues(alpha: 0.6), size: 28),
                ),
                Positioned(
                  right: 20,
                  top: 0,
                  bottom: 0,
                  child: Icon(Icons.unfold_more_sharp, color: Colors.greenAccent.withValues(alpha: 0.6), size: 28),
                ),
                // Top status bar
                Positioned(
                  top: 16,
                  left: 20,
                  right: 20,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.sensors, color: Colors.white, size: 12),
                            SizedBox(width: 4),
                            Text('GYRO ACTIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      if (_isCapturing)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.circle, color: Colors.white, size: 10),
                              SizedBox(width: 4),
                              Text('REC', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Bottom instructions
                Positioned(
                  bottom: 16,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _captureInstruction,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        if (!_isCapturing)
          ElevatedButton.icon(
            onPressed: _triggerSimulatedCapture,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Simulation'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          )
        else ...[
          Text(
            'Scanning Sweep: ${(_captureProgress * 100).toInt()}%',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 250,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _captureProgress,
                minHeight: 12,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => setState(() => _mode = 'select'),
          child: const Text('Cancel & Return', style: TextStyle(color: AppTheme.primary)),
        ),
      ],
    );
  }

  Widget _buildPreviewModeView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Spatial Room Model Preview',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Interact with the captured digital room model. Zoom and pan in 3D.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              icon: const Icon(Icons.refresh),
              onPressed: _retake,
              tooltip: 'Retake / Choose different image',
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Panoramic Viewer Container
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade300, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Container(
            height: 320,
            width: double.infinity,
            color: Colors.black,
            child: InteractivePanoramaViewer(
              roomType: widget.roomType,
              isInteractive: true,
              lightMode: false,
              panoramaUrl: _selectedUrl,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionButtons() {
    return Container(
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 360) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        text: 'Back',
                        onPressed: widget.onBack,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        text: 'Next',
                        onPressed: _selectedUrl != null
                            ? () => widget.onPanoramaSelected(_selectedUrl!)
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: widget.onSkip,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Skip Panorama',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            );
          } else {
            return Row(
              children: [
                SecondaryButton(
                  text: 'Back',
                  onPressed: widget.onBack,
                ),
                const Spacer(),
                TextButton(
                  onPressed: widget.onSkip,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Skip Panorama',
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
                  onPressed: _selectedUrl != null
                      ? () => widget.onPanoramaSelected(_selectedUrl!)
                      : null,
                ),
              ],
            );
          }
        },
      ),
    );
  }
}

class ViewerGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.2)
      ..strokeWidth = 1.0;

    // Draw horizontal grid lines
    const int rows = 6;
    for (int i = 1; i < rows; i++) {
      final y = size.height * i / rows;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Draw perspective converging lines to center
    final center = Offset(size.width / 2, size.height / 2);
    final diagonalPaint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.15)
      ..strokeWidth = 1.0;

    canvas.drawLine(const Offset(0, 0), center, diagonalPaint);
    canvas.drawLine(Offset(size.width, 0), center, diagonalPaint);
    canvas.drawLine(Offset(0, size.height), center, diagonalPaint);
    canvas.drawLine(Offset(size.width, size.height), center, diagonalPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PanoramaImageWidget extends StatelessWidget {
  final String urlOrPath;
  final BoxFit fit;

  const PanoramaImageWidget({
    super.key,
    required this.urlOrPath,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (urlOrPath.startsWith('memory:')) {
      final bytes = PanoramaImageCache.get(urlOrPath);
      if (bytes == null) {
        return const Center(child: Icon(Icons.broken_image, color: Colors.red, size: 48));
      }
      return Image.memory(bytes, fit: fit);
    } else if (urlOrPath.startsWith('http://') || urlOrPath.startsWith('https://')) {
      return Image.network(
        urlOrPath,
        fit: fit,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppTheme.primary),
                SizedBox(height: 12),
                Text(
                  'Downloading panorama image...',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              SizedBox(height: 12),
              Text(
                'Failed to load panorama image',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    } else {
      if (kIsWeb) {
        return Image.network(
          urlOrPath,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                SizedBox(height: 12),
                Text(
                  'Failed to load web panorama image',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        );
      } else {
        return Image.file(
          File(urlOrPath),
          fit: fit,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                SizedBox(height: 12),
                Text(
                  'Failed to load local panorama image',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        );
      }
    }
  }
}
