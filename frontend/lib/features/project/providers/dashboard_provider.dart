import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/project_api_client.dart';

class DashboardState {
  final bool isLoading;
  final String? errorMessage;
  final Map<String, dynamic>? data;

  const DashboardState({
    this.isLoading = false,
    this.errorMessage,
    this.data,
  });

  DashboardState copyWith({
    bool? isLoading,
    String? errorMessage,
    Map<String, dynamic>? data,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      data: data ?? this.data,
    );
  }
}

class DashboardNotifier extends Notifier<DashboardState> {
  final ProjectApiClient _apiClient = ProjectApiClient();

  @override
  DashboardState build() {
    return const DashboardState();
  }

  Future<void> fetchDashboard() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _apiClient.getDashboardSummary();
      if (res['success'] == true) {
        state = state.copyWith(isLoading: false, data: res['data']);
      } else {
        state = state.copyWith(isLoading: false, errorMessage: res['message'] ?? 'Failed to load');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }
}

final dashboardProvider = NotifierProvider<DashboardNotifier, DashboardState>(() {
  return DashboardNotifier();
});
