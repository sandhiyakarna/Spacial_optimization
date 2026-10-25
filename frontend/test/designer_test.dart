import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowspace_frontend/features/designer/providers/designer_provider.dart';
import 'package:flowspace_frontend/features/designer/providers/validation_provider.dart';

void main() {
  group('2D Designer State Notifier Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial state is empty and select tool is active', () {
      final state = container.read(designerProvider);
      expect(state.walls, isEmpty);
      expect(state.openings, isEmpty);
      expect(state.tool, DesignerTool.select);
      expect(state.snapToGrid, isTrue);
      expect(state.selectedWallIndex, isNull);
    });

    test('Adding a wall applies snapping when grid snapping is enabled', () {
      final notifier = container.read(designerProvider.notifier);
      
      // gridSpacing is 20.0, so:
      // Offset(12.0, 28.0) snaps to Offset(20.0, 20.0)
      // Offset(105.0, 211.0) snaps to Offset(100.0, 220.0)
      notifier.addWall(const Offset(12.0, 28.0), const Offset(105.0, 211.0));
      
      final state = container.read(designerProvider);
      expect(state.walls, hasLength(1));
      expect(state.walls[0].start, const Offset(20.0, 20.0));
      expect(state.walls[0].end, const Offset(100.0, 220.0));
    });

    test('Adding a wall does not snap when grid snapping is disabled', () {
      final notifier = container.read(designerProvider.notifier);
      notifier.updateSnapToGrid(false);
      
      notifier.addWall(const Offset(12.0, 28.0), const Offset(105.0, 211.0));
      
      final state = container.read(designerProvider);
      expect(state.walls, hasLength(1));
      expect(state.walls[0].start, const Offset(12.0, 28.0));
      expect(state.walls[0].end, const Offset(105.0, 211.0));
    });

    test('Undo and Redo tracking works correctly for wall additions', () {
      final notifier = container.read(designerProvider.notifier);
      
      // Add one wall
      notifier.addWall(const Offset(0, 0), const Offset(100, 100));
      expect(container.read(designerProvider).walls, hasLength(1));

      // Undo
      notifier.undo();
      expect(container.read(designerProvider).walls, isEmpty);

      // Redo
      notifier.redo();
      expect(container.read(designerProvider).walls, hasLength(1));
    });

    test('Selecting a wall and updating thickness / deleting works', () {
      final notifier = container.read(designerProvider.notifier);
      notifier.addWall(const Offset(0, 0), const Offset(100, 100));
      
      notifier.selectWall(0);
      expect(container.read(designerProvider).selectedWallIndex, 0);

      // Change thickness
      notifier.updateSelectedWallThickness(25.0);
      expect(container.read(designerProvider).walls[0].thickness, 25.0);

      // Delete wall
      notifier.deleteSelected();
      expect(container.read(designerProvider).walls, isEmpty);
      expect(container.read(designerProvider).selectedWallIndex, isNull);
    });

    test('Door and Window wall-snapping and alignment', () {
      final notifier = container.read(designerProvider.notifier);
      // Place a horizontal wall from (0, 100) to (200, 100)
      notifier.addWall(const Offset(0, 100), const Offset(200, 100));

      // Place a door close to the wall at (50, 110)
      // Since it is 10 pixels away (less than 50 max distance), it should snap to (50, 100)
      // And its angle should align to the wall's angle (0.0 radians)
      notifier.placeOpening('door', const Offset(50, 110));

      final state = container.read(designerProvider);
      expect(state.openings, hasLength(1));
      expect(state.openings[0].type, 'door');
      expect(state.openings[0].position, const Offset(50, 100));
      expect(state.openings[0].angle, 0.0);
    });

    test('applyFixCorrection updates furniture position, preserves others, and integrates with undo/redo', () {
      final notifier = container.read(designerProvider.notifier);
      final sofa = PlacedFurniture(
        id: 'sofa_1',
        assetId: 'sofa_asset',
        name: 'Sofa',
        width: 180.0,
        depth: 85.0,
        height: 75.0,
        x: 250.0,
        z: 460.0,
      );
      final table = PlacedFurniture(
        id: 'table_1',
        assetId: 'table_asset',
        name: 'Coffee Table',
        width: 90.0,
        depth: 60.0,
        height: 45.0,
        x: 250.0,
        z: 300.0,
      );

      notifier.setFurnitureListForTesting([sofa, table]);

      // Apply fix correction to sofa
      notifier.applyFixCorrection(
        furnitureId: 'sofa_1',
        proposedX: 250.0,
        proposedZ: 380.0,
        proposedRotation: 0.0,
      );

      var state = container.read(designerProvider);
      var updatedSofa = state.furniture.firstWhere((f) => f.id == 'sofa_1');
      var updatedTable = state.furniture.firstWhere((f) => f.id == 'table_1');
      expect(updatedSofa.z, 380.0);
      expect(updatedTable.z, 300.0); // Other furniture is strictly preserved

      // Scenario 10: Undoing and redoing a successfully applied correction
      notifier.undo();
      state = container.read(designerProvider);
      updatedSofa = state.furniture.firstWhere((f) => f.id == 'sofa_1');
      expect(updatedSofa.z, 460.0); // Restored original position

      notifier.redo();
      state = container.read(designerProvider);
      updatedSofa = state.furniture.firstWhere((f) => f.id == 'sofa_1');
      expect(updatedSofa.z, 380.0); // Reapplied fix
    });

    test('ValidationIssue and FixCandidate models parse real-world usability metadata correctly', () {
      final issueJson = {
        'rule_id': 'RULE_DOOR',
        'rule_name': 'Doorway Clearance',
        'category': 'Accessibility',
        'severity': 'Error',
        'message': 'Furniture obstructs door-swing area',
        'recommendation': 'Move 40 cm north',
        'affected_furniture_ids': ['sofa_1'],
        'measured_clearance': 42.5,
        'required_clearance': 90.0,
        'clearance_source': 'Door Swing Arc',
        'issue_type': 'door_swing',
        'is_fixable': true,
      };

      final issue = ValidationIssue.fromJson(issueJson);
      expect(issue.ruleId, 'RULE_DOOR');
      expect(issue.measuredClearance, 42.5);
      expect(issue.requiredClearance, 90.0);
      expect(issue.clearanceSource, 'Door Swing Arc');
      expect(issue.isFixable, isTrue);

      final candidateJson = {
        'can_fix': true,
        'room_id': 'room_123',
        'rule_id': 'RULE_DOOR',
        'issue_type': 'door_swing',
        'target_furniture_id': 'sofa_1',
        'strategy': 'directional_clearance_shift',
        'explanation': 'Shift sofa away from door swing arc',
        'measured_before': 42.5,
        'measured_after': 95.0,
        'required_clearance': 90.0,
        'changes': [
          {
            'furniture_id': 'sofa_1',
            'original_x': 250.0,
            'original_z': 460.0,
            'original_rotation': 0.0,
            'proposed_x': 250.0,
            'proposed_z': 380.0,
            'proposed_rotation': 0.0,
            'movement_distance': 80.0,
            'rotation_delta_degrees': 0.0,
          }
        ],
        'alternative_suggestions': ['Use a smaller sofa'],
      };

      final candidate = FixCandidate.fromJson(candidateJson);
      expect(candidate.canFix, isTrue);
      expect(candidate.changes, hasLength(1));
      expect(candidate.changes[0].proposedZ, 380.0);
      expect(candidate.measuredAfter, 95.0);
      expect(candidate.alternativeSuggestions, contains('Use a smaller sofa'));
    });
  });
}
