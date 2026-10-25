import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../presentation/graphics_3d.dart';
import 'designer_provider.dart';

// --- CAMERA VIEW MODES ---
enum ViewMode {
  perspective,
  top,
  front,
  left,
  right,
  isometric,
  free,
  orbit,
}

// --- CAMERA NAVIGATION SETTINGS ---
class NavigationSettings {
  final double fov; // in radians
  final double near;
  final double far;
  final double movementSpeed;
  final double rotationSpeed;
  final double zoomSpeed;

  NavigationSettings({
    this.fov = pi / 4.0, // 45 degrees
    this.near = 10.0,
    this.far = 8000.0,
    this.movementSpeed = 6.0,
    this.rotationSpeed = 0.005,
    this.zoomSpeed = 30.0,
  });

  NavigationSettings copyWith({
    double? fov,
    double? near,
    double? far,
    double? movementSpeed,
    double? rotationSpeed,
    double? zoomSpeed,
  }) {
    return NavigationSettings(
      fov: fov ?? this.fov,
      near: near ?? this.near,
      far: far ?? this.far,
      movementSpeed: movementSpeed ?? this.movementSpeed,
      rotationSpeed: rotationSpeed ?? this.rotationSpeed,
      zoomSpeed: zoomSpeed ?? this.zoomSpeed,
    );
  }
}

// --- CAMERA STATE (IMMUTABLE WITH CACHED MATRICES) ---
class CameraState {
  // Actual values (current frame)
  final Vector3D position;
  final Vector3D target;
  final Vector3D up;
  final double orbitRadius;
  final double azimuth;
  final double elevation;
  final double walkYaw;
  final double walkPitch;
  final double eyeHeight;
  final double feetHeight;
  final double targetFeetHeight;

  // Target values (destination for interpolation)
  final Vector3D targetPosition;
  final Vector3D targetTarget;
  final double targetOrbitRadius;
  final double targetAzimuth;
  final double targetElevation;
  final double targetWalkYaw;
  final double targetWalkPitch;

  // Projection options
  final double fov;
  final double near;
  final double far;
  final double aspect;

  // Cached Matrices (computed during object creation)
  final Matrix4x4 viewMatrix;
  final Matrix4x4 projectionMatrix;
  final Matrix4x4 viewProjectionMatrix;

  CameraState({
    required this.position,
    required this.target,
    required this.up,
    required this.orbitRadius,
    required this.azimuth,
    required this.elevation,
    required this.walkYaw,
    required this.walkPitch,
    required this.eyeHeight,
    this.feetHeight = 0.0,
    this.targetFeetHeight = 0.0,
    required this.targetPosition,
    required this.targetTarget,
    required this.targetOrbitRadius,
    required this.targetAzimuth,
    required this.targetElevation,
    required this.targetWalkYaw,
    required this.targetWalkPitch,
    required this.fov,
    required this.near,
    required this.far,
    required this.aspect,
  })  : viewMatrix = Matrix4x4.lookAt(position, target, up),
        projectionMatrix = Matrix4x4.perspective(fov, aspect, near, far),
        viewProjectionMatrix = Matrix4x4.multiply(
          Matrix4x4.lookAt(position, target, up),
          Matrix4x4.perspective(fov, aspect, near, far),
        );

