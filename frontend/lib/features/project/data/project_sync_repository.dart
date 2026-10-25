import 'dart:convert';
import '../../../core/api/api_client.dart';
import '../../room/data/room_api_client.dart';
import 'project_api_client.dart';
import 'project_local_cache.dart';

class ProjectConflict {
  final String projectId;
  final String projectName;
  final String localUpdatedAt;
  final String remoteUpdatedAt;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;

  ProjectConflict({
    required this.projectId,
    required this.projectName,
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
    required this.localData,
    required this.remoteData,
  });
}

class ProjectSyncRepository {
  final ProjectApiClient _projectApi = ProjectApiClient();
  final RoomApiClient _roomApi = RoomApiClient();
  final ProjectLocalCache _localCache = ProjectLocalCache();
  final ApiClient _apiClient = ApiClient();

  final List<ProjectConflict> conflicts = [];

  // Check online status
  Future<bool> isOnline() async {
    try {
      final response = await _apiClient.get('/health').timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['status'] == 'healthy';
      }
    } catch (_) {}
    return false;
  }

  // Get list of projects
  Future<List<dynamic>> getProjects({
    String? search,
    String? status,
    String? sort,
    bool favorite = false,
  }) async {
    await _localCache.loadCache();

    if (await isOnline()) {
      try {
        // Sync pending first
        await sync();

        final remoteList = await _projectApi.getProjects(
          search: search,
          status: status,
          sort: sort,
          favorite: favorite,
        );

        // Update local cache with remote list items (partial details, but enough for listing)
        final updatedCache = await _localCache.loadCache();
        final projectsMap = updatedCache['projects'] as Map<String, dynamic>;
        for (var p in remoteList) {
          final id = p['id'] as String;
          if (!projectsMap.containsKey(id)) {
            projectsMap[id] = p;
          } else {
            // merge
            final existing = projectsMap[id] as Map<String, dynamic>;
            existing.addAll(p);
          }
        }
        await _localCache.saveCache(updatedCache);
      } catch (_) {}
    }

    // Load from cache and filter locally
    final latestCache = await _localCache.loadCache();
    final latestProjectsMap = latestCache['projects'] as Map<String, dynamic>;

    final list = latestProjectsMap.values.where((p) {
      if (p['status'] == 'Deleted') return false;
      if (favorite && p['is_favorite'] != true) return false;
      if (status != null && p['status'] != status) return false;
      if (search != null && search.isNotEmpty) {
        final name = (p['project_name'] ?? '').toString().toLowerCase();
        final desc = (p['description'] ?? '').toString().toLowerCase();
        final loc = (p['location'] ?? '').toString().toLowerCase();
        final q = search.toLowerCase();
        if (!name.contains(q) && !desc.contains(q) && !loc.contains(q)) return false;
      }
      return true;
    }).toList();

    // Sort locally
    list.sort((a, b) {
      if (sort == 'project_name') {
        return (a['project_name'] ?? '').compareTo(b['project_name'] ?? '');
      } else if (sort == 'project_name_desc') {
        return (b['project_name'] ?? '').compareTo(a['project_name'] ?? '');
      } else if (sort == 'updated_at') {
        final aTime = DateTime.parse(a['updated_at'] ?? a['created_at']);
        final bTime = DateTime.parse(b['updated_at'] ?? b['created_at']);
        return bTime.compareTo(aTime);
      } else {
        final aTime = DateTime.parse(a['created_at'] ?? DateTime.now().toIso8601String());
        final bTime = DateTime.parse(b['created_at'] ?? DateTime.now().toIso8601String());
        return bTime.compareTo(aTime);
      }
    });

    return list;
  }

  // Get project details
  Future<Map<String, dynamic>> getProjectDetails(String projectId) async {
    final cache = await _localCache.loadCache();
    final projectsMap = cache['projects'] as Map<String, dynamic>;

    if (await isOnline() && !projectId.startsWith('local_proj_')) {
      try {
        final remoteDetails = await _projectApi.getProjectDetails(projectId);
        
        // Save project and its settings/rooms to cache
        projectsMap[projectId] = remoteDetails;
        
        // Save rooms
        final roomsMap = cache['rooms'] as Map<String, dynamic>;
        final roomsList = remoteDetails['rooms'] as List<dynamic>? ?? [];
        roomsMap[projectId] = roomsList;

        // Overwrite layouts and measurements from remote rooms if possible
        final layoutsMap = cache['layouts'] as Map<String, dynamic>;
        for (var r in roomsList) {
          final rId = r['id'] as String;
          if (r['properties'] != null) {
            layoutsMap[rId] = r['properties'];
          }
        }

        await _localCache.saveCache(cache);
        return remoteDetails;
      } catch (_) {}
    }

    if (projectsMap.containsKey(projectId)) {
      final localDetails = Map<String, dynamic>.from(projectsMap[projectId]);
      // Attach rooms from local cache
      final roomsMap = cache['rooms'] as Map<String, dynamic>;
      localDetails['rooms'] = roomsMap[projectId] ?? [];
      return localDetails;
    }
    throw Exception('Project not found');
  }

  // Create Project
  Future<String> createProject({
    required String projectName,
    String? description,
    String? location,
  }) async {
    final cache = await _localCache.loadCache();
    final queue = await _localCache.loadQueue();

    final tempId = 'local_proj_${DateTime.now().millisecondsSinceEpoch}';
    final nowStr = DateTime.now().toUtc().toIso8601String();

    final localProj = {
      'id': tempId,
      'project_name': projectName,
      'description': description,
      'location': location,
      'status': 'Draft',
      'is_favorite': false,
      'created_at': nowStr,
      'updated_at': nowStr,
      'settings': {
        'default_style': null,
        'measurement_unit': 'Centimeters',
        'grid_enabled': true,
        'snap_enabled': true,
      },
    };

    cache['projects'][tempId] = localProj;
    cache['rooms'][tempId] = [];
    await _localCache.saveCache(cache);

    // Queue action
    queue.add({
      'id': 'act_${DateTime.now().microsecondsSinceEpoch}',
      'action': 'CREATE_PROJECT',
      'projectId': tempId,
      'payload': {
        'project_name': projectName,
        'description': description,
        'location': location,
      },
      'timestamp': nowStr,
    });
    await _localCache.saveQueue(queue);

    // Attempt online execution
    if (await isOnline()) {
      await sync();
      final updatedCache = await _localCache.loadCache();
      // Find server ID
      for (var entry in updatedCache['projects'].entries) {
        if (entry.value['project_name'] == projectName && !entry.key.startsWith('local_proj_')) {
          return entry.key;
        }
      }
    }

    return tempId;
  }

  // Update Project
  Future<void> updateProject(String projectId, {
    String? projectName,
    String? description,
    String? location,
    String? status,
    bool? isFavorite,
  }) async {
    final cache = await _localCache.loadCache();
    final queue = await _localCache.loadQueue();
    final nowStr = DateTime.now().toUtc().toIso8601String();

    if (!cache['projects'].containsKey(projectId)) return;
    final proj = cache['projects'][projectId] as Map<String, dynamic>;

    if (projectName != null) proj['project_name'] = projectName;
    if (description != null) proj['description'] = description;
    if (location != null) proj['location'] = location;
    if (status != null) proj['status'] = status;
    if (isFavorite != null) proj['is_favorite'] = isFavorite;
    proj['updated_at'] = nowStr;

    await _localCache.saveCache(cache);

    queue.add({
      'id': 'act_${DateTime.now().microsecondsSinceEpoch}',
      'action': 'UPDATE_PROJECT',
      'projectId': projectId,
      'payload': {
        if (projectName != null) 'project_name': projectName,
        if (description != null) 'description': description,
        if (location != null) 'location': location,
        if (status != null) 'status': status,
        if (isFavorite != null) 'is_favorite': isFavorite,
      },
      'timestamp': nowStr,
    });
    await _localCache.saveQueue(queue);

    if (await isOnline()) {
      await sync();
    }
  }

  // Soft Delete Project
  Future<void> softDeleteProject(String projectId) async {
    await updateProject(projectId, status: 'Deleted');
  }

  // Toggle Favorite
  Future<bool> toggleFavorite(String projectId) async {
    final cache = await _localCache.loadCache();
    if (!cache['projects'].containsKey(projectId)) return false;
    final proj = cache['projects'][projectId] as Map<String, dynamic>;
    final nextFav = !(proj['is_favorite'] as bool? ?? false);
    await updateProject(projectId, isFavorite: nextFav);
    return nextFav;
  }

  // Duplicate Project
  Future<String> duplicateProject(String projectId) async {
    final cache = await _localCache.loadCache();
    if (!cache['projects'].containsKey(projectId)) {
      throw Exception('Project not found');
    }
    final sourceProj = cache['projects'][projectId] as Map<String, dynamic>;
    final dupName = '${sourceProj['project_name']} (Copy)';

    final newProjId = await createProject(
      projectName: dupName,
      description: sourceProj['description'],
      location: sourceProj['location'],
    );

    final newCache = await _localCache.loadCache();
    final newProj = newCache['projects'][newProjId] as Map<String, dynamic>;
    if (sourceProj['settings'] != null) {
      newProj['settings'] = Map<String, dynamic>.from(sourceProj['settings']);
    }

    final roomsMap = newCache['rooms'] as Map<String, dynamic>;
    final sourceRooms = roomsMap[projectId] as List<dynamic>? ?? [];
    final dupRooms = [];
    final queue = await _localCache.loadQueue();
    final nowStr = DateTime.now().toUtc().toIso8601String();

    for (var room in sourceRooms) {
      final tempRoomId = 'local_room_${DateTime.now().millisecondsSinceEpoch}_${room['id']}';
      final newRoom = {
        'id': tempRoomId,
        'project_id': newProjId,
        'room_name': room['room_name'],
        'room_type': room['room_type'],
        'floor_number': room['floor_number'] ?? 1,
        'notes': room['notes'],
        'room_color': room['room_color'] ?? '#FFFFFF',
        'properties': room['properties'],
        'created_at': nowStr,
        'updated_at': nowStr,
      };
      dupRooms.add(newRoom);

      if (newCache['layouts'].containsKey(room['id'])) {
        newCache['layouts'][tempRoomId] = newCache['layouts'][room['id']];
      }
      if (newCache['measurements'].containsKey(room['id'])) {
        newCache['measurements'][tempRoomId] = Map<String, dynamic>.from(newCache['measurements'][room['id']]);
      }

      queue.add({
        'id': 'act_${DateTime.now().microsecondsSinceEpoch}_room',
        'action': 'CREATE_ROOM',
        'projectId': newProjId,
        'roomId': tempRoomId,
        'payload': {
          'room_name': room['room_name'],
          'room_type': room['room_type'],
          'floor_number': room['floor_number'] ?? 1,
          'notes': room['notes'],
          'room_color': room['room_color'] ?? '#FFFFFF',
          'properties': room['properties'],
        },
        'timestamp': nowStr,
      });
    }
    roomsMap[newProjId] = dupRooms;

    await _localCache.saveCache(newCache);
    await _localCache.saveQueue(queue);

    if (await isOnline()) {
      await sync();
    }
    return newProjId;
  }

  // Room methods
  Future<List<dynamic>> getRooms(String projectId) async {
    final cache = await _localCache.loadCache();
    final roomsMap = cache['rooms'] as Map<String, dynamic>;

    if (await isOnline() && !projectId.startsWith('local_proj_')) {
      try {
        final remoteRooms = await _roomApi.getRooms(projectId);
        roomsMap[projectId] = remoteRooms;
        await _localCache.saveCache(cache);
        return remoteRooms;
      } catch (_) {}
    }

    return roomsMap[projectId] ?? [];
  }

  Future<Map<String, dynamic>> getRoomDetails(String roomId) async {
    final cache = await _localCache.loadCache();
    
    if (await isOnline() && !roomId.startsWith('local_room_')) {
      try {
        final remoteDetails = await _roomApi.getRoomDetails(roomId);
        final measurementsMap = cache['measurements'] as Map<String, dynamic>;
        if (remoteDetails['measurements'] != null) {
          measurementsMap[roomId] = remoteDetails['measurements'];
        }
        if (remoteDetails['properties'] != null) {
          cache['layouts'][roomId] = remoteDetails['properties'];
        }
        await _localCache.saveCache(cache);
        return remoteDetails;
      } catch (_) {}
    }

    // Build local room details
    for (var projectRooms in cache['rooms'].values) {
      for (var r in projectRooms) {
        if (r['id'] == roomId) {
          final localDetails = Map<String, dynamic>.from(r);
          localDetails['measurements'] = cache['measurements'][roomId];
          return localDetails;
        }
      }
    }
    throw Exception('Room details not found');
  }

  Future<String> createRoom(String projectId, {
    required String roomName,
    required String roomType,
    int floorNumber = 1,
    String? notes,
    String roomColor = '#FFFFFF',
    String? properties,
  }) async {
    final cache = await _localCache.loadCache();
    final queue = await _localCache.loadQueue();
    final tempRoomId = 'local_room_${DateTime.now().millisecondsSinceEpoch}';
    final nowStr = DateTime.now().toUtc().toIso8601String();

    final localRoom = {
      'id': tempRoomId,
      'project_id': projectId,
      'room_name': roomName,
      'room_type': roomType,
      'floor_number': floorNumber,
      'notes': notes,
      'room_color': roomColor,
      'properties': properties,
      'created_at': nowStr,
      'updated_at': nowStr,
    };

    final projectRooms = cache['rooms'][projectId] as List<dynamic>? ?? [];
    projectRooms.add(localRoom);
    cache['rooms'][projectId] = projectRooms;

    if (properties != null) {
      cache['layouts'][tempRoomId] = properties;
    }

    // Default measurements
    cache['measurements'][tempRoomId] = {
      'length': 600.0,
      'width': 450.0,
      'height': 300.0,
      'floor_thickness': 30.0,
      'wall_thickness': 20.0,
      'ceiling_height': 300.0,
    };

    await _localCache.saveCache(cache);

    queue.add({
      'id': 'act_${DateTime.now().microsecondsSinceEpoch}',
      'action': 'CREATE_ROOM',
      'projectId': projectId,
      'roomId': tempRoomId,
      'payload': {
        'room_name': roomName,
        'room_type': roomType,
        'floor_number': floorNumber,
        'notes': notes,
        'room_color': roomColor,
        'properties': properties,
      },
      'timestamp': nowStr,
    });
    await _localCache.saveQueue(queue);

    if (await isOnline()) {
      await sync();
      final updatedCache = await _localCache.loadCache();
      final roomsList = updatedCache['rooms'][projectId] as List<dynamic>? ?? [];
      for (var r in roomsList) {
        if (r['room_name'] == roomName && !r['id'].startsWith('local_room_')) {
          return r['id'];
        }
      }
    }

    return tempRoomId;
  }

  Future<void> updateRoom(String roomId, {
    String? roomName,
    String? roomType,
    int? floorNumber,
    String? notes,
    String? roomColor,
    String? properties,
  }) async {
    final cache = await _localCache.loadCache();
    final queue = await _localCache.loadQueue();
    final nowStr = DateTime.now().toUtc().toIso8601String();

    String? projectId;
    Map<String, dynamic>? targetRoom;

    for (var entry in cache['rooms'].entries) {
      final roomsList = entry.value as List<dynamic>;
      for (var r in roomsList) {
        if (r['id'] == roomId) {
          projectId = entry.key;
          targetRoom = r as Map<String, dynamic>;
          break;
        }
      }
    }

    if (targetRoom == null) return;

    if (roomName != null) targetRoom['room_name'] = roomName;
    if (roomType != null) targetRoom['room_type'] = roomType;
    if (floorNumber != null) targetRoom['floor_number'] = floorNumber;
    if (notes != null) targetRoom['notes'] = notes;
    if (roomColor != null) targetRoom['room_color'] = roomColor;
    if (properties != null) {
      targetRoom['properties'] = properties;
      cache['layouts'][roomId] = properties;
    }
    targetRoom['updated_at'] = nowStr;

    await _localCache.saveCache(cache);

    queue.add({
      'id': 'act_${DateTime.now().microsecondsSinceEpoch}',
      'action': 'UPDATE_ROOM',
      'projectId': projectId,
      'roomId': roomId,
      'payload': {
        if (roomName != null) 'room_name': roomName,
        if (roomType != null) 'room_type': roomType,
        if (floorNumber != null) 'floor_number': floorNumber,
        if (notes != null) 'notes': notes,
        if (roomColor != null) 'room_color': roomColor,
        if (properties != null) 'properties': properties,
      },
      'timestamp': nowStr,
    });
    await _localCache.saveQueue(queue);

    if (await isOnline()) {
      await sync();
    }
  }

  Future<void> deleteRoom(String projectId, String roomId) async {
    final cache = await _localCache.loadCache();
    final queue = await _localCache.loadQueue();
    final nowStr = DateTime.now().toUtc().toIso8601String();

    final roomsList = cache['rooms'][projectId] as List<dynamic>? ?? [];
    roomsList.removeWhere((r) => r['id'] == roomId);
    cache['measurements'].remove(roomId);
    cache['layouts'].remove(roomId);
    await _localCache.saveCache(cache);

    queue.add({
      'id': 'act_${DateTime.now().microsecondsSinceEpoch}',
      'action': 'DELETE_ROOM',
      'projectId': projectId,
      'roomId': roomId,
      'timestamp': nowStr,
    });
    await _localCache.saveQueue(queue);

    if (await isOnline()) {
      await sync();
    }
  }

  Future<String> duplicateRoom(String projectId, String roomId) async {
    final details = await getRoomDetails(roomId);
    final dupName = '${details['room_name']} (Copy)';

    final newRoomId = await createRoom(
      projectId,
      roomName: dupName,
      roomType: details['room_type'],
      floorNumber: details['floor_number'] ?? 1,
      notes: details['notes'],
      roomColor: details['room_color'] ?? '#FFFFFF',
      properties: details['properties'],
    );

    final cache = await _localCache.loadCache();
    if (cache['measurements'].containsKey(roomId)) {
      cache['measurements'][newRoomId] = Map<String, dynamic>.from(cache['measurements'][roomId]);
      await _localCache.saveCache(cache);

      final queue = await _localCache.loadQueue();
      final nowStr = DateTime.now().toUtc().toIso8601String();
      final m = cache['measurements'][newRoomId];
      queue.add({
        'id': 'act_${DateTime.now().microsecondsSinceEpoch}_measure',
        'action': 'UPDATE_MEASUREMENTS',
        'projectId': projectId,
        'roomId': newRoomId,
        'payload': {
          'length': m['length'],
          'width': m['width'],
          'height': m['height'],
          'floor_thickness': m['floor_thickness'],
          'wall_thickness': m['wall_thickness'],
          'ceiling_height': m['ceiling_height'],
        },
        'timestamp': nowStr,
      });
      await _localCache.saveQueue(queue);
    }

    if (await isOnline()) {
      await sync();
    }
    return newRoomId;
  }

  Future<void> updateMeasurements(String roomId, {
    required double length,
    required double width,
    required double height,
    double? floorThickness,
    double? wallThickness,
    double? ceilingHeight,
  }) async {
    final cache = await _localCache.loadCache();
    final queue = await _localCache.loadQueue();
    final nowStr = DateTime.now().toUtc().toIso8601String();

    String? projectId;
    for (var entry in cache['rooms'].entries) {
      final roomsList = entry.value as List<dynamic>;
      for (var r in roomsList) {
        if (r['id'] == roomId) {
          projectId = entry.key;
          break;
        }
      }
    }

    cache['measurements'][roomId] = {
      'length': length,
      'width': width,
      'height': height,
      'floor_thickness': floorThickness ?? 30.0,
      'wall_thickness': wallThickness ?? 20.0,
      'ceiling_height': ceilingHeight ?? height,
    };
    await _localCache.saveCache(cache);

    queue.add({
      'id': 'act_${DateTime.now().microsecondsSinceEpoch}',
      'action': 'UPDATE_MEASUREMENTS',
      'projectId': projectId,
      'roomId': roomId,
      'payload': {
        'length': length,
        'width': width,
        'height': height,
        'floor_thickness': floorThickness ?? 30.0,
        'wall_thickness': wallThickness ?? 20.0,
        'ceiling_height': ceilingHeight ?? height,
      },
      'timestamp': nowStr,
    });
    await _localCache.saveQueue(queue);

    if (await isOnline()) {
      await sync();
    }
  }

  // Main Sync Entrypoint
  Future<void> sync() async {
    if (!(await isOnline())) return;

    try {
      await _pushPendingQueue();
      await _pullIncrementalChanges();
    } catch (_) {}
  }

  // Push pending actions queue
  Future<void> _pushPendingQueue() async {
    final queue = await _localCache.loadQueue();
    if (queue.isEmpty) return;

    final cache = await _localCache.loadCache();
    final List<dynamic> remainingQueue = List.from(queue);

    // Track ID mappings for offline created resources
    final Map<String, String> projectIdsMap = {};
    final Map<String, String> roomIdsMap = {};

    for (var action in queue) {
      final actionId = action['id'] as String;
      final actionType = action['action'] as String;
      var projectId = action['projectId'] as String?;
      var roomId = action['roomId'] as String?;
      final payload = action['payload'] as Map<String, dynamic>? ?? {};

      // Map temporary IDs
      if (projectId != null && projectIdsMap.containsKey(projectId)) {
        projectId = projectIdsMap[projectId];
      }
      if (roomId != null && roomIdsMap.containsKey(roomId)) {
        roomId = roomIdsMap[roomId];
      }

      try {
        switch (actionType) {
          case 'CREATE_PROJECT':
            final serverId = await _projectApi.createProject(
              projectName: payload['project_name'],
              description: payload['description'],
              location: payload['location'],
            );
            projectIdsMap[action['projectId']] = serverId;

            // Update local cache references
            final oldProj = cache['projects'].remove(action['projectId']);
            if (oldProj != null) {
              oldProj['id'] = serverId;
              cache['projects'][serverId] = oldProj;
            }
            final oldRooms = cache['rooms'].remove(action['projectId']);
            if (oldRooms != null) {
              for (var r in oldRooms) {
                r['project_id'] = serverId;
              }
              cache['rooms'][serverId] = oldRooms;
            } else {
              cache['rooms'][serverId] = [];
            }
            break;

          case 'UPDATE_PROJECT':
            if (projectId != null && !projectId.startsWith('local_proj_')) {
              await _projectApi.updateProject(
                projectId,
                projectName: payload['project_name'],
                description: payload['description'],
                location: payload['location'],
                status: payload['status'],
                isFavorite: payload['is_favorite'],
              );
            }
            break;

          case 'DELETE_PROJECT':
            if (projectId != null && !projectId.startsWith('local_proj_')) {
              await _projectApi.softDeleteProject(projectId);
            }
            break;

          case 'CREATE_ROOM':
            if (projectId != null && !projectId.startsWith('local_proj_')) {
              final serverRoomId = await _roomApi.createRoom(
                projectId,
                roomName: payload['room_name'],
                roomType: payload['room_type'],
                floorNumber: payload['floor_number'] ?? 1,
                notes: payload['notes'],
                roomColor: payload['room_color'] ?? '#FFFFFF',
                properties: payload['properties'],
              );
              roomIdsMap[action['roomId']] = serverRoomId;

              // Update room references in local cache
              final projectRooms = cache['rooms'][projectId] as List<dynamic>? ?? [];
              for (var r in projectRooms) {
                if (r['id'] == action['roomId']) {
                  r['id'] = serverRoomId;
                  break;
                }
              }

              // Update layout/measurements references in cache
              final oldLayout = cache['layouts'].remove(action['roomId']);
              if (oldLayout != null) {
                cache['layouts'][serverRoomId] = oldLayout;
              }
              final oldMeasure = cache['measurements'].remove(action['roomId']);
              if (oldMeasure != null) {
                cache['measurements'][serverRoomId] = oldMeasure;
              }
            }
            break;

          case 'UPDATE_ROOM':
            if (roomId != null && !roomId.startsWith('local_room_')) {
              await _roomApi.updateRoom(
                roomId,
                roomName: payload['room_name'],
                roomType: payload['room_type'],
                floorNumber: payload['floor_number'],
                notes: payload['notes'],
                roomColor: payload['room_color'],
                properties: payload['properties'],
              );
              if (payload['properties'] != null) {
                try {
                  await _roomApi.saveRoomLayout(roomId, payload['properties']);
                } catch (_) {}
              }
            }
            break;

          case 'DELETE_ROOM':
            if (roomId != null && !roomId.startsWith('local_room_')) {
              await _roomApi.deleteRoom(roomId);
            }
            break;

          case 'UPDATE_MEASUREMENTS':
            if (roomId != null && !roomId.startsWith('local_room_')) {
              await _roomApi.updateMeasurements(
                roomId,
                length: (payload['length'] as num).toDouble(),
                width: (payload['width'] as num).toDouble(),
                height: (payload['height'] as num).toDouble(),
                floorThickness: (payload['floor_thickness'] as num?)?.toDouble(),
                wallThickness: (payload['wall_thickness'] as num?)?.toDouble(),
                ceilingHeight: (payload['ceiling_height'] as num?)?.toDouble(),
              );
            }
            break;
        }

        // Successfully executed, remove from remaining queue
        remainingQueue.removeWhere((item) => item['id'] == actionId);
      } catch (e) {
        // If it failed because of duplicate project name (FastAPI status 400),
        // we skip it to prevent queue deadlock and let sync continue.
        if (e.toString().contains('Duplicate') || e.toString().contains('400')) {
          remainingQueue.removeWhere((item) => item['id'] == actionId);
        } else {
          // General connection error, stop execution to retry later
          break;
        }
      }
    }

    await _localCache.saveCache(cache);

    // Translate any leftover actions in the remaining queue
    for (var act in remainingQueue) {
      final actProjId = act['projectId'] as String?;
      if (actProjId != null && projectIdsMap.containsKey(actProjId)) {
        act['projectId'] = projectIdsMap[actProjId];
      }
      final actRoomId = act['roomId'] as String?;
      if (actRoomId != null && roomIdsMap.containsKey(actRoomId)) {
        act['roomId'] = roomIdsMap[actRoomId];
      }
    }

    await _localCache.saveQueue(remainingQueue);
  }

  // Pull updates incrementally
  Future<void> _pullIncrementalChanges() async {
    final cache = await _localCache.loadCache();
    final localProjects = cache['projects'] as Map<String, dynamic>;
    final queue = await _localCache.loadQueue();

    final remoteList = await _projectApi.getProjects();
    conflicts.clear();

    for (var remoteProj in remoteList) {
      final projectId = remoteProj['id'] as String;
      final remoteUpdated = DateTime.parse(remoteProj['updated_at']);

      final hasLocalChanges = queue.any((action) => action['projectId'] == projectId);

      if (localProjects.containsKey(projectId)) {
        final localProj = localProjects[projectId] as Map<String, dynamic>;
        final localUpdated = DateTime.parse(localProj['updated_at'] ?? localProj['created_at']);

        if (remoteUpdated.isAfter(localUpdated)) {
          if (hasLocalChanges) {
            // Conflict detected!
            conflicts.add(ProjectConflict(
              projectId: projectId,
              projectName: remoteProj['project_name'],
              localUpdatedAt: localUpdated.toLocal().toIso8601String(),
              remoteUpdatedAt: remoteUpdated.toLocal().toIso8601String(),
              localData: localProj,
              remoteData: remoteProj,
            ));
          } else {
            // Safe to pull remote project details and overwrite local
            await _pullProjectAndRooms(projectId, cache);
          }
        }
      } else {
        // New project on server, pull it
        await _pullProjectAndRooms(projectId, cache);
      }
    }

    // Save sync completion time
    cache['lastSyncTime'] = DateTime.now().toUtc().toIso8601String();
    await _localCache.saveCache(cache);
  }

  Future<void> _pullProjectAndRooms(String projectId, Map<String, dynamic> cache) async {
    try {
      final remoteDetails = await _projectApi.getProjectDetails(projectId);
      cache['projects'][projectId] = remoteDetails;

      final roomsList = remoteDetails['rooms'] as List<dynamic>? ?? [];
      cache['rooms'][projectId] = roomsList;

      for (var r in roomsList) {
        final roomId = r['id'] as String;
        if (r['properties'] != null) {
          cache['layouts'][roomId] = r['properties'];
        }
        // Fetch measurements
        try {
          final m = await _roomApi.getMeasurements(roomId);
          cache['measurements'][roomId] = m;
        } catch (_) {}
      }
    } catch (_) {}
  }

  // Conflict Resolution Action
  Future<void> resolveConflict(String projectId, bool useLocal) async {
    final cache = await _localCache.loadCache();
    final queue = await _localCache.loadQueue();

    if (useLocal) {
      // Keep local: update the timestamp to now so local is newer and will overwrite remote
      final proj = cache['projects'][projectId] as Map<String, dynamic>?;
      if (proj != null) {
        proj['updated_at'] = DateTime.now().toUtc().toIso8601String();
        // Add a dummy project update action to queue to force overwrite on next sync
        queue.add({
          'id': 'act_force_${DateTime.now().microsecondsSinceEpoch}',
          'action': 'UPDATE_PROJECT',
          'projectId': projectId,
          'payload': {
            'project_name': proj['project_name'],
            'description': proj['description'],
            'location': proj['location'],
            'status': proj['status'],
            'is_favorite': proj['is_favorite'],
          },
          'timestamp': proj['updated_at'],
        });
      }
      await _localCache.saveCache(cache);
      await _localCache.saveQueue(queue);
    } else {
      // Use Cloud: clear local queue actions for this project and pull remote
      queue.removeWhere((action) => action['projectId'] == projectId);
      await _localCache.saveQueue(queue);

      await _pullProjectAndRooms(projectId, cache);
      await _localCache.saveCache(cache);
    }

    conflicts.removeWhere((c) => c.projectId == projectId);
    await sync();
  }
}
