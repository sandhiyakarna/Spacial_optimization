import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/validation_api_client.dart';
import 'design_score_provider.dart';

class ValidationIssue {
  final String? ruleId;
  final String ruleName;
  final String category;
  final String severity;
  final String message;
  final String? recommendation;
  final List<String> affectedFurnitureIds;
  final double? measuredClearance;
  final double? requiredClearance;
  final String? clearanceSource;
  final String? issueType;
  final bool isFixable;
  final String? suggestedAction;

  ValidationIssue({
    this.ruleId,
    required this.ruleName,
    required this.category,
    required this.severity,
    required this.message,
    this.recommendation,
    this.affectedFurnitureIds = const [],
    this.measuredClearance,
    this.requiredClearance,
    this.clearanceSource,
    this.issueType,
    this.isFixable = true,
    this.suggestedAction,
  });

  factory ValidationIssue.fromJson(Map<String, dynamic> json) {
    return ValidationIssue(
      ruleId: json['rule_id'] as String?,
      ruleName: json['rule_name'] as String? ?? 'Rule',
      category: json['category'] as String? ?? 'General',
      severity: json['severity'] as String? ?? 'Info',
      message: json['message'] as String? ?? '',
      recommendation: json['recommendation'] as String?,
      affectedFurnitureIds: json['affected_furniture_ids'] != null 
          ? List<String>.from(json['affected_furniture_ids']) 
          : const [],
      measuredClearance: (json['measured_clearance'] as num?)?.toDouble(),
      requiredClearance: (json['required_clearance'] as num?)?.toDouble(),
      clearanceSource: json['clearance_source'] as String?,
      issueType: json['issue_type'] as String?,
      isFixable: json['is_fixable'] as bool? ?? true,
      suggestedAction: json['suggested_action'] as String?,
    );
  }
}

class ProposedFurnitureChange {
  final String furnitureId;
  final double originalX;
  final double originalZ;
  final double originalRotation;
  final double proposedX;
  final double proposedZ;
  final double proposedRotation;
  final double movementDistance;
  final double rotationDeltaDegrees;

  ProposedFurnitureChange({
    required this.furnitureId,
    required this.originalX,
    required this.originalZ,
    required this.originalRotation,
    required this.proposedX,
    required this.proposedZ,
    required this.proposedRotation,
    required this.movementDistance,
    required this.rotationDeltaDegrees,
  });

  factory ProposedFurnitureChange.fromJson(Map<String, dynamic> json) {
    return ProposedFurnitureChange(
      furnitureId: json['furniture_id'] as String? ?? '',
      originalX: (json['original_x'] as num? ?? 0.0).toDouble(),
      originalZ: (json['original_z'] as num? ?? 0.0).toDouble(),
      originalRotation: (json['original_rotation'] as num? ?? 0.0).toDouble(),
      proposedX: (json['proposed_x'] as num? ?? 0.0).toDouble(),
      proposedZ: (json['proposed_z'] as num? ?? 0.0).toDouble(),
      proposedRotation: (json['proposed_rotation'] as num? ?? 0.0).toDouble(),
      movementDistance: (json['movement_distance'] as num? ?? 0.0).toDouble(),
      rotationDeltaDegrees: (json['rotation_delta_degrees'] as num? ?? 0.0).toDouble(),
    );
  }
}

class FixCandidate {
  final bool canFix;
  final String roomId;
  final String ruleId;
  final String issueType;
  final String targetFurnitureId;
  final String strategy;
  final String explanation;
  final double? measuredBefore;
  final double? measuredAfter;
  final double? requiredClearance;
  final String? clearanceSource;
  final List<ProposedFurnitureChange> changes;
  final List<String> alternativeSuggestions;

  FixCandidate({
    required this.canFix,
    required this.roomId,
    required this.ruleId,
    required this.issueType,
    required this.targetFurnitureId,
    required this.strategy,
    required this.explanation,
    this.measuredBefore,
    this.measuredAfter,
    this.requiredClearance,
    this.clearanceSource,
    this.changes = const [],
    this.alternativeSuggestions = const [],
  });