  CameraState copyWith({
    Vector3D? position,
    Vector3D? target,
    Vector3D? up,
    double? orbitRadius,
    double? azimuth,
    double? elevation,
    double? walkYaw,
    double? walkPitch,
    double? eyeHeight,
    double? feetHeight,
    double? targetFeetHeight,
    Vector3D? targetPosition,
    Vector3D? targetTarget,
    double? targetOrbitRadius,
    double? targetAzimuth,
    double? targetElevation,
    double? targetWalkYaw,
    double? targetWalkPitch,
    double? fov,
    double? near,
    double? far,
    double? aspect,
  }) {
    return CameraState(
      position: position ?? this.position,
      target: target ?? this.target,
      up: up ?? this.up,
      orbitRadius: orbitRadius ?? this.orbitRadius,
      azimuth: azimuth ?? this.azimuth,
      elevation: elevation ?? this.elevation,
      walkYaw: walkYaw ?? this.walkYaw,
      walkPitch: walkPitch ?? this.walkPitch,
      eyeHeight: eyeHeight ?? this.eyeHeight,
      feetHeight: feetHeight ?? this.feetHeight,
      targetFeetHeight: targetFeetHeight ?? this.targetFeetHeight,
      targetPosition: targetPosition ?? this.targetPosition,
      targetTarget: targetTarget ?? this.targetTarget,
      targetOrbitRadius: targetOrbitRadius ?? this.targetOrbitRadius,
      targetAzimuth: targetAzimuth ?? this.targetAzimuth,
      targetElevation: targetElevation ?? this.targetElevation,
      targetWalkYaw: targetWalkYaw ?? this.targetWalkYaw,
      targetWalkPitch: targetWalkPitch ?? this.targetWalkPitch,
      fov: fov ?? this.fov,
      near: near ?? this.near,
      far: far ?? this.far,
      aspect: aspect ?? this.aspect,
    );
  }

  // Convert immutable CameraState to standard graphics Camera for compatibility
  Camera toCamera() {
    final cam = Camera();
    cam.position = position;
    cam.target = target;
    cam.up = up;
    cam.fov = fov;
    cam.aspect = aspect;
    cam.near = near;
    // Set orbit/walk parameters on the target camera object
    cam.orbitRadius = orbitRadius;
    cam.azimuth = azimuth;
    cam.elevation = elevation;
    cam.walkYaw = walkYaw;
    cam.walkPitch = walkPitch;
    cam.eyeHeight = eyeHeight;
    return cam;
  }

  // Project point directly using cached viewProjectionMatrix
  Offset? projectPoint(Vector3D v, Size viewportSize) {
    final x = v.x * viewProjectionMatrix.m[0] + v.y * viewProjectionMatrix.m[4] + v.z * viewProjectionMatrix.m[8] + viewProjectionMatrix.m[12];
    final y = v.x * viewProjectionMatrix.m[1] + v.y * viewProjectionMatrix.m[5] + v.z * viewProjectionMatrix.m[9] + viewProjectionMatrix.m[13];
    final w = v.x * viewProjectionMatrix.m[3] + v.y * viewProjectionMatrix.m[7] + v.z * viewProjectionMatrix.m[11] + viewProjectionMatrix.m[15];

    if (w <= 0.0) return null;

    final ndcX = x / w;
    final ndcY = y / w;

    final sx = (ndcX + 1.0) * viewportSize.width / 2.0;
    final sy = (1.0 - ndcY) * viewportSize.height / 2.0;
    return Offset(sx, sy);
  }
}

// --- VIEW MODE NOTIFIER ---
class ViewModeNotifier extends Notifier<ViewMode> {
  @override
  ViewMode build() {
    return ViewMode.orbit;
  }

  void setMode(ViewMode mode) {
    state = mode;
    ref.read(cameraProvider.notifier).onViewModeChanged(mode);
  }
}

// --- NAVIGATION NOTIFIER ---
class NavigationNotifier extends Notifier<NavigationSettings> {
  @override
  NavigationSettings build() {
    return NavigationSettings();
  }

  void updateSettings({
    double? fov,
    double? near,
    double? far,
    double? movementSpeed,
    double? rotationSpeed,
    double? zoomSpeed,
  }) {
    state = state.copyWith(
      fov: fov,
      near: near,
      far: far,
      movementSpeed: movementSpeed,
      rotationSpeed: rotationSpeed,
      zoomSpeed: zoomSpeed,
    );
    // Propagate fov, near, far to camera state
    ref.read(cameraProvider.notifier).updateProjectionParams(
      fov: fov,
      near: near,
      far: far,
    );
  }
}

