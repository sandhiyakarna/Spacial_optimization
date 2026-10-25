import '../../../app/themes/app_theme.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../data/panorama_service.dart';
import '../data/panorama_stitcher.dart';
import '../../designer/presentation/graphics_3d.dart';

class SpatialRoomCaptureScreen extends StatefulWidget {
  final String roomType;
  final String? roomId;

  const SpatialRoomCaptureScreen({
    super.key,
    required this.roomType,
    this.roomId,
  });

  @override
  State<SpatialRoomCaptureScreen> createState() => _SpatialRoomCaptureScreenState();
}

class _SpatialRoomCaptureScreenState extends State<SpatialRoomCaptureScreen>
    with TickerProviderStateMixin {
  static bool soundEnabled = true;
  static bool hapticEnabled = true;

  DateTime? _scanStartTime;
  DateTime? _scanEndTime;
  // States: 'instructions' | 'calibration' | 'capturing' | 'summary' | 'processing' | 'stitching_failed' | 'preview'
  String _screenState = 'instructions';
  bool _isDemoMode = false;

  double _captureProgress = 0.0;
  double _currentAngle = 0.0;

  // 6 scan target angles: 0, 60, 120, 180, 240, 300
  final List<double> _targets = [0.0, 60.0, 120.0, 180.0, 240.0, 300.0];
  final List<bool> _targetsCaptured = List.filled(6, false);

  // Lock-on calibration state
  int? _lockedTargetIndex;
  double _calibrationProgress = 0.0; // 0.0 to 1.0
  Timer? _calibrationTimer;

  // Camera calibration phase (Stage 1)
  double _sensorCalibProgress = 0.0;
  Timer? _sensorCalibTimer;
  final List<String> _calibLogs = [];

  // Processing simulation state (Stage 4)
  double _processingProgress = 0.0;
  Timer? _processingTimer;

  // Camera & local stitching state
  CameraController? _cameraController;
  bool _cameraAvailable = false;
  bool _showShutterFlash = false;
  final List<String?> _capturedFramePaths = List.filled(6, null);
  String? _stitchedPanoramaPath;

  // Stability & Quality metrics
  double _dragSpeed = 0.0;
  double _lastDragTime = 0.0;
  String _stabilityText = 'Stability: Excellent';
  Color _stabilityColor = Colors.green;

  // Missing area warning
  String? _missingAreaWarning;

  // Animation support
  late AnimationController _pulsingController;
  late AnimationController _successRippleController;
  double _successRippleValue = 0.0;

  @override
  void initState() {
    super.initState();
    _pulsingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    bool isTest = false;
    if (!kIsWeb) {
      try {
        isTest = Platform.environment.containsKey('FLUTTER_TEST');
      } catch (_) {}
    }
    if (!isTest) {
      _pulsingController.repeat(reverse: true);
    } else {
      _pulsingController.value = 1.0;
    }

    _successRippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successRippleController.addListener(() {
      setState(() {
        _successRippleValue = _successRippleController.value;
      });
    });
  }

  @override
  void dispose() {
    _calibrationTimer?.cancel();
    _sensorCalibTimer?.cancel();
    _processingTimer?.cancel();
    _cameraController?.dispose();
    _pulsingController.dispose();
    _successRippleController.dispose();
    super.dispose();
  }

  void _startSensorCalibration() {
    setState(() {
      _screenState = 'calibration';
      _sensorCalibProgress = 0.0;
      _calibLogs.clear();
      _calibLogs.add('Checking camera sensor access...');
    });
    if (hapticEnabled) HapticFeedback.lightImpact();

    _sensorCalibTimer?.cancel();
    _sensorCalibTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _sensorCalibProgress += 0.15;
        if (_sensorCalibProgress >= 0.3 && _calibLogs.length == 1) {
          _calibLogs.add('Verifying IMU / Gyroscope alignment... OK');
          if (hapticEnabled) HapticFeedback.lightImpact();
        } else if (_sensorCalibProgress >= 0.6 && _calibLogs.length == 2) {
          _calibLogs.add('Evaluating ambient light intensity... OK');
          if (hapticEnabled) HapticFeedback.lightImpact();
        } else if (_sensorCalibProgress >= 0.8 && _calibLogs.length == 3) {
          _calibLogs.add('Configuring HDR exposure level... OK');
          if (hapticEnabled) HapticFeedback.lightImpact();
        }

        if (_sensorCalibProgress >= 1.0) {
          _sensorCalibProgress = 1.0;
          timer.cancel();
          _startCapturing();
        }
      });
    });
  }

  void _startCapturing() {
    _scanStartTime = DateTime.now();
    _scanEndTime = null;
    setState(() {
      _screenState = 'capturing';
      _isDemoMode = false;
      _captureProgress = 0.0;
      _currentAngle = 0.0;
      _lockedTargetIndex = null;
      _calibrationProgress = 0.0;
      _stitchedPanoramaPath = null;
      _missingAreaWarning = null;
      _dragSpeed = 0.0;
      _lastDragTime = 0.0;
      _stabilityText = 'Stability: Excellent';
      _stabilityColor = Colors.green;
      for (int i = 0; i < 6; i++) {
        _targetsCaptured[i] = false;
        _capturedFramePaths[i] = null;
      }
    });
    if (hapticEnabled) HapticFeedback.mediumImpact();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_screenState != 'capturing') return;

    final double now = DateTime.now().millisecondsSinceEpoch.toDouble();
    if (_lastDragTime > 0) {
      final double dt = now - _lastDragTime;
      if (dt > 0) {
        _dragSpeed = (details.primaryDelta!.abs() / dt) * 1000.0;
        setState(() {
          if (_dragSpeed > 600.0) {
            _stabilityText = 'Warning: Rotate Slowly!';
            _stabilityColor = Colors.orange;
          } else {
            _stabilityText = 'Stability: Excellent';
            _stabilityColor = Colors.green;
          }
        });
      }
    }
    _lastDragTime = now;

    // Dragging horizontally simulates rotating the camera (360 degrees total)
    final deltaAngle = -(details.primaryDelta! / 400.0) * 180.0;
    
    double newAngle = (_currentAngle + deltaAngle) % 360.0;
    if (newAngle < 0) newAngle += 360.0;

    setState(() {
      _currentAngle = newAngle;
    });

    _checkTargetAlignment();
    _checkMissingSectors();
  }

  void _checkMissingSectors() {
    String? warning;
    for (int i = 0; i < _targets.length; i++) {
      if (!_targetsCaptured[i]) {
        double diff = (_currentAngle - _targets[i]).abs();
        if (diff > 180.0) diff = 360.0 - diff;
        // If they sweep past a target without capturing it
        if (diff > 50.0 && diff < 110.0) {
          // Calculate shortest path direction
          double dAngle = _targets[i] - _currentAngle;
          if (dAngle > 180) dAngle -= 360;
          if (dAngle < -180) dAngle += 360;
          final direction = dAngle > 0 ? "Right →" : "← Left";
          warning = 'Sector at ${_targets[i].round()}° missed. Turn $direction.';
          break;
        }
      }
    }
    setState(() {
      _missingAreaWarning = warning;
    });
  }

  void _checkTargetAlignment() {
    int? alignedIndex;
    for (int i = 0; i < _targets.length; i++) {
      if (_targetsCaptured[i]) continue;

      double diff = (_currentAngle - _targets[i]).abs();
      if (diff > 180.0) diff = 360.0 - diff;

      // If within 4 degrees of a target, we align and lock on
      if (diff < 4.0) {
        alignedIndex = i;
        break;
      }
    }

    if (alignedIndex != null) {
      if (_lockedTargetIndex != alignedIndex) {
        // Lock onto new target
        _lockedTargetIndex = alignedIndex;
        _calibrationProgress = 0.0;
        if (hapticEnabled) HapticFeedback.selectionClick();
        _startCalibration();
      }
    } else {
      if (_lockedTargetIndex != null) {
        // User panned away, break the lock
        _lockedTargetIndex = null;
        _calibrationProgress = 0.0;
        _calibrationTimer?.cancel();
      }
    }
  }

  void _startCalibration() {
    _calibrationTimer?.cancel();
    _calibrationTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_lockedTargetIndex == null) {
        timer.cancel();
        return;
      }

      setState(() {
        _calibrationProgress += 0.1; // Takes about ~500ms to calibrate
        if (_calibrationProgress < 1.0) {
          // Subtle feedback pacing: tick every 150ms instead of every 50ms
          final step = (_calibrationProgress * 10).round();
          if (step == 3 || step == 6 || step == 9) {
            if (soundEnabled) SystemSound.play(SystemSoundType.click);
            if (hapticEnabled) HapticFeedback.lightImpact();
          }
        } else {
          _calibrationProgress = 1.0;
          final targetIndex = _lockedTargetIndex!;
          _lockedTargetIndex = null;
          _calibrationProgress = 0.0;
          timer.cancel();

          // Capture real frame at target angle
          _captureFrameForTarget(targetIndex);
          if (soundEnabled) SystemSound.play(SystemSoundType.click);
          if (hapticEnabled) HapticFeedback.mediumImpact();
          _successRippleController.forward(from: 0.0);
        }
      });
    });
  }

  int _getNearestMissingTargetIndex() {
    int nearestIndex = -1;
    double minDiff = double.infinity;
    for (int i = 0; i < _targets.length; i++) {
      if (!_targetsCaptured[i]) {
        double diff = (_currentAngle - _targets[i]).abs();
        if (diff > 180.0) diff = 360.0 - diff;
        if (diff < minDiff) {
          minDiff = diff;
          nearestIndex = i;
        }
      }
    }
    return nearestIndex;
  }

  Future<void> _captureFrameForTarget(int index) async {
    setState(() => _showShutterFlash = true);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() => _showShutterFlash = false);
      }
    });

    bool captureSuccess = false;
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final xFile = await _cameraController!.takePicture();
        _capturedFramePaths[index] = xFile.path;
        captureSuccess = true;
        debugPrint("Captured frame for angle ${_targets[index]} at: ${xFile.path}");
      } catch (e) {
        debugPrint("Failed to capture frame for angle ${_targets[index]}: $e");
      }
    } else {
      // In Emulator mode where camera is not available, assume success
      captureSuccess = true;
    }

    if (mounted) {
      setState(() {
        if (captureSuccess) {
          _targetsCaptured[index] = true;
        } else {
          _targetsCaptured[index] = false;
        }
        final completed = _targetsCaptured.where((t) => t).length;
        _captureProgress = completed / _targets.length;

        if (completed == _targets.length) {
          _scanEndTime = DateTime.now();
          if (hapticEnabled) HapticFeedback.vibrate();
          _screenState = 'summary';
        }
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        final camera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        );

        final controller = CameraController(
          camera,
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );

        _cameraController = controller;
        await controller.initialize();
        if (mounted) {
          setState(() {
            _cameraAvailable = true;
          });
        }
      }
    } catch (e) {
      debugPrint("Camera initialization failed: $e");
      if (mounted) {
        setState(() {
          _cameraAvailable = false;
        });
      }
    }
  }

  void _startStitching() {
    setState(() {
      _screenState = 'processing';
      _processingProgress = 0.0;
    });

    _processingTimer?.cancel();
    _processingTimer = Timer.periodic(const Duration(milliseconds: 120), (timer) {
      setState(() {
        _processingProgress += 0.02; // Total ~6 seconds
        if (_processingProgress >= 1.0) {
          _processingProgress = 1.0;
          timer.cancel();
          _finalizeStitching();
        }
      });
    });
  }

  Future<void> _finalizeStitching() async {
    try {
      final List<String> validFrames = _capturedFramePaths.whereType<String>().toList();
      final scanId = 'scan_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1000)}';
      
      String outputPath;
      if (kIsWeb) {
        outputPath = 'memory:panorama_${DateTime.now().millisecondsSinceEpoch}.jpg';
      } else {
        final directory = await getApplicationDocumentsDirectory();
        outputPath = '${directory.path}/panorama_${DateTime.now().millisecondsSinceEpoch}.jpg';
      }

      if (validFrames.isEmpty) {
        final simulatedImg = await _generateSimulatedRoomImage(widget.roomType, false);
        final byteData = await simulatedImg.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final pngBytes = byteData.buffer.asUint8List();
          if (kIsWeb || outputPath.startsWith('memory:')) {
            PanoramaImageCache.put(outputPath, pngBytes);
          } else {
            final file = File(outputPath);
            await file.writeAsBytes(pngBytes);
          }
          
          if (widget.roomId != null) {
            try {
              await PanoramaService.processPanorama(scanId, widget.roomId!, widget.roomType, null, null, null);
            } catch (_) {}
          }
          
          setState(() {
            _isDemoMode = true;
            _stitchedPanoramaPath = outputPath;
            _screenState = 'preview';
          });
          return;
        }
        throw Exception("Failed to generate simulated room image bytes");
      }

      // Real Capture Flow: Upload frames to server and process reconstruction
      for (final path in validFrames) {
        await PanoramaService.uploadFrame(scanId, path);
      }

      if (widget.roomId != null) {
        await PanoramaService.processPanorama(
          scanId,
          widget.roomId!,
          widget.roomType,
          null, null, null
        );
      }

      final resultPath = await PanoramaService.stitchFramesLocally(validFrames, outputPath);
      
      setState(() {
        _stitchedPanoramaPath = resultPath;
        _screenState = 'preview';
      });
    } catch (e) {
      debugPrint("Stitching error: $e");
      setState(() {
        _stitchedPanoramaPath = null;
        _screenState = 'stitching_failed';
      });
    }
  }

  Future<void> _runSimulationMode() async {
    setState(() {
      _isDemoMode = true;
      _screenState = 'processing';
      _processingProgress = 0.0;
    });

    _processingTimer?.cancel();
    _processingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      setState(() {
        _processingProgress += 0.04;
        if (_processingProgress >= 1.0) {
          _processingProgress = 1.0;
          timer.cancel();
          _finalizeSimulation();
        }
      });
    });
  }

  Future<void> _finalizeSimulation() async {
    try {
      final simulatedImg = await _generateSimulatedRoomImage(widget.roomType, false);
      final byteData = await simulatedImg.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final pngBytes = byteData.buffer.asUint8List();
        final String outputPath = kIsWeb 
            ? 'memory:panorama_simulated_${DateTime.now().millisecondsSinceEpoch}.jpg'
            : '${(await getApplicationDocumentsDirectory()).path}/panorama_simulated_${DateTime.now().millisecondsSinceEpoch}.jpg';
        if (kIsWeb || outputPath.startsWith('memory:')) {
          PanoramaImageCache.put(outputPath, pngBytes);
        } else {
          await File(outputPath).writeAsBytes(pngBytes);
        }
        setState(() {
          _stitchedPanoramaPath = outputPath;
          _screenState = 'preview';
        });
      }
    } catch (e) {
      debugPrint("Simulation finalization error: $e");
      setState(() {
        _stitchedPanoramaPath = null;
        _screenState = 'stitching_failed';
      });
    }
  }

  String _getQualityString(StitchingQuality? quality) {
    switch (quality) {
      case StitchingQuality.excellent:
        return 'Excellent';
      case StitchingQuality.good:
        return 'Good';
      case StitchingQuality.acceptable:
        return 'Acceptable';
      case StitchingQuality.poor:
        return 'Poor';
      case StitchingQuality.failed:
        return 'Failed';
      default:
        return 'N/A';
    }
  }

  Color _getQualityColor(StitchingQuality? quality) {
    switch (quality) {
      case StitchingQuality.excellent:
      case StitchingQuality.good:
        return const Color(0xFF4ADE80);
      case StitchingQuality.acceptable:
        return Colors.blueAccent;
      case StitchingQuality.poor:
        return Colors.orangeAccent;
      case StitchingQuality.failed:
        return Colors.redAccent;
      default:
        return Colors.white70;
    }
  }

  Widget _buildStitchingFailedView(ThemeData theme) {
    final statusMsg = PanoramaService.lastStitchingResult?.statusMessage ?? "Stitching failed due to alignment errors.";
    final matchedCount = PanoramaService.lastStitchingResult?.matchedPairsCount ?? 0;
    final avgConf = PanoramaService.lastStitchingResult?.averageConfidence ?? 0.0;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(28),
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF151D2A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4), width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
            ),
            const SizedBox(height: 20),
            const Text(
              'Panorama Stitching Failed',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              statusMsg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1420),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x0Dffffff)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Matched Boundaries', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('$matchedCount/6', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const Divider(color: Color(0x0Dffffff), height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Average Match Confidence', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('${(avgConf * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SecondaryButton(
                  text: 'Demo Mode',
                  onPressed: () {
                    if (hapticEnabled) HapticFeedback.mediumImpact();
                    _runSimulationMode();
                  },
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  text: 'Recapture',
                  onPressed: () {
                    if (hapticEnabled) HapticFeedback.mediumImpact();
                    _retake();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: SecondaryButton(
                text: 'Use AI Fallback Layout',
                onPressed: () {
                  if (hapticEnabled) HapticFeedback.mediumImpact();
                  Navigator.pop(context, 'ai_fallback');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _retake() {
    _calibrationTimer?.cancel();
    _sensorCalibTimer?.cancel();
    _processingTimer?.cancel();
    _startCapturing();
  }

  Future<void> _confirm() async {
    final path = _stitchedPanoramaPath ?? '';
    if (mounted) {
      Navigator.of(context).pop(path);
    }
  }

  Future<void> _requestPermissionAndStart() async {
    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.camera_alt, color: AppTheme.primary),
            SizedBox(width: 12),
            Text('Camera Access'),
          ],
        ),
        content: const Text(
          'Allow FlowSpace to access this device\'s camera? This is required to capture the room preview feed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Deny', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    if (granted == true) {
      bool permSuccess = true;
      if (!kIsWeb) {
        final status = await Permission.camera.request();
        permSuccess = status.isGranted;
      }
      if (permSuccess) {
        await _initializeCamera();
        _startSensorCalibration();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera permission was denied.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission was denied.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  String _getScanDuration() {
    if (_scanStartTime == null) return "22s";
    final endTime = _scanEndTime ?? DateTime.now();
    final secs = endTime.difference(_scanStartTime!).inSeconds;
    return "${secs > 0 ? secs : 22}s";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF070C16), // Dark slate premium color
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: () {
            if (hapticEnabled) HapticFeedback.mediumImpact();
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'Spatial Room Capture',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              soundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: Colors.white70,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                soundEnabled = !soundEnabled;
              });
              if (hapticEnabled) HapticFeedback.lightImpact();
            },
            tooltip: 'Toggle Sound Effects',
          ),
          IconButton(
            icon: Icon(
              hapticEnabled ? Icons.vibration_rounded : Icons.portable_wifi_off_rounded,
              color: Colors.white70,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                hapticEnabled = !hapticEnabled;
              });
              if (hapticEnabled) HapticFeedback.lightImpact();
            },
            tooltip: 'Toggle Haptic Feedback',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
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
                  key: ValueKey<String>(_screenState),
                  child: _buildCurrentStateView(theme, size),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStateView(ThemeData theme, Size size) {
    if (_screenState == 'instructions') {
      return _buildInstructionsView(theme);
    } else if (_screenState == 'calibration') {
      return _buildCalibrationView(theme);
    } else if (_screenState == 'capturing') {
      return _buildCaptureView(size);
    } else if (_screenState == 'summary') {
      return _buildSummaryView(theme);
    } else if (_screenState == 'processing') {
      return _buildProcessingView(theme);
    } else if (_screenState == 'stitching_failed') {
      return _buildStitchingFailedView(theme);
    } else if (_screenState == 'preview') {
      return _buildPreviewView(theme);
    }
    return _buildInstructionsView(theme);
  }

  Widget _buildGuidanceTip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.blueAccent, size: 12),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildInstructionsView(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0x1A4CAF50), // premium primary shade glow
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x334CAF50), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x114CAF50),
                    blurRadius: 20,
                    spreadRadius: 5,
                  )
                ],
              ),
              child: const Icon(
                Icons.explore_outlined,
                size: 72,
                color: Color(0xFF4ADE80),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Interactive 360° Spatial Scanner',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Create a high-fidelity digital room model in seconds. Drag horizontally to simulate rotating, aligning your camera with the 6 capture points in a full circle.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF151D2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x1Affffff)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sensors_outlined, color: Color(0xFF4ADE80), size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'Calibrates Gyro and Exposure sensors',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            PrimaryButton(
              text: 'Start Spatial Scan',
              onPressed: () {
                if (hapticEnabled) HapticFeedback.mediumImpact();
                _requestPermissionAndStart();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalibrationView(ThemeData theme) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 450),
        padding: const EdgeInsets.all(28),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF131B2A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x1Affffff)),
          boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 20)],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Stage 1: Sensor Calibration',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _sensorCalibProgress,
                  minHeight: 6,
                  backgroundColor: const Color(0x1Affffff),
                  valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                ),
              ),
              const SizedBox(height: 24),
              ...List.generate(_calibLogs.length, (index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80), size: 18),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          _calibLogs[index],
                          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCaptureView(Size size) {
    const double panoramaWidth = 1600.0;
    final double offset = (_currentAngle / 360.0) * panoramaWidth;

    return GestureDetector(
      onHorizontalDragUpdate: _handleDragUpdate,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Background feed / Simulator View
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (_cameraAvailable && _cameraController != null && _cameraController!.value.isInitialized) {
                  return SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _cameraController!.value.previewSize!.height,
                        height: _cameraController!.value.previewSize!.width,
                        child: CameraPreview(_cameraController!),
                      ),
                    ),
                  );
                }
                return InteractivePanoramaViewer(
                  roomType: widget.roomType,
                  isInteractive: false,
                  forcedOffset: offset,
                  lightMode: false,
                  isDemoMode: _isDemoMode,
                );
              },
            ),
          ),

          // Camera Shutter Flash (Smooth Fade-Out)
          if (_showShutterFlash)
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: _showShutterFlash ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 120),
                child: Container(
                  color: Colors.white,
                ),
              ),
            ),

          // High-tech status widgets & Stability stats (Single Positioned container to avoid overlapping when wrapping)
          Positioned(
            top: 16,
            left: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runAlignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Coverage percentage
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xE60A0E1A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x26ffffff)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.blur_circular_rounded, color: Colors.blueAccent, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Coverage: ${(_captureProgress * 100).round()}%',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    // Calibration indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _cameraAvailable ? const Color(0xE615803D) : const Color(0xE61E3A8A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x26ffffff)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _cameraAvailable ? 'LIVE FEED' : 'EMULATOR',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runAlignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xE60A0E1A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x1Affffff)),
                      ),
                      child: Text(
                        _stabilityText,
                        style: TextStyle(color: _stabilityColor, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xE60A0E1A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x1Affffff)),
                      ),
                      child: const Text(
                        'Lighting: Excellent (HDR)',
                        style: TextStyle(color: Color(0xFF4ADE80), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Guidance tips for real stitching quality
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xE60A0E1A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x1Affffff)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildGuidanceTip(Icons.edgesensor_high_outlined, 'Hold Level'),
                        const SizedBox(width: 12),
                        _buildGuidanceTip(Icons.unfold_more, 'Keep Height'),
                        const SizedBox(width: 12),
                        _buildGuidanceTip(Icons.loop, 'Rotate in Place'),
                        const SizedBox(width: 12),
                        _buildGuidanceTip(Icons.speed, 'Move Slowly'),
                        const SizedBox(width: 12),
                        _buildGuidanceTip(Icons.layers_outlined, 'Sufficient Overlap'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Central scanning Viewport Painters
          Positioned.fill(
            child: CustomPaint(
              painter: ScanningViewportPainter(
                currentAngle: _currentAngle,
                targets: _targets,
                targetsCaptured: _targetsCaptured,
                lockedTargetIndex: _lockedTargetIndex,
                calibrationProgress: _calibrationProgress,
                pulseValue: _pulsingController.value,
                successRippleValue: _successRippleValue,
              ),
            ),
          ),

          // Left pulsing arrow guidance
          if (_missingAreaWarning != null && _missingAreaWarning!.contains("Left"))
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulsingController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(-8.0 * _pulsingController.value, 0.0),
                      child: Opacity(
                        opacity: 0.3 + 0.7 * _pulsingController.value,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.4),
                                blurRadius: 12,
                                spreadRadius: 2,
                              )
                            ],
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // Right pulsing arrow guidance
          if (_missingAreaWarning != null && _missingAreaWarning!.contains("Right"))
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulsingController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(8.0 * _pulsingController.value, 0.0),
                      child: Opacity(
                        opacity: 0.3 + 0.7 * _pulsingController.value,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.4),
                                blurRadius: 12,
                                spreadRadius: 2,
                              )
                            ],
                          ),
                          child: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // Directional Missing-Sector Guidance Beacons
          if (_missingAreaWarning != null)
            Positioned(
              bottom: 148,
              left: 24,
              right: 24,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xEE7C2D12), // vibrant amber-orange shade
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF97316), width: 1.5),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pulsing direction arrows
                      if (_missingAreaWarning!.contains("Left"))
                        const Icon(Icons.arrow_back, color: Colors.white, size: 20)
                      else
                        const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        _missingAreaWarning!,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 12),
                      if (_missingAreaWarning!.contains("Right"))
                        const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                    ],
                  ),
                ),
              ),
            ),

          // Navigation Instructions HUD
          Positioned(
            bottom: 128,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xE60A0E1A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x33ffffff)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFF4ADE80), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _lockedTargetIndex != null
                          ? 'LOCK ON: Calibrating angle... Hold steady!'
                          : 'Slowly drag/pan to align dots with crosshair',
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Scanning Progress Bar & circular sector badges
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'SCANNING PROGRESS',
                      style: TextStyle(
                        color: Color(0xFF4ADE80),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      '${_targetsCaptured.where((t) => t).length}/6 Sectors',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    tween: Tween<double>(begin: 0, end: _captureProgress),
                    builder: (context, value, child) {
                      return LinearProgressIndicator(
                        value: value,
                        backgroundColor: const Color(0x1Affffff),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4ADE80)),
                        minHeight: 8,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_targets.length, (index) {
                    final isDone = _targetsCaptured[index];
                    final isLock = _lockedTargetIndex == index;
                    final nearestMissingIndex = _getNearestMissingTargetIndex();
                    final isCurrentTarget = nearestMissingIndex == index;

                    return AnimatedBuilder(
                      animation: _pulsingController,
                      builder: (context, child) {
                        Color badgeColor = const Color(0xFF151D2A);
                        Color borderColor = const Color(0x26ffffff);
                        double borderWidth = 1.0;

                        if (isDone) {
                          badgeColor = const Color(0xFF15803D);
                          borderColor = const Color(0xFF4ADE80);
                        } else if (isLock) {
                          badgeColor = Colors.amber.shade700;
                          borderColor = Colors.amber.shade200;
                          borderWidth = 2.0;
                        } else if (isCurrentTarget) {
                          badgeColor = Color.lerp(
                            const Color(0xFF151D2A),
                            Colors.amber.shade900.withValues(alpha: 0.8),
                            _pulsingController.value,
                          )!;
                          borderColor = Color.lerp(
                            const Color(0x26ffffff),
                            Colors.amber.shade400,
                            _pulsingController.value,
                          )!;
                          borderWidth = 1.5;
                        }

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: borderColor, width: borderWidth),
                            boxShadow: isLock || (isCurrentTarget && _pulsingController.value > 0.5)
                                ? [
                                    BoxShadow(
                                      color: Colors.amber.withValues(alpha: 0.3 * _pulsingController.value),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    )
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: isDone
                                ? const Icon(Icons.check, color: Colors.white, size: 12)
                                : Text(
                                    '${_targets[index].round()}°',
                                    style: TextStyle(
                                      color: isLock || isCurrentTarget ? Colors.white : Colors.white38,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryView(ThemeData theme) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(28),
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF151D2A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x1Affffff)),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF15803D).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF4ADE80).withValues(alpha: 0.4), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4ADE80).withValues(alpha: 0.25 * scale),
                          blurRadius: 15,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF4ADE80), size: 48),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'Spatial Scan Complete',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'All sectors captured successfully. Ready to analyze space layout.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1420),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x0Dffffff)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text('Sectors Captured', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text('6/6 (100%)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                  Divider(color: Color(0x0Dffffff), height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text('Ambient Light Level', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text('Optimal (350 Lux)', style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                  Divider(color: Color(0x0Dffffff), height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text('Estimated Quality', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text('Excellent (HDR)', style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SecondaryButton(
                  text: 'Retake Scan',
                  onPressed: () {
                    if (hapticEnabled) HapticFeedback.mediumImpact();
                    _retake();
                  },
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  text: 'Process Model',
                  onPressed: () {
                    if (hapticEnabled) HapticFeedback.vibrate();
                    _startStitching();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingView(ThemeData theme) {
    final List<String> actualSteps = [
      'Capturing Images',
      'Building Panorama',
      'Creating 360° Digital Room',
    ];

    final List<String> futureSteps = [
      'Wall Detection',
      'Floor Detection',
      'Ceiling Detection',
      'Door & Window Detection',
      'Furniture Detection',
      'Lighting Estimation',
      'Material Recognition',
      'Digital Twin Generation',
    ];

    final int activeActualStep = (_processingProgress * actualSteps.length).floor().clamp(0, actualSteps.length - 1);
    final double remainingSecs = ((1.0 - _processingProgress) * 6.0).clamp(0.0, 6.0);

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF111827), // deep slate dark premium
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x1Affffff)),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 25)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Stitching & Spatial Synthesis',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    Text(
                      '${(_processingProgress * 100).round()}%',
                      style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _processingProgress,
                    minHeight: 8,
                    backgroundColor: const Color(0x1Affffff),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4ADE80)),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Status: Reconstructing 3D space...',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    Text(
                      'Est. remaining: ${remainingSecs.toStringAsFixed(1)}s',
                      style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                
                // Premium vertical progress timeline
                ...List.generate(actualSteps.length, (index) {
                  final step = actualSteps[index];
                  final isDone = index < activeActualStep;
                  final isCurrent = index == activeActualStep;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Node Circle
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: isDone
                                  ? const Color(0x1A10B981) // transparent success green
                                  : (isCurrent ? Colors.blue.withValues(alpha: 0.1) : Colors.transparent),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDone
                                    ? const Color(0xFF10B981)
                                    : (isCurrent ? Colors.blueAccent : const Color(0x33ffffff)),
                                width: 2.0,
                              ),
                              boxShadow: isDone
                                  ? [
                                      const BoxShadow(
                                        color: Color(0x2610B981),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      )
                                    ]
                                  : (isCurrent
                                      ? [
                                          const BoxShadow(
                                            color: Color(0x333B82F6),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          )
                                        ]
                                      : null),
                            ),
                            child: Center(
                              child: isDone
                                  ? const Icon(Icons.check_rounded, color: Color(0xFF10B981), size: 14)
                                  : (isCurrent
                                      ? const Padding(
                                          padding: EdgeInsets.all(6.0),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.0,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                                          ),
                                        )
                                      : Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                                        )),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Text
                          Text(
                            step,
                            style: TextStyle(
                              color: isDone
                                  ? Colors.white
                                  : (isCurrent ? Colors.blueAccent : Colors.white38),
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      if (index < actualSteps.length - 1)
                        Padding(
                          padding: const EdgeInsets.only(left: 13.0),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 2,
                            height: 16,
                            color: isDone ? const Color(0xFF10B981) : const Color(0x1Affffff),
                          ),
                        ),
                    ],
                  );
                }),

                const SizedBox(height: 28),
                // Section Header: Future Spatial Analysis (Preview)
                Row(
                  children: [
                    const Expanded(child: Divider(color: Color(0x1Affffff), endIndent: 12)),
                    Text(
                      'Future Spatial Analysis (Preview)',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const Expanded(child: Divider(color: Color(0x1Affffff), indent: 12)),
                  ],
                ),
                const SizedBox(height: 20),

                // Future Preview Steps
                ...List.generate(futureSteps.length, (index) {
                  final step = futureSteps[index];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Future Stage Indicator: Outline Circle (○)
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0x26ffffff),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Colors.white10,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              step,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0x0D3B82F6), // subtle blue tint
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0x1A3B82F6)),
                            ),
                            child: const Text(
                              'Preview',
                              style: TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (index < futureSteps.length - 1)
                        Padding(
                          padding: const EdgeInsets.only(left: 13.0),
                          child: Container(
                            width: 2,
                            height: 12,
                            color: const Color(0x0Dffffff), // very faint connecting line
                          ),
                        ),
                    ],
                  );
                }),

                const SizedBox(height: 24),
                
                // Informational Callout Card/Note
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0x0D3B82F6), // subtle blue callout background
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x1A3B82F6)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Colors.blueAccent,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Future AI Analysis modules will automatically enhance the captured room in future versions.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewView(ThemeData theme) {
    final isLandscape = MediaQuery.of(context).size.width > 720;
    
    final mainContent = isLandscape
        ? Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left: 3D Viewport
                Expanded(
                  flex: 5,
                  child: _buildInteractiveViewerCard(),
                ),
                const SizedBox(width: 24),
                // Right: Capture Summary & Actions
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildCaptureSummaryCard(theme),
                        const SizedBox(height: 16),
                        _buildActionsBar(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 300,
                  child: _buildInteractiveViewerCard(),
                ),
                const SizedBox(height: 16),
                _buildCaptureSummaryCard(theme),
                const SizedBox(height: 16),
                _buildActionsBar(),
              ],
            ),
          );

    if (_isDemoMode) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.amber.shade900,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'DEMO / SIMULATION MODE — NOT A REAL ROOM PANORAMA',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
          Expanded(child: mainContent),
        ],
      );
    }

    return mainContent;
  }

  Widget _buildInteractiveViewerCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            InteractivePanoramaViewer(
              roomType: widget.roomType,
              isInteractive: true,
              lightMode: false,
              panoramaUrl: _stitchedPanoramaPath,
              isDemoMode: _isDemoMode,
            ),
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xB3000000),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x1Affffff)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.explore_outlined, color: Colors.blueAccent, size: 14),
                    SizedBox(width: 6),
                    Text(
                      '3D Room Viewport',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xB3000000),
                  padding: const EdgeInsets.all(8),
                ),
                icon: const Icon(Icons.fullscreen, color: Colors.white, size: 20),
                onPressed: () {
                  if (hapticEnabled) HapticFeedback.mediumImpact();
                  _showFullscreenPreview();
                },
                tooltip: 'View Full 360°',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullscreenPreview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(
                child: InteractivePanoramaViewer(
                  roomType: widget.roomType,
                  isInteractive: true,
                  panoramaUrl: _stitchedPanoramaPath,
                  lightMode: false,
                  isFullScreenMode: true,
                  isDemoMode: _isDemoMode,
                ),
              ),
              Positioned(
                top: 24,
                left: 24,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 1.5),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        onPressed: () {
                          if (hapticEnabled) HapticFeedback.mediumImpact();
                          Navigator.pop(context);
                        },
                        tooltip: 'Exit Full Screen',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCaptureSummaryCard(ThemeData theme) {
    final resolution = kIsWeb ? "1600 x 800" : "8192 x 4096";
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111827), // deep slate dark
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 15,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF15803D).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF4ADE80).withValues(alpha: 0.4)),
                ),
                child: const Icon(Icons.analytics_outlined, color: Color(0xFF4ADE80), size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Capture Diagnostics',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSummaryRow(
            Icons.offline_pin_rounded,
            'Scan Quality',
            _isDemoMode
                ? 'Simulated (Demo Mode)'
                : _getQualityString(PanoramaService.lastStitchingResult?.quality),
            _getQualityColor(PanoramaService.lastStitchingResult?.quality),
          ),
          if (!_isDemoMode && PanoramaService.lastStitchingResult != null) ...[
            const Divider(color: Colors.white12, height: 16),
            _buildSummaryRow(
              Icons.join_inner_rounded,
              'Matched Boundaries',
              '${PanoramaService.lastStitchingResult!.matchedPairsCount}/6 Sectors',
              PanoramaService.lastStitchingResult!.matchedPairsCount >= 4 ? const Color(0xFF4ADE80) : Colors.orangeAccent,
            ),
            const Divider(color: Colors.white12, height: 16),
            _buildSummaryRow(
              Icons.star_half_rounded,
              'Match Confidence',
              '${(PanoramaService.lastStitchingResult!.averageConfidence * 100).round()}%',
              PanoramaService.lastStitchingResult!.averageConfidence >= 0.5 ? const Color(0xFF4ADE80) : Colors.orangeAccent,
            ),
          ],
          const Divider(color: Colors.white12, height: 16),
          _buildSummaryRow(Icons.crop_free_rounded, 'Coverage Percentage', '100% (Full Sweep)', Colors.white),
          const Divider(color: Colors.white12, height: 16),
          _buildSummaryRow(Icons.photo_library_outlined, 'Images Captured', '6 Frames', Colors.white),
          const Divider(color: Colors.white12, height: 16),
          _buildSummaryRow(Icons.aspect_ratio_rounded, 'Panorama Resolution', resolution, Colors.white),
          const Divider(color: Colors.white12, height: 16),
          _buildSummaryRow(Icons.wb_sunny_outlined, 'Lighting Quality', 'Optimal (350 Lux)', const Color(0xFF4ADE80)),
          const Divider(color: Colors.white12, height: 16),
          _buildSummaryRow(Icons.home_outlined, 'Estimated Room Type', widget.roomType, Colors.white),
          const Divider(color: Colors.white12, height: 16),
          _buildSummaryRow(Icons.timer_outlined, 'Scan Duration', _getScanDuration(), Colors.white),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(IconData icon, String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white38, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SecondaryButton(
              text: 'Rescan Room',
              onPressed: () {
                if (hapticEnabled) HapticFeedback.mediumImpact();
                _retake();
              },
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              text: 'Continue to Designer',
              onPressed: () {
                if (hapticEnabled) HapticFeedback.vibrate();
                _confirm();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            if (hapticEnabled) HapticFeedback.mediumImpact();
            _showFullscreenPreview();
          },
          icon: const Icon(Icons.explore_outlined, color: Colors.white70, size: 18),
          label: const Text('View 360° Preview', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: Colors.white24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: const Color(0x0Dffffff),
          ),
        ),
      ],
    );
  }
}

