import '../../../../app/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/recommendation_provider.dart';
import '../../providers/design_score_provider.dart';
import '../../providers/optimization_provider.dart';
import '../../../../shared/widgets/snackbar_manager.dart';

class AiRecommendationPanel extends ConsumerWidget {
  final String roomId;

  const AiRecommendationPanel({super.key, required this.roomId});

  Color _getScoreColor(double score) {
    if (score >= 80.0) return Colors.green;
    if (score >= 50.0) return Colors.orange;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scoreState = ref.watch(designScoreProvider);
    final recState = ref.watch(recommendationProvider);
    final optState = ref.watch(optimizationProvider);

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
                    'AI Layout Assistant',
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
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Overall Design Score Circular Dashboard
                      if (scoreState.isLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (scoreState.scores != null) ...[
                        _buildScoreDashboard(scoreState.scores!),
                        const SizedBox(height: 20.0),
                      ],

                      // 2. Optimization Button Triggers
                      _buildOptimizationCard(context, ref, optState),
                      const SizedBox(height: 20.0),

                      // 3. AI Layout Recommendations List
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Layout Recommendations',
                            style: TextStyle(
                              fontSize: 16.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: () {
                              ref.read(designScoreProvider.notifier).fetchScores(roomId);
                              ref.read(recommendationProvider.notifier).fetchRecommendations(roomId);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8.0),

                      if (recState.isLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (recState.recommendations.isEmpty)
                        const Card(
                          color: Color(0xFFF5F5F5),
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text(
                              'No rule violations detected. Your room layout meets all ergonomic standards!',
                              style: TextStyle(color: Colors.grey, fontSize: 13.0),
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: recState.recommendations.length,
                          itemBuilder: (context, index) {
                            final card = recState.recommendations[index];
                            return _buildRecommendationCard(context, ref, card);
                          },
                        ),
                      
                      const SizedBox(height: 20.0),
                      _buildHistoryList(recState),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreDashboard(DesignScores scores) {
    final overall = scores.overallScore;
    final color = _getScoreColor(overall);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Circular indicator
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 110,
                  height: 110,
                  child: CircularProgressIndicator(
                    value: overall / 100.0,
                    strokeWidth: 10,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${overall.round()}%',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const Text(
                      'Design Health',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Layout Subscores',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            // Progress bars for subscores
            ...scores.subscores.entries.map((entry) {
              final val = entry.value;
              final label = entry.key.replaceAll('_', ' ').toUpperCase();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        Text('${val.round()}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: val / 100.0,
                        backgroundColor: Colors.grey.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(_getScoreColor(val)),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildOptimizationCard(BuildContext context, WidgetRef ref, OptimizationState state) {
    return Card(
      elevation: 0,
      color: AppTheme.primary.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, color: AppTheme.primary),
                SizedBox(width: 8),
                Text(
                  'Auto Layout Optimizer',
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Rearranges room furniture using simulated annealing to satisfy all walkways, accessibility, and comfort rules.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            if (state.isLoading)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppTheme.primary),
                    SizedBox(height: 8),
                    Text('Running local simulated annealing...', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              )
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run Layout Optimization'),
                onPressed: () async {
                  final ok = await ref.read(optimizationProvider.notifier).runOptimization(roomId);
                  if (ok && context.mounted) {
                    SnackbarManager.showSuccess(context, 'Layout optimized successfully!');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationCard(BuildContext context, WidgetRef ref, Recommendation card) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  label: Text(
                    card.type.toUpperCase(),
                    style: const TextStyle(fontSize: 9.0, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  backgroundColor: AppTheme.primary.shade700,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Text(
                  card.scoreImpact,
                  style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              card.title,
              style: const TextStyle(fontSize: 15.0, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              card.description,
              style: const TextStyle(fontSize: 12.0, color: Colors.black87),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.grey.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Rule: ${card.ruleTriggered}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text('Reason: ${card.reason}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  const SizedBox(height: 2),
                  Text('Improvement: ${card.expectedImprovement}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                final success = await ref.read(recommendationProvider.notifier).apply(roomId, card.id);
                if (success && context.mounted) {
                  ref.read(designScoreProvider.notifier).fetchScores(roomId);
                  SnackbarManager.showSuccess(context, 'Recommendation applied successfully!');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary.shade50,
                foregroundColor: AppTheme.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: const Text('Apply Recommendation'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList(RecommendationState state) {
    if (state.history.isEmpty) return const SizedBox.shrink();
    
    return ExpansionTile(
      title: const Text(
        'Applied Recommendations History',
        style: TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold, color: Colors.grey),
      ),
      children: state.history.map((h) {
        return ListTile(
          dense: true,
          title: Text('Recommendation ID: ${h.id.substring(0, 8)}...'),
          subtitle: Text('Applied at: ${h.createdAt.toLocal().toString().split('.')[0]}'),
          trailing: const Icon(Icons.check_circle, color: Colors.green),
        );
      }).toList(),
    );
  }
}