// --- CAMERA NOTIFIER ---
class CameraNotifier extends Notifier<CameraState> {
  @override
  CameraState build() {
    return CameraState(
      position: Vector3D(0, 300, 500),
      target: Vector3D(0, 50, 0),
      up: Vector3D(0, 1, 0),
      orbitRadius: 900.0,
      azimuth: pi / 4.0,
      elevation: pi / 6.0,
      walkYaw: -pi / 2,
      walkPitch: 0.0,
      eyeHeight: 160.0,
      feetHeight: 0.0,
      targetFeetHeight: 0.0,
      targetPosition: Vector3D(0, 300, 500),
      targetTarget: Vector3D(0, 50, 0),
      targetOrbitRadius: 900.0,
      targetAzimuth: pi / 4.0,
      targetElevation: pi / 6.0,
      targetWalkYaw: -pi / 2,
      targetWalkPitch: 0.0,
      fov: pi / 4.0,
      near: 10.0,
      far: 8000.0,
      aspect: 1.0,
    );
  }

  void updateAspect(double aspect) {
    if (state.aspect != aspect) {
      state = state.copyWith(aspect: aspect);
    }
  }

  void updateProjectionParams({double? fov, double? near, double? far}) {
    state = state.copyWith(
      fov: fov,
      near: near,
      far: far,
    );
  }

  void zoom(double zoomDelta, bool isFree) {
    if (isFree) {
      final F = (state.target - state.position).normalize();
      final move = F * (-zoomDelta * 5.0);
      state = state.copyWith(
        targetPosition: state.targetPosition + move,
      );
    } else {
      state = state.copyWith(
        targetOrbitRadius: (state.targetOrbitRadius + zoomDelta).clamp(50.0, 3000.0),
      );
    }
  }

  void pan(double dx, double dy) {
    final F = (state.target - state.position).normalize();
    final R = F.cross(state.up).normalize();
    final U = R.cross(F).normalize();

    // Scale sensitivity by camera distance
    final sensitivity = state.orbitRadius * 0.0015;
    final delta = (R * (-dx * sensitivity)) + (U * (dy * sensitivity));

    state = state.copyWith(
      targetTarget: state.targetTarget + delta,
      targetPosition: state.targetPosition + delta,
      target: state.target + delta,
      position: state.position + delta,
    );
  }

  void rotate(double dx, double dy, double rotationSpeed, bool isFree) {
    if (isFree) {
      state = state.copyWith(
        targetWalkYaw: state.targetWalkYaw + dx * rotationSpeed,
        targetWalkPitch: (state.targetWalkPitch - dy * rotationSpeed).clamp(-pi / 2.2, pi / 2.2),
      );
    } else {
      state = state.copyWith(
        targetAzimuth: state.targetAzimuth - dx * rotationSpeed,
        targetElevation: (state.targetElevation + dy * rotationSpeed).clamp(0.02, pi / 2.02),
      );
    }
  }

  void fitCameraToRoom(double roomWidth, double roomLength, double roomHeight) {
    final cx = roomWidth / 2.0;
    final cz = roomLength / 2.0;
    final eyeY = 160.0;
    final pos = Vector3D(cx, eyeY, cz + 30.0);
    final tgt = Vector3D(cx, eyeY - 20.0, cz - 80.0);
    state = state.copyWith(
      position: pos,
      target: tgt,
      targetPosition: pos,
      targetTarget: tgt,
    );
    clampCameraToRoom(roomWidth, roomLength, roomHeight);
  }

  void clampCameraToRoom(double roomWidth, double roomLength, double roomHeight) {
    const margin = 20.0;
    final minX = margin;
    final maxX = (roomWidth <= margin * 2) ? roomWidth : roomWidth - margin;
    final minZ = margin;
    final maxZ = (roomLength <= margin * 2) ? roomLength : roomLength - margin;
    final minY = 30.0;
    final maxY = (roomHeight <= 50.0) ? roomHeight : roomHeight - 20.0;

    final clampedX = state.position.x.clamp(minX, maxX);
    final clampedY = state.position.y.clamp(minY, maxY);
    final clampedZ = state.position.z.clamp(minZ, maxZ);

    final newPos = Vector3D(clampedX, clampedY, clampedZ);
    if (newPos.x != state.position.x || newPos.y != state.position.y || newPos.z != state.position.z) {
      state = state.copyWith(
        position: newPos,
        targetPosition: newPos,
      );
    }
  }