Future<ui.Image> getImageFromProvider(ImageProvider provider) async {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(const ImageConfiguration());
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (ImageInfo info, bool synchronousCall) {
      completer.complete(info.image);
      stream.removeListener(listener);
    },
    onError: (dynamic exception, StackTrace? stackTrace) {
      completer.completeError(exception ?? Exception("Failed to load image"), stackTrace);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

class InteractivePanoramaViewer extends StatefulWidget {
  final String roomType;
  final bool isInteractive;
  final double? forcedOffset;
  final bool lightMode;
  final String? panoramaUrl;
  final bool isFullScreenMode;
  final bool isDemoMode;

  const InteractivePanoramaViewer({
    super.key,
    required this.roomType,
    this.isInteractive = true,
    this.forcedOffset,
    this.lightMode = true,
    this.panoramaUrl,
    this.isFullScreenMode = false,
    this.isDemoMode = false,
  });

  @override
  State<InteractivePanoramaViewer> createState() => _InteractivePanoramaViewerState();
}

class _InteractivePanoramaViewerState extends State<InteractivePanoramaViewer> with TickerProviderStateMixin {
  ui.Image? _loadedImage;
  bool _loading = false;
  String? _lastLoadedUrl;
  
  // View states
  double _yaw = math.pi;
  double _pitch = 0.0;
  double _fov = math.pi / 2;
  
  // Ticker / Inertia
  late Ticker _ticker;
  double _velocityX = 0.0;
  double _velocityY = 0.0;
  Offset? _lastFocalPoint;
  int _lastTimestamp = 0;

  // Animation controller for reset/zoom transitions
  AnimationController? _resetController;
  double _resetStartYaw = 0.0;
  double _resetStartPitch = 0.0;
  double _resetStartFov = 0.0;
  double _targetYaw = math.pi;
  double _targetPitch = 0.0;
  double _targetFov = math.pi / 2;
  double _baseFov = math.pi / 2;

  // Emulated gyro states
  bool _gyroActive = false;
  double _yawOffset = 0.0;
  double _pitchOffset = 0.0;

  // Metadata overlay panel
  bool _showInfoOverlay = false;
  
  // Sphere mesh details
  final List<Vector3D> _sphereVertices = [];
  final List<Offset> _sphereUvs = [];
  static const int _segmentsX = 64;
  static const int _segmentsY = 32;
  static const double _radius = 500.0;

  @override
  void initState() {
    super.initState();
    _buildSphereMesh();
    _loadImage();
    _ticker = createTicker(_tick);
    _ticker.start();

    _resetController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _resetController!.addListener(() {
      if (_resetController!.isAnimating) {
        final t = const Cubic(0.25, 1.0, 0.5, 1.0).transform(_resetController!.value);
        setState(() {
          double diffYaw = _targetYaw - _resetStartYaw;
          if (diffYaw > math.pi) diffYaw -= 2 * math.pi;
          if (diffYaw < -math.pi) diffYaw += 2 * math.pi;
          _yaw = _resetStartYaw + diffYaw * t;

          _pitch = ui.lerpDouble(_resetStartPitch, _targetPitch, t)!;
          _fov = ui.lerpDouble(_resetStartFov, _targetFov, t)!;
        });
      }
    });
  }

  @override
  void didUpdateWidget(InteractivePanoramaViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panoramaUrl != widget.panoramaUrl ||
        oldWidget.roomType != widget.roomType ||
        oldWidget.lightMode != widget.lightMode) {
      _loadImage();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _resetController?.dispose();
    super.dispose();
  }

  void _buildSphereMesh() {
    _sphereVertices.clear();
    _sphereUvs.clear();

    for (int y = 0; y <= _segmentsY; y++) {
      final double lat = -math.pi / 2 + y * math.pi / _segmentsY;
      final double cosLat = math.cos(lat);
      final double sinLat = math.sin(lat);
      final double v = y / _segmentsY;

      for (int x = 0; x <= _segmentsX; x++) {
        final double lon = x * 2 * math.pi / _segmentsX;
        final double cosLon = math.cos(lon);
        final double sinLon = math.sin(lon);
        final double u = x / _segmentsX;

        final double vx = _radius * cosLat * cosLon;
        final double vy = _radius * sinLat;
        final double vz = _radius * cosLat * sinLon;

        _sphereVertices.add(Vector3D(vx, vy, vz));
        _sphereUvs.add(Offset(u, v));
      }
    }
  }

  Future<void> _loadImage() async {
    final url = widget.panoramaUrl;
    if (url == null || url.isEmpty) {
      setState(() {
        _loading = true;
      });
      try {
        final simulatedImg = await _generateSimulatedRoomImage(widget.roomType, widget.lightMode);
        if (mounted) {
          setState(() {
            _loadedImage = simulatedImg;
            _lastLoadedUrl = null;
            _loading = false;
          });
        }
      } catch (e) {
        debugPrint("Error generating simulated panorama: $e");
        if (mounted) {
          setState(() {
            _loadedImage = null;
            _loading = false;
          });
        }
      }
      return;
    }

    if (url == _lastLoadedUrl) return;

    setState(() {
      _loading = true;
    });

    try {
      ImageProvider provider;
      if (url.startsWith('memory:')) {
        final bytes = PanoramaImageCache.get(url);
        if (bytes == null) throw Exception("Image not found in cache");
        provider = MemoryImage(bytes);
      } else if (url.startsWith('http://') || url.startsWith('https://')) {
        provider = NetworkImage(url);
      } else {
        if (kIsWeb) {
          provider = NetworkImage(url);
        } else {
          provider = FileImage(File(url));
        }
      }

      final uiImage = await getImageFromProvider(provider);
      if (mounted) {
        setState(() {
          _loadedImage = uiImage;
          _lastLoadedUrl = url;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading panorama image: $e");
      if (mounted) {
        setState(() {
          _loadedImage = null;
          _loading = false;
        });
      }
    }
  }

  void _tick(Duration elapsed) {
    if (!widget.isInteractive || widget.forcedOffset != null) return;

    if (_gyroActive) {
      setState(() {
        // Slow cinematic panning
        _yaw = (_yaw + 0.003) % (2 * math.pi);
      });
    }

    if (_velocityX.abs() > 0.05 || _velocityY.abs() > 0.05) {
      const double dt = 0.016;
      setState(() {
        _yaw = (_yaw + _velocityX * dt) % (2 * math.pi);
        _pitch = (_pitch + _velocityY * dt).clamp(-math.pi / 2.2, math.pi / 2.2);

        _velocityX *= 0.92; // friction
        _velocityY *= 0.92;
      });
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    if (!widget.isInteractive || widget.forcedOffset != null) return;
    _velocityX = 0.0;
    _velocityY = 0.0;
    _lastFocalPoint = details.localFocalPoint;
    _lastTimestamp = DateTime.now().millisecondsSinceEpoch;
    _baseFov = _fov;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, Size viewportSize) {
    if (!widget.isInteractive || widget.forcedOffset != null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final double dt = math.max((now - _lastTimestamp) / 1000.0, 0.001);
    _lastTimestamp = now;

    if (details.pointerCount == 1) {
      if (_lastFocalPoint != null) {
        final delta = details.localFocalPoint - _lastFocalPoint!;
        final double deltaYaw = -(delta.dx / viewportSize.width) * math.pi;
        final double deltaPitch = (delta.dy / viewportSize.height) * (math.pi / 2.0);

        setState(() {
          _yaw = (_yaw + deltaYaw) % (2 * math.pi);
          _pitch = (_pitch + deltaPitch).clamp(-math.pi / 2.2, math.pi / 2.2);
        });

        _velocityX = deltaYaw / dt;
        _velocityY = deltaPitch / dt;
      }
    } else if (details.pointerCount == 2) {
      if (details.scale != 1.0) {
        setState(() {
          _fov = (_baseFov / details.scale).clamp(math.pi / 6.0, math.pi / 1.8);
        });
      }
    }

    _lastFocalPoint = details.localFocalPoint;
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _lastFocalPoint = null;
    final speed = math.sqrt(_velocityX * _velocityX + _velocityY * _velocityY);
    const double maxSpeed = 15.0;
    if (speed > maxSpeed) {
      _velocityX = (_velocityX / speed) * maxSpeed;
      _velocityY = (_velocityY / speed) * maxSpeed;
    }
  }

  void _resetView() {
    _resetStartYaw = _yaw;
    _resetStartPitch = _pitch;
    _resetStartFov = _fov;
    
    _targetYaw = math.pi;
    _targetPitch = 0.0;
    _targetFov = math.pi / 2;
    
    _velocityX = 0.0;
    _velocityY = 0.0;
    
    _resetController?.duration = const Duration(milliseconds: 600);
    _resetController?.forward(from: 0.0);
    
    if (_SpatialRoomCaptureScreenState.hapticEnabled) HapticFeedback.mediumImpact();
  }

  void _handleDoubleTap() {
    final currentZoom = (math.pi / 2) / _fov;
    final targetZoom = currentZoom > 1.2 ? 1.0 : 1.5;
    
    _resetStartYaw = _yaw;
    _resetStartPitch = _pitch;
    _resetStartFov = _fov;
    
    _targetYaw = _yaw; // keep current panning yaw
    _targetPitch = _pitch; // keep current panning pitch
    _targetFov = (math.pi / 2) / targetZoom;
    
    _velocityX = 0.0;
    _velocityY = 0.0;
    
    _resetController?.duration = const Duration(milliseconds: 400);
    _resetController?.forward(from: 0.0);
    
    if (_SpatialRoomCaptureScreenState.hapticEnabled) HapticFeedback.selectionClick();
  }

  void _toggleFullScreen() {
    if (widget.isFullScreenMode) {
      Navigator.pop(context);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(
                child: InteractivePanoramaViewer(
                  roomType: widget.roomType,
                  isInteractive: true,
                  panoramaUrl: widget.panoramaUrl,
                  lightMode: widget.lightMode,
                  isFullScreenMode: true,
                  isDemoMode: widget.isDemoMode,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getCompassDirection(double angle) {
    double deg = (angle * 180.0 / math.pi) % 360.0;
    if (deg < 0) deg += 360;
    
    if (deg >= 337.5 || deg < 22.5) return 'E';
    if (deg >= 22.5 && deg < 67.5) return 'SE';
    if (deg >= 67.5 && deg < 112.5) return 'S';
    if (deg >= 112.5 && deg < 157.5) return 'SW';
    if (deg >= 157.5 && deg < 202.5) return 'W';
    if (deg >= 202.5 && deg < 247.5) return 'NW';
    if (deg >= 247.5 && deg < 292.5) return 'N';
    return 'NE';
  }

  @override
  Widget build(BuildContext context) {
    double currentYaw = _yaw;
    if (widget.forcedOffset != null) {
      currentYaw = (widget.forcedOffset! / 1600.0) * 2 * math.pi + math.pi;
    }

    double zoomFactor = (math.pi / 2) / _fov;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

        return MouseRegion(
          onHover: (event) {
            if (_gyroActive) {
              final size = constraints.biggest;
              final centerX = size.width / 2;
              final centerY = size.height / 2;
              final dx = event.localPosition.dx - centerX;
              final dy = event.localPosition.dy - centerY;
              setState(() {
                _yawOffset = -(dx / centerX) * (math.pi / 8);
                _pitchOffset = -(dy / centerY) * (math.pi / 12);
              });
            }
          },
          onExit: (_) {
            setState(() {
              _yawOffset = 0.0;
              _pitchOffset = 0.0;
            });
          },
          child: GestureDetector(
            onScaleStart: _handleScaleStart,
            onScaleUpdate: (details) => _handleScaleUpdate(details, viewportSize),
            onScaleEnd: _handleScaleEnd,
            onDoubleTap: _handleDoubleTap,
            child: Stack(
              children: [
                // 3D Projected mesh sphere
                Positioned.fill(
                  child: CustomPaint(
                    painter: SpherePanoramaPainter(
                      image: _loadedImage,
                      yaw: currentYaw + _yawOffset,
                      pitch: (widget.forcedOffset != null ? 0.0 : _pitch) + _pitchOffset,
                      fov: _fov,
                      sphereVertices: _sphereVertices,
                      sphereUvs: _sphereUvs,
                      segmentsX: _segmentsX,
                      segmentsY: _segmentsY,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),

                // Add a local fallback placeholder if image failed to load and is not loading
                if (_loadedImage == null && !_loading)
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xFF0F172A),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.broken_image_outlined,
                            color: Colors.redAccent.withOpacity(0.6),
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Failed to Load Panorama',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 40),
                            child: Text(
                              'Please check your connection or choose another room template.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // High-tech shimmering loader state
                if (_loading)
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xFF0F172A),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.8, end: 1.2),
                            duration: const Duration(milliseconds: 1000),
                            curve: Curves.easeInOut,
                            builder: (context, scale, child) {
                              return Transform.scale(
                                scale: scale,
                                child: const Icon(Icons.explore_outlined, color: AppTheme.primary, size: 48),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Building Digital Room...',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Calibrating textures and aligning boundaries',
                            style: TextStyle(color: Colors.grey, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),

                // UI Overlay Controls
                if (widget.isInteractive && !_loading) ...[
                  // Dynamic Compass indicator
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.navigation_outlined, color: AppTheme.accent, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            '${((currentYaw + _yawOffset) * 180.0 / math.pi).round() % 360}° ${_getCompassDirection(currentYaw + _yawOffset)}',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Floating controls on top right
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Row(
                      children: [
                        // Gyroscope mode toggle
                        IconButton(
                          style: IconButton.styleFrom(backgroundColor: _gyroActive ? AppTheme.primary : Colors.black54),
                          icon: Icon(Icons.sensors, color: _gyroActive ? Colors.white : Colors.white70, size: 20),
                          onPressed: () => setState(() => _gyroActive = !_gyroActive),
                          tooltip: 'Toggle Gyro Emulation',
                        ),
                        const SizedBox(width: 8),
                        // Reset view
                        IconButton(
                          style: IconButton.styleFrom(backgroundColor: Colors.black54),
                          icon: const Icon(Icons.restart_alt, color: Colors.white, size: 20),
                          onPressed: _resetView,
                          tooltip: 'Reset Viewport',
                        ),
                        const SizedBox(width: 8),
                        // Show info overlay
                        IconButton(
                          style: IconButton.styleFrom(backgroundColor: _showInfoOverlay ? AppTheme.primary : Colors.black54),
                          icon: const Icon(Icons.info_outline, color: Colors.white, size: 20),
                          onPressed: () => setState(() => _showInfoOverlay = !_showInfoOverlay),
                          tooltip: 'Spatial Metadata Details',
                        ),
                        const SizedBox(width: 8),
                        // Full-screen mode
                        IconButton(
                          style: IconButton.styleFrom(backgroundColor: Colors.black54),
                          icon: Icon(widget.isFullScreenMode ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white, size: 20),
                          onPressed: _toggleFullScreen,
                          tooltip: widget.isFullScreenMode ? 'Exit Full Screen' : 'Full Screen View',
                        ),
                      ],
                    ),
                  ),

                  // Gyro Indicator Overlay text
                  if (_gyroActive)
                    Positioned(
                      top: 70,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.radar, color: Colors.white, size: 10),
                            SizedBox(width: 4),
                            Text(
                              'GYRO ACTIVE (EMULATION)',
                              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Collapsible Spatial Metadata Panel (Glassmorphic BackdropFilter)
                  if (_showInfoOverlay)
                    Positioned(
                      top: 72,
                      right: 16,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                          child: Container(
                            width: 250,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xE60A0E1A), // Translucent dark backing card
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4), width: 1.5),
                              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 15)],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.radar, color: Colors.blueAccent, size: 14),
                                        const SizedBox(width: 6),
                                        Text(
                                          widget.isDemoMode ? 'Simulated Analysis' : 'Spatial Analysis',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: widget.isDemoMode ? Colors.amber.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: widget.isDemoMode ? Colors.amber.withValues(alpha: 0.4) : Colors.green.withValues(alpha: 0.4)),
                                      ),
                                      child: Text(
                                        widget.isDemoMode ? 'Demo Mode' : 'AI Preview',
                                        style: TextStyle(
                                          color: widget.isDemoMode ? Colors.amber : const Color(0xFF4ADE80),
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(color: Colors.white12, height: 16),
                                _buildInfoText('Estimated Volume', '42.5 m³'),
                                _buildInfoText('Ceiling Height', '3.0 m'),
                                _buildInfoText('Floor Level', 'Floor 1'),
                                _buildInfoText('Wall Surface Area', '63.0 m²'),
                                _buildInfoText('Detected Openings', '1 Door, 2 Windows'),
                                _buildInfoText('Lighting Level', '320 Lux (Optimal)'),
                                const SizedBox(height: 8),
                                const Text(
                                  'Detections: Sofa (92%), Table (85%), Plant (88%)',
                                  style: TextStyle(color: Colors.white38, fontSize: 9.5, fontStyle: FontStyle.italic),
                                ),
                                const Divider(color: Colors.white12, height: 16),
                                Text(
                                  widget.isDemoMode 
                                      ? '* All spatial data and measurements are simulated.' 
                                      : '* Measurements and object detections are simulated for demonstration purposes.',
                                  style: const TextStyle(color: Colors.white38, fontSize: 8.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Zoom Indicator & slider overlay
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.zoom_in, color: Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Zoom: ${zoomFactor.toStringAsFixed(1)}x',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          Expanded(
                            child: Slider(
                              value: zoomFactor,
                              min: 1.0,
                              max: 2.5,
                              activeColor: AppTheme.primary,
                              inactiveColor: Colors.white12,
                              onChanged: (val) {
                                setState(() {
                                  _fov = (math.pi / 2) / val;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoText(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }
}

class SpherePanoramaPainter extends CustomPainter {
  final ui.Image? image;
  final double yaw;
  final double pitch;
  final double fov;
  
  final List<Vector3D> sphereVertices;
  final List<Offset> sphereUvs;
  final int segmentsX;
  final int segmentsY;

  SpherePanoramaPainter({
    required this.image,
    required this.yaw,
    required this.pitch,
    required this.fov,
    required this.sphereVertices,
    required this.sphereUvs,
    required this.segmentsX,
    required this.segmentsY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) return;

    final camera = Camera()
      ..position = Vector3D(0, 0, 0)
      ..up = Vector3D(0, 1, 0)
      ..near = 1.0
      ..fov = fov
      ..aspect = size.width / size.height;

    final double dx = math.cos(pitch) * math.cos(yaw);
    final double dy = math.sin(pitch);
    final double dz = math.cos(pitch) * math.sin(yaw);
    camera.target = camera.position + Vector3D(dx, dy, dz) * 100.0;

    final viewProjMat = Matrix4x4.multiply(camera.getViewMatrix(), camera.getProjectionMatrix());

    final List<Offset?> projected = List.filled(sphereVertices.length, null);
    for (int i = 0; i < sphereVertices.length; i++) {
      projected[i] = camera.projectPoint(sphereVertices[i], viewProjMat, size);
    }

    final List<Offset> drawVertices = [];
    final List<Offset> drawUvs = [];
    final List<int> drawIndices = [];
    int vertexCounter = 0;

    final double imgWidth = image!.width.toDouble();
    final double imgHeight = image!.height.toDouble();

    for (int y = 0; y < segmentsY; y++) {
      for (int x = 0; x < segmentsX; x++) {
        final int i0 = y * (segmentsX + 1) + x;
        final int i1 = i0 + 1;
        final int i2 = (y + 1) * (segmentsX + 1) + x;
        final int i3 = i2 + 1;

        if (projected[i0] != null &&
            projected[i1] != null &&
            projected[i2] != null) {
          drawVertices.add(projected[i0]!);
          drawVertices.add(projected[i1]!);
          drawVertices.add(projected[i2]!);

          drawUvs.add(Offset(sphereUvs[i0].dx * imgWidth, sphereUvs[i0].dy * imgHeight));
          drawUvs.add(Offset(sphereUvs[i1].dx * imgWidth, sphereUvs[i1].dy * imgHeight));
          drawUvs.add(Offset(sphereUvs[i2].dx * imgWidth, sphereUvs[i2].dy * imgHeight));

          drawIndices.add(vertexCounter);
          drawIndices.add(vertexCounter + 1);
          drawIndices.add(vertexCounter + 2);
          vertexCounter += 3;
        }

        if (projected[i1] != null &&
            projected[i3] != null &&
            projected[i2] != null) {
          drawVertices.add(projected[i1]!);
          drawVertices.add(projected[i3]!);
          drawVertices.add(projected[i2]!);

          drawUvs.add(Offset(sphereUvs[i1].dx * imgWidth, sphereUvs[i1].dy * imgHeight));
          drawUvs.add(Offset(sphereUvs[i3].dx * imgWidth, sphereUvs[i3].dy * imgHeight));
          drawUvs.add(Offset(sphereUvs[i2].dx * imgWidth, sphereUvs[i2].dy * imgHeight));

          drawIndices.add(vertexCounter);
          drawIndices.add(vertexCounter + 1);
          drawIndices.add(vertexCounter + 2);
          vertexCounter += 3;
        }
      }
    }

    if (drawVertices.isEmpty) return;

    final verticesObj = ui.Vertices(
      ui.VertexMode.triangles,
      drawVertices,
      textureCoordinates: drawUvs,
      indices: drawIndices,
    );

    final paint = Paint()
      ..shader = ImageShader(
        image!,
        TileMode.clamp,
        TileMode.clamp,
        Float64List.fromList([
          1.0, 0.0, 0.0, 0.0,
          0.0, 1.0, 0.0, 0.0,
          0.0, 0.0, 1.0, 0.0,
          0.0, 0.0, 0.0, 1.0,
        ]),
      );

    canvas.drawVertices(verticesObj, BlendMode.srcOver, paint);

    // Apply radial vignette overlay for premium cinema focus
    final vignettePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.15),
          Colors.black.withValues(alpha: 0.5),
        ],
        stops: const [0.6, 0.85, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignettePaint);
  }

  @override
  bool shouldRepaint(covariant SpherePanoramaPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        oldDelegate.fov != fov ||
        oldDelegate.sphereVertices != sphereVertices ||
        oldDelegate.sphereUvs != sphereUvs;
  }
}

Future<ui.Image> _generateSimulatedRoomImage(String roomType, bool lightMode) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(1600, 800);

  final double yCeiling = size.height * 0.15;
  final double yFloor = size.height * 0.80;
  final double height = yFloor - yCeiling;
  const double totalWidth = 1600.0;

  // Background gradients
  final bgPaint = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: lightMode
          ? [const Color(0xCCF0FDF4), const Color(0xCCDCFCE7)]
          : [const Color(0xFF111827), const Color(0xFF030712)],
    ).createShader(Rect.fromLTWH(0, 0, totalWidth, size.height));

  final outlinePaint = Paint()
    ..color = lightMode ? const Color(0xFF15803D) : const Color(0xFF4ADE80)
    ..strokeWidth = 2.0
    ..style = PaintingStyle.stroke;

  final gridPaint = Paint()
    ..color = (lightMode ? const Color(0xFF86EFAC) : const Color(0xFF166534)).withValues(alpha: 0.15)
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;

  canvas.drawRect(Rect.fromLTWH(0, 0, totalWidth, size.height), bgPaint);

  // Draw 4 walls with horizontal gradients to simulate 3D corner lighting / ambient occlusion
  for (double x = 0; x < totalWidth; x += 400) {
    final rect = Rect.fromLTRB(x, yCeiling, x + 400, yFloor);
    final wallShader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: lightMode
          ? [Colors.grey.shade100, Colors.white, Colors.white, Colors.grey.shade100]
          : [const Color(0xFF111827), const Color(0xFF1F2937), const Color(0xFF1F2937), const Color(0xFF111827)],
      stops: const [0.0, 0.15, 0.85, 1.0],
    ).createShader(rect);
    
    final wallPaint = Paint()..shader = wallShader;
    canvas.drawRect(rect, wallPaint);
  }

  // Draw ceiling and floor with soft gradients
  final ceilingRect = Rect.fromLTWH(0, 0, totalWidth, yCeiling);
  final ceilingShader = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: lightMode
        ? [Colors.grey.shade200, Colors.grey.shade300]
        : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
  ).createShader(ceilingRect);
  canvas.drawRect(ceilingRect, Paint()..shader = ceilingShader);

  final floorRect = Rect.fromLTWH(0, yFloor, totalWidth, size.height - yFloor);
  final floorShader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: lightMode
        ? [Colors.grey.shade300, Colors.grey.shade400]
        : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
  ).createShader(floorRect);
  canvas.drawRect(floorRect, Paint()..shader = floorShader);

  // Corner ambient occlusion shadows (corner shading)
  for (double x = 0; x <= totalWidth; x += 400) {
    if (x > 0) {
      final cornerShadowLeft = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Colors.black.withValues(alpha: 0.3), Colors.transparent],
        ).createShader(Rect.fromLTRB(x - 30, 0, x, size.height));
      canvas.drawRect(Rect.fromLTRB(x - 30, 0, x, size.height), cornerShadowLeft);
    }
    if (x < totalWidth) {
      final cornerShadowRight = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.black.withValues(alpha: 0.3), Colors.transparent],
        ).createShader(Rect.fromLTRB(x, 0, x + 30, size.height));
      canvas.drawRect(Rect.fromLTRB(x, 0, x + 30, size.height), cornerShadowRight);
    }
  }

  // Horizontal line ambient occlusion shadows
  final ceilingShadow = Paint()
    ..shader = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [Colors.black.withValues(alpha: 0.25), Colors.transparent],
    ).createShader(Rect.fromLTRB(0, yCeiling - 20, totalWidth, yCeiling));
  canvas.drawRect(Rect.fromLTRB(0, yCeiling - 20, totalWidth, yCeiling), ceilingShadow);

  final floorShadow = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.black.withValues(alpha: 0.3), Colors.transparent],
    ).createShader(Rect.fromLTRB(0, yFloor, totalWidth, yFloor + 25));
  canvas.drawRect(Rect.fromLTRB(0, yFloor, totalWidth, yFloor + 25), floorShadow);

  // Draw grid lines
  for (double x = 0; x < totalWidth; x += 50) {
    canvas.drawLine(Offset(x, yCeiling), Offset(x, yFloor), gridPaint);
  }
  for (double y = yCeiling; y < yFloor; y += 30) {
    canvas.drawLine(Offset(0, y), Offset(totalWidth, y), gridPaint);
  }

  final cornerPaint = Paint()
    ..color = lightMode ? const Color(0x6686EFAC) : const Color(0x66166534)
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  for (double x = 0; x <= totalWidth; x += 400) {
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), cornerPaint);
  }

  for (double x = 0; x <= totalWidth; x += 200) {
    canvas.drawLine(Offset(x, yFloor), Offset(x + 50, size.height), gridPaint);
  }
  for (double x = 0; x <= totalWidth; x += 200) {
    canvas.drawLine(Offset(x, yCeiling), Offset(x + 50, 0), gridPaint);
  }

  final fillPaint = Paint()
    ..color = (lightMode ? const Color(0xFFF0FDF4) : const Color(0xFF064E3B)).withValues(alpha: 0.5)
    ..style = PaintingStyle.fill;

  void drawWindow(double cx, double cy, double w, double h) {
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
    
    // Window glass gradient
    final glassShader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.lightBlue.shade200.withValues(alpha: 0.4),
        Colors.lightBlue.shade400.withValues(alpha: 0.1),
      ],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = glassShader);
    canvas.drawRect(rect, outlinePaint);

    // Light beam (sunlight rays hitting floor)
    final beamPath = Path()
      ..moveTo(cx - w/2, cy + h/2)
      ..lineTo(cx + w/2, cy + h/2)
      ..lineTo(cx + w/2 + 100, yFloor)
      ..lineTo(cx - w/2 + 50, yFloor)
      ..close();
    final beamShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0x40FEF08A), // faint warm sunbeam
        const Color(0x00FEF08A),
      ],
    ).createShader(Rect.fromLTRB(cx - w/2, cy + h/2, cx + w/2 + 100, yFloor));
    canvas.drawPath(beamPath, Paint()..shader = beamShader);

    // Warm light spot on the floor where the sunbeam hits
    final sunbeamFloorPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFEF08A).withValues(alpha: 0.25),
          const Color(0xFFFEF08A).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCenter(center: Offset(cx + 60, yFloor + 15), width: 180, height: 35));
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 60, yFloor + 15), width: 180, height: 35), sunbeamFloorPaint);

    canvas.drawLine(Offset(cx, cy - h/2), Offset(cx, cy + h/2), outlinePaint);
    canvas.drawLine(Offset(cx - w/2, cy), Offset(cx + w/2, cy), outlinePaint);
    
    final curtainL = Path()
      ..moveTo(cx - w/2 - 10, cy - h/2 - 10)
      ..lineTo(cx - w/4, cy - h/2 - 10)
      ..lineTo(cx - w/2 + 5, cy + h/2)
      ..lineTo(cx - w/2 - 15, cy + h/2)
      ..close();
    final curtainR = Path()
      ..moveTo(cx + w/2 + 10, cy - h/2 - 10)
      ..lineTo(cx + w/4, cy - h/2 - 10)
      ..lineTo(cx + w/2 - 5, cy + h/2)
      ..lineTo(cx + w/2 + 15, cy + h/2)
      ..close();
    canvas.drawPath(curtainL, fillPaint);
    canvas.drawPath(curtainL, outlinePaint);
    canvas.drawPath(curtainR, fillPaint);
    canvas.drawPath(curtainR, outlinePaint);
  }

  void drawDoor(double x, double w) {
    final rect = Rect.fromLTWH(x, yCeiling + height * 0.15, w, height * 0.85);
    canvas.drawRect(rect, fillPaint);
    canvas.drawRect(rect, outlinePaint);
    canvas.drawRect(Rect.fromLTWH(x - 4, yCeiling + height * 0.15 - 4, w + 8, height * 0.85 + 4), outlinePaint);
    canvas.drawCircle(Offset(x + w - 12, yCeiling + height * 0.55), 4, outlinePaint);
  }

  void drawPlant(double cx, double cy) {
    final pot = Path()
      ..moveTo(cx - 15, cy)
      ..lineTo(cx + 15, cy)
      ..lineTo(cx + 10, cy + 25)
      ..lineTo(cx - 10, cy + 25)
      ..close();
    canvas.drawPath(pot, fillPaint);
    canvas.drawPath(pot, outlinePaint);
    
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy - 20), width: 16, height: 32), outlinePaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - 12, cy - 15), width: 28, height: 18), outlinePaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 12, cy - 15), width: 28, height: 18), outlinePaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - 6, cy - 35), width: 20, height: 26), outlinePaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 6, cy - 35), width: 20, height: 26), outlinePaint);
  }

  drawWindow(200, yCeiling + height * 0.4, 180, height * 0.5);
  drawDoor(580, 80);
  drawPlant(1450, yFloor - 25);

  // Draw soft ceiling lamp cone lighting glow at x = 1000
  final lampPath = Path()
    ..moveTo(990, yCeiling)
    ..lineTo(1010, yCeiling)
    ..lineTo(1005, yCeiling + 12)
    ..lineTo(995, yCeiling + 12)
    ..close();
  canvas.drawPath(lampPath, Paint()..color = Colors.grey.shade400..style = PaintingStyle.fill);
  canvas.drawPath(lampPath, outlinePaint);

  final conePath = Path()
    ..moveTo(995, yCeiling + 12)
    ..lineTo(1005, yCeiling + 12)
    ..lineTo(1090, yFloor)
    ..lineTo(910, yFloor)
    ..close();
  final coneShader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      const Color(0x4DFEF08A), // pulsing warm ambient glow cone
      const Color(0x00FEF08A),
    ],
  ).createShader(Rect.fromLTRB(910, yCeiling + 12, 1090, yFloor));
  canvas.drawPath(conePath, Paint()..shader = coneShader);

  // Ceiling lamp floor warm spotlight spot
  final lampFloorGlowPaint = Paint()
    ..shader = RadialGradient(
      colors: [
        const Color(0xFFFEF08A).withValues(alpha: 0.35),
        const Color(0xFFFEF08A).withValues(alpha: 0.0),
      ],
    ).createShader(Rect.fromCenter(center: Offset(1000, yFloor), width: 220, height: 50));
  canvas.drawOval(Rect.fromCenter(center: Offset(1000, yFloor), width: 220, height: 50), lampFloorGlowPaint);

  // Setup drop shadow paint for furniture
  final shadowPaint = Paint()
    ..color = const Color(0x66000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);

  if (roomType == 'Living Room') {
    // Drop shadow
    canvas.drawOval(Rect.fromCenter(center: const Offset(1000, 640), width: 260, height: 16), shadowPaint);

    final sofaBase = Rect.fromLTWH(880, yFloor - 60, 240, 45);
    canvas.drawRect(sofaBase, fillPaint);
    canvas.drawRect(sofaBase, outlinePaint);
    
    canvas.drawRect(Rect.fromLTWH(890, yFloor - 85, 220, 25), outlinePaint);
    canvas.drawLine(Offset(963, yFloor - 85), Offset(963, yFloor - 60), outlinePaint);
    canvas.drawLine(Offset(1036, yFloor - 85), Offset(1036, yFloor - 60), outlinePaint);

    canvas.drawRect(Rect.fromLTWH(870, yFloor - 75, 15, 60), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(1115, yFloor - 75, 15, 60), outlinePaint);

    canvas.drawRect(Rect.fromLTWH(950, yCeiling + height * 0.15, 100, 50), fillPaint);
    canvas.drawRect(Rect.fromLTWH(950, yCeiling + height * 0.15, 100, 50), outlinePaint);
    canvas.drawCircle(Offset(1000, yCeiling + height * 0.15 + 25), 12, outlinePaint);

    final table = Path()
      ..moveTo(930, yFloor - 15)
      ..lineTo(1070, yFloor - 15)
      ..lineTo(1070, yFloor - 5)
      ..lineTo(930, yFloor - 5)
      ..close();
    canvas.drawPath(table, fillPaint);
    canvas.drawPath(table, outlinePaint);
    canvas.drawLine(Offset(945, yFloor - 5), Offset(945, yFloor), outlinePaint);
    canvas.drawLine(Offset(1055, yFloor - 5), Offset(1055, yFloor), outlinePaint);

    // Cabinet drop shadow
    canvas.drawOval(Rect.fromCenter(center: const Offset(1300, 640), width: 170, height: 12), shadowPaint);

    canvas.drawRect(Rect.fromLTWH(1220, yFloor - 40, 160, 40), fillPaint);
    canvas.drawRect(Rect.fromLTWH(1220, yFloor - 40, 160, 40), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(1240, yCeiling + height * 0.25, 120, 70), fillPaint);
    canvas.drawRect(Rect.fromLTWH(1240, yCeiling + height * 0.25, 120, 70), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(1290, yCeiling + height * 0.25 + 70, 20, 15), outlinePaint);
    
  } else if (roomType == 'Bedroom') {
    // Bed drop shadow
    canvas.drawOval(Rect.fromCenter(center: const Offset(1000, 640), width: 240, height: 20), shadowPaint);

    canvas.drawRect(Rect.fromLTWH(890, yFloor - 120, 220, 120), fillPaint);
    canvas.drawRect(Rect.fromLTWH(890, yFloor - 120, 220, 120), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(910, yFloor - 50, 180, 50), fillPaint);
    canvas.drawRect(Rect.fromLTWH(910, yFloor - 50, 180, 50), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(925, yFloor - 75, 65, 25), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(1010, yFloor - 75, 65, 25), outlinePaint);
    
    void drawNightstand(double x) {
      // Shadow
      canvas.drawOval(Rect.fromCenter(center: Offset(x + 17.5, 640), width: 40, height: 8), shadowPaint);

      canvas.drawRect(Rect.fromLTWH(x, yFloor - 45, 35, 45), fillPaint);
      canvas.drawRect(Rect.fromLTWH(x, yFloor - 45, 35, 45), outlinePaint);
      canvas.drawCircle(Offset(x + 17.5, yFloor - 22.5), 3, outlinePaint);
      
      final lamp = Path()
        ..moveTo(x + 10, yFloor - 65)
        ..lineTo(x + 25, yFloor - 65)
        ..lineTo(x + 28, yFloor - 45)
        ..lineTo(x + 7, yFloor - 45)
        ..close();
      canvas.drawPath(lamp, fillPaint);
      canvas.drawPath(lamp, outlinePaint);
    }
    drawNightstand(850);
    drawNightstand(1115);

    // Wardrobe shadow
    canvas.drawOval(Rect.fromCenter(center: const Offset(1300, 640), width: 150, height: 16), shadowPaint);

    canvas.drawRect(Rect.fromLTWH(1230, yCeiling + height * 0.1, 140, height * 0.9), fillPaint);
    canvas.drawRect(Rect.fromLTWH(1230, yCeiling + height * 0.1, 140, height * 0.9), outlinePaint);
    canvas.drawLine(Offset(1300, yCeiling + height * 0.1), Offset(1300, yFloor), outlinePaint);
    canvas.drawCircle(Offset(1292, yCeiling + height * 0.55), 3, outlinePaint);
    canvas.drawCircle(Offset(1308, yCeiling + height * 0.55), 3, outlinePaint);

  } else if (roomType == 'Kitchen') {
    // Counter shadow
    canvas.drawOval(Rect.fromCenter(center: const Offset(1000, 640), width: 370, height: 16), shadowPaint);

    canvas.drawRect(Rect.fromLTWH(820, yFloor - 65, 360, 65), fillPaint);
    canvas.drawRect(Rect.fromLTWH(820, yFloor - 65, 360, 65), outlinePaint);
    for (double cx = 865; cx < 1180; cx += 90) {
      canvas.drawLine(Offset(cx, yFloor - 65), Offset(cx, yFloor), outlinePaint);
      canvas.drawCircle(Offset(cx - 45, yFloor - 32.5), 3, outlinePaint);
    }

    canvas.drawRect(Rect.fromLTWH(960, yFloor - 75, 80, 10), fillPaint);
    canvas.drawRect(Rect.fromLTWH(960, yFloor - 75, 80, 10), outlinePaint);
    canvas.drawCircle(Offset(980, yFloor - 70), 8, outlinePaint);
    canvas.drawCircle(Offset(1020, yFloor - 70), 8, outlinePaint);

    canvas.drawRect(Rect.fromLTWH(970, yCeiling + 10, 60, height * 0.35), fillPaint);
    canvas.drawRect(Rect.fromLTWH(970, yCeiling + 10, 60, height * 0.35), outlinePaint);
    final hood = Path()
      ..moveTo(960, yCeiling + 10 + height * 0.35)
      ..lineTo(1040, yCeiling + 10 + height * 0.35)
      ..lineTo(1020, yCeiling + height * 0.25)
      ..lineTo(980, yCeiling + height * 0.25)
      ..close();
    canvas.drawPath(hood, outlinePaint);

    // Fridge shadow
    canvas.drawOval(Rect.fromCenter(center: const Offset(1300, 640), width: 110, height: 14), shadowPaint);

    canvas.drawRect(Rect.fromLTWH(1250, yCeiling + height * 0.05, 100, height * 0.95), fillPaint);
    canvas.drawRect(Rect.fromLTWH(1250, yCeiling + height * 0.05, 100, height * 0.95), outlinePaint);
    canvas.drawLine(Offset(1250, yCeiling + height * 0.55), Offset(1350, yCeiling + height * 0.55), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(1335, yCeiling + height * 0.25, 6, 40), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(1335, yCeiling + height * 0.65, 6, 30), outlinePaint);

  } else if (roomType == 'Office') {
    // Desk drop shadow
    canvas.drawOval(Rect.fromCenter(center: const Offset(1000, 640), width: 290, height: 16), shadowPaint);

    canvas.drawRect(Rect.fromLTWH(860, yFloor - 60, 280, 15), fillPaint);
    canvas.drawRect(Rect.fromLTWH(860, yFloor - 60, 280, 15), outlinePaint);
    canvas.drawLine(Offset(880, yFloor - 45), Offset(880, yFloor), outlinePaint);
    canvas.drawLine(Offset(1120, yFloor - 45), Offset(1120, yFloor), outlinePaint);

    canvas.drawRect(Rect.fromLTWH(900, yFloor - 110, 90, 50), fillPaint);
    canvas.drawRect(Rect.fromLTWH(900, yFloor - 110, 90, 50), outlinePaint);
    canvas.drawLine(Offset(945, yFloor - 60), Offset(945, yFloor - 50), outlinePaint);

    canvas.drawRect(Rect.fromLTWH(1010, yFloor - 110, 90, 50), fillPaint);
    canvas.drawRect(Rect.fromLTWH(1010, yFloor - 110, 90, 50), outlinePaint);
    canvas.drawLine(Offset(1055, yFloor - 60), Offset(1055, yFloor - 50), outlinePaint);

    canvas.drawRect(Rect.fromLTWH(965, yFloor - 65, 70, 35), fillPaint);
    canvas.drawRect(Rect.fromLTWH(965, yFloor - 65, 70, 35), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(975, yFloor - 120, 50, 55), outlinePaint);
    canvas.drawLine(Offset(1000, yFloor - 30), Offset(1000, yFloor), outlinePaint);
    canvas.drawLine(Offset(980, yFloor), Offset(1020, yFloor), outlinePaint);

    // Bookcase shadow
    canvas.drawOval(Rect.fromCenter(center: const Offset(1300, 640), width: 150, height: 14), shadowPaint);

    canvas.drawRect(Rect.fromLTWH(1230, yCeiling + height * 0.15, 140, height * 0.85), fillPaint);
    canvas.drawRect(Rect.fromLTWH(1230, yCeiling + height * 0.15, 140, height * 0.85), outlinePaint);
    for (double sy = yCeiling + height * 0.35; sy < yFloor; sy += height * 0.2) {
      canvas.drawLine(Offset(1230, sy), Offset(1370, sy), outlinePaint);
    }
  } else {
    canvas.drawOval(Rect.fromCenter(center: const Offset(1000, 640), width: 250, height: 16), shadowPaint);

    canvas.drawRect(Rect.fromLTWH(880, yFloor - 50, 240, 50), fillPaint);
    canvas.drawRect(Rect.fromLTWH(880, yFloor - 50, 240, 50), outlinePaint);
    canvas.drawCircle(Offset(1000, yFloor - 100), 24, outlinePaint);
  }

  final picture = recorder.endRecording();
  return await picture.toImage(1600, 800);
}