  factory FixCandidate.fromJson(Map<String, dynamic> json) {
    final changesList = (json['changes'] as List<dynamic>?)
            ?.map((c) => ProposedFurnitureChange.fromJson(c as Map<String, dynamic>))
            .toList() ??
        [];
    final altList = (json['alternative_suggestions'] as List<dynamic>?)
            ?.map((a) => a.toString())
            .toList() ??
        [];

    return FixCandidate(
      canFix: json['can_fix'] as bool? ?? false,
      roomId: json['room_id'] as String? ?? '',
      ruleId: json['rule_id'] as String? ?? '',
      issueType: json['issue_type'] as String? ?? '',
      targetFurnitureId: json['target_furniture_id'] as String? ?? '',
      strategy: json['strategy'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
      measuredBefore: (json['measured_before'] as num?)?.toDouble(),
      measuredAfter: (json['measured_after'] as num?)?.toDouble(),
      requiredClearance: (json['required_clearance'] as num?)?.toDouble(),
      clearanceSource: json['clearance_source'] as String?,
      changes: changesList,
      alternativeSuggestions: altList,
    );
  }
}

class ChecklistItem {
  final String id;
  final String checklistItem;
  final bool completed;
  final DateTime? completedAt;

  ChecklistItem({
    required this.id,
    required this.checklistItem,
    required this.completed,
    this.completedAt,
  });

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: json['id'] as String,
      checklistItem: json['checklist_item'] as String,
      completed: json['completed'] as bool? ?? false,
      completedAt: json['completed_at'] != null 
          ? DateTime.tryParse(json['completed_at'] as String) 
          : null,
    );
  }
}

class ValidationSummary {
  final double passRate;
  final int warningCount;
  final int errorCount;
  final String overallStatus;
  final double overallScore;
  final double accessibilityScore;
  final double lightingScore;
  final double ergonomicScore;
  final double spaceUtilizationScore;
  final double furnitureBalanceScore;

  ValidationSummary({
    required this.passRate,
    required this.warningCount,
    required this.errorCount,
    required this.overallStatus,
    required this.overallScore,
    required this.accessibilityScore,
    required this.lightingScore,
    required this.ergonomicScore,
    required this.spaceUtilizationScore,
    required this.furnitureBalanceScore,
  });

  factory ValidationSummary.fromJson(Map<String, dynamic> json) {
    return ValidationSummary(
      passRate: (json['pass_rate'] as num? ?? 100.0).toDouble(),
      warningCount: json['warning_count'] as int? ?? 0,
      errorCount: json['error_count'] as int? ?? 0,
      overallStatus: json['overall_status'] as String? ?? 'Pass',
      overallScore: (json['overall_score'] as num? ?? 100.0).toDouble(),
      accessibilityScore: (json['accessibility_score'] as num? ?? 100.0).toDouble(),
      lightingScore: (json['lighting_score'] as num? ?? 100.0).toDouble(),
      ergonomicScore: (json['ergonomic_score'] as num? ?? 100.0).toDouble(),
      spaceUtilizationScore: (json['space_utilization_score'] as num? ?? 0.0).toDouble(),
      furnitureBalanceScore: (json['furniture_balance_score'] as num? ?? 100.0).toDouble(),
    );
  }
}

class ValidationState {
  final bool isLoading;
  final String? errorMessage;
  final List<ValidationIssue> errors;
  final List<ValidationIssue> warnings;
  final List<ValidationIssue> suggestions;
  final List<ChecklistItem> checklist;
  final ValidationSummary? summary;

  // Real-world Usability & Configurable clearings
  final double minWalkwayClearance;
  final bool requireBothSidesBedAccess;

  // One-Click Fix State
  final FixCandidate? activeFixCandidate;
  final ValidationIssue? previewingIssue;
  final String? highlightedFurnitureId;
  final bool isEvaluatingFix;
  final bool isApplyingFix;
  final String? fixErrorMessage;

  const ValidationState({
    this.isLoading = false,
    this.errorMessage,
    this.errors = const [],
    this.warnings = const [],
    this.suggestions = const [],
    this.checklist = const [],
    this.summary,
    this.minWalkwayClearance = 75.0,
    this.requireBothSidesBedAccess = false,
    this.activeFixCandidate,
    this.previewingIssue,
    this.highlightedFurnitureId,
    this.isEvaluatingFix = false,
    this.isApplyingFix = false,
    this.fixErrorMessage,
  });

