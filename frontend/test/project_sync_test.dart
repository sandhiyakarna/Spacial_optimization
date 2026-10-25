import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowspace_frontend/features/project/data/project_local_cache.dart';
import 'package:flowspace_frontend/features/project/data/project_sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock path_provider MethodChannel
  const MethodChannel channel = MethodChannel('plugins.flutter.io/path_provider');
  
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return '.'; // Return current directory as mock paths
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ProjectLocalCache Unit Tests', () {
    late ProjectLocalCache cache;

    setUp(() {
      cache = ProjectLocalCache();
    });

    tearDown(() async {
      await cache.clearAll();
    });

    test('Initial cache is empty and structured properly', () async {
      final data = await cache.loadCache();
      expect(data['projects'], isEmpty);
      expect(data['rooms'], isEmpty);
      expect(data['measurements'], isEmpty);
      expect(data['layouts'], isEmpty);
      expect(data['lastSyncTime'], isNull);
    });

    test('Save and load cache updates successfully', () async {
      final mockData = {
        'projects': {
          'p-1': {'id': 'p-1', 'project_name': 'Offline House'}
        },
        'rooms': {
          'p-1': [
            {'id': 'r-1', 'room_name': 'Offline Living Room'}
          ]
        },
        'measurements': {
          'r-1': {'length': 500.0, 'width': 400.0, 'height': 300.0}
        },
        'layouts': {'r-1': '{"walls":[]}'},
        'lastSyncTime': '2026-08-10T10:00:00Z',
      };

      await cache.saveCache(mockData);
      final loaded = await cache.loadCache();

      expect(loaded['projects']['p-1']['project_name'], equals('Offline House'));
      expect(loaded['rooms']['p-1'][0]['room_name'], equals('Offline Living Room'));
      expect(loaded['measurements']['r-1']['length'], equals(500.0));
      expect(loaded['layouts']['r-1'], equals('{"walls":[]}'));
      expect(loaded['lastSyncTime'], equals('2026-08-10T10:00:00Z'));
    });

    test('Save and load pending sync actions queue', () async {
      final mockQueue = [
        {
          'id': 'act_1',
          'action': 'CREATE_PROJECT',
          'projectId': 'local_proj_123',
          'payload': {'project_name': 'Offline Project'},
          'timestamp': '2026-08-10T10:00:00Z'
        }
      ];

      await cache.saveQueue(mockQueue);
      final loadedQueue = await cache.loadQueue();

      expect(loadedQueue, hasLength(1));
      expect(loadedQueue[0]['action'], equals('CREATE_PROJECT'));
      expect(loadedQueue[0]['projectId'], equals('local_proj_123'));
    });
  });

  group('ProjectSyncRepository Unit Tests', () {
    late ProjectSyncRepository repository;
    late ProjectLocalCache cache;

    setUp(() async {
      repository = ProjectSyncRepository();
      cache = ProjectLocalCache();
      await cache.clearAll();
    });

    tearDown(() async {
      await cache.clearAll();
    });

    test('Creating project offline writes to local cache and appends to action queue', () async {
      final tempId = await repository.createProject(
        projectName: 'Offline Mansion',
        description: 'No internet connection test',
        location: 'Space',
      );

      expect(tempId, startsWith('local_proj_'));

      // Check cache content
      final currentCache = await cache.loadCache();
      expect(currentCache['projects'].containsKey(tempId), isTrue);
      expect(currentCache['projects'][tempId]['project_name'], equals('Offline Mansion'));

      // Check queue content
      final queue = await cache.loadQueue();
      expect(queue, hasLength(1));
      expect(queue[0]['action'], equals('CREATE_PROJECT'));
      expect(queue[0]['projectId'], equals(tempId));
      expect(queue[0]['payload']['project_name'], equals('Offline Mansion'));
    });

    test('Creating room offline updates cache and registers queue action', () async {
      final tempRoomId = await repository.createRoom(
        'local_proj_111',
        roomName: 'Sync Bedroom',
        roomType: 'Bedroom',
        floorNumber: 2,
        notes: 'Offline room creation notes',
        roomColor: '#00FF00',
        properties: '{"walls":[]}',
      );

      expect(tempRoomId, startsWith('local_room_'));

      final currentCache = await cache.loadCache();
      expect(currentCache['rooms']['local_proj_111'], hasLength(1));
      expect(currentCache['rooms']['local_proj_111'][0]['room_name'], equals('Sync Bedroom'));
      expect(currentCache['layouts'][tempRoomId], equals('{"walls":[]}'));

      final queue = await cache.loadQueue();
      expect(queue, hasLength(1));
      expect(queue[0]['action'], equals('CREATE_ROOM'));
      expect(queue[0]['roomId'], equals(tempRoomId));
    });
  });
}
