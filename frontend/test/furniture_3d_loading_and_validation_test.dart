import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowspace_frontend/features/designer/presentation/three_d_designer_view.dart';
import 'package:flowspace_frontend/features/designer/presentation/widgets/designer_status_bar.dart';
import 'package:flowspace_frontend/features/designer/providers/designer_provider.dart';
import 'package:flowspace_frontend/features/designer/providers/design_score_provider.dart';
import 'package:flowspace_frontend/features/designer/providers/validation_provider.dart';
import 'package:flowspace_frontend/features/designer/bridge/viewport_controller.dart';
import 'package:flowspace_frontend/features/designer/bridge/bridge_client_stub.dart';
import 'package:flowspace_frontend/features/furniture/models/furniture_asset.dart';
import 'package:flowspace_frontend/features/furniture/providers/furniture_provider.dart';

class MockBridgeClient extends StubBridgeClient {
  final List<String> sentMessages = [];

  @override
  void send(String message) {
    sentMessages.add(message);
    super.send(message);
  }
}

void main() {
  group('3D Furniture Loading & Asynchronous Catalog Sync Tests', () {
    testWidgets('ThreeDDesignerView loads furniture with fallback and re-syncs on didUpdateWidget', (tester) async {
      final mockBridge = MockBridgeClient();
      final container = ProviderContainer(
        overrides: [
          bridgeClientProvider.overrideWithValue(mockBridge),
        ],
      );

      final layoutNotifier = container.read(designerProvider.notifier);
      layoutNotifier.addFurniture(
        FurnitureAsset(
          id: 'EXEC_DESK001',
          name: 'Executive Manager Desk',
          category: 'Office',
          style: 'Modern',
          width: 180.0,
          depth: 90.0,
          height: 76.0,
          clearance: 60.0,
          assemblyClearance: 80.0,
          glbUrl: '',
          thumbnailUrl: '',
          createdAt: DateTime.now(),
        ),
        100.0,
        150.0,
      );

      // 1. Initial build with empty furnitureAssets list (simulating async loading catalog)
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: ThreeDDesignerView(
                roomId: 'test_room',
                furnitureAssets: [],
                simplified: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Simulate renderer ready event so command queue flushes
      mockBridge.simulateMessageFromRenderer(
        '{"type":"READY","version":"1.0.0","transactionId":"hs_1","payload":{}}',
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Viewport should have received LOAD_ROOM and LOAD_MODEL with fallback url
      final loadModelCommands = mockBridge.sentMessages.where((m) => m.contains('LOAD_MODEL')).toList();
      expect(loadModelCommands.isNotEmpty, isTrue);
      expect(loadModelCommands.first.contains('EXEC_DESK001'), isTrue);
      expect(loadModelCommands.first.contains('/uploads/furniture/models/EXEC_DESK001.glb'), isTrue);

      final initialCommandCount = loadModelCommands.length;

      // 2. Simulate async catalog population by updating widget with populated furnitureAssets
      final populatedAsset = FurnitureAsset(
        id: 'EXEC_DESK001',
        name: 'Executive Manager Desk',
        category: 'Office',
        style: 'Modern',
        width: 180.0,
        depth: 90.0,
        height: 76.0,
        clearance: 60.0,
        assemblyClearance: 80.0,
        glbUrl: '/uploads/furniture/models/EXEC_DESK001.glb',
        thumbnailUrl: '',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ThreeDDesignerView(
                roomId: 'test_room',
                furnitureAssets: [populatedAsset],
                simplified: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Duplicate prevention: already loaded identical signature should not send redundant duplicate
      final updatedModelCommands = mockBridge.sentMessages.where((m) => m.contains('LOAD_MODEL')).toList();
      expect(updatedModelCommands.length, equals(initialCommandCount));

      // Unmount ThreeDDesignerView to stop its ticker cleanly
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  });

  group('Validation Status Distinction Tests', () {
    testWidgets('DesignerStatusBar displays COLLISION only on actual collision errors', (tester) async {
      final layout = DesignerLayoutState();
      const scoreState = DesignScoreState();

      // 1. True collision error
      final collisionState = ValidationState(
        errors: [
          ValidationIssue(
            ruleId: 'RULE_COLLISION',
            ruleName: 'Collision Detection',
            category: 'Furniture',
            severity: 'Error',
            message: 'Desk overlaps with chair',
          ),
        ],
        summary: ValidationSummary(
          passRate: 50.0,
          warningCount: 0,
          errorCount: 1,
          overallStatus: 'Fail',
          overallScore: 50.0,
          accessibilityScore: 100.0,
          lightingScore: 100.0,
          ergonomicScore: 50.0,
          spaceUtilizationScore: 50.0,
          furnitureBalanceScore: 100.0,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DesignerStatusBar(
                roomId: 'room_1',
                layout: layout,
                scoreState: scoreState,
                validationState: collisionState,
                zoomLevel: 1.0,
                is3DMode: false,
                showGrid: true,
                autoSaveStatus: 'Saved',
                translation2D: Offset.zero,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('🔴 COLLISION'), findsOneWidget);

      // 2. Wall collision error
      final wallState = ValidationState(
        errors: [
          ValidationIssue(
            ruleId: 'RULE_WALL',
            ruleName: 'Wall Collision',
            category: 'Safety',
            severity: 'Error',
            message: 'Cabinet intersects exterior wall',
          ),
        ],
        summary: ValidationSummary(
          passRate: 50.0,
          warningCount: 0,
          errorCount: 1,
          overallStatus: 'Fail',
          overallScore: 50.0,
          accessibilityScore: 100.0,
          lightingScore: 100.0,
          ergonomicScore: 50.0,
          spaceUtilizationScore: 50.0,
          furnitureBalanceScore: 100.0,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DesignerStatusBar(
                roomId: 'room_1',
                layout: layout,
                scoreState: scoreState,
                validationState: wallState,
                zoomLevel: 1.0,
                is3DMode: false,
                showGrid: true,
                autoSaveStatus: 'Saved',
                translation2D: Offset.zero,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('🔴 WALL COLLISION'), findsOneWidget);

      // 3. Walkway error
      final walkwayState = ValidationState(
        errors: [
          ValidationIssue(
            ruleId: 'RULE_WALKWAY',
            ruleName: 'Walkway Width Validation',
            category: 'Circulation',
            severity: 'Error',
            message: 'Walkway width is less than 75cm',
          ),
        ],
        summary: ValidationSummary(
          passRate: 50.0,
          warningCount: 0,
          errorCount: 1,
          overallStatus: 'Fail',
          overallScore: 50.0,
          accessibilityScore: 100.0,
          lightingScore: 100.0,
          ergonomicScore: 50.0,
          spaceUtilizationScore: 50.0,
          furnitureBalanceScore: 100.0,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DesignerStatusBar(
                roomId: 'room_1',
                layout: layout,
                scoreState: scoreState,
                validationState: walkwayState,
                zoomLevel: 1.0,
                is3DMode: false,
                showGrid: true,
                autoSaveStatus: 'Saved',
                translation2D: Offset.zero,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('🔴 WALKWAY BLOCKED'), findsOneWidget);

      // 4. Safe state
      final safeState = ValidationState(
        errors: const [],
        warnings: const [],
        summary: ValidationSummary(
          passRate: 100.0,
          warningCount: 0,
          errorCount: 0,
          overallStatus: 'Pass',
          overallScore: 100.0,
          accessibilityScore: 100.0,
          lightingScore: 100.0,
          ergonomicScore: 100.0,
          spaceUtilizationScore: 100.0,
          furnitureBalanceScore: 100.0,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DesignerStatusBar(
                roomId: 'room_1',
                layout: layout,
                scoreState: scoreState,
                validationState: safeState,
                zoomLevel: 1.0,
                is3DMode: false,
                showGrid: true,
                autoSaveStatus: 'Saved',
                translation2D: Offset.zero,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('🟢 SAFE'), findsOneWidget);
    });
  });

  group('Catalog Pagination and Access Tests', () {
    test('FurnitureListState has increased limit for complete access', () {
      const state = FurnitureListState();
      expect(state.limit, equals(50));
      expect(state.page, equals(1));
    });
  });
}
