import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../app/themes/app_theme.dart';
import '../../../../shared/widgets/snackbar_manager.dart';
import '../../providers/designer_provider.dart';

// ─── Dark Theme Color Tokens ──────────────────────────────────────────────────
const _kSurface = Color(0xFF111827);
const _kSurfaceElevated = Color(0xFF1E293B);
const _kSurfaceCard = Color(0xFF1E293B);
const _kBorder = Color(0xFF334155);
const _kAccent = Color(0xFF0F766E);
const _kAccentLight = Color(0xFF14B8A6);
const _kTextPrimary = Color(0xFFF8FAFC);
const _kTextSecondary = Color(0xFF94A3B8);
const _kTextMuted = Color(0xFF64748B);

class AiCandidatesComparisonDialog extends StatefulWidget {
  final Map<String, dynamic> resultData;
  final DesignerLayoutState layout;
  final DesignerNotifier notifier;

  const AiCandidatesComparisonDialog({
    super.key,
    required this.resultData,
    required this.layout,
    required this.notifier,
  });

  @override
  State<AiCandidatesComparisonDialog> createState() =>
      _AiCandidatesComparisonDialogState();
}

class _AiCandidatesComparisonDialogState
    extends State<AiCandidatesComparisonDialog> {
  int _selectedOptionIndex = 0;
  bool _showComparisonTable = false;

  late List<Map<String, dynamic>> _candidates;
  late Map<String, dynamic> _parsedLayoutData;

  @override
  void initState() {
    super.initState();
    _extractCandidates();
  }

  void _extractCandidates() {
    try {
      final rawLayout = widget.resultData['layout_data'];
      if (rawLayout is String) {
        _parsedLayoutData = jsonDecode(rawLayout) as Map<String, dynamic>;
      } else if (rawLayout is Map<String, dynamic>) {
        _parsedLayoutData = rawLayout;
      } else {
        _parsedLayoutData = {};
      }
    } catch (_) {
      _parsedLayoutData = {};
    }

    final rawOptions = _parsedLayoutData['options'];
    if (rawOptions is List && rawOptions.isNotEmpty) {
      _candidates = rawOptions
          .map((o) => Map<String, dynamic>.from(o as Map))
          .toList();
    } else {
      // Fallback single candidate from primary layout data
      final furniture = _parsedLayoutData['furniture'] ?? [];
      final overallScore = widget.resultData['overall_score'] ?? 75;
      final subscores = widget.resultData['subscores'] ?? {};
      final explanation = widget.resultData['explanation'] ??
          'Curated AI spatial arrangement optimized for circulation and usability.';

      _candidates = [
        {
          'id': 'balanced',
          'title': 'Balanced Layout',
          'strategy': 'balanced',
          'furniture': furniture,
          'design_scores': {'overall_score': overallScore, 'subscores': subscores},
          'overall_score': (overallScore as num).toInt(),
          'explanation': explanation,
          'highlights': [
            'Optimal balance of functional living zones',
            'Smooth primary circulation path',
            'Symmetric focal point orientation'
          ],
        }
      ];
    }
  }

  void _applySelectedCandidate() {
    if (_candidates.isEmpty) return;
    final candidate = _candidates[_selectedOptionIndex];
    final furnitureList = candidate['furniture'];

    if (furnitureList is List) {
      widget.notifier.placeFurnitureFromLayout(furnitureList);
      Navigator.of(context).pop();
      SnackbarManager.showSuccess(
        context,
        'Applied "${candidate['title']}" (${furnitureList.length} items placed)',
      );
    } else {
      SnackbarManager.showError(context, 'No furniture data in this layout candidate.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_candidates.isEmpty) {
      return AlertDialog(
        backgroundColor: _kSurface,
        title: const Text('No Candidates Available', style: TextStyle(color: _kTextPrimary)),
        content: const Text('AI layout generation did not return valid candidates.', style: TextStyle(color: _kTextSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }

    final current = _candidates[_selectedOptionIndex];

    return Dialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildCandidateSelector(),
              const SizedBox(height: 16),
              Expanded(
                child: _showComparisonTable
                    ? _buildComparisonTableView()
                    : _buildCandidateDetailView(current),
              ),
              const SizedBox(height: 16),
              _buildFooter(current),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _kAccent.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.auto_awesome, color: _kAccentLight, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI Layout Studio — Candidate Comparison',
                style: TextStyle(
                  color: _kTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${_candidates.length} spatial arrangements synthesized & validated against room constraints',
                style: const TextStyle(color: _kTextSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: _kTextSecondary),
          tooltip: 'Close',
        ),
      ],
    );
  }

  Widget _buildCandidateSelector() {
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<int>(
            segments: List.generate(_candidates.length, (index) {
              final c = _candidates[index];
              final title = c['title'] ?? 'Option ${index + 1}';
              final score = c['overall_score'] ?? 75;
              IconData icon = Icons.balance;
              if (c['id'] == 'space_efficient') icon = Icons.open_in_full;
              if (c['id'] == 'style_focused') icon = Icons.palette_outlined;

              return ButtonSegment<int>(
                value: index,
                icon: Icon(icon, size: 16),
                label: Text(
                  '$title ($score)',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              );
            }),
            selected: {_selectedOptionIndex},
            onSelectionChanged: (set) {
              if (set.isNotEmpty) {
                setState(() {
                  _selectedOptionIndex = set.first;
                  _showComparisonTable = false;
                });
              }
            },
            style: ButtonStyle(
              backgroundColor: MaterialStateProperty.resolveWith((states) {
                if (states.contains(MaterialState.selected)) {
                  return _kAccent;
                }
                return _kSurfaceElevated;
              }),
              foregroundColor: MaterialStateProperty.resolveWith((states) {
                if (states.contains(MaterialState.selected)) {
                  return Colors.white;
                }
                return _kTextSecondary;
              }),
              side: MaterialStateProperty.all(const BorderSide(color: _kBorder)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () {
            setState(() => _showComparisonTable = !_showComparisonTable);
          },
          icon: Icon(
            _showComparisonTable ? Icons.view_sidebar : Icons.table_chart_outlined,
            size: 16,
            color: _showComparisonTable ? _kAccentLight : _kTextSecondary,
          ),
          label: Text(
            _showComparisonTable ? 'Detail View' : 'Compare All',
            style: TextStyle(
              color: _showComparisonTable ? _kAccentLight : _kTextSecondary,
              fontSize: 12,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: _showComparisonTable ? _kAccentLight : _kBorder,
            ),
            backgroundColor: _showComparisonTable ? _kAccent.withOpacity(0.15) : null,
          ),
        ),
      ],
    );
  }

  Widget _buildCandidateDetailView(Map<String, dynamic> candidate) {
    final furniture = candidate['furniture'] as List? ?? [];
    final designScores = candidate['design_scores'] as Map? ?? {};
    final subscores = (designScores['subscores'] as Map?) ?? {};
    final overallScore = candidate['overall_score'] ?? 75;
    final explanation = candidate['explanation'] ?? '';
    final highlights = candidate['highlights'] as List? ?? [];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left Column: 2D Blueprint Preview of this candidate
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '2D Blueprint Preview',
                      style: TextStyle(
                        color: _kTextSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${furniture.length} items placed',
                      style: const TextStyle(color: _kTextMuted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      painter: _MiniLayoutPainter(
                        roomWidth: widget.layout.roomWidth,
                        roomLength: widget.layout.roomLength,
                        furniture: furniture,
                        openings: widget.layout.openings,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLegendItem(const Color(0xFF14B8A6), 'Furniture'),
                    const SizedBox(width: 16),
                    _buildLegendItem(const Color(0xFF38BDF8), 'Door / Window'),
                    const SizedBox(width: 16),
                    _buildLegendItem(const Color(0xFFE2E8F0), 'Walls'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),

        // Right Column: Scores, Rationales, Highlights & Manifest
        Expanded(
          flex: 6,
          child: Container(
            decoration: BoxDecoration(
              color: _kSurfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Overall Score Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _getScoreColor(overallScore).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _getScoreColor(overallScore)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.verified, color: _getScoreColor(overallScore), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '$overallScore',
                              style: TextStyle(
                                color: _getScoreColor(overallScore),
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              ' / 100',
                              style: TextStyle(color: _kTextMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              candidate['title'] ?? 'Layout Option',
                              style: const TextStyle(
                                color: _kTextPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Strategy: ${candidate['strategy'] ?? 'Standard'}',
                              style: const TextStyle(color: _kAccentLight, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Subscores Grid
                  const Text(
                    'Spatial & Ergonomic Score Breakdown',
                    style: TextStyle(
                      color: _kTextPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildScoreBar('Space Utilization', subscores['space_utilization'] ?? 75),
                  _buildScoreBar('Ergonomics & Clearances', subscores['ergonomics'] ?? 80),
                  _buildScoreBar('Circulation & Walkways', subscores['accessibility'] ?? 75),
                  _buildScoreBar('Aesthetic & Focal Balance', subscores['aesthetics'] ?? 85),
                  _buildScoreBar('Lighting & Openings Access', subscores['lighting'] ?? 80),

                  const SizedBox(height: 16),
                  const Divider(color: _kBorder, height: 1),
                  const SizedBox(height: 16),

                  // "Why This Layout?" Section
                  Row(
                    children: const [
                      Icon(Icons.psychology, color: _kAccentLight, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Why this layout?',
                        style: TextStyle(
                          color: _kTextPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _kSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kBorder.withOpacity(0.6)),
                    ),
                    child: Text(
                      explanation.isNotEmpty
                          ? explanation
                          : 'This layout positions the primary seating opposite room entry to establish a welcoming focal zone while maintaining unobstructed walkways.',
                      style: const TextStyle(
                        color: _kTextSecondary,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),

                  if (highlights.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...highlights.map((h) => Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.check_circle_outline,
                                  color: _kAccentLight, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  h.toString(),
                                  style: const TextStyle(
                                      color: _kTextSecondary, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],

                  const SizedBox(height: 16),
                  const Divider(color: _kBorder, height: 1),
                  const SizedBox(height: 16),

                  // Furniture Manifest Preview
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Curated Furniture Manifest',
                        style: TextStyle(
                          color: _kTextPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${furniture.length} items',
                        style: const TextStyle(color: _kTextMuted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...furniture.take(8).map((f) {
                    final item = f is Map ? f : {};
                    final name = item['name'] ?? 'Furniture Item';
                    final w = (item['width'] as num? ?? 100).toInt();
                    final d = (item['depth'] as num? ?? 100).toInt();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3.0),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: _kAccentLight,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name.toString(),
                              style: const TextStyle(
                                  color: _kTextPrimary, fontSize: 12),
                            ),
                          ),
                          Text(
                            '$w × $d cm',
                            style: const TextStyle(
                                color: _kTextMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (furniture.length > 8)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        '+ ${furniture.length - 8} additional items',
                        style: const TextStyle(
                            color: _kAccentLight, fontSize: 11, fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonTableView() {
    return Container(
      decoration: BoxDecoration(
        color: _kSurfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Side-by-Side Candidates Matrix',
              style: TextStyle(
                color: _kTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Compare key metrics across all generated spatial arrangements to choose the ideal fit for your space.',
              style: TextStyle(color: _kTextSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2.5),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2),
              },
              border: TableBorder.all(color: _kBorder, width: 1),
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xFF0F172A)),
                  children: [
                    _buildTableCell('Metric / Criterion', isHeader: true),
                    ...List.generate(_candidates.length, (i) {
                      final c = _candidates[i];
                      return _buildTableCell(
                        c['title'] ?? 'Option ${i + 1}',
                        isHeader: true,
                        isSelected: i == _selectedOptionIndex,
                      );
                    }),
                  ],
                ),
                _buildMatrixRow(
                  'Overall Design Score',
                  _candidates.map((c) => '${c['overall_score'] ?? 75}/100').toList(),
                ),
                _buildMatrixRow(
                  'Furniture Count',
                  _candidates.map((c) => '${(c['furniture'] as List? ?? []).length} items').toList(),
                ),
                _buildMatrixRow(
                  'Space Utilization',
                  _candidates.map((c) {
                    final sub = (c['design_scores'] as Map?)?['subscores'] as Map? ?? {};
                    return '${(sub['space_utilization'] as num? ?? 75).toInt()}%';
                  }).toList(),
                ),
                _buildMatrixRow(
                  'Ergonomics & Clearance',
                  _candidates.map((c) {
                    final sub = (c['design_scores'] as Map?)?['subscores'] as Map? ?? {};
                    return '${(sub['ergonomics'] as num? ?? 80).toInt()}%';
                  }).toList(),
                ),
                _buildMatrixRow(
                  'Circulation & Walkways',
                  _candidates.map((c) {
                    final sub = (c['design_scores'] as Map?)?['subscores'] as Map? ?? {};
                    return '${(sub['accessibility'] as num? ?? 75).toInt()}%';
                  }).toList(),
                ),
                _buildMatrixRow(
                  'Aesthetics & Balance',
                  _candidates.map((c) {
                    final sub = (c['design_scores'] as Map?)?['subscores'] as Map? ?? {};
                    return '${(sub['aesthetics'] as num? ?? 85).toInt()}%';
                  }).toList(),
                ),
                _buildMatrixRow(
                  'Primary Strategic Focus',
                  _candidates.map((c) {
                    final id = c['id'] ?? '';
                    if (id == 'space_efficient') return 'Open Circulation';
                    if (id == 'style_focused') return 'Focal Point Styling';
                    return 'Harmonious Balance';
                  }).toList(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TableRow _buildMatrixRow(String label, List<String> values) {
    return TableRow(
      children: [
        _buildTableCell(label),
        ...List.generate(values.length, (i) {
          return _buildTableCell(
            values[i],
            isSelected: i == _selectedOptionIndex,
          );
        }),
      ],
    );
  }

  Widget _buildTableCell(String text, {bool isHeader = false, bool isSelected = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      color: isSelected ? _kAccent.withOpacity(0.12) : null,
      child: Text(
        text,
        textAlign: isHeader ? TextAlign.center : TextAlign.left,
        style: TextStyle(
          color: isHeader
              ? (isSelected ? _kAccentLight : _kTextPrimary)
              : (isSelected ? _kAccentLight : _kTextSecondary),
          fontSize: isHeader ? 12 : 11,
          fontWeight: isHeader || isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildScoreBar(String label, dynamic scoreVal) {
    final score = (scoreVal as num? ?? 75).toInt();
    final pct = (score / 100.0).clamp(0.0, 1.0);
    final color = _getScoreColor(score);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 11)),
              Text('$score%', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: _kSurface,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 10)),
      ],
    );
  }

  Widget _buildFooter(Map<String, dynamic> candidate) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back to Editor'),
          style: TextButton.styleFrom(foregroundColor: _kTextSecondary),
        ),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _applySelectedCandidate,
              icon: const Icon(Icons.check, size: 18),
              label: Text('Apply "${candidate['title'] ?? 'Layout'}" to Room'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _getScoreColor(num score) {
    if (score >= 85) return const Color(0xFF10B981);
    if (score >= 70) return const Color(0xFF38BDF8);
    if (score >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }
}

// ─── Custom Mini Layout Blueprint Painter ────────────────────────────────────
class _MiniLayoutPainter extends CustomPainter {
  final double roomWidth;
  final double roomLength;
  final List<dynamic> furniture;
  final List<dynamic> openings;

  _MiniLayoutPainter({
    required this.roomWidth,
    required this.roomLength,
    required this.furniture,
    required this.openings,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (roomWidth <= 0 || roomLength <= 0) return;

    // Background
    final bgPaint = Paint()..color = const Color(0xFF090D16);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Calculate scale and centering
    const margin = 20.0;
    final availW = size.width - margin * 2;
    final availH = size.height - margin * 2;
    final scale = math.min(availW / roomWidth, availH / roomLength);

    final drawnW = roomWidth * scale;
    final drawnH = roomLength * scale;
    final ox = margin + (availW - drawnW) / 2;
    final oy = margin + (availH - drawnH) / 2;

    // Room Floor
    final floorRect = Rect.fromLTWH(ox, oy, drawnW, drawnH);
    final floorPaint = Paint()..color = const Color(0xFF1E293B);
    canvas.drawRect(floorRect, floorPaint);

    // Grid lines inside room
    final gridPaint = Paint()
      ..color = const Color(0xFF334155).withOpacity(0.4)
      ..strokeWidth = 0.5;
    const gridStepCm = 50.0;
    for (double x = gridStepCm; x < roomWidth; x += gridStepCm) {
      canvas.drawLine(
        Offset(ox + x * scale, oy),
        Offset(ox + x * scale, oy + drawnH),
        gridPaint,
      );
    }
    for (double y = gridStepCm; y < roomLength; y += gridStepCm) {
      canvas.drawLine(
        Offset(ox, oy + y * scale),
        Offset(ox + drawnW, oy + y * scale),
        gridPaint,
      );
    }

    // Walls
    final wallPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    canvas.drawRect(floorRect, wallPaint);

    // Openings (doors and windows)
    final openingPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    for (final op in openings) {
      if (op is! Map) continue;
      final start = op['start'];
      final end = op['end'];
      if (start is Map && end is Map) {
        final x1 = (start['x'] as num? ?? 0.0) * scale + ox;
        final y1 = (start['y'] as num? ?? 0.0) * scale + oy;
        final x2 = (end['x'] as num? ?? 0.0) * scale + ox;
        final y2 = (end['y'] as num? ?? 0.0) * scale + oy;
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), openingPaint);
      }
    }

    // Furniture
    final furnitureFill = Paint()
      ..color = const Color(0xFF14B8A6).withOpacity(0.75)
      ..style = PaintingStyle.fill;
    final furnitureStroke = Paint()
      ..color = const Color(0xFF2DD4BF)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (final item in furniture) {
      if (item is! Map) continue;
      final x = (item['x'] as num? ?? 0.0).toDouble();
      final z = (item['z'] as num? ?? 0.0).toDouble();
      final w = (item['width'] as num? ?? 60.0).toDouble();
      final d = (item['depth'] as num? ?? 60.0).toDouble();
      final rotY = (item['rotationY'] as num? ?? item['rotation'] as num? ?? 0.0).toDouble();

      final cx = ox + x * scale;
      final cy = oy + z * scale;
      final sw = w * scale;
      final sd = d * scale;

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(rotY);

      final r = Rect.fromCenter(center: Offset.zero, width: sw, height: sd);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)), furnitureFill);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)), furnitureStroke);

      // Orientation indicator: small notch pointing forward (+Z)
      final notchPaint = Paint()
        ..color = Colors.white.withOpacity(0.7)
        ..strokeWidth = 1.5;
      canvas.drawLine(
        Offset(0, sd / 4),
        Offset(0, sd / 2),
        notchPaint,
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _MiniLayoutPainter oldDelegate) {
    return oldDelegate.furniture != furniture ||
        oldDelegate.roomWidth != roomWidth ||
        oldDelegate.roomLength != roomLength;
  }
}