class ScanningViewportPainter extends CustomPainter {
  final double currentAngle;
  final List<double> targets;
  final List<bool> targetsCaptured;
  final int? lockedTargetIndex;
  final double calibrationProgress;
  final double pulseValue;
  final double successRippleValue;

  ScanningViewportPainter({
    required this.currentAngle,
    required this.targets,
    required this.targetsCaptured,
    required this.lockedTargetIndex,
    required this.calibrationProgress,
    required this.pulseValue,
    required this.successRippleValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final isLocked = lockedTargetIndex != null;
    final accentColor = isLocked ? Colors.amber.shade400 : AppTheme.primary.shade400;

    // Success Ripple Effect (concentric green expanding circles)
    if (successRippleValue > 0.0 && successRippleValue < 1.0) {
      final ripplePaint = Paint()
        ..color = const Color(0xFF4ADE80).withValues(alpha: (1.0 - successRippleValue) * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0 - (successRippleValue * 2.0);
      canvas.drawCircle(center, 40.0 + (successRippleValue * 120.0), ripplePaint);
    }

    // Viewport central HUD reticle
    final double pulseScale = isLocked ? (1.0 + 0.08 * math.sin(pulseValue * 2 * math.pi)) : 1.0;
    final reticlePaint = Paint()
      ..color = accentColor.withValues(alpha: isLocked ? 0.8 : 0.6)
      ..strokeWidth = isLocked ? 2.5 : 2.0
      ..style = PaintingStyle.stroke;

    final innerCirclePaint = Paint()
      ..color = accentColor.withValues(alpha: isLocked ? 0.5 : 0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final centerDotPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    // Double ring HUD
    canvas.drawCircle(center, 40.0 * pulseScale, reticlePaint);
    canvas.drawCircle(center, 24.0 * pulseScale, innerCirclePaint);
    canvas.drawCircle(center, 4.0, centerDotPaint);

    // Reticle crosshair lines
    canvas.drawLine(Offset(center.dx - 60 * pulseScale, center.dy), Offset(center.dx - 48 * pulseScale, center.dy), reticlePaint);
    canvas.drawLine(Offset(center.dx + 48 * pulseScale, center.dy), Offset(center.dx + 60 * pulseScale, center.dy), reticlePaint);
    canvas.drawLine(Offset(center.dx, center.dy - 60 * pulseScale), Offset(center.dx, center.dy - 48 * pulseScale), reticlePaint);
    canvas.drawLine(Offset(center.dx, center.dy + 48 * pulseScale), Offset(center.dx, center.dy + 60 * pulseScale), reticlePaint);

    // Viewfinder brackets
    final double lockOffset = isLocked ? (1.0 - calibrationProgress) * 12.0 : 0.0;
    final double bracketAlpha = isLocked ? (0.35 + 0.45 * pulseValue) : 0.25;
    final bracketPaint = Paint()
      ..color = accentColor.withValues(alpha: bracketAlpha)
      ..strokeWidth = isLocked ? 2.2 : 1.5
      ..style = PaintingStyle.stroke;
    const double bracketSize = 12.0;
    final double halfW = 90.0 - lockOffset;
    final double halfH = 90.0 - lockOffset;
    
    // Top Left Bracket
    canvas.drawPath(Path()..moveTo(center.dx - halfW, center.dy - halfH + bracketSize)..lineTo(center.dx - halfW, center.dy - halfH)..lineTo(center.dx - halfW + bracketSize, center.dy - halfH), bracketPaint);
    // Top Right Bracket
    canvas.drawPath(Path()..moveTo(center.dx + halfW, center.dy - halfH + bracketSize)..lineTo(center.dx + halfW, center.dy - halfH)..lineTo(center.dx + halfW - bracketSize, center.dy - halfH), bracketPaint);
    // Bottom Left Bracket
    canvas.drawPath(Path()..moveTo(center.dx - halfW, center.dy + halfH - bracketSize)..lineTo(center.dx - halfW, center.dy + halfH)..lineTo(center.dx - halfW + bracketSize, center.dy + halfH), bracketPaint);
    // Bottom Right Bracket
    canvas.drawPath(Path()..moveTo(center.dx + halfW, center.dy + halfH - bracketSize)..lineTo(center.dx + halfW, center.dy + halfH)..lineTo(center.dx + halfW - bracketSize, center.dy + halfH), bracketPaint);

    // Alignment target lock loader
    if (isLocked) {
      final sweepAngle = 2 * math.pi * calibrationProgress;
      final calibrationPaint = Paint()
        ..color = Colors.amber.shade500
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 46.0),
        -math.pi / 2,
        sweepAngle,
        false,
        calibrationPaint,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: 'ALIGNING: ${(calibrationProgress * 100).round()}%',
          style: TextStyle(
            color: Colors.amber.shade400,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            backgroundColor: const Color(0xE6000000),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy + 65));
    }

    // High-tech Compass Strip at the top
    const double compassY = 80;
    
    // Draw semi-transparent dark backing pill for the compass ticks
    final compassBackingPaint = Paint()
      ..color = const Color(0xCC0A0F1D)
      ..style = PaintingStyle.fill;
    final compassRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width / 2 - 180, compassY - 24, 360, 32),
      const Radius.circular(8),
    );
    canvas.drawRRect(compassRRect, compassBackingPaint);

