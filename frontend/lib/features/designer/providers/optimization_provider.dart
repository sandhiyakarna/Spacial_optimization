import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/ai_api_client.dart';
import 'designer_provider.dart';
import 'design_score_provider.dart';
import 'recommendation_provider.dart';

class OptimizationState {
  final bool isLoading;
  final String? errorMessage;
  final bool success;

  const OptimizationState({
    this.isLoading = false,
    this.errorMessage,
    this.success = false,
  });

  OptimizationState copyWith({
    bool? isLoading,
    String? errorMessage,
    bool? success,
  }) {
    return OptimizationState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      success: success ?? this.success,
    );
  }
}

class OptimizationNotifier extends Notifier<OptimizationState> {
  final AiApiClient _apiClient = AiApiClient();

  @override
  OptimizationState build() {
    return const OptimizationState();
  }

  Future<bool> runOptimization(String roomId) async {
    state = state.copyWith(isLoading: true, errorMessage: null, success: false);
    try {
      await _apiClient.optimizeLayout(roomId);
      
      // Load optimized layout in the designer notifier
      await ref.read(designerProvider.notifier).loadLayout(roomId);
      
      // Refresh scores and recommendations
      ref.read(designScoreProvider.notifier).fetchScores(roomId);
      ref.read(recommendationProvider.notifier).fetchRecommendations(roomId);
      
      state = state.copyWith(isLoading: false, success: true);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }
}

final optimizationProvider = NotifierProvider<OptimizationNotifier, OptimizationState>(() {
  return OptimizationNotifier();
});
