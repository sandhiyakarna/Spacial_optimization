import '../../../app/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/room_provider.dart';
import 'room_dialogs.dart';
import '../../../shared/widgets/custom_card.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/snackbar_manager.dart';
import '../../designer/presentation/full_floor_view.dart';

class RoomListScreen extends ConsumerStatefulWidget {
  final String projectId;
  final bool isEmbedded;
  final ValueChanged<String>? onRoomSelected;

  const RoomListScreen({
    super.key,
    required this.projectId,
    this.isEmbedded = false,
    this.onRoomSelected,
  });

  @override
  ConsumerState<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends ConsumerState<RoomListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(roomListProvider.notifier).fetchRooms(widget.projectId);
    });
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateRoomDialog(projectId: widget.projectId),
    );
  }

  void _showEditDialog(Map<String, dynamic> room) {
    showDialog(
      context: context,
      builder: (context) => EditRoomDialog(room: room, projectId: widget.projectId),
    );
  }

  void _showDeleteDialog(Map<String, dynamic> room) {
    showDialog(
      context: context,
      builder: (context) => DeleteRoomDialog(room: room, projectId: widget.projectId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(roomListProvider);
    final notifier = ref.read(roomListProvider.notifier);

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('Rooms Catalog'),
            ),
      body: listState.isLoading
          ? const LoadingIndicator(message: 'Loading rooms catalog...')
          : listState.rooms.isEmpty
              ? EmptyState(
                  title: 'No Rooms Found',
                  message: 'Create a room to define space layouts and furniture placements.',
                  actionText: 'Add Room',
                  onActionPressed: _showAddDialog,
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: listState.rooms.length,
                  itemBuilder: (context, index) {
                    final room = listState.rooms[index] as Map<String, dynamic>;
                    
                    // Parse Color safely
                    Color parsedColor = Colors.grey;
                    try {
                      final hex = (room['room_color'] ?? '#FFFFFF').toString().replaceAll('#', '');
                      parsedColor = Color(int.parse('FF$hex', radix: 16));
                    } catch (_) {}

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: CustomCard(
                        child: InkWell(
                          onTap: () {
                            if (widget.onRoomSelected != null) {
                              widget.onRoomSelected!(room['id']);
                            } else {
                              context.go('/designer/${room['id']}');
                            }
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: parsedColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.grey.shade400),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      room['room_name'] ?? 'Unnamed Room',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios, size: 14),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Type: ${room['room_type']} • Floor: ${room['floor_number']}',
                                style: TextStyle(color: Theme.of(context).hintColor),
                              ),
                              if (room['notes'] != null && room['notes'].toString().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  room['notes'],
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const Divider(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(Icons.copy, size: 18),
                                    label: const Text('Duplicate'),
                                    onPressed: () async {
                                      final success = await notifier.duplicateRoom(widget.projectId, room['id']);
                                      if (context.mounted && success) {
                                        SnackbarManager.showSuccess(context, 'Room duplicated.');
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    icon: const Icon(Icons.settings, size: 18),
                                    label: const Text('Settings'),
                                    onPressed: () => _showEditDialog(room),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                                    onPressed: () => _showDeleteDialog(room),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (listState.rooms.isNotEmpty)
            FloatingActionButton.extended(
              heroTag: 'generate_all_rooms_fab',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => FullFloorView(
                      projectId: widget.projectId,
                      rooms: listState.rooms.cast<Map<String, dynamic>>(),
                      furnitureAssets: const [],
                    ),
                  ),
                );
              },
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.auto_awesome, color: Colors.white),
              label: const Text('GENERATE ALL ROOMS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'add_room_fab',
            onPressed: _showAddDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Room'),
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
        ],
      ),
    );
  }
}