  void resetToRoom(DesignerLayoutState layout, {bool snap = false}) {
    // Calculate room bounds
    double minX = 0.0, maxX = 600.0;
    double minZ = 0.0, maxZ = 450.0;

    if (layout.walls.isNotEmpty) {
      minX = double.infinity; maxX = -double.infinity;
      minZ = double.infinity; maxZ = -double.infinity;
      for (final w in layout.walls) {
        minX = min(minX, min(w.start.dx, w.end.dx));
        maxX = max(maxX, max(w.start.dx, w.end.dx));
        minZ = min(minZ, min(w.start.dy, w.end.dy));
        maxZ = max(maxZ, max(w.start.dy, w.end.dy));
      }
    }

    final roomWid = maxX - minX;
    final roomLen = maxZ - minZ;
    final cx = (minX + maxX) / 2.0;
    final cz = (minZ + maxZ) / 2.0;
    
    // Target the center of the room at a reasonable eye height
    final targetCenter = Vector3D(cx, 50.0, cz);
    
    // Orbit radius scales with room dimensions for proper framing
    final targetRadius = max(max(roomWid, roomLen) * 1.3, 400.0);

    final isometricAzimuth = pi / 4.0;
    final isometricElevation = pi / 6.0;

    final pos = Vector3D(
      cx + targetRadius * cos(isometricElevation) * cos(isometricAzimuth),
      50.0 + targetRadius * sin(isometricElevation),
      cz + targetRadius * cos(isometricElevation) * sin(isometricAzimuth),
    );

    if (snap) {
      state = state.copyWith(
        position: pos,
        target: targetCenter,
        orbitRadius: targetRadius,
        azimuth: isometricAzimuth,
        elevation: isometricElevation,
        targetPosition: pos,
        targetTarget: targetCenter,
        targetOrbitRadius: targetRadius,
        targetAzimuth: isometricAzimuth,
        targetElevation: isometricElevation,
      );
    } else {
      state = state.copyWith(
        targetPosition: pos,
        targetTarget: targetCenter,
        targetOrbitRadius: targetRadius,
        targetAzimuth: isometricAzimuth,
        targetElevation: isometricElevation,
      );
    }
  }

  void resetToWalkthrough(DesignerLayoutState layout) {
    double minX = -300.0, maxX = 300.0;
    double minZ = -225.0, maxZ = 225.0;

    if (layout.walls.isNotEmpty) {
      minX = double.infinity; maxX = -double.infinity;
      minZ = double.infinity; maxZ = -double.infinity;
      for (final w in layout.walls) {
        minX = min(minX, min(w.start.dx, w.end.dx));
        maxX = max(maxX, max(w.start.dx, w.end.dx));
        minZ = min(minZ, min(w.start.dy, w.end.dy));
        maxZ = max(maxZ, max(w.start.dy, w.end.dy));
      }
    }
    
    final cx = minX + (maxX - minX) / 2;
    final cz = maxZ - 80.0; 
    
    final eyeHt = state.eyeHeight;
    final startPos = Vector3D(cx, eyeHt, cz);
    
    state = state.copyWith(
      position: startPos,
      target: startPos + Vector3D(0, 0, -100.0),
      orbitRadius: 900.0,
      azimuth: 0.0,
      elevation: 0.0,
      walkYaw: -pi / 2,
      walkPitch: 0.0,
      feetHeight: 0.0,
      targetFeetHeight: 0.0,
      targetPosition: startPos,
      targetTarget: startPos + Vector3D(0, 0, -100.0),
      targetOrbitRadius: 900.0,
      targetAzimuth: 0.0,
      targetElevation: 0.0,
      targetWalkYaw: -pi / 2,
      targetWalkPitch: 0.0,
    );
  }

