import '../../../app/themes/app_theme.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/export_provider.dart';
import '../providers/project_provider.dart';
import '../providers/dashboard_provider.dart';

class ImportProjectDialog extends ConsumerStatefulWidget {
  const ImportProjectDialog({super.key});

  @override
  ConsumerState<ImportProjectDialog> createState() => _ImportProjectDialogState();
}

class _ImportProjectDialogState extends ConsumerState<ImportProjectDialog> {
  final TextEditingController _jsonController = TextEditingController();
  String? _error;
  bool _loading = false;

  void _import() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    final text = _jsonController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _error = 'Please paste project JSON data';
        _loading = false;
      });
      return;
    }

    try {
      // Validate JSON structure
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON must be a key-value object');
      }

      final success = await ref.read(exportProvider.notifier).importProjectJson(text);
      if (success) {
        // Refresh project list and dashboard
        ref.read(projectProvider.notifier).fetchProjects();
        ref.read(dashboardProvider.notifier).fetchDashboard();
        
        if (mounted) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Project imported successfully!'),
              backgroundColor: AppTheme.primary,
            ),
          );
        }
      } else {
        setState(() {
          _error = ref.read(exportProvider).errorMessage ?? 'Failed to import project';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Invalid JSON format: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Project'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Paste the exported Project JSON data below to recreate and import the project.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _jsonController,
              maxLines: 10,
              decoration: InputDecoration(
                hintText: '{\n  "project_name": "My Room Project",\n  ...\n}',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: _loading ? null : _import,
          child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Import'),
        ),
      ],
    );
  }
}

class RestoreProjectDialog extends ConsumerStatefulWidget {
  const RestoreProjectDialog({super.key});

  @override
  ConsumerState<RestoreProjectDialog> createState() => _RestoreProjectDialogState();
}

class _RestoreProjectDialogState extends ConsumerState<RestoreProjectDialog> {
  final TextEditingController _jsonController = TextEditingController();
  String? _error;
  bool _loading = false;

  void _restore() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    final text = _jsonController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _error = 'Please paste backup JSON data';
        _loading = false;
      });
      return;
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON must be a key-value object');
      }

      final success = await ref.read(exportProvider.notifier).restoreProjectJson(text);
      if (success) {
        ref.read(projectProvider.notifier).fetchProjects();
        ref.read(dashboardProvider.notifier).fetchDashboard();
        
        if (mounted) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Project restored successfully from backup!'),
              backgroundColor: AppTheme.primary,
            ),
          );
        }
      } else {
        setState(() {
          _error = ref.read(exportProvider).errorMessage ?? 'Failed to restore project';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Invalid Backup JSON format: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Restore Project Backup'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Paste your project backup JSON to restore the project config, rooms, measurements, and layouts.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _jsonController,
              maxLines: 10,
              decoration: InputDecoration(
                hintText: 'Paste backup JSON here...',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: _loading ? null : _restore,
          child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Restore'),
        ),
      ],
    );
  }
}

class ExportProjectDialog extends ConsumerStatefulWidget {
  final String projectId;
  final String projectName;

  const ExportProjectDialog({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  @override
  ConsumerState<ExportProjectDialog> createState() => _ExportProjectDialogState();
}

class _ExportProjectDialogState extends ConsumerState<ExportProjectDialog> {
  bool _exporting = false;
  String? _jsonText;

  void _exportJson() async {
    setState(() {
      _exporting = true;
      _jsonText = null;
    });

    final data = await ref.read(exportProvider.notifier).exportProjectJson(widget.projectId);
    if (data != null) {
      setState(() {
        _jsonText = const JsonEncoder.withIndent('  ').convert(data);
        _exporting = false;
      });
    } else {
      setState(() {
        _exporting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export: ${ref.read(exportProvider).errorMessage}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _exportFile(String format) async {
    setState(() {
      _exporting = true;
    });

    final bytes = await ref.read(exportProvider.notifier).exportProjectFile(widget.projectId, format);
    setState(() {
      _exporting = false;
    });

    if (bytes != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Project exported as $format successfully! (${bytes.length} bytes)'),
          backgroundColor: AppTheme.primary,
        ),
      );
      Navigator.of(context).pop();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: ${ref.read(exportProvider).errorMessage}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Export Project: ${widget.projectName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_jsonText == null) ...[
              const Text('Select an export format below:'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _exporting ? null : _exportJson,
                icon: const Icon(Icons.code),
                label: const Text('Export JSON Data'),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _exporting ? null : () => _exportFile('PDF'),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Export PDF Summary'),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _exporting ? null : () => _exportFile('PNG'),
                icon: const Icon(Icons.image),
                label: const Text('Export PNG Layout Chart'),
              ),
            ] else ...[
              const Text(
                'JSON Data ready! Click below to copy to clipboard.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _jsonText!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _jsonText!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('JSON copied to clipboard!')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy to Clipboard'),
              ),
            ],
            if (_exporting) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
