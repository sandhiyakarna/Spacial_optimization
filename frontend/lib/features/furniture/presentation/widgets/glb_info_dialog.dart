import '../../../../app/themes/app_theme.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/furniture_asset.dart';
import '../../providers/furniture_provider.dart';
import '../../../../core/utils/url_helper.dart';

class GlbInfoDialog extends ConsumerStatefulWidget {
  final FurnitureAsset asset;

  const GlbInfoDialog({super.key, required this.asset});

  @override
  ConsumerState<GlbInfoDialog> createState() => _GlbInfoDialogState();
}

class _GlbInfoDialogState extends ConsumerState<GlbInfoDialog> with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  bool _isLoading = true;
  String? _error;
  GlbMetadata? _metadata;
  bool _wasCached = false;
  int _fileSizeBytes = 0;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _loadGlb();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  Future<void> _loadGlb() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final absoluteUrl = widget.asset.glbUrl.startsWith('http')
        ? widget.asset.glbUrl
        : '${getBaseUrl()}${widget.asset.glbUrl}';

    _wasCached = AssetCache().has(absoluteUrl);

    try {
      final parsed = await ref.read(furnitureProvider.notifier).loadAndParseGlb(widget.asset.glbUrl);
      
      // Calculate file size from the cache
      final bytes = AssetCache().get(absoluteUrl);
      _fileSizeBytes = bytes?.length ?? 0;

      if (mounted) {
        setState(() {
          _metadata = parsed;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF181818) : Colors.white,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width > 900 ? 900 : (width > 600 ? 650 : 450),
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header title bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                color: AppTheme.primary,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.asset.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: width > 650
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 4, child: _buildLeftPanel(isDark)),
                          const SizedBox(width: 24),
                          Expanded(flex: 5, child: _buildRightPanel(isDark)),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildLeftPanel(isDark),
                          const SizedBox(height: 24),
                          _buildRightPanel(isDark),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeftPanel(bool isDark) {
    final String thumbnailUrl = widget.asset.thumbnailUrl;
    final String resolvedUrl = (thumbnailUrl.contains('unsplash.com') || thumbnailUrl.isEmpty)
        ? '/uploads/furniture/thumbnails/${widget.asset.id.replaceAll('model_', '')}.png'
        : thumbnailUrl;
    final String imageUrl = resolvedUrl.startsWith('http')
        ? resolvedUrl
        : '${getBaseUrl()}$resolvedUrl';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Thumbnail card
        Card(
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: AspectRatio(
            aspectRatio: 1.2,
            child: Container(
              color: isDark ? const Color(0xFF282828) : const Color(0xFFF9FBFB),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.chair_outlined, size: 64, color: AppTheme.primary);
                    },
                  ),
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Chip(
                      backgroundColor: Colors.black87,
                      label: Text(
                        widget.asset.category,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Physical parameters
        Text(
          'Physical Metadata',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.primary[700],
            fontSize: 15,
          ),
        ),
        const Divider(),
        _buildInfoRow('Dimensions', '${widget.asset.width.round()} × ${widget.asset.depth.round()} × ${widget.asset.height.round()} cm'),
        _buildInfoRow('Clearance Req.', '${widget.asset.clearance.round()} cm'),
        _buildInfoRow('Assembly Clear.', '${widget.asset.assemblyClearance.round()} cm'),
        _buildInfoRow('Style Theme', widget.asset.style),
        if (widget.asset.tags != null && widget.asset.tags!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Tags',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700], fontSize: 12),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.asset.tags!.split(',').map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                ),
                child: Text(
                  tag.trim(),
                  style: const TextStyle(fontSize: 10, color: AppTheme.primary),
                ),
              );
            }).toList(),
          ),
        ]
      ],
    );
  }

  Widget _buildRightPanel(bool isDark) {
    if (_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 16),
              Text(
                'Downloading GLB File...',
                style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Extracting 3D headers & schema',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Card(
        color: Colors.red.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.red, width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    'GLB Loading Failed',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                onPressed: _loadGlb,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final meta = _metadata!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Load Success and Cache Status Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 6),
                Text(
                  'GLB Verified Correctly',
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _wasCached ? Colors.green[100] : Colors.amber[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _wasCached ? 'Loaded from Cache' : 'Downloaded',
                style: TextStyle(
                  color: _wasCached ? Colors.green[800] : Colors.amber[800],
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Animated Mock 3D rotation view to verify it loaded correctly!
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF202020) : Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Spinning Mock Furniture Box
              AnimatedBuilder(
                animation: _rotationController,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(100, 100),
                    painter: _Mock3DWireframePainter(
                      rotationAngle: _rotationController.value * 2 * pi,
                      isDark: isDark,
                    ),
                  );
                },
              ),
              Positioned(
                bottom: 8,
                left: 12,
                child: Text(
                  'Simulated 3D Mesh Preview',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500], fontStyle: FontStyle.italic),
                ),
              ),
              Positioned(
                top: 8,
                right: 12,
                child: Row(
                  children: [
                    const Icon(Icons.threed_rotation, size: 12, color: AppTheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Ready to Render',
                      style: TextStyle(fontSize: 10, color: AppTheme.primary[600], fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
        const SizedBox(height: 16),

        // GLB File Details
        Text(
          'Binary GLB Schema info',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.primary[700],
            fontSize: 15,
          ),
        ),
        const Divider(),
        _buildInfoRow('Header Magic', meta.magic),
        _buildInfoRow('glTF Version', 'v${meta.gltfVersion}'),
        _buildInfoRow('File Size', '${(_fileSizeBytes / 1024).toStringAsFixed(2)} KB ($_fileSizeBytes bytes)'),
        _buildInfoRow('Generator Tool', meta.generator),
        _buildInfoRow('Meshes Count', '${meta.meshesCount} mesh(es)'),
        _buildInfoRow('Materials Count', '${meta.materialsCount} material(s)'),
        _buildInfoRow('Nodes Count', '${meta.nodesCount} layout node(s)'),
        _buildInfoRow('Textures Count', '${meta.texturesCount} texture(s)'),
        
        const SizedBox(height: 12),
        // Inspect Raw GLB JSON content
        ExpansionTile(
          title: const Text(
            'Inspect glTF JSON Chunk',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          expandedAlignment: Alignment.topLeft,
          children: [
            Container(
              height: 150,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF121212) : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(meta.jsonContent),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

// Custom Painter to draw a rotating 3D wireframe box
class _Mock3DWireframePainter extends CustomPainter {
  final double rotationAngle;
  final bool isDark;

  _Mock3DWireframePainter({required this.rotationAngle, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double r = size.width * 0.25;

    // Define 8 vertices of a cube
    final vertices = [
      Offset3D(-1, -1, -1),
      Offset3D(1, -1, -1),
      Offset3D(1, 1, -1),
      Offset3D(-1, 1, -1),
      Offset3D(-1, -1, 1),
      Offset3D(1, -1, 1),
      Offset3D(1, 1, 1),
      Offset3D(-1, 1, 1),
    ];

    // Rotate vertices around Y axis and X axis (isometric angle)
    final rotated2D = vertices.map((v) {
      // Y-axis rotation
      double x = v.x * cos(rotationAngle) - v.z * sin(rotationAngle);
      double z = v.x * sin(rotationAngle) + v.z * cos(rotationAngle);
      double y = v.y;

      // X-axis rotation (pitch/isometric angle)
      final pitch = 0.5;
      double yRot = y * cos(pitch) - z * sin(pitch);
      
      // Project to 2D
      return Offset(cx + x * r, cy + yRot * r);
    }).toList();

    // Draw edges
    final edges = [
      [0, 1], [1, 2], [2, 3], [3, 0], // Back face
      [4, 5], [5, 6], [6, 7], [7, 4], // Front face
      [0, 4], [1, 5], [2, 6], [3, 7], // Connecting edges
    ];

    for (final edge in edges) {
      canvas.drawLine(rotated2D[edge[0]], rotated2D[edge[1]], paint);
    }

    // Draw little circles at vertices
    final vertexPaint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.fill;
      
    for (final pt in rotated2D) {
      canvas.drawCircle(pt, 3, vertexPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _Mock3DWireframePainter oldDelegate) {
    return oldDelegate.rotationAngle != rotationAngle || oldDelegate.isDark != isDark;
  }
}

class Offset3D {
  final double x;
  final double y;
  final double z;

  Offset3D(this.x, this.y, this.z);
}