  void focusFurniture(PlacedFurniture f, {bool snap = false}) {
    final targetCenter = Vector3D(f.x, f.y + f.height / 2.0, f.z);
    final targetRadius = max(f.width, f.depth) * 3.0;

    if (snap) {
      final cxPos = targetCenter.x + targetRadius * cos(state.elevation) * cos(state.azimuth);
      final cyPos = targetCenter.y + targetRadius * sin(state.elevation);
      final czPos = targetCenter.z + targetRadius * cos(state.elevation) * sin(state.azimuth);
      final targetPos = Vector3D(cxPos, cyPos, czPos);

      state = state.copyWith(
        position: targetPos,
        target: targetCenter,
        orbitRadius: targetRadius,
        targetPosition: targetPos,
        targetTarget: targetCenter,
        targetOrbitRadius: targetRadius,
      );
    } else {
      state = state.copyWith(
        targetTarget: targetCenter,
        targetOrbitRadius: targetRadius,
      );
    }
  }

  void onViewModeChanged(ViewMode mode) {
    final r = state.targetOrbitRadius;

    switch (mode) {
      case ViewMode.perspective:
      case ViewMode.orbit:
        state = state.copyWith(
          targetAzimuth: pi / 4.0,
          targetElevation: pi / 6.0,
          targetOrbitRadius: r,
          up: Vector3D(0, 1, 0),
        );
        break;
      case ViewMode.top:
        state = state.copyWith(
          targetAzimuth: pi / 2.0,
          targetElevation: pi / 2.0 - 0.001,
          targetOrbitRadius: r,
          up: Vector3D(0, 0, -1),
        );
        break;
      case ViewMode.front:
        state = state.copyWith(
          targetAzimuth: pi / 2.0,
          targetElevation: 0.02,
          targetOrbitRadius: r,
          up: Vector3D(0, 1, 0),
        );
        break;
      case ViewMode.left:
        state = state.copyWith(
          targetAzimuth: 0.0,
          targetElevation: 0.02,
          targetOrbitRadius: r,
          up: Vector3D(0, 1, 0),
        );
        break;
      case ViewMode.right:
        state = state.copyWith(
          targetAzimuth: pi,
          targetElevation: 0.02,
          targetOrbitRadius: r,
          up: Vector3D(0, 1, 0),
        );
        break;
      case ViewMode.isometric:
        state = state.copyWith(
          targetAzimuth: pi / 4.0,
          targetElevation: 35.26 * pi / 180.0,
          targetOrbitRadius: r,
          up: Vector3D(0, 1, 0),
        );
        break;
      case ViewMode.free:
        state = state.copyWith(
          targetPosition: state.position,
          targetWalkYaw: state.walkYaw,
          targetWalkPitch: state.walkPitch,
        );
        break;
    }
  }

  bool _isInsideAnyFurniture(Vector3D pos, List<PlacedFurniture> furniture) {
    for (final f in furniture) {
      final dx = pos.x - f.x;
      final dz = pos.z - f.z;
      final rotatedX = dx * cos(f.rotationY) + dz * sin(f.rotationY);
      final rotatedZ = -dx * sin(f.rotationY) + dz * cos(f.rotationY);

      final halfW = f.width / 2.0;
      final halfD = f.depth / 2.0;

      if (rotatedX.abs() < halfW + 15.0 &&
          pos.y >= f.y && pos.y <= f.y + f.height + 15.0 &&
          rotatedZ.abs() < halfD + 15.0) {
        return true;
      }
    }
    return false;
  }

