import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/analytics_api_client.dart';

class AnalyticsState {
  final bool isLoading;
  final String? errorMessage;
  final Map<String, dynamic>? dashboard;
  final List<dynamic>? history;
  final Map<String, dynamic>? statistics;
  final List<dynamic>? insights;
  final Map<String, dynamic>? projectAnalytics;
  final Map<String, dynamic>? comparison;

  const AnalyticsState({
    this.isLoading = false,
    this.errorMessage,
    this.dashboard,
    this.history,
    this.statistics,
    this.insights,
    this.projectAnalytics,
    this.comparison,
  });

  AnalyticsState copyWith({
    bool? isLoading,
    String? errorMessage,
    Map<String, dynamic>? dashboard,
    List<dynamic>? history,
    Map<String, dynamic>? statistics,
    List<dynamic>? insights,
    Map<String, dynamic>? projectAnalytics,
    Map<String, dynamic>? comparison,
  }) {
    return AnalyticsState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      dashboard: dashboard ?? this.dashboard,
      history: history ?? this.history,
      statistics: statistics ?? this.statistics,
      insights: insights ?? this.insights,
      projectAnalytics: projectAnalytics ?? this.projectAnalytics,
      comparison: comparison ?? this.comparison,
    );
  }
}

class AnalyticsNotifier extends Notifier<AnalyticsState> {
  final AnalyticsApiClient _apiClient = AnalyticsApiClient();

  @override
  AnalyticsState build() {
    return const AnalyticsState();
  }

  Future<void> fetchRoomAnalytics(String roomId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final dashboard = await _apiClient.getAnalyticsDashboard(roomId);
      final stats = await _apiClient.getStatistics(roomId);
      final insights = await _apiClient.getInsights(roomId);
      final history = await _apiClient.getHistory(roomId);

      state = state.copyWith(
        isLoading: false,
        dashboard: dashboard,
        statistics: stats,
        insights: insights,
        history: history,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> fetchProjectAnalytics(String projectId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final data = await _apiClient.getProjectAnalytics(projectId);
      state = state.copyWith(isLoading: false, projectAnalytics: data);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> compareLayouts(String layoutA, String layoutB) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final comp = await _apiClient.compareLayouts(layoutA, layoutB);
      state = state.copyWith(isLoading: false, comparison: comp);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<bool> restoreVersion(String roomId, int versionNumber) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _apiClient.restoreHistory(roomId, versionNumber);
      await fetchRoomAnalytics(roomId);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }
}

final analyticsProvider = NotifierProvider<AnalyticsNotifier, AnalyticsState>(() {
  return AnalyticsNotifier();
});