  ValidationState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<ValidationIssue>? errors,
    List<ValidationIssue>? warnings,
    List<ValidationIssue>? suggestions,
    List<ChecklistItem>? checklist,
    ValidationSummary? summary,
    double? minWalkwayClearance,
    bool? requireBothSidesBedAccess,
    FixCandidate? activeFixCandidate,
    bool clearActiveFixCandidate = false,
    ValidationIssue? previewingIssue,
    bool clearPreviewingIssue = false,
    String? highlightedFurnitureId,
    bool clearHighlightedFurnitureId = false,
    bool? isEvaluatingFix,
    bool? isApplyingFix,
    String? fixErrorMessage,
  }) {
    return ValidationState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      errors: errors ?? this.errors,
      warnings: warnings ?? this.warnings,
      suggestions: suggestions ?? this.suggestions,
      checklist: checklist ?? this.checklist,
      summary: summary ?? this.summary,
      minWalkwayClearance: minWalkwayClearance ?? this.minWalkwayClearance,
      requireBothSidesBedAccess: requireBothSidesBedAccess ?? this.requireBothSidesBedAccess,
      activeFixCandidate: clearActiveFixCandidate ? null : (activeFixCandidate ?? this.activeFixCandidate),
      previewingIssue: clearPreviewingIssue ? null : (previewingIssue ?? this.previewingIssue),
      highlightedFurnitureId: clearHighlightedFurnitureId ? null : (highlightedFurnitureId ?? this.highlightedFurnitureId),
      isEvaluatingFix: isEvaluatingFix ?? this.isEvaluatingFix,
      isApplyingFix: isApplyingFix ?? this.isApplyingFix,
      fixErrorMessage: fixErrorMessage,
    );
  }
}

class ValidationNotifier extends Notifier<ValidationState> {
  final ValidationApiClient _apiClient = ValidationApiClient();
  Timer? _debounceTimer;

  @override
  ValidationState build() {
    return const ValidationState();
  }

  void setWalkwayClearance(String roomId, double clearance) {
    state = state.copyWith(minWalkwayClearance: clearance);
    scheduleValidation(roomId);
  }

  void setRequireBothSidesBedAccess(String roomId, bool require) {
    state = state.copyWith(requireBothSidesBedAccess: require);
    scheduleValidation(roomId);
  }

  void highlightFurniture(String? furnitureId) {
    state = state.copyWith(
      highlightedFurnitureId: furnitureId,
      clearHighlightedFurnitureId: furnitureId == null,
    );
  }

