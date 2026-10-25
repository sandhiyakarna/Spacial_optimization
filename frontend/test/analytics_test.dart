import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowspace_frontend/features/analytics/providers/analytics_provider.dart';

void main() {
  group('Analytics State & Provider Tests', () {
    test('Default AnalyticsState initial values', () {
      const state = AnalyticsState();
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNull);
      expect(state.dashboard, isNull);
      expect(state.history, isNull);
      expect(state.statistics, isNull);
      expect(state.insights, isNull);
      expect(state.projectAnalytics, isNull);
      expect(state.comparison, isNull);
    });

    test('AnalyticsState copyWith updates fields correctly', () {
      const state = AnalyticsState();
      final updated = state.copyWith(
        isLoading: true,
        errorMessage: 'Connection timeout',
        dashboard: {'overall_score': 85.0},
        history: [{'version_number': 1}],
      );

      expect(updated.isLoading, isTrue);
      expect(updated.errorMessage, 'Connection timeout');
      expect(updated.dashboard?['overall_score'], 85.0);
      expect(updated.history?.length, 1);
      expect(updated.history?.first['version_number'], 1);
    });

    test('AnalyticsProvider default state initialization', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(analyticsProvider);
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNull);
      expect(state.dashboard, isNull);
    });
  });
}