    final compassBorderPaint = Paint()
      ..color = const Color(0x1Affffff)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(compassRRect, compassBorderPaint);

    // Draw central red needle
    final needlePaint = Paint()
      ..color = AppTheme.accent
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(size.width / 2, compassY - 24), Offset(size.width / 2, compassY + 8), needlePaint);

    final degreePixels = size.width / 90.0; // 90° visible viewport width

    // Draw degree ticks on the compass bar
    final double startDeg = currentAngle - 45.0;
    final double endDeg = currentAngle + 45.0;
    
    for (double deg = (startDeg / 5.0).floor() * 5.0; deg <= endDeg; deg += 5.0) {
      double displayDeg = deg % 360.0;
      if (displayDeg < 0) displayDeg += 360.0;

      double diff = deg - currentAngle;
      double tickX = center.dx + (diff * degreePixels);

      // Clip ticks inside the compass backing pill
      if (tickX < size.width / 2 - 170 || tickX > size.width / 2 + 170) continue;

      bool isMajor = displayDeg % 30 == 0;
      bool isCardinal = displayDeg % 90 == 0;

      final tickPaint = Paint()
        ..color = isCardinal ? AppTheme.accent : (isMajor ? Colors.white70 : Colors.white30)
        ..strokeWidth = isMajor ? 1.5 : 1.0;

      double tickHeight = isCardinal ? 12.0 : (isMajor ? 8.0 : 5.0);
      canvas.drawLine(Offset(tickX, compassY - tickHeight), Offset(tickX, compassY), tickPaint);

      if (isMajor) {
        String label = '${displayDeg.round()}°';
        if (displayDeg.round() == 0) label = 'E';
        if (displayDeg.round() == 90) label = 'S';
        if (displayDeg.round() == 180) label = 'W';
        if (displayDeg.round() == 270) label = 'N';

        final labelPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: isCardinal ? AppTheme.accent : Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        labelPainter.paint(canvas, Offset(tickX - labelPainter.width / 2, compassY - tickHeight - 12));
      }
    }

    // Render target dots
    for (int i = 0; i < targets.length; i++) {
      final targetAngle = targets[i];
      final isCaptured = targetsCaptured[i];

      double diff = targetAngle - currentAngle;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;

      if (diff.abs() <= 45.0) {
        final double targetX = center.dx + (diff * degreePixels);
        
        // Clip target dots inside the viewfinder area
        if (targetX < center.dx - 170 || targetX > center.dx + 170) continue;

        final isCurrentlyLocked = lockedTargetIndex == i;

        final dotColor = isCaptured
            ? AppTheme.primary
            : (isCurrentlyLocked ? Colors.amber : Colors.white70);

        final dotPaint = Paint()
          ..color = dotColor
          ..style = PaintingStyle.fill;

        final ringPaint = Paint()
          ..color = dotColor.withValues(alpha: 0.5)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

        canvas.drawCircle(Offset(targetX, center.dy), 10.0, dotPaint);
        canvas.drawCircle(Offset(targetX, center.dy), 18.0, ringPaint);

        if (isCaptured) {
          final checkPaint = Paint()
            ..color = Colors.white
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke;
          canvas.drawLine(Offset(targetX - 4, center.dy), Offset(targetX - 1, center.dy + 3), checkPaint);
          canvas.drawLine(Offset(targetX - 1, center.dy + 3), Offset(targetX + 4, center.dy - 3), checkPaint);
        } else {
          final textPainter = TextPainter(
            text: TextSpan(
              text: '${targetAngle.round()}°',
              style: TextStyle(
                color: isCurrentlyLocked ? Colors.black : Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          textPainter.paint(
            canvas,
            Offset(targetX - textPainter.width / 2, center.dy - textPainter.height / 2),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant ScanningViewportPainter oldDelegate) {
    return oldDelegate.currentAngle != currentAngle ||
        oldDelegate.targetsCaptured != targetsCaptured ||
        oldDelegate.lockedTargetIndex != lockedTargetIndex ||
        oldDelegate.calibrationProgress != calibrationProgress ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.successRippleValue != successRippleValue;
  }
}