  void scheduleValidation(String roomId) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      runValidation(roomId);
    });
  }

  Future<void> runValidation(String roomId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final runData = await _apiClient.runValidation(
        roomId,
        minWalkwayClearance: state.minWalkwayClearance,
        requireBothSidesBedAccess: state.requireBothSidesBedAccess,
      );
      final List<dynamic> errsJson = runData['errors'] ?? [];
      final List<dynamic> warnsJson = runData['warnings'] ?? [];
      final List<dynamic> suggsJson = runData['suggestions'] ?? [];

      final errors = errsJson.map((e) => ValidationIssue.fromJson(e)).toList();
      final warnings = warnsJson.map((w) => ValidationIssue.fromJson(w)).toList();
      final suggestions = suggsJson.map((s) => ValidationIssue.fromJson(s)).toList();

      final chkData = await _apiClient.getValidationChecklist(roomId);
      final List<dynamic> itemsJson = chkData['checklist_items'] ?? [];
      final checklist = itemsJson.map((i) => ChecklistItem.fromJson(i)).toList();

      final sumData = await _apiClient.getValidationSummary(roomId);
      final summary = ValidationSummary.fromJson(sumData);

      state = state.copyWith(
        isLoading: false,
        errors: errors,
        warnings: warnings,
        suggestions: suggestions,
        checklist: checklist,
        summary: summary,
      );
      
      ref.read(designScoreProvider.notifier).fetchScores(roomId);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> loadValidationResults(String roomId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final resData = await _apiClient.getValidationResults(roomId);
      final List<dynamic> errsJson = resData['errors'] ?? [];
      final List<dynamic> warnsJson = resData['warnings'] ?? [];
      final errors = errsJson.map((e) => ValidationIssue.fromJson(e)).toList();
      final warnings = warnsJson.map((w) => ValidationIssue.fromJson(w)).toList();

      final chkData = await _apiClient.getValidationChecklist(roomId);
      final List<dynamic> itemsJson = chkData['checklist_items'] ?? [];
      final checklist = itemsJson.map((i) => ChecklistItem.fromJson(i)).toList();

      final sumData = await _apiClient.getValidationSummary(roomId);
      final summary = ValidationSummary.fromJson(sumData);

      state = state.copyWith(
        isLoading: false,
        errors: errors,
        warnings: warnings,
        suggestions: const [],
        checklist: checklist,
        summary: summary,
      );
      
      ref.read(designScoreProvider.notifier).fetchScores(roomId);
    } catch (e) {
      await runValidation(roomId);
    }
  }

  Future<FixCandidate?> requestFixCandidate(String roomId, ValidationIssue issue) async {
    final furnitureId = issue.affectedFurnitureIds.isNotEmpty ? issue.affectedFurnitureIds.first : null;
    if (furnitureId == null) {
      state = state.copyWith(fixErrorMessage: 'No specific furniture item identified for this issue.');
      return null;
    }

    state = state.copyWith(
      isEvaluatingFix: true,
      fixErrorMessage: null,
      previewingIssue: issue,
      highlightedFurnitureId: furnitureId,
    );

    try {
      final fixResp = await _apiClient.getFixCandidate(
        roomId: roomId,
        ruleId: issue.ruleId ?? '',
        issueType: issue.issueType ?? 'clearance',
        furnitureId: furnitureId,
        minWalkwayClearance: state.minWalkwayClearance,
        requireBothSidesBedAccess: state.requireBothSidesBedAccess,
      );

      final candidate = FixCandidate.fromJson(fixResp);
      state = state.copyWith(
        isEvaluatingFix: false,
        activeFixCandidate: candidate,
      );
      return candidate;
    } catch (e) {
      state = state.copyWith(
        isEvaluatingFix: false,
        fixErrorMessage: e.toString(),
      );
      return null;
    }
  }

  void dismissFixPreview() {
    state = state.copyWith(
      clearActiveFixCandidate: true,
      clearPreviewingIssue: true,
      clearHighlightedFurnitureId: true,
      fixErrorMessage: null,
    );
  }

  Future<bool> applyCandidateFix(
    String roomId, {
    required Future<void> Function(String furnitureId, double proposedX, double proposedZ, double proposedRotation) onApplyLocally,
  }) async {
    final candidate = state.activeFixCandidate;
    if (candidate == null || !candidate.canFix || candidate.changes.isEmpty) {
      return false;
    }

    state = state.copyWith(isApplyingFix: true, fixErrorMessage: null);

    try {
      final change = candidate.changes.first;

      // 1. Apply to local DesignerProvider first (pushes to undo stack)
      await onApplyLocally(
        change.furnitureId,
        change.proposedX,
        change.proposedZ,
        change.proposedRotation,
      );

      // 2. Persist to backend and revalidate
      final applyResp = await _apiClient.applyFix(
        roomId: roomId,
        furnitureId: change.furnitureId,
        proposedX: change.proposedX,
        proposedZ: change.proposedZ,
        proposedRotation: change.proposedRotation,
      );

      final List<dynamic> errsJson = applyResp['errors'] ?? [];
      final List<dynamic> warnsJson = applyResp['warnings'] ?? [];
      final List<dynamic> suggsJson = applyResp['suggestions'] ?? [];

      final errors = errsJson.map((e) => ValidationIssue.fromJson(e)).toList();
      final warnings = warnsJson.map((w) => ValidationIssue.fromJson(w)).toList();
      final suggestions = suggsJson.map((s) => ValidationIssue.fromJson(s)).toList();

      // Refresh checklist & summary
      final chkData = await _apiClient.getValidationChecklist(roomId);
      final List<dynamic> itemsJson = chkData['checklist_items'] ?? [];
      final checklist = itemsJson.map((i) => ChecklistItem.fromJson(i)).toList();

      final sumData = await _apiClient.getValidationSummary(roomId);
      final summary = ValidationSummary.fromJson(sumData);

      state = state.copyWith(
        isApplyingFix: false,
        clearActiveFixCandidate: true,
        clearPreviewingIssue: true,
        clearHighlightedFurnitureId: true,
        errors: errors,
        warnings: warnings,
        suggestions: suggestions,
        checklist: checklist,
        summary: summary,
      );

      ref.read(designScoreProvider.notifier).fetchScores(roomId);
      return true;
    } catch (e) {
      state = state.copyWith(
        isApplyingFix: false,
        fixErrorMessage: e.toString(),
      );
      return false;
    }
  }
}

final validationProvider = NotifierProvider<ValidationNotifier, ValidationState>(() {
  return ValidationNotifier();
});