  void tick({
    required Set<LogicalKeyboardKey> pressedKeys,
    required bool isFreeOrWalkthrough,
    required DesignerLayoutState layout,
    bool isWalkthrough = false,
    Offset joystickValue = Offset.zero,
  }) {
    final settings = ref.read(navigationProvider);

    if (isFreeOrWalkthrough) {
      final moveSpeed = settings.movementSpeed;
      double dx = 0.0;
      double dy = 0.0;
      double dz = 0.0;

      if (isWalkthrough) {
        if (pressedKeys.contains(LogicalKeyboardKey.keyW) || pressedKeys.contains(LogicalKeyboardKey.arrowUp)) {
          dx += cos(state.walkYaw);
          dz += sin(state.walkYaw);
        }
        if (pressedKeys.contains(LogicalKeyboardKey.keyS) || pressedKeys.contains(LogicalKeyboardKey.arrowDown)) {
          dx -= cos(state.walkYaw);
          dz -= sin(state.walkYaw);
        }
        if (pressedKeys.contains(LogicalKeyboardKey.keyA) || pressedKeys.contains(LogicalKeyboardKey.arrowLeft)) {
          dx += sin(state.walkYaw);
          dz -= cos(state.walkYaw);
        }
        if (pressedKeys.contains(LogicalKeyboardKey.keyD) || pressedKeys.contains(LogicalKeyboardKey.arrowRight)) {
          dx -= sin(state.walkYaw);
          dz += cos(state.walkYaw);
        }
        
        if (joystickValue != Offset.zero) {
          final joyForward = -joystickValue.dy;
          final joyStrafe = joystickValue.dx;
          dx += joyForward * cos(state.walkYaw) - joyStrafe * sin(state.walkYaw);
          dz += joyForward * sin(state.walkYaw) + joyStrafe * cos(state.walkYaw);
        }
      } else {
        if (pressedKeys.contains(LogicalKeyboardKey.keyW) || pressedKeys.contains(LogicalKeyboardKey.arrowUp)) {
          dx += cos(state.walkYaw);
          dz += sin(state.walkYaw);
        }
        if (pressedKeys.contains(LogicalKeyboardKey.keyS) || pressedKeys.contains(LogicalKeyboardKey.arrowDown)) {
          dx -= cos(state.walkYaw);
          dz -= sin(state.walkYaw);
        }
        if (pressedKeys.contains(LogicalKeyboardKey.keyA) || pressedKeys.contains(LogicalKeyboardKey.arrowLeft)) {
          dx += sin(state.walkYaw);
          dz -= cos(state.walkYaw);
        }
        if (pressedKeys.contains(LogicalKeyboardKey.keyD) || pressedKeys.contains(LogicalKeyboardKey.arrowRight)) {
          dx -= sin(state.walkYaw);
          dz += cos(state.walkYaw);
        }
        if (pressedKeys.contains(LogicalKeyboardKey.keyQ)) {
          dy += 1.0;
        }
        if (pressedKeys.contains(LogicalKeyboardKey.keyE)) {
          dy -= 1.0;
        }
      }

      if (dx != 0.0 || dy != 0.0 || dz != 0.0) {
        var moveVec = Vector3D(dx, 0.0, dz);
        if (moveVec.length > 0) {
          moveVec = moveVec.normalize() * moveSpeed;
        }
        if (!isWalkthrough) {
          moveVec = Vector3D(moveVec.x, dy * moveSpeed, moveVec.z);
        }

        final nextPos = state.targetPosition + moveVec;

        Vector3D constrained = nextPos;
        if (!isWalkthrough) {
          if (constrained.y < 10.0) {
            constrained = Vector3D(constrained.x, 10.0, constrained.z);
          }
        }

        double minX = -300.0, maxX = 300.0;
        double minZ = -225.0, maxZ = 225.0;
        if (layout.walls.isNotEmpty) {
          minX = double.infinity; maxX = -double.infinity;
          minZ = double.infinity; maxZ = -double.infinity;
          for (final w in layout.walls) {
            minX = min(minX, min(w.start.dx, w.end.dx));
            maxX = max(maxX, max(w.start.dx, w.end.dx));
            minZ = min(minZ, min(w.start.dy, w.end.dy));
            maxZ = max(maxZ, max(w.start.dy, w.end.dy));
          }
        }
        
        const pad = 20.0;
        final clampedX = constrained.x.clamp(minX + pad, maxX - pad);
        final clampedZ = constrained.z.clamp(minZ + pad, maxZ - pad);
        constrained = Vector3D(clampedX, constrained.y, clampedZ);

        if (isWalkthrough || !_isInsideAnyFurniture(constrained, layout.furniture)) {
          state = state.copyWith(targetPosition: constrained);
        }
      }
    }

    const damping = 0.15;

    final nextAzimuth = state.azimuth + (state.targetAzimuth - state.azimuth) * damping;
    final nextElevation = state.elevation + (state.targetElevation - state.elevation) * damping;
    final nextOrbitRadius = state.orbitRadius + (state.targetOrbitRadius - state.orbitRadius) * damping;

    final nextWalkYaw = state.walkYaw + (state.targetWalkYaw - state.walkYaw) * damping;
    final nextWalkPitch = state.walkPitch + (state.targetWalkPitch - state.walkPitch) * damping;

    final rawTarget = state.target + (state.targetTarget - state.target) * damping;
    final nextTarget = Vector3D(rawTarget.x, rawTarget.y.clamp(0.0, 1000.0), rawTarget.z);

    Vector3D nextPosition;
    if (isFreeOrWalkthrough) {
      nextPosition = state.position + (state.targetPosition - state.position) * damping;
    } else {
      final cx = nextTarget.x + nextOrbitRadius * cos(nextElevation) * cos(nextAzimuth);
      final cy = nextTarget.y + nextOrbitRadius * sin(nextElevation);
      final cz = nextTarget.z + nextOrbitRadius * cos(nextElevation) * sin(nextAzimuth);
      nextPosition = Vector3D(cx, cy, cz);
    }

    // --- OBSTACLE COLLISION RESOLUTION (PREVENT CLIPPING) ---
    Vector3D resolvedPosition = nextPosition;
    const double padding = 25.0; // Comfort distance from obstacles

    // A. Wall collisions
    for (final w in layout.walls) {
      final p = Offset(resolvedPosition.x, resolvedPosition.z);
      final a = w.start;
      final b = w.end;
      
      final l2 = (a - b).distanceSquared;
      if (l2 == 0) continue;
      
      final t = ((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2;
      final clampedT = t.clamp(0.0, 1.0);
      final projection = Offset(
        a.dx + clampedT * (b.dx - a.dx),
        a.dy + clampedT * (b.dy - a.dy),
      );
      
      final distToSegment = (p - projection).distance;
      final minDist = (w.thickness / 2.0) + padding;
      
      if (distToSegment < minDist) {
        final dir = p - projection;
        final pushDir = dir.distance > 0.1 ? dir / dir.distance : const Offset(0, 1);
        final pushAmount = minDist - distToSegment;
        
        resolvedPosition = Vector3D(
          resolvedPosition.x + pushDir.dx * pushAmount,
          resolvedPosition.y,
          resolvedPosition.z + pushDir.dy * pushAmount,
        );
      }
    }

    // B. Furniture collisions
    for (final f in layout.furniture) {
      if (isWalkthrough) {
        final topHeight = f.y + f.height;
        if (topHeight - state.feetHeight <= 40.0) {
          // Walkable stair/step/platform. Don't block horizontally.
          continue;
        }
      }

      final dx = resolvedPosition.x - f.x;
      final dz = resolvedPosition.z - f.z;
      
      // Rotate camera position to furniture's local coordinate space
      final rotatedX = dx * cos(f.rotationY) + dz * sin(f.rotationY);
      final rotatedZ = -dx * sin(f.rotationY) + dz * cos(f.rotationY);
      
      final halfW = (f.width / 2.0) + padding;
      final halfD = (f.depth / 2.0) + padding;
      final fTop = f.y + f.height + padding;
      final fBottom = f.y - padding;
      
      final double currentFeet = isWalkthrough ? state.feetHeight : resolvedPosition.y - padding;
      final double currentHead = isWalkthrough ? state.feetHeight + state.eyeHeight : resolvedPosition.y + padding;
      final verticalOverlap = (currentFeet < f.y + f.height && currentHead > f.y);

      if (rotatedX.abs() < halfW && verticalOverlap && rotatedZ.abs() < halfD) {
        // Colliding! Find the shallowest penetration axis to push out
        final overlapX = halfW - rotatedX.abs();
        final overlapZ = halfD - rotatedZ.abs();
        final overlapY = (resolvedPosition.y > f.y + f.height / 2.0) 
            ? (fTop - resolvedPosition.y) 
            : (resolvedPosition.y - fBottom);
            
        if (!isWalkthrough && overlapY < overlapX && overlapY < overlapZ) {
          // Push vertically
          final pushY = (resolvedPosition.y > f.y + f.height / 2.0) ? overlapY : -overlapY;
          resolvedPosition = Vector3D(resolvedPosition.x, resolvedPosition.y + pushY, resolvedPosition.z);
        } else if (overlapX < overlapZ) {
          // Push along local X
          final pushLocalX = rotatedX >= 0 ? overlapX : -overlapX;
          resolvedPosition = resolvedPosition + Vector3D(pushLocalX * cos(f.rotationY), 0, pushLocalX * sin(f.rotationY));
        } else {
          // Push along local Z
          final pushLocalZ = rotatedZ >= 0 ? overlapZ : -overlapZ;
          resolvedPosition = resolvedPosition + Vector3D(-pushLocalZ * sin(f.rotationY), 0, pushLocalZ * cos(f.rotationY));
        }
      }
    }

    // C. Ground & Stair Height Constraint
    double finalFeetHeight = 0.0;
    if (isWalkthrough) {
      // Find highest walkable ground surface under resolved position
      for (final f in layout.furniture) {
        final dx = resolvedPosition.x - f.x;
        final dz = resolvedPosition.z - f.z;
        final rotatedX = dx * cos(f.rotationY) + dz * sin(f.rotationY);
        final rotatedZ = -dx * sin(f.rotationY) + dz * cos(f.rotationY);
        
        final halfW = f.width / 2.0;
        final halfD = f.depth / 2.0;
        
        if (rotatedX.abs() < halfW && rotatedZ.abs() < halfD) {
          final topHeight = f.y + f.height;
          // Stair check: step height <= 40cm
          if (topHeight - state.feetHeight <= 40.0) {
            if (topHeight > finalFeetHeight) {
              finalFeetHeight = topHeight;
            }
          }
        }
      }
      
      // Smoothly interpolate the camera's feet height
      final nextFeetHeight = state.feetHeight + (finalFeetHeight - state.feetHeight) * damping;
      final targetY = nextFeetHeight + state.eyeHeight;
      resolvedPosition = Vector3D(resolvedPosition.x, targetY, resolvedPosition.z);
      
      state = state.copyWith(
        feetHeight: nextFeetHeight,
        targetFeetHeight: finalFeetHeight,
      );
    } else {
      // Floor collision constraint
      if (resolvedPosition.y < 15.0) {
        resolvedPosition = Vector3D(resolvedPosition.x, 15.0, resolvedPosition.z);
      }
    }

    if (isFreeOrWalkthrough) {
      final dx = cos(nextWalkPitch) * cos(nextWalkYaw);
      final dy = sin(nextWalkPitch);
      final dz = cos(nextWalkPitch) * sin(nextWalkYaw);
      final lookTarget = resolvedPosition + Vector3D(dx, dy, dz) * 100.0;

      state = state.copyWith(
        position: resolvedPosition,
        target: lookTarget,
        targetTarget: lookTarget,
        azimuth: nextAzimuth,
        elevation: nextElevation,
        orbitRadius: nextOrbitRadius,
        walkYaw: nextWalkYaw,
        walkPitch: nextWalkPitch,
        up: Vector3D(0, 1, 0),
        targetPosition: resolvedPosition,
      );
    } else {
      final mode = ref.read(viewModeProvider);
      final targetUp = (mode == ViewMode.top) ? Vector3D(0, 0, -1) : Vector3D(0, 1, 0);
      var nextUp = state.up + (targetUp - state.up) * damping;
      if (nextUp.length > 0.001) {
        nextUp = nextUp.normalize();
      } else {
        nextUp = Vector3D(0, 1, 0);
      }

      state = state.copyWith(
        position: resolvedPosition,
        target: nextTarget,
        azimuth: nextAzimuth,
        elevation: nextElevation,
        orbitRadius: nextOrbitRadius,
        walkYaw: nextWalkYaw,
        walkPitch: nextWalkPitch,
        up: nextUp,
        targetPosition: resolvedPosition,
      );
    }
  }
}

// --- RIVERPOD PROVIDERS DEFINITIONS ---
final viewModeProvider = NotifierProvider<ViewModeNotifier, ViewMode>(ViewModeNotifier.new);
final navigationProvider = NotifierProvider<NavigationNotifier, NavigationSettings>(NavigationNotifier.new);
final cameraProvider = NotifierProvider<CameraNotifier, CameraState>(CameraNotifier.new);
