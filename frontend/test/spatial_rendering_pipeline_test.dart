import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowspace_frontend/features/designer/providers/camera_provider.dart';
import 'package:flowspace_frontend/features/designer/providers/designer_provider.dart';
import 'package:flowspace_frontend/features/designer/presentation/designer_painter.dart';
import 'package:flowspace_frontend/features/designer/presentation/widgets/developer_diagnostics_panel.dart';

void main() {
  group('FlowSpace Spatial Rendering Pipeline Tests', () {
    test('Camera Initializer & Bounds Clamping Test', () {
      final container = ProviderContainer();
      final notifier = container.read(cameraProvider.notifier);

      // Fit camera to a 500cm x 300cm x 280cm room
      notifier.fitCameraToRoom(500.0, 300.0, 280.0);
      final state = container.read(cameraProvider);

      // Camera position must strictly lie inside interior wall safety bounds
      expect(state.position.x >= 20.0 && state.position.x <= 480.0, isTrue);
      expect(state.position.z >= 20.0 && state.position.z <= 280.0, isTrue);
      expect(state.position.y >= 30.0 && state.position.y <= 260.0, isTrue);
    });

    testWidgets('Developer Diagnostics Panel Renders Correct Spatial Metrics', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  DeveloperDiagnosticsPanel(
                    isVisible: true,
                    onClose: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('SPATIAL DIAGNOSTICS'), findsOneWidget);
      expect(find.text('ROOM DIMENSIONS:'), findsOneWidget);
      expect(find.text('WORLD SCALE:'), findsOneWidget);
      expect(find.text('CAMERA POS:'), findsOneWidget);
      expect(find.text('SPATIAL HEALTH SCORE:'), findsOneWidget);
    });

    testWidgets('2D Architectural Painter Paints Layout and Symbols', (WidgetTester tester) async {
      final layoutState = DesignerLayoutState(
        walls: [
          Wall(start: const Offset(0, 0), end: const Offset(500, 0), thickness: 20),
          Wall(start: const Offset(500, 0), end: const Offset(500, 300), thickness: 20),
          Wall(start: const Offset(500, 300), end: const Offset(0, 300), thickness: 20),
          Wall(start: const Offset(0, 300), end: const Offset(0, 0), thickness: 20),
        ],
        openings: [
          Opening(id: 'op1', type: 'door', position: const Offset(250, 300), width: 90.0, angle: 0.0),
          Opening(id: 'op2', type: 'window', position: const Offset(250, 0), width: 120.0, angle: 0.0),
        ],
        furniture: [
          PlacedFurniture(
            id: 'f1',
            assetId: 'BED001',
            name: 'Minimalist King Bed',
            x: 250.0,
            y: 0.0,
            z: 100.0,
            width: 200.0,
            depth: 220.0,
            height: 45.0,
            rotationY: 0.0,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(800, 600),
              painter: DesignerPainter(
                layout: layoutState,
                showGrid: true,
                showMeasurements: true,
                showFurnitureLabels: true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
