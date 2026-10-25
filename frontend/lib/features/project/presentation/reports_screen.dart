import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/themes/app_theme.dart';
import '../providers/export_provider.dart';
import '../providers/project_provider.dart';
import '../../room/providers/room_provider.dart';
import '../models/report_templates.dart';
import '../../../shared/widgets/custom_card.dart';


class ReportsScreen extends ConsumerStatefulWidget {
  final String? projectId;
  final bool isEmbedded;

  const ReportsScreen({
    super.key,
    this.projectId,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String? _selectedProjectId;
  String? _selectedRoomId;
  String _selectedReportType = 'Design Report';
  String _selectedFormat = 'PDF';
  ReportTemplate _selectedTemplate = ReportTemplate.templates[0];

  final List<String> _reportTypes = [
    'Design Report',
    'Analytics Report',
    'Validation Report',
    'Recommendation Report'
  ];

  final List<String> _formats = ['PDF', 'PNG', 'JSON'];

  @override
  void initState() {
    super.initState();
    if (widget.isEmbedded && widget.projectId != null) {
      _selectedProjectId = widget.projectId;
      Future.microtask(() {
        _loadProjectDetails(widget.projectId!);
      });
    } else {
      Future.microtask(() {
        ref.read(projectProvider.notifier).fetchProjects().then((_) {
          final projects = ref.read(projectProvider).projects;
          if (projects.isNotEmpty) {
            setState(() {
              _selectedProjectId = projects[0]['id'];
            });
            _loadProjectDetails(projects[0]['id']);
          }
        });
      });
    }
  }

  void _loadProjectDetails(String projectId) {
    ref.read(roomListProvider.notifier).fetchRooms(projectId);
    ref.read(exportProvider.notifier).fetchReportHistory(projectId);
    setState(() {
      _selectedRoomId = null; // Reset room select
    });
  }

  void _generateReport() async {
    if (_selectedProjectId == null) return;

    ref.read(exportProvider.notifier).generateAndPollReport(
      projectId: _selectedProjectId!,
      roomId: _selectedRoomId,
      reportType: _selectedReportType,
      format: _selectedFormat,
    ).then((_) {
      if (!mounted) return;
      final state = ref.read(exportProvider);
      if (state.errorMessage != null) {

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${state.errorMessage}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      } else if (state.downloadedBytes != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report generated and downloaded successfully! (${state.downloadedBytes!.length} bytes)'),
            backgroundColor: AppTheme.primary,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final projectState = ref.watch(projectProvider);
    final roomState = ref.watch(roomListProvider);
    final exportState = ref.watch(exportProvider);

    final projects = projectState.projects;
    final rooms = roomState.rooms;

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('Report & Export Center'),
              centerTitle: false,
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (projects.isEmpty && !widget.isEmbedded)
              const CustomCard(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(
                    child: Text(
                      'No projects found. Please create a project before generating reports.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Config Column
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Configuration Card
                        CustomCard(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '1. Select Scope',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primary,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                // Project Select
                                if (!widget.isEmbedded) ...[
                                  DropdownButtonFormField<String>(
                                    initialValue: _selectedProjectId,
                                    decoration: const InputDecoration(
                                      labelText: 'Project',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.folder),
                                    ),
                                    items: projects.map<DropdownMenuItem<String>>((p) {
                                      return DropdownMenuItem<String>(
                                        value: p['id'],
                                        child: Text(p['project_name']),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _selectedProjectId = val;
                                        });
                                        _loadProjectDetails(val);
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                // Room Select
                                DropdownButtonFormField<String?>(
                                  initialValue: _selectedRoomId,
                                  decoration: const InputDecoration(
                                    labelText: 'Room',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.room),
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('All Rooms (Project Summary)'),
                                    ),
                                    ...rooms.map<DropdownMenuItem<String?>>((r) {
                                      return DropdownMenuItem<String?>(
                                        value: r['id'],
                                        child: Text('${r['room_name']} (${r['room_type']})'),
                                      );
                                    }),
                                  ],
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedRoomId = val;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Report Type & Template
                        CustomCard(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '2. Select Report Type & Style',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primary,
                                      ),
                                ),
                                const SizedBox(height: 16),
                                // Report Types grid
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: _reportTypes.map((type) {
                                    final isSelected = _selectedReportType == type;
                                    return InkWell(
                                      onTap: () {
                                        setState(() {
                                          _selectedReportType = type;
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: isSelected ? AppTheme.primary.withOpacity(0.1) : Colors.transparent,
                                          border: Border.all(
                                            color: isSelected ? AppTheme.primary : Colors.grey.shade300,
                                            width: 1.5,
                                          ),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isSelected ? Icons.check_circle : Icons.circle_outlined,
                                              color: isSelected ? AppTheme.primary : Colors.grey,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              type,
                                              style: TextStyle(
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'Select Report Template Styling',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                // Horizontal List of Templates
                                SizedBox(
                                  height: 110,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: ReportTemplate.templates.length,
                                    itemBuilder: (context, idx) {
                                      final temp = ReportTemplate.templates[idx];
                                      final isSelected = _selectedTemplate.id == temp.id;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 12.0),
                                        child: InkWell(
                                          onTap: () {
                                            setState(() {
                                              _selectedTemplate = temp;
                                            });
                                          },
                                          child: Container(
                                            width: 180,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: isSelected ? AppTheme.primary : Colors.grey.shade300,
                                                width: isSelected ? 2 : 1,
                                              ),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      width: 14,
                                                      height: 14,
                                                      decoration: BoxDecoration(
                                                        color: Color(int.parse(temp.primaryColorHex.replaceAll('#', '0xff'))),
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        temp.styleName,
                                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  temp.description,
                                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                                  maxLines: 3,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Format & Generate Button
                        CustomCard(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      '3. Choose Export Format',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    ToggleButtons(
                                      borderRadius: BorderRadius.circular(8),
                                      isSelected: _formats.map((f) => _selectedFormat == f).toList(),
                                      onPressed: (idx) {
                                        setState(() {
                                          _selectedFormat = _formats[idx];
                                        });
                                      },
                                      children: _formats.map((f) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                          child: Text(f),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                if (exportState.isLoading)
                                  Column(
                                    children: [
                                      const LinearProgressIndicator(),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Generating: Status [ ${exportState.reportStatus ?? 'Pending'} ]',
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  )
                                else
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: _generateReport,
                                    icon: const Icon(Icons.analytics),
                                    label: const Text(
                                      'Generate Report',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 20),

                  // Right History Column
                  Expanded(
                    flex: 2,
                    child: CustomCard(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Report Generation History',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.refresh),
                                  onPressed: () {
                                    if (_selectedProjectId != null) {
                                      ref.read(exportProvider.notifier).fetchReportHistory(_selectedProjectId!);
                                    }
                                  },
                                ),
                              ],
                            ),
                            const Divider(),
                            const SizedBox(height: 10),
                            if (exportState.reportHistory.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 40.0),
                                child: Center(
                                  child: Text(
                                    'No generated reports found for this project.',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: exportState.reportHistory.length,
                                separatorBuilder: (context, idx) => const Divider(),
                                itemBuilder: (context, idx) {
                                  final item = exportState.reportHistory[idx];
                                  final createdAt = DateTime.parse(item['created_at']);
                                  final sizeKb = (item['file_size'] / 1024).toStringAsFixed(1);
                                  final format = item['format'];

                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: format == 'PDF'
                                            ? Colors.red.withOpacity(0.1)
                                            : (format == 'PNG' ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1)),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        format == 'PDF'
                                            ? Icons.picture_as_pdf
                                            : (format == 'PNG' ? Icons.image : Icons.code),
                                        color: format == 'PDF'
                                            ? Colors.red
                                            : (format == 'PNG' ? Colors.green : Colors.orange),
                                      ),
                                    ),
                                    title: Text(
                                      item['report_type'] ?? 'Report',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    subtitle: Text(
                                      '${createdAt.month}/${createdAt.day} ${createdAt.hour}:${createdAt.minute} • $sizeKb KB • Status: ${item['status']}',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                    trailing: item['status'] == 'Completed'
                                        ? IconButton(
                                            icon: const Icon(Icons.download, color: AppTheme.primary),
                                            onPressed: () {
                                              ref.read(exportProvider.notifier).downloadReport(item['id']).then((bytes) {
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context).showSnackBar(

                                                  SnackBar(
                                                    content: Text('Downloaded report: ${item['report_type']} (${bytes.length} bytes)'),
                                                    backgroundColor: AppTheme.primary,
                                                  ),
                                                );
                                              });
                                            },
                                          )
                                        : const Icon(Icons.hourglass_empty, color: Colors.amber),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
