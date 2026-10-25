import 'dart:math' as math;
import '../../../../app/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/validation_provider.dart';
import '../../providers/designer_provider.dart';
import '../../../../shared/widgets/snackbar_manager.dart';

class ValidationPanel extends ConsumerWidget {
  final String roomId;

  const ValidationPanel({super.key, required this.roomId});

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pass':
        return Colors.green.shade600;
      case 'warning':
        return Colors.amber.shade700;
      case 'fail':
      default:
        return Colors.red.shade600;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(validationProvider);
    final layout = ref.watch(designerProvider);

    return Drawer(
      width: 400.0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Validation & Rules',
                    style: TextStyle(
                      fontSize: 22.0,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),

              Expanded(
                child: state.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.primary),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 0. Active Fix Candidate Preview Card
                            if (state.activeFixCandidate != null || state.isEvaluatingFix || state.fixErrorMessage != null)
                              _buildFixPreviewCard(context, ref, state),

                            // Usability & Clearance Configuration
                            _buildUsabilityConfigCard(context, ref, state),
                            const SizedBox(height: 16.0),

                            // 1. Overall Status Card
                            if (state.summary != null)
                              _buildSummaryCard(context, state.summary!),
                            const SizedBox(height: 16.0),

                            // Space Utilization & Geometric Analytics Card
                            _buildSpaceUtilizationCard(layout, state),
                            const SizedBox(height: 20.0),

                            // 2. Checklist Section
                            _buildChecklistSection(context, state),
                            const SizedBox(height: 24.0),

                            // 3. Issues Sections (Errors, Warnings, Suggestions)
                            _buildIssuesSection(context, ref, state),
                          ],
                        ),
                      ),
              ),
              
              // Bottom Action Button
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Revalidate Layout'),
                  onPressed: () {
                    ref.read(validationProvider.notifier).runValidation(roomId);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreBar(String label, double score, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.w500),
              ),
              Text(
                '${score.round()}/100',
                style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 4.0),
          ClipRRect(
            borderRadius: BorderRadius.circular(4.0),
            child: LinearProgressIndicator(
              value: score / 100.0,
              color: color,
              backgroundColor: Colors.grey.shade200,
              minHeight: 4.0,
            ),
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 80.0) return Colors.green.shade600;
    if (score >= 50.0) return Colors.amber.shade700;
    return Colors.red.shade600;
  }

  Widget _buildSummaryCard(BuildContext context, ValidationSummary summary) {
    final statusColor = _getStatusColor(summary.overallStatus);
    final scoreColor = _getScoreColor(summary.overallScore);
    
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(color: statusColor.withOpacity(0.2)),
      ),
      color: statusColor.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Layout Health: ${summary.overallStatus.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 15.0,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      '${summary.passRate.round()}% of rules passed',
                      style: TextStyle(
                        fontSize: 12.0,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                  decoration: BoxDecoration(
                    color: scoreColor,
                    borderRadius: BorderRadius.circular(12.0),
                    boxShadow: [
                      BoxShadow(
                        color: scoreColor.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${summary.overallScore.round()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22.0,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                      const Text(
                        'Design Score',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 9.0,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: LinearProgressIndicator(
                value: summary.passRate / 100.0,
                color: statusColor,
                backgroundColor: Colors.grey.shade200,
                minHeight: 6.0,
              ),
            ),
            const SizedBox(height: 12.0),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: const Text(
                  'View Score Breakdown',
                  style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.bold),
                ),
                dense: true,
                childrenPadding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                children: [
                  _buildScoreBar('Space Utilization', summary.spaceUtilizationScore, _getScoreColor(summary.spaceUtilizationScore)),
                  _buildScoreBar('Accessibility Standards', summary.accessibilityScore, _getScoreColor(summary.accessibilityScore)),
                  _buildScoreBar('Comfort & Ergonomics', summary.ergonomicScore, _getScoreColor(summary.ergonomicScore)),
                  _buildScoreBar('Lighting Coverage', summary.lightingScore, _getScoreColor(summary.lightingScore)),
                  _buildScoreBar('Visual Balance', summary.furnitureBalanceScore, _getScoreColor(summary.furnitureBalanceScore)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistSection(BuildContext context, ValidationState state) {
    if (state.checklist.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Design Checklist',
              style: TextStyle(
                fontSize: 16.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${state.summary?.passRate.round() ?? 0}% Complete',
              style: const TextStyle(
                fontSize: 13.0,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: state.checklist.length,
              itemBuilder: (context, index) {
                final item = state.checklist[index];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    item.completed ? Icons.check_circle : Icons.cancel_outlined,
                    color: item.completed ? Colors.green : Colors.red,
                    size: 20.0,
                  ),
                  title: Text(
                    item.checklistItem,
                    style: TextStyle(
                      decoration: item.completed ? TextDecoration.lineThrough : null,
                      color: item.completed ? Colors.grey.shade500 : Colors.black87,
                      fontWeight: item.completed ? null : FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIssuesSection(BuildContext context, WidgetRef ref, ValidationState state) {
    if (state.errors.isEmpty && state.warnings.isEmpty && state.suggestions.isEmpty) {
      return Card(
        elevation: 0,
        color: Colors.green.withOpacity(0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
          side: BorderSide(color: Colors.green.withOpacity(0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green, size: 28.0),
              const SizedBox(width: 12.0),
              Expanded(
                child: Text(
                  'No issues detected! Your layout complies with all architectural, design, and accessibility rules.',
                  style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final List<Widget> issuesList = [];

    // Group 1: Errors (Critical violations)
    if (state.errors.isNotEmpty) {
      issuesList.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Icon(Icons.cancel, color: Colors.red, size: 18.0),
            SizedBox(width: 6.0),
            Text(
              'Critical Violations (Errors)',
              style: TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold, color: Colors.red),
            ),
          ],
        ),
      ));
      for (final err in state.errors) {
        issuesList.add(_buildIssueCard(context, ref, err, Colors.red.shade600, Icons.error_outline));
        issuesList.add(const SizedBox(height: 8.0));
      }
    }

    // Group 2: Warnings (Potential issues)
    if (state.warnings.isNotEmpty) {
      issuesList.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Icon(Icons.warning, color: Colors.amber.shade700, size: 18.0),
            SizedBox(width: 6.0),
            Text(
              'Warnings & Alerts',
              style: TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold, color: Colors.amber.shade800),
            ),
          ],
        ),
      ));
      for (final wrn in state.warnings) {
        issuesList.add(_buildIssueCard(context, ref, wrn, Colors.amber.shade700, Icons.warning_amber_outlined));
        issuesList.add(const SizedBox(height: 8.0));
      }
    }

    // Group 3: Suggestions (Improvement advice)
    if (state.suggestions.isNotEmpty) {
      issuesList.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Icon(Icons.lightbulb, color: Colors.blue, size: 18.0),
            SizedBox(width: 6.0),
            Text(
              'Design Improvements (Suggestions)',
              style: TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ],
        ),
      ));
      for (final sug in state.suggestions) {
        issuesList.add(_buildIssueCard(context, ref, sug, Colors.blue.shade600, Icons.info_outline));
        issuesList.add(const SizedBox(height: 8.0));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Warning Panel & Recommendations',
          style: TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8.0),
        ...issuesList,
      ],
    );
  }

  Widget _buildUsabilityConfigCard(BuildContext context, WidgetRef ref, ValidationState state) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(color: AppTheme.primary.withOpacity(0.2)),
      ),
      color: AppTheme.primary.withOpacity(0.03),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, size: 16.0, color: AppTheme.primary.shade800),
                const SizedBox(width: 6.0),
                Text(
                  'Usability & Clearance Config',
                  style: TextStyle(
                    fontSize: 13.0,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Min Walkway Width:', style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w500)),
                Text(
                  '${state.minWalkwayClearance.round()} cm',
                  style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: AppTheme.primary),
                ),
              ],
            ),
            Slider(
              value: state.minWalkwayClearance.clamp(60.0, 120.0),
              min: 60.0,
              max: 120.0,
              divisions: 12,
              activeColor: AppTheme.primary,
              label: '${state.minWalkwayClearance.round()} cm',
              onChanged: (val) {
                ref.read(validationProvider.notifier).setWalkwayClearance(roomId, val);
              },
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Require Both Sides Bed Access', style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w500)),
              subtitle: const Text('Enforces dual bedside egress for master/double suites', style: TextStyle(fontSize: 10.5, color: Colors.black54)),
              value: state.requireBothSidesBedAccess,
              activeColor: AppTheme.primary,
              onChanged: (val) {
                ref.read(validationProvider.notifier).setRequireBothSidesBedAccess(roomId, val);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFixPreviewCard(BuildContext context, WidgetRef ref, ValidationState state) {
    if (state.isEvaluatingFix) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
          side: BorderSide(color: Colors.blue.withOpacity(0.3)),
        ),
        color: Colors.blue.withOpacity(0.05),
        margin: const EdgeInsets.only(bottom: 16.0),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Row(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.blue)),
              SizedBox(width: 12.0),
              Expanded(
                child: Text('Evaluating intelligent, minimal-displacement fix candidate...', style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      );
    }

    if (state.fixErrorMessage != null) {
      return Card(
        elevation: 0,
        color: Colors.red.withOpacity(0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
          side: BorderSide(color: Colors.red.withOpacity(0.3)),
        ),
        margin: const EdgeInsets.only(bottom: 16.0),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 20.0),
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(state.fixErrorMessage!, style: TextStyle(fontSize: 11.5, color: Colors.red.shade900)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16.0),
                onPressed: () => ref.read(validationProvider.notifier).dismissFixPreview(),
              ),
            ],
          ),
        ),
      );
    }

    final candidate = state.activeFixCandidate;
    if (candidate == null) return const SizedBox.shrink();

    if (candidate.canFix) {
      final change = candidate.changes.isNotEmpty ? candidate.changes.first : null;
      return Card(
        elevation: 0,
        color: Colors.green.withOpacity(0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
          side: BorderSide(color: Colors.green.shade600, width: 1.5),
        ),
        margin: const EdgeInsets.only(bottom: 16.0),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_fix_high, color: Colors.green.shade700, size: 20.0),
                  const SizedBox(width: 8.0),
                  const Expanded(
                    child: Text(
                      'One-Click Correction Preview',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16.0),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => ref.read(validationProvider.notifier).dismissFixPreview(),
                  ),
                ],
              ),
              const SizedBox(height: 6.0),
              Text(
                candidate.explanation,
                style: TextStyle(fontSize: 12.0, color: Colors.grey.shade900, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8.0),
              if (candidate.measuredBefore != null && candidate.measuredAfter != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6.0),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Before: ${candidate.measuredBefore!.toStringAsFixed(0)} cm',
                        style: TextStyle(fontSize: 11.0, color: Colors.red.shade700, fontWeight: FontWeight.bold),
                      ),
                      const Icon(Icons.arrow_forward, size: 14.0, color: Colors.green),
                      Text(
                        'Predicted: ${candidate.measuredAfter!.toStringAsFixed(0)} cm',
                        style: TextStyle(fontSize: 11.0, color: Colors.green.shade800, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '(Req: ${candidate.requiredClearance?.toStringAsFixed(0) ?? "75"} cm)',
                        style: const TextStyle(fontSize: 10.0, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              if (change != null) ...[
                const SizedBox(height: 6.0),
                Text(
                  'Preservation: Shifts only ${candidate.targetFurnitureId} by ${change.movementDistance.round()} cm. Non-involved items unchanged.',
                  style: const TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: Colors.black54),
                ),
              ],
              const SizedBox(height: 10.0),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: state.isApplyingFix 
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check, size: 16.0),
                      label: const Text('Apply Correction (Undo Supported)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10.0),
                      ),
                      onPressed: state.isApplyingFix
                          ? null
                          : () async {
                              final success = await ref.read(validationProvider.notifier).applyCandidateFix(
                                roomId,
                                onApplyLocally: (id, x, z, rot) async {
                                  ref.read(designerProvider.notifier).applyFixCorrection(
                                    furnitureId: id,
                                    proposedX: x,
                                    proposedZ: z,
                                    proposedRotation: rot,
                                  );
                                },
                              );
                              if (context.mounted && success) {
                                SnackbarManager.showSuccess(context, 'Layout correction applied! Press Ctrl+Z to undo anytime.');
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  OutlinedButton(
                    onPressed: () => ref.read(validationProvider.notifier).dismissFixPreview(),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12.0)),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } else {
      // Unresolvable layout issue
      return Card(
        elevation: 0,
        color: Colors.amber.withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
          side: BorderSide(color: Colors.amber.shade700, width: 1.5),
        ),
        margin: const EdgeInsets.only(bottom: 16.0),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 20.0),
                  const SizedBox(width: 8.0),
                  const Expanded(
                    child: Text(
                      'No Valid Correction Found',
                      style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.bold, color: Colors.brown),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16.0),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => ref.read(validationProvider.notifier).dismissFixPreview(),
                  ),
                ],
              ),
              const SizedBox(height: 6.0),
              Text(
                candidate.explanation,
                style: TextStyle(fontSize: 11.5, color: Colors.brown.shade900),
              ),
              if (candidate.alternativeSuggestions.isNotEmpty) ...[
                const SizedBox(height: 8.0),
                const Text('Suggested Alternatives:', style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4.0),
                ...candidate.alternativeSuggestions.map((alt) => Padding(
                  padding: const EdgeInsets.only(bottom: 2.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(child: Text(alt, style: const TextStyle(fontSize: 11.0, color: Colors.black87))),
                    ],
                  ),
                )),
              ],
            ],
          ),
        ),
      );
    }
  }

  Widget _buildIssueCard(
    BuildContext context,
    WidgetRef ref,
    ValidationIssue issue,
    Color color,
    IconData icon,
  ) {
    final hasClearance = issue.measuredClearance != null;
    final isFixable = issue.isFixable && issue.affectedFurnitureIds.isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(color: color.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 22.0),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              issue.ruleName,
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: color),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: color.withOpacity(0.3)),
                            ),
                            child: Text(
                              issue.severity.toUpperCase(),
                              style: TextStyle(fontSize: 9.0, fontWeight: FontWeight.bold, color: color),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        issue.message,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (hasClearance) ...[
              const SizedBox(height: 8.0),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(color: color.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Measured: ${issue.measuredClearance!.toStringAsFixed(1)} cm',
                      style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: color),
                    ),
                    Text(
                      'Required: ${issue.requiredClearance?.toStringAsFixed(1) ?? "75.0"} cm',
                      style: const TextStyle(fontSize: 11.0, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                    if (issue.clearanceSource != null)
                      Text(
                        issue.clearanceSource!,
                        style: const TextStyle(fontSize: 9.5, color: Colors.black54, fontStyle: FontStyle.italic),
                      ),
                  ],
                ),
              ),
            ],
            if (issue.recommendation != null) ...[
              const SizedBox(height: 6.0),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, color: AppTheme.primary.shade700, size: 14.0),
                        const SizedBox(width: 4.0),
                        Text(
                          'Suggested Correction',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.primary.shade900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      issue.recommendation!,
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (issue.affectedFurnitureIds.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.center_focus_strong, size: 15.0),
                    label: const Text('Highlight in Room', style: TextStyle(fontSize: 11.5)),
                    style: TextButton.styleFrom(foregroundColor: color),
                    onPressed: () {
                      final targetId = issue.affectedFurnitureIds.first;
                      ref.read(validationProvider.notifier).highlightFurniture(targetId);
                      ref.read(designerProvider.notifier).selectFurniture(targetId);
                      SnackbarManager.showInfo(context, 'Focused $targetId in layout floor plan');
                    },
                  ),
                if (isFixable) ...[
                  const SizedBox(width: 8.0),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.auto_fix_high, size: 14.0),
                    label: const Text('One-Click Fix', style: TextStyle(fontSize: 11.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      ref.read(validationProvider.notifier).requestFixCandidate(roomId, issue);
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpaceUtilizationCard(DesignerLayoutState layout, ValidationState state) {
    final roomW = layout.roomWidth > 0 ? layout.roomWidth : 400.0;
    final roomL = layout.roomLength > 0 ? layout.roomLength : 500.0;
    final totalAreaM2 = (roomW * roomL) / 10000.0;

    double furnitureAreaM2 = 0.0;
    int boundaryViolations = 0;
    for (final f in layout.furniture) {
      furnitureAreaM2 += (f.width * f.depth) / 10000.0;
      final halfW = f.width / 2.0;
      final halfD = f.depth / 2.0;
      if (f.x - halfW < 0 || f.x + halfW > roomW || f.z - halfD < 0 || f.z + halfD > roomL) {
        boundaryViolations++;
      }
    }

    final unoccupiedAreaM2 = math.max(0.0, totalAreaM2 - furnitureAreaM2);
    final coveragePct = totalAreaM2 > 0 ? ((furnitureAreaM2 / totalAreaM2) * 100.0).clamp(0.0, 100.0) : 0.0;
    final collisionCount = layout.collisionIndices.length;
    final isFeasible = collisionCount == 0 && boundaryViolations == 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(color: Colors.grey.withOpacity(0.2)),
      ),
      color: Colors.grey.withOpacity(0.04),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.pie_chart_outline, size: 16, color: AppTheme.primary),
                    SizedBox(width: 6),
                    Text(
                      'Spatial & Area Utilization',
                      style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isFeasible ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isFeasible ? Colors.green.shade300 : Colors.red.shade300,
                    ),
                  ),
                  child: Text(
                    isFeasible ? 'FEASIBLE' : 'VIOLATIONS DETECTED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isFeasible ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12.0),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    'Room Area',
                    '${totalAreaM2.toStringAsFixed(1)} m²',
                    '${(totalAreaM2 * 10.764).toStringAsFixed(0)} sq ft',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricTile(
                    'Furniture Area',
                    '${furnitureAreaM2.toStringAsFixed(1)} m²',
                    '${coveragePct.toStringAsFixed(1)}% coverage',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricTile(
                    'Free Floor',
                    '${unoccupiedAreaM2.toStringAsFixed(1)} m²',
                    '${(100.0 - coveragePct).toStringAsFixed(1)}% open',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12.0),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Floor Footprint Coverage', style: TextStyle(fontSize: 11.0, color: Colors.grey)),
                    Text(
                      '${coveragePct.toStringAsFixed(1)}% (Ideal: 25-40%)',
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w600,
                        color: coveragePct > 45 ? Colors.amber.shade800 : Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4.0),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: LinearProgressIndicator(
                    value: (coveragePct / 100.0).clamp(0.0, 1.0),
                    color: coveragePct > 50 ? Colors.red.shade600 : (coveragePct > 40 ? Colors.amber.shade700 : Colors.green.shade600),
                    backgroundColor: Colors.grey.shade200,
                    minHeight: 6.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10.0),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildIssueChip(
                  Icons.blur_linear,
                  'Overlaps: $collisionCount',
                  collisionCount == 0,
                ),
                _buildIssueChip(
                  Icons.crop_free,
                  'Boundary: $boundaryViolations',
                  boundaryViolations == 0,
                ),
                _buildIssueChip(
                  Icons.door_front_door_outlined,
                  'Circulation: ${state.warnings.length} alerts',
                  state.warnings.isEmpty,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, String sub) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          Text(sub, style: const TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildIssueChip(IconData icon, String label, bool isOk) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isOk ? Icons.check_circle_outline : Icons.warning_amber_rounded,
          size: 13,
          color: isOk ? Colors.green.shade600 : Colors.amber.shade800,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isOk ? Colors.grey.shade700 : Colors.amber.shade800,
          ),
        ),
      ],
    );
  }
}
