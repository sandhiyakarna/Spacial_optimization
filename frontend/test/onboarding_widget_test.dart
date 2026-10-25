import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowspace_frontend/app/app.dart';
import 'package:flowspace_frontend/core/storage/token_storage.dart';

void main() {
  setUp(() async {
    await TokenStorage().clearTokens();
    await TokenStorage().setHasSeenOnboarding(false);
  });

  testWidgets('Verify Onboarding screen renders first slide and can transition', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: FlowSpaceApp(),
      ),
    );

    // Let Splash transition complete
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Verify we are on Onboarding first page
    expect(find.text('Visualize Your Space'), findsOneWidget);
    expect(find.text('Capture 360° of your room and bring it to life in 3D.'), findsOneWidget);

    // Tap next button (find icon arrow_forward_rounded)
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();

    // Verify we transitioned to the second page
    expect(find.text('AI-Powered Planning'), findsOneWidget);
    expect(find.text('Get intelligent layout suggestions based on interior design rules.'), findsOneWidget);
  });
}
