import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/ai_api_client.dart';
import 'designer_provider.dart';

class Recommendation {
  final String id;
  final String type;
  final String title;
  final String description;
  final String reason;
  final String ruleTriggered;
  final String expectedImprovement;
  final String scoreImpact;
  final Map<String, dynamic> action;

  Recommendation({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.reason,
    required this.ruleTriggered,
    required this.expectedImprovement,
    required this.scoreImpact,
    required this.action,
  });

  factory Recommendation.fromJson(Map<String, dynamic> json) {
    return Recommendation(
      id: json['id'],
      type: json['recommendation_type'],
      title: json['title'],
      description: json['description'],
      reason: json['reason'],
      ruleTriggered: json['rule_triggered'],
      expectedImprovement: json['expected_improvement'],
      scoreImpact: json['score_impact'],
      action: Map<String, dynamic>.from(json['action'] ?? {}),
    );
  }
}

class RecommendationHistoryItem {
  final String id;
  final String roomId;
  final String aiResultId;
  final bool applied;
  final DateTime createdAt;

  RecommendationHistoryItem({
    required this.id,
    required this.roomId,
    required this.aiResultId,
    required this.applied,
    required this.createdAt,
  });

  factory RecommendationHistoryItem.fromJson(Map<String, dynamic> json) {
    return RecommendationHistoryItem(
      id: json['id'],
      roomId: json['room_id'],
      aiResultId: json['ai_result_id'],
      applied: json['applied'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class RecommendationState {
  final bool isLoading;
  final String? errorMessage;
  final List<Recommendation> recommendations;
  final List<RecommendationHistoryItem> history;
  final Set<String> ignoredIds;
  final Set<String> savedIds;
  final Set<String> ignoredTitles;
  final Set<String> savedTitles;

  const RecommendationState({
    this.isLoading = false,
    this.errorMessage,
    this.recommendations = const [],
    this.history = const [],
    this.ignoredIds = const {},
    this.savedIds = const {},
    this.ignoredTitles = const {},
    this.savedTitles = const {},
  });

  RecommendationState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<Recommendation>? recommendations,
    List<RecommendationHistoryItem>? history,
    Set<String>? ignoredIds,
    Set<String>? savedIds,
    Set<String>? ignoredTitles,
    Set<String>? savedTitles,
  }) {
    return RecommendationState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      recommendations: recommendations ?? this.recommendations,
      history: history ?? this.history,
      ignoredIds: ignoredIds ?? this.ignoredIds,
      savedIds: savedIds ?? this.savedIds,
      ignoredTitles: ignoredTitles ?? this.ignoredTitles,
      savedTitles: savedTitles ?? this.savedTitles,
    );
  }
}

class RecommendationNotifier extends Notifier<RecommendationState> {
  final AiApiClient _apiClient = AiApiClient();

  @override
  RecommendationState build() {
    return const RecommendationState();
  }

  Future<void> fetchRecommendations(String roomId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final list = await _apiClient.getRecommendations(roomId);
      final recs = list.map((json) => Recommendation.fromJson(json)).toList();
      state = state.copyWith(isLoading: false, recommendations: recs);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> fetchHistory(String roomId) async {
    try {
      final list = await _apiClient.getHistory(roomId);
      final hist = list.map((json) => RecommendationHistoryItem.fromJson(json)).toList();
      state = state.copyWith(history: hist);
    } catch (_) {}
  }

  void ignore(Recommendation card) {
    final ignoredIds = Set<String>.from(state.ignoredIds)..add(card.id);
    final ignoredTitles = Set<String>.from(state.ignoredTitles)..add(card.title);
    state = state.copyWith(ignoredIds: ignoredIds, ignoredTitles: ignoredTitles);
  }

  void unignore(Recommendation card) {
    final ignoredIds = Set<String>.from(state.ignoredIds)..remove(card.id);
    final ignoredTitles = Set<String>.from(state.ignoredTitles)..remove(card.title);
    state = state.copyWith(ignoredIds: ignoredIds, ignoredTitles: ignoredTitles);
  }

  void save(Recommendation card) {
    final savedIds = Set<String>.from(state.savedIds)..add(card.id);
    final savedTitles = Set<String>.from(state.savedTitles)..add(card.title);
    state = state.copyWith(savedIds: savedIds, savedTitles: savedTitles);
  }

  void unsave(Recommendation card) {
    final savedIds = Set<String>.from(state.savedIds)..remove(card.id);
    final savedTitles = Set<String>.from(state.savedTitles)..remove(card.title);
    state = state.copyWith(savedIds: savedIds, savedTitles: savedTitles);
  }

  Future<bool> apply(String roomId, String recId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _apiClient.applyRecommendation(recId);
      if (res['success'] == true) {
        // Reload layout in designer provider
        await ref.read(designerProvider.notifier).loadLayout(roomId);
        // Refresh recommendations
        await fetchRecommendations(roomId);
        await fetchHistory(roomId);
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }
}

final recommendationProvider = NotifierProvider<RecommendationNotifier, RecommendationState>(() {
  return RecommendationNotifier();
});
