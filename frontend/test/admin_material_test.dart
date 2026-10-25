import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowspace_frontend/features/admin/providers/admin_provider.dart';
import 'package:flowspace_frontend/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:flowspace_frontend/features/designer/presentation/admin_material_upload_screen.dart';
import 'package:flowspace_frontend/features/designer/models/material_model.dart';
import 'package:flowspace_frontend/features/designer/data/material_api_client.dart';

// Mock material models
final mockCategoryWood = MaterialCategory(
  id: 'cat_wood',
  name: 'Wood',
  createdAt: DateTime.now(),
);

final mockCategoryMarble = MaterialCategory(
  id: 'cat_marble',
  name: 'Marble',
  createdAt: DateTime.now(),
);

final mockMaterials = [
  MaterialModel(
    id: 'mat_oak',
    name: 'Oak Plank',
    categoryId: 'cat_wood',
    baseColor: '#D27D2D',
    previewImage: null,
    opacity: 1.0,
    reflectivity: 0.1,
    defaultScale: 1.0,
    createdAt: DateTime.now(),
    category: mockCategoryWood,
    textures: const [],
  ),
  MaterialModel(
    id: 'mat_carrara',
    name: 'Carrara Marble',
    categoryId: 'cat_marble',
    baseColor: '#FFFFFF',
    previewImage: '/uploads/carrara.png',
    opacity: 1.0,
    reflectivity: 0.8,
    defaultScale: 2.0,
    createdAt: DateTime.now(),
    category: mockCategoryMarble,
    textures: const [],
  ),
];

class MockAdminNotifier extends AdminNotifier {
  final AdminState mockState;
  MockAdminNotifier(this.mockState);

  @override
  AdminState build() => mockState;

  @override
  Future<void> fetchAdminDashboard() async {}
}

class MockMaterialApiClient extends MaterialApiClient {
  @override
  Future<List<MaterialCategory>> getCategories() async {
    return [
      MaterialCategory(id: 'cat_wood', name: 'Wood', createdAt: DateTime.now()),
      MaterialCategory(id: 'cat_marble', name: 'Marble', createdAt: DateTime.now()),
    ];
  }
}


void main() {
  group('Admin Materials UI & Rendering Tests', () {
    testWidgets('Renders AdminMaterialsSection grid and handles searching/filtering', (WidgetTester tester) async {
      final mockState = AdminState(
        activeSection: AdminSection.materials,
        materials: mockMaterials,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminProvider.overrideWith(() => MockAdminNotifier(mockState)),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: AdminMaterialsSection(
                materials: mockState.materials,
                notifier: MockAdminNotifier(mockState),
                isDark: true,
              ),
            ),
          ),
        ),
      );

      // Verify page titles and elements
      expect(find.text('Material Library Management'), findsOneWidget);
      expect(find.text('Add Material'), findsOneWidget);
      expect(find.text('Oak Plank'), findsOneWidget);
      expect(find.text('Carrara Marble'), findsOneWidget);

      // Verify PBR chip parameters
      expect(find.text('Op: 1.0'), findsNWidgets(2));
      expect(find.text('Ref: 0.1'), findsOneWidget);
      expect(find.text('Ref: 0.8'), findsOneWidget);

      // Search for Oak
      await tester.enterText(find.byKey(const Key('material_search_input')), 'Oak');
      await tester.pump();

      // Only Oak Plank should be shown now
      expect(find.text('Oak Plank'), findsOneWidget);
      expect(find.text('Carrara Marble'), findsNothing);

      // Clear search
      await tester.enterText(find.byKey(const Key('material_search_input')), '');
      await tester.pump();
      expect(find.text('Carrara Marble'), findsOneWidget);
    });

    testWidgets('AdminMaterialUploadScreen validates form inputs correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: AdminMaterialUploadScreen(
              apiClient: MockMaterialApiClient(),
            ),
          ),
        ),
      );

      // Wait for loading to settle (async fetch fails/completes)
      await tester.pumpAndSettle();

      // Tapping Register without filling anything should trigger validation errors
      await tester.ensureVisible(find.byKey(const Key('save_material_btn')));
      await tester.tap(find.byKey(const Key('save_material_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter material name'), findsOneWidget);

      // Enter invalid color code format
      await tester.enterText(find.widgetWithText(TextFormField, 'Base Color Hex Code'), 'invalid-color');
      await tester.ensureVisible(find.byKey(const Key('save_material_btn')));
      await tester.tap(find.byKey(const Key('save_material_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Invalid hex color code (use format #RRGGBB)'), findsOneWidget);
    });
  });
}
