import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/ai_api_client.dart';

class DesignScores {
  final double overallScore;
  final Map<String, double> subscores;

  DesignScores({required this.overallScore, required this.subscores});

  factory DesignScores.fromJson(Map<String, dynamic> json) {
    final sub = Map<String, dynamic>.from(json['subscores'] ?? {});
    final Map<String, double> mappedSub = {};
    sub.forEach((key, val) {
      mappedSub[key] = (val as num).toDouble();
    });
    return DesignScores(
      overallScore: (json['overall_score'] as num? ?? 0.0).toDouble(),
      subscores: mappedSub,
    );
  }
}

class DesignScoreState {
  final bool isLoading;
  final String? errorMessage;
  final DesignScores? scores;

  const DesignScoreState({
    this.isLoading = false,
    this.errorMessage,
    this.scores,
  });

  DesignScoreState copyWith({
    bool? isLoading,
    String? errorMessage,
    DesignScores? scores,
  }) {
    return DesignScoreState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      scores: scores ?? this.scores,
    );
  }
}

class DesignScoreNotifier extends Notifier<DesignScoreState> {
  final AiApiClient _apiClient = AiApiClient();

  @override
  DesignScoreState build() {
    return const DesignScoreState();
  }

  Future<void> fetchScores(String roomId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final json = await _apiClient.getRoomScores(roomId);
      final scores = DesignScores.fromJson(json);
      state = state.copyWith(isLoading: false, scores: scores);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }
}

final designScoreProvider = NotifierProvider<DesignScoreNotifier, DesignScoreState>(() {
  return DesignScoreNotifier();
});
