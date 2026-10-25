import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/room_provider.dart';
import '../../../app/themes/app_theme.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';

import '../../../shared/widgets/secondary_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

class _AILayoutResult {
  final double overallScore;
  final Map<String, double> subscores;
  final List<Map<String, dynamic>> furniture;
  final List<String> layoutSuggestions;
  final String? explanation;
  final String provider;
  final String providerStatus;

  const _AILayoutResult({
    required this.overallScore,
    required this.subscores,
    required this.furniture,
    required this.layoutSuggestions,
    this.explanation,
    required this.provider,
    required this.providerStatus,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

class AIPlanningStep extends ConsumerStatefulWidget {
  final String roomId;
  final String roomType;
  final String? selectedStyle;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const AIPlanningStep({
    super.key,
    required this.roomId,
    required this.roomType,
    this.selectedStyle,
    required this.onBack,
    required this.onContinue,
  });

  @override
  ConsumerState<AIPlanningStep> createState() => _AIPlanningStepState();
}

class _AIPlanningStepState extends ConsumerState<AIPlanningStep>
    with SingleTickerProviderStateMixin {
  final ApiClient _api = ApiClient();
  final TextEditingController _commandController = TextEditingController();

  bool _isGenerating = false;
  bool _hasResult = false;
  String? _errorMessage;
  _AILayoutResult? _result;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  Timer? _pollTimer;
  String? _jobId;
  int _pollCount = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseCtrl.dispose();
    _commandController.dispose();
    super.dispose();
  }

  // ── API calls ──────────────────────────────────────────────────────────────

  Future<void> _generateLayout() async {
    setState(() {
      _isGenerating = true;
      _hasResult = false;
      _errorMessage = null;
      _result = null;
      _jobId = null;
      _pollCount = 0;
    });

    try {
      final postResp = await _api.post('/ai/layout', body: {
        'room_id': widget.roomId,
        'style': widget.selectedStyle ?? 'Modern',
        'preferences': <String>[],
        'command': _commandController.text.trim().isEmpty ? null : _commandController.text.trim(),
      });

      if (postResp.statusCode != 201) {
        final body = jsonDecode(postResp.body);
        throw Exception(body['detail'] ?? 'Failed to start AI layout');
      }

      final postBody = jsonDecode(postResp.body);
      _jobId = postBody['data']['job_id'] as String?;

      if (_jobId == null) throw Exception('No job ID returned from AI');

      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (!mounted) {
          _pollTimer?.cancel();
          return;
        }
        await _checkJobAndFetch();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _checkJobAndFetch() async {
    _pollCount++;
    if (_pollCount > 240) { // Poll for up to 8 minutes (240 * 2s) to accommodate local LLM latency
      _pollTimer?.cancel();
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _errorMessage = 'AI generation timed out. Please try again.';
        });
      }
      return;
    }

    try {
      final jobResp = await _api.get('/ai/jobs/$_jobId');
      if (jobResp.statusCode != 200) return;

      final jobBody = jsonDecode(jobResp.body);
      final status = jobBody['data']['status'] as String? ?? '';

      if (status == 'Completed') {
        _pollTimer?.cancel();
        await _fetchResult();
      } else if (status == 'Failed') {
        _pollTimer?.cancel();
        String errorMsg = 'AI layout generation failed. Please retry.';
        try {
          final resultResp = await _api.get('/ai/results/$_jobId');
          if (resultResp.statusCode == 200) {
            final resultBody = jsonDecode(resultResp.body);
            final data = resultBody['data'] as Map<String, dynamic>;
            final String? explanation = data['explanation'] as String?;
            if (explanation != null && explanation.isNotEmpty) {
              errorMsg = explanation.replaceFirst('400: ', '');
            }
          }
        } catch (_) {}
        if (mounted) {
          setState(() {
            _isGenerating = false;
            _errorMessage = errorMsg;
          });
        }
      }
    } catch (_) {
      // Network hiccup – keep polling
    }
  }

  Future<void> _fetchResult() async {
    try {
      final resultResp = await _api.get('/ai/results/$_jobId');
      if (resultResp.statusCode != 200) {
        throw Exception('Could not retrieve AI result');
      }

      final resultBody = jsonDecode(resultResp.body);
      final data = resultBody['data'] as Map<String, dynamic>;

      final double overallScore = (data['overall_score'] as num).toDouble();
      final rawSubscores = (data['subscores'] as Map<String, dynamic>?) ?? {};
      final Map<String, double> subscores = rawSubscores.map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      );
      final String? explanation = data['explanation'] as String?;

      // Parse furniture and provider info from layout_data
      List<Map<String, dynamic>> furniture = [];
      String provider = 'UNKNOWN';
      String providerStatus = 'UNKNOWN';
      try {
        final layoutJson =
            jsonDecode(data['layout_data'] as String? ?? '{}') as Map<String, dynamic>;
        final rawFurniture = layoutJson['furniture'] as List<dynamic>? ?? [];
        furniture = rawFurniture.cast<Map<String, dynamic>>();

        final meta = layoutJson['ai_layout_metadata'] as Map<String, dynamic>?;
        if (meta != null) {
          final perf = meta['performance'] as Map<String, dynamic>?;
          if (perf != null) {
            provider = perf['ai_provider']?.toString() ?? 'UNKNOWN';
            providerStatus = perf['ai_provider_status']?.toString() ?? 'UNKNOWN';
          }
        }
      } catch (_) {}

      // Fetch recommendations for extra furniture
      List<Map<String, dynamic>> recommendations = [];
      try {
        final recResp = await _api.get('/ai/recommendations/${widget.roomId}');
        if (recResp.statusCode == 200) {
          final recBody = jsonDecode(recResp.body);
          final recData = recBody['data'] as List<dynamic>? ?? [];
          recommendations = recData.cast<Map<String, dynamic>>();
        }
      } catch (_) {}

      // Merge furniture list
      final Set<String> seen = {};
      final List<Map<String, dynamic>> merged = [];

      for (final f in furniture) {
        final name = (f['name'] ?? f['type'] ?? 'Item').toString();
        if (seen.add(name.toLowerCase())) {
          merged.add({'name': name, 'from': 'layout'});
        }
      }
      for (final rec in recommendations) {
        final action = rec['action'] as Map<String, dynamic>? ?? {};
        final name = action['furniture_type']?.toString() ??
            rec['title']?.toString() ??
            'Item';
        if (seen.add(name.toLowerCase())) {
          merged.add({
            'name': name,
            'from': 'recommendation',
          });
        }
      }

      if (merged.isEmpty) {
        merged.addAll(_fallbackFurniture(widget.roomType));
      }

      final suggestions = _buildLayoutSuggestions(
        widget.roomType,
        overallScore,
        subscores,
        widget.selectedStyle,
      );

      if (mounted) {
        setState(() {
          _result = _AILayoutResult(
            overallScore: overallScore,
            subscores: subscores,
            furniture: merged,
            layoutSuggestions: suggestions,
            explanation: explanation,
            provider: provider,
            providerStatus: providerStatus,
          );
          _isGenerating = false;
          _hasResult = true;
        });
        try {
          await ref.read(roomDetailsProvider.notifier).fetchDetails(widget.roomId);
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _fallbackFurniture(String roomType) {
    const map = <String, List<String>>{
      'Living Room': ['Sofa', 'Coffee Table', 'TV Unit', 'Bookshelf', 'Floor Lamp'],
      'Bedroom': ['Bed Frame', 'Wardrobe', 'Bedside Table', 'Dresser', 'Study Desk'],
      'Kitchen': ['Dining Table', 'Bar Stools', 'Kitchen Island', 'Refrigerator'],
      'Dining Room': ['Dining Table', 'Chairs', 'Sideboard', 'Pendant Light'],
      'Office': ['Desk', 'Ergonomic Chair', 'Bookshelf', 'Filing Cabinet'],
      'Bathroom': ['Vanity Unit', 'Mirror Cabinet', 'Towel Rack', 'Storage Shelf'],
    };
    final items = map[roomType] ?? ['Chair', 'Table', 'Lamp', 'Shelf'];
    return items.map((n) => {'name': n, 'from': 'fallback'}).toList();
  }

  List<String> _buildLayoutSuggestions(
    String roomType,
    double score,
    Map<String, double> subscores,
    String? style,
  ) {
    final suggestions = <String>[];
    final styleName = style ?? 'Modern';
    suggestions.add('Use a $styleName aesthetic with curated materials for the $roomType.');

    if ((subscores['space_utilization'] ?? 0) < 0.6) {
      suggestions.add('Maximise floor area by placing large furniture along the walls.');
    } else {
      suggestions.add('Spatial planning is efficient — maintain clear circulation paths.');
    }

    if ((subscores['lighting'] ?? 0) < 0.5) {
      suggestions.add('Add layered lighting: ambient, task, and accent sources.');
    } else {
      suggestions.add('Lighting is well-planned. Consider dimmers for ambience control.');
    }

    if ((subscores['accessibility'] ?? 0) < 0.5) {
      suggestions.add('Widen pathways to at least 90 cm for comfortable movement.');
    }

    suggestions.add('Balance symmetry on both sides of the focal wall for visual harmony.');
    return suggestions;
  }

  Color _scoreColor(double score) {
    if (score >= 0.75) return const Color(0xFF10B981);
    if (score >= 0.5) return const Color(0xFFF59E0B);
    return const Color(0xFFF43F5E);
  }

  String _scoreLabel(double score) {
    if (score >= 0.8) return 'Excellent';
    if (score >= 0.65) return 'Good';
    if (score >= 0.5) return 'Fair';
    return 'Needs Work';
  }

  IconData _subscoreIconFor(String key) {
    switch (key) {
      case 'accessibility': return Icons.accessibility_new_outlined;
      case 'space_utilization': return Icons.aspect_ratio_outlined;
      case 'ergonomics': return Icons.self_improvement_outlined;
      case 'safety': return Icons.shield_outlined;
      case 'balance': return Icons.balance_outlined;
      case 'aesthetics': return Icons.brush_outlined;
      case 'functionality': return Icons.settings_outlined;
      case 'lighting': return Icons.wb_sunny_outlined;
      default: return Icons.star_outline;
    }
  }

  String _formatKey(String key) {
    return key
        .split('_')
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Widget _buildPromptCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'AI Special Instructions (Optional)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commandController,
            enabled: !_isGenerating,
            decoration: InputDecoration(
              hintText: 'e.g. "Create a spacious bedroom", "Add more storage"',
              hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.primary),
              ),
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 750),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    if (!_isGenerating) ...[
                      _buildPromptCard(),
                      const SizedBox(height: 20),
                    ],
                    if (_isGenerating) _buildGeneratingState(),
                    if (_errorMessage != null && !_isGenerating)
                      _buildErrorState(),
                    if (_hasResult && _result != null && !_isGenerating) ...[
                      _buildScoreCard(),
                      const SizedBox(height: 20),
                      _buildLayoutSuggestionsCard(),
                      const SizedBox(height: 20),
                      _buildFurnitureCard(),
                      const SizedBox(height: 20),
                      _buildSubscoresCard(),
                    ],
                    if (!_isGenerating && !_hasResult && _errorMessage == null)
                      _buildEmptyState(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primary.shade400, AppTheme.primary.shade700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Layout Planning',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Let the AI engine analyse your room and suggest the optimal layout.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.primary.shade200),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.auto_awesome, color: AppTheme.primary, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Option 1: Generate Room with AI',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'AI will automatically select, orient and arrange real furniture from the Asset Library based on your dimensions, room type (${widget.roomType}), doors, windows and instructions.',
                          style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _generateLayout,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Generate Room with AI'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.edit_note_outlined, color: Colors.black87, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Option 2: Design Manually',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Skip AI generation and start with a clean architectural floor plan with room boundaries and openings. Place and arrange furniture manually in 2D & 3D.',
                          style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onContinue,
                  icon: const Icon(Icons.handyman_outlined),
                  label: const Text('Design Manually'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGeneratingState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.shade100),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) =>
                Opacity(opacity: _pulseAnim.value, child: child),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primary.shade50,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.auto_awesome, size: 48, color: AppTheme.primary.shade600),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'AI is analysing your room…',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Optimising furniture placement, lighting, and\nspace utilisation for your ${widget.roomType}.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 28),
          LinearProgressIndicator(
            backgroundColor: AppTheme.primary.shade50,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary.shade400),
            minHeight: 6,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDA4AF)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFF43F5E), size: 36),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? 'An unknown error occurred.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Color(0xFF9F1239)),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _generateLayout,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFF43F5E),
              side: const BorderSide(color: Color(0xFFF43F5E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderBadge() {
    if (_result == null) return const SizedBox.shrink();
    final isFallback = _result!.provider == 'FALLBACK';
    final providerText = isFallback ? 'Heuristic Fallback' : _result!.provider;
    final color = isFallback ? Colors.amber.shade700 : AppTheme.primary;
    final bgColor = isFallback ? Colors.amber.shade50 : AppTheme.primary.shade50;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        providerText.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildScoreCard() {
    final score = _result!.overallScore;
    final pct = (score * 100).round();
    final color = _scoreColor(score);
    final label = _scoreLabel(score);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.08), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score,
                  strokeWidth: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$pct',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      '%',
                      style: TextStyle(
                        fontSize: 11,
                        color: color.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 18, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    const Text(
                      'Estimated Design Score',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    _buildProviderBadge(),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Based on space, lighting, ergonomics & aesthetics',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutSuggestionsCard() {
    final suggestions = _result!.layoutSuggestions;
    final explanation = _result!.explanation;
    return _card(
      icon: Icons.lightbulb_outline,
      iconColor: const Color(0xFFF59E0B),
      title: 'AI Layout Suggestions',
      subtitle: 'Smart recommendations from the AI engine',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (explanation != null && explanation.trim().isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primary.shade50.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.shade100),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: AppTheme.primary.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      explanation,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.primary.shade900,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
          ],
          ...suggestions.asMap().entries.map((e) {
            final i = e.key;
            final text = e.value;
            return Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                          fontSize: 14, color: Colors.black87, height: 1.4),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildFurnitureCard() {
    final furniture = _result!.furniture;
    return _card(
      icon: Icons.chair_outlined,
      iconColor: AppTheme.primary,
      title: 'Recommended Furniture',
      subtitle: '${furniture.length} items suggested for your ${widget.roomType}',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: furniture.map((f) {
          final name = f['name'] as String? ?? 'Item';
          final isFromRec = f['from'] == 'recommendation';
          return Chip(
            avatar: Icon(
              isFromRec ? Icons.star_rounded : Icons.weekend_outlined,
              size: 16,
              color: isFromRec ? Colors.amber.shade700 : AppTheme.primary.shade700,
            ),
            label: Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary.shade900,
              ),
            ),
            backgroundColor:
                isFromRec ? Colors.amber.shade50 : AppTheme.primary.shade50,
            side: BorderSide(
              color: isFromRec ? Colors.amber.shade200 : AppTheme.primary.shade100,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSubscoresCard() {
    final subscores = _result!.subscores;
    if (subscores.isEmpty) return const SizedBox.shrink();

    return _card(
      icon: Icons.bar_chart_outlined,
      iconColor: const Color(0xFF6366F1),
      title: 'Score Breakdown',
      subtitle: 'Individual dimension analysis',
      child: Column(
        children: subscores.entries.toList().asMap().entries.map((outer) {
          final idx = outer.key;
          final entry = outer.value;
          final key = entry.key;
          final val = entry.value.clamp(0.0, 1.0);
          final pct = (val * 100).round();
          final color = _scoreColor(val);
          final isLast = idx == subscores.length - 1;
          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_subscoreIconFor(key),
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formatKey(key),
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black87),
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: val,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        subtitle,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.black45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  // ── Bottom Bar ─────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          SecondaryButton(
            text: 'Back',
            onPressed: _isGenerating ? null : widget.onBack,
          ),
          const Spacer(),
          if (_hasResult) ...[
            OutlinedButton.icon(
              onPressed: _isGenerating ? null : _generateLayout,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Regenerate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 12),
          ],
          FilledButton.icon(
            onPressed: _isGenerating
                ? null
                : _hasResult
                    ? widget.onContinue
                    : _generateLayout,
            icon: Icon(
              _hasResult ? Icons.arrow_forward_rounded : Icons.auto_awesome,
              size: 18,
            ),
            label: Text(_hasResult ? 'Continue' : 'Generate Layout'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              textStyle:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
