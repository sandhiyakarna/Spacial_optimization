import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowspace_frontend/features/designer/providers/camera_provider.dart';
import 'package:flowspace_frontend/features/designer/providers/designer_provider.dart';

void main() {
  group('Camera Controller & 3D Navigation Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial camera state matches default specifications', () {
      final cameraState = container.read(cameraProvider);
      
      expect(cameraState.fov, pi / 4.0);
      expect(cameraState.near, 10.0);
      expect(cameraState.far, 8000.0);
      expect(cameraState.orbitRadius, 900.0);
      expect(cameraState.azimuth, pi / 4.0);
      expect(cameraState.elevation, pi / 6.0);
    });

    test('Navigation settings default and updates', () {
      final settings = container.read(navigationProvider);
      expect(settings.movementSpeed, 6.0);
      expect(settings.rotationSpeed, 0.005);
      expect(settings.zoomSpeed, 30.0);

      container.read(navigationProvider.notifier).updateSettings(
        movementSpeed: 10.0,
        rotationSpeed: 0.01,
        zoomSpeed: 50.0,
      );

      final updated = container.read(navigationProvider);
      expect(updated.movementSpeed, 10.0);
      expect(updated.rotationSpeed, 0.01);
      expect(updated.zoomSpeed, 50.0);
    });

    test('View mode selector updates targets and up vector', () {
      final notifier = container.read(viewModeProvider.notifier);
      
      // Top view check
      notifier.setMode(ViewMode.top);
      expect(container.read(viewModeProvider), ViewMode.top);
      var cameraState = container.read(cameraProvider);
      expect(cameraState.targetElevation, pi / 2.0 - 0.001);
      expect(cameraState.up.x, 0.0);
      expect(cameraState.up.y, 0.0);
      expect(cameraState.up.z, -1.0);

      // Left view check
      notifier.setMode(ViewMode.left);
      cameraState = container.read(cameraProvider);
      expect(cameraState.targetAzimuth, 0.0);
      expect(cameraState.targetElevation, 0.02);
      expect(cameraState.up.y, 1.0);

      // Isometric view check
      notifier.setMode(ViewMode.isometric);
      cameraState = container.read(cameraProvider);
      expect(cameraState.targetAzimuth, pi / 4.0);
      expect(cameraState.targetElevation, closeTo(35.26 * pi / 180.0, 0.001));
    });

    test('Rotate, Pan, Zoom apply correct changes to targets', () {
      final notifier = container.read(cameraProvider.notifier);
      
      // Zoom
      notifier.zoom(100.0, false); // zoom out in Orbit
      expect(container.read(cameraProvider).targetOrbitRadius, 1000.0);

      notifier.zoom(-200.0, false); // zoom in in Orbit
      expect(container.read(cameraProvider).targetOrbitRadius, 800.0);

      // Rotate
      notifier.rotate(10.0, 5.0, 0.005, false);
      final cameraState = container.read(cameraProvider);
      expect(cameraState.targetAzimuth, closeTo(pi / 4.0 - 0.05, 0.001));
      expect(cameraState.targetElevation, closeTo(pi / 6.0 + 0.025, 0.001));
    });

    test('Focus furniture sets camera target and orbit radius', () {
      final f = PlacedFurniture(
        id: 'f1',
        assetId: 'asset1',
        name: 'Test Couch',
        width: 200,
        depth: 90,
        height: 80,
        x: 100,
        y: 0,
        z: -150,
      );

      container.read(cameraProvider.notifier).focusFurniture(f, snap: true);
      final cameraState = container.read(cameraProvider);

      expect(cameraState.target.x, 100.0);
      expect(cameraState.target.y, 40.0); // center height (f.y + f.height/2)
      expect(cameraState.target.z, -150.0);
      expect(cameraState.orbitRadius, 600.0); // max(width, depth) * 3 = 200 * 3 = 600
    });

    test('Reset camera centers on the room boundaries', () {
      final layout = DesignerLayoutState(
        walls: [
          Wall(start: const Offset(-200, -200), end: const Offset(200, -200)),
          Wall(start: const Offset(200, -200), end: const Offset(200, 200)),
          Wall(start: const Offset(200, 200), end: const Offset(-200, 200)),
          Wall(start: const Offset(-200, 200), end: const Offset(-200, -200)),
        ],
      );

      container.read(cameraProvider.notifier).resetToRoom(layout, snap: true);
      final cameraState = container.read(cameraProvider);

      expect(cameraState.target.x, 0.0);
      expect(cameraState.target.y, 50.0);
      expect(cameraState.target.z, 0.0);
      expect(cameraState.orbitRadius, 400.0 * 1.3); // max(roomLen, roomWid) * 1.3
    });

    test('Tick performs smooth interpolation towards target values', () {
      // 1. Move target values
      container.read(cameraProvider.notifier).zoom(100.0, false); // targetRadius = 1000
      
      var cameraState = container.read(cameraProvider);
      expect(cameraState.orbitRadius, 900.0);
      expect(cameraState.targetOrbitRadius, 1000.0);

      // 2. Run single tick
      container.read(cameraProvider.notifier).tick(
        pressedKeys: {},
        isFreeOrWalkthrough: false,
        layout: DesignerLayoutState(),
      );

      cameraState = container.read(cameraProvider);
      // orbitRadius = 900 + (1000 - 900) * 0.15 = 915.0
      expect(cameraState.orbitRadius, 915.0);

      // 3. Run multiple ticks
      for (int i = 0; i < 30; i++) {
        container.read(cameraProvider.notifier).tick(
          pressedKeys: {},
          isFreeOrWalkthrough: false,
          layout: DesignerLayoutState(),
        );
      }

      cameraState = container.read(cameraProvider);
      // Should have settled extremely close to 1000.0
      expect(cameraState.orbitRadius, closeTo(1000.0, 1.0));
    });
  });
}
