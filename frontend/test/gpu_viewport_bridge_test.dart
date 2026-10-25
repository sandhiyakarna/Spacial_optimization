import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowspace_frontend/features/designer/bridge/renderer_command.dart';
import 'package:flowspace_frontend/features/designer/bridge/renderer_event.dart';
import 'package:flowspace_frontend/features/designer/bridge/bridge_client_stub.dart';
import 'package:flowspace_frontend/features/designer/bridge/viewport_controller.dart';
import 'package:flowspace_frontend/features/designer/bridge/bridge_client.dart';
import 'package:flowspace_frontend/features/designer/providers/designer_provider.dart';
import 'package:flowspace_frontend/features/designer/providers/lighting_provider.dart';
import 'package:flutter/widgets.dart';

void main() {
  group('RendererCommand and RendererEvent Serialization', () {
    test('RendererCommand toJson and fromJson', () {
      final cmd = RendererCommand(
        type: 'LOAD_ROOM',
        transactionId: 'tx_123',
        payload: {
          'roomId': 'room_abc',
          'dimensions': {'width': 600.0, 'height': 300.0}
        },
      );

      final jsonStr = cmd.toJsonString();
      final decodedMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      final redecoded = RendererCommand.fromJson(decodedMap);

      expect(redecoded.type, 'LOAD_ROOM');
      expect(redecoded.transactionId, 'tx_123');
      expect(redecoded.version, '1.0.0');
      expect(redecoded.payload['roomId'], 'room_abc');
      expect(redecoded.payload['dimensions']['width'], 600.0);
      expect(redecoded.timestamp, isA<int>());
    });

    test('RendererEvent toJson and fromJson', () {
      final event = RendererEvent(
        type: 'OBJECT_MOVED',
        transactionId: 'tx_456',
        payload: {
          'id': 'sofa_01',
          'position': {'x': 100.0, 'y': 0.0, 'z': 200.0}
        },
      );

      final jsonStr = event.toJsonString();
      final decodedMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      final redecoded = RendererEvent.fromJson(decodedMap);

      expect(redecoded.type, 'OBJECT_MOVED');
      expect(redecoded.transactionId, 'tx_456');
      expect(redecoded.version, '1.0.0');
      expect(redecoded.payload['id'], 'sofa_01');
      expect(redecoded.payload['position']['x'], 100.0);
    });
  });

  group('ViewportController Integration Tests', () {
    late StubBridgeClient mockBridge;
    late ProviderContainer container;

    setUp(() {
      mockBridge = StubBridgeClient();
    });

    tearDown(() {
      container.dispose();
    });

    test('Initialization starts connecting and sends HELLO', () async {
      final sentMessages = <String>[];
      
      final controllerBridge = _TestBridgeClient(mockBridge, (payload) {
        sentMessages.add(payload);
      });

      container = ProviderContainer(
        overrides: [
          bridgeClientProvider.overrideWithValue(controllerBridge),
        ],
      );

      container.read(viewportControllerProvider.notifier);

      // Wait a microtask for the startHandshake scheduleMicrotask to fire
      await Future.value();

      expect(container.read(viewportControllerProvider).status, RendererState.LOADING);
      expect(container.read(viewportControllerProvider).isConnecting, isTrue);
      expect(container.read(viewportControllerProvider).isRendererReady, isFalse);
      expect(sentMessages.length, 1);

      final cmd = RendererCommand.fromJson(jsonDecode(sentMessages.first));
      expect(cmd.type, 'HELLO');
      expect(cmd.payload['clientVersion'], '1.0.0');
    });

    test('Receiving READY establishes ready state, sends ACK, and flushes queue', () async {
      final sentMessages = <String>[];
      final controllerBridge = _TestBridgeClient(mockBridge, (payload) {
        sentMessages.add(payload);
      });

      container = ProviderContainer(
        overrides: [
          bridgeClientProvider.overrideWithValue(controllerBridge),
        ],
      );

      final controller = container.read(viewportControllerProvider.notifier);
      await Future.value(); // microtask

      // Queue some commands while not ready
      controller.sendCommand('LOAD_ROOM', {'roomId': 'test_room'});
      controller.sendCommand('SELECT_OBJECT', {'id': 'chair_01'});

      expect(controller.commandQueue.length, 2);
      expect(sentMessages.length, 1); // Only HELLO sent so far

      // Retrieve transaction id of HELLO
      final helloCmd = RendererCommand.fromJson(jsonDecode(sentMessages.first));
      final hsTxId = helloCmd.transactionId;

      // Simulate READY from renderer
      final readyEvent = RendererEvent(
        type: 'READY',
        transactionId: hsTxId,
        payload: {'status': 'ready'},
      );
      mockBridge.simulateMessageFromRenderer(readyEvent.toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      expect(container.read(viewportControllerProvider).status, RendererState.BUSY);
      expect(container.read(viewportControllerProvider).isRendererReady, isTrue);
      expect(container.read(viewportControllerProvider).isConnecting, isFalse);
      expect(controller.commandQueue, isEmpty);

      // Verify handshake flow: HELLO (0) -> ACK (1) -> LOAD_ROOM (2) -> SELECT_OBJECT (3)
      expect(sentMessages.length, 4);

      final ackCmd = RendererCommand.fromJson(jsonDecode(sentMessages[1]));
      expect(ackCmd.type, 'ACK');
      expect(ackCmd.transactionId, hsTxId);

      final cmd1 = RendererCommand.fromJson(jsonDecode(sentMessages[2]));
      expect(cmd1.type, 'LOAD_ROOM');
      expect(cmd1.payload['roomId'], 'test_room');

      final cmd2 = RendererCommand.fromJson(jsonDecode(sentMessages[3]));
      expect(cmd2.type, 'SELECT_OBJECT');
      expect(cmd2.payload['id'], 'chair_01');

      // Simulate ACKs for both queued commands to transition state back to READY
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'ACK',
        transactionId: cmd1.transactionId,
      ).toJsonString());
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'ACK',
        transactionId: cmd2.transactionId,
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      expect(container.read(viewportControllerProvider).status, RendererState.READY);
    });

    test('Commands sent after ready status are sent immediately and track pending transactions with BUSY state', () async {
      final sentMessages = <String>[];
      final controllerBridge = _TestBridgeClient(mockBridge, (payload) {
        sentMessages.add(payload);
      });

      container = ProviderContainer(
        overrides: [
          bridgeClientProvider.overrideWithValue(controllerBridge),
        ],
      );

      final controller = container.read(viewportControllerProvider.notifier);
      await Future.value(); // microtask

      // Complete handshake
      final helloCmd = RendererCommand.fromJson(jsonDecode(sentMessages.first));
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'READY',
        transactionId: helloCmd.transactionId,
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      sentMessages.clear();

      // Send a command now that renderer is ready
      final txId = controller.sendCommand('UPDATE_MATERIAL', {'color': '#ff0000'});

      expect(sentMessages.length, 1);
      final sentCmd = RendererCommand.fromJson(jsonDecode(sentMessages.first));
      expect(sentCmd.type, 'UPDATE_MATERIAL');
      expect(sentCmd.transactionId, txId);
      expect(controller.pendingTransactions.contains(txId), isTrue);

      // Verify status transitions to BUSY
      expect(container.read(viewportControllerProvider).status, RendererState.BUSY);
      expect(container.read(viewportControllerProvider).isRendererReady, isTrue);

      // Simulate ACK
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'ACK',
        transactionId: txId,
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      expect(controller.pendingTransactions.contains(txId), isFalse);
      
      // Verify status transitions back to READY
      expect(container.read(viewportControllerProvider).status, RendererState.READY);
    });

    test('Handshake timeout triggers reconnection loop up to 3 attempts and sets ERROR', () async {
      final sentMessages = <String>[];
      final controllerBridge = _TestBridgeClient(mockBridge, (payload) {
        sentMessages.add(payload);
      });

      container = ProviderContainer(
        overrides: [
          bridgeClientProvider.overrideWithValue(controllerBridge),
        ],
      );

      final controller = container.read(viewportControllerProvider.notifier);
      controller.handshakeTimeout = const Duration(milliseconds: 20);
      controller.ackTimeout = const Duration(milliseconds: 20);
      
      await Future.value(); // microtask

      // Wait for reconnect attempts to exhaust (initially starts, then 3 retries, total 4 attempts)
      await Future.delayed(const Duration(milliseconds: 150));

      expect(container.read(viewportControllerProvider).reconnectAttempts, 3);
      expect(container.read(viewportControllerProvider).status, RendererState.ERROR);
      expect(container.read(viewportControllerProvider).isConnecting, isFalse);
      expect(container.read(viewportControllerProvider).isRendererReady, isFalse);
      expect(container.read(viewportControllerProvider).lastError, contains('Connection failed after max reconnect attempts'));
    });

    test('Command ACK timeout triggers reconnect and sets ERROR', () async {
      final sentMessages = <String>[];
      final controllerBridge = _TestBridgeClient(mockBridge, (payload) {
        sentMessages.add(payload);
      });

      container = ProviderContainer(
        overrides: [
          bridgeClientProvider.overrideWithValue(controllerBridge),
        ],
      );

      final controller = container.read(viewportControllerProvider.notifier);
      controller.handshakeTimeout = const Duration(seconds: 1);
      controller.ackTimeout = const Duration(milliseconds: 25);
      
      await Future.value(); // microtask

      // Complete handshake
      final helloCmd = RendererCommand.fromJson(jsonDecode(sentMessages.first));
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'READY',
        transactionId: helloCmd.transactionId,
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      // Send command
      final txId = controller.sendCommand('REMOVE_MODEL', {'id': 'sofa_02'});
      expect(controller.pendingTransactions.contains(txId), isTrue);

      // Wait for ACK timeout (25ms)
      await Future.delayed(const Duration(milliseconds: 45));

      // Command should time out, trigger reconnect (status becomes LOADING, then it fails or keeps retrying)
      expect(controller.pendingTransactions.contains(txId), isFalse);
      expect(container.read(viewportControllerProvider).reconnectAttempts, 1);
      expect(container.read(viewportControllerProvider).status, RendererState.LOADING);
      expect(container.read(viewportControllerProvider).isConnecting, isTrue);
      expect(container.read(viewportControllerProvider).isRendererReady, isFalse);
      expect(container.read(viewportControllerProvider).lastError, contains('ACK timed out'));
    });

    test('Lighting commands are sent correctly after handshake', () async {
      final sentMessages = <String>[];
      final controllerBridge = _TestBridgeClient(mockBridge, (payload) {
        sentMessages.add(payload);
      });

      container = ProviderContainer(
        overrides: [
          bridgeClientProvider.overrideWithValue(controllerBridge),
        ],
      );

      final controller = container.read(viewportControllerProvider.notifier);
      await Future.value(); // microtask

      // Complete handshake
      final helloCmd = RendererCommand.fromJson(jsonDecode(sentMessages.first));
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'READY',
        transactionId: helloCmd.transactionId,
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      sentMessages.clear();

      // Send UPDATE_LIGHT
      controller.sendCommand('UPDATE_LIGHT', {
        'id': 'test_light',
        'type': 'directional',
        'intensity': 1.2,
      });

      // Send REMOVE_LIGHT
      controller.sendCommand('REMOVE_LIGHT', {'id': 'test_light'});

      // Send TOGGLE_SHADOWS
      controller.sendCommand('TOGGLE_SHADOWS', {'enabled': false});

      expect(sentMessages.length, 3);

      final cmd1 = RendererCommand.fromJson(jsonDecode(sentMessages[0]));
      expect(cmd1.type, 'UPDATE_LIGHT');
      expect(cmd1.payload['id'], 'test_light');
      expect(cmd1.payload['type'], 'directional');
      expect(cmd1.payload['intensity'], 1.2);

      final cmd2 = RendererCommand.fromJson(jsonDecode(sentMessages[1]));
      expect(cmd2.type, 'REMOVE_LIGHT');
      expect(cmd2.payload['id'], 'test_light');

      final cmd3 = RendererCommand.fromJson(jsonDecode(sentMessages[2]));
      expect(cmd3.type, 'TOGGLE_SHADOWS');
      expect(cmd3.payload['enabled'], false);
    });

    test('Receiving PING event triggers PONG command response', () async {
      final sentMessages = <String>[];
      final controllerBridge = _TestBridgeClient(mockBridge, (payload) {
        sentMessages.add(payload);
      });

      container = ProviderContainer(
        overrides: [
          bridgeClientProvider.overrideWithValue(controllerBridge),
        ],
      );

      container.read(viewportControllerProvider.notifier);
      await Future.value(); // microtask

      // Complete handshake first so connection is ready
      final helloCmd = RendererCommand.fromJson(jsonDecode(sentMessages.first));
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'READY',
        transactionId: helloCmd.transactionId,
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      sentMessages.clear();

      // Simulate receiving PING from renderer
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'PING',
        transactionId: 'ping_test_123',
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      // Viewport controller should have sent a PONG command back
      expect(sentMessages.length, 1);
      final responseCmd = RendererCommand.fromJson(jsonDecode(sentMessages.first));
      expect(responseCmd.type, 'PONG');
      expect(responseCmd.transactionId, 'ping_test_123');
    });

    test('LOAD_ROOM command sends full payload with room layout and materials', () async {
      final sentMessages = <String>[];
      final controllerBridge = _TestBridgeClient(mockBridge, (payload) {
        sentMessages.add(payload);
      });

      container = ProviderContainer(
        overrides: [
          bridgeClientProvider.overrideWithValue(controllerBridge),
        ],
      );

      final controller = container.read(viewportControllerProvider.notifier);
      await Future.value(); // microtask

      // Complete handshake first so connection is ready
      final helloCmd = RendererCommand.fromJson(jsonDecode(sentMessages.first));
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'READY',
        transactionId: helloCmd.transactionId,
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      sentMessages.clear();

      // Send LOAD_ROOM command
      final roomPayload = {
        'walls': [
          {'x1': 0.0, 'y1': 0.0, 'x2': 600.0, 'y2': 0.0, 'thickness': 10.0}
        ],
        'openings': [
          {'id': 'door_1', 'type': 'door', 'x': 300.0, 'y': 0.0, 'width': 80.0, 'angle': 0.0}
        ],
        'openDoorIds': ['door_1'],
        'floorMaterialColor': '#ff0000',
        'floorMaterialType': 'wood',
        'floorMetallic': 0.1,
        'floorRoughness': 0.5,
        'wallMaterialColor': '#00ff00',
        'wallMaterialType': 'paint',
        'wallMetallic': 0.0,
        'wallRoughness': 0.9,
        'ceilingMaterialColor': '#0000ff',
        'ceilingMaterialType': 'plaster',
        'ceilingMetallic': 0.0,
        'ceilingRoughness': 0.8,
        'showCeiling': true,
      };

      controller.sendCommand('LOAD_ROOM', roomPayload);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(sentMessages.length, 1);
      final cmd = RendererCommand.fromJson(jsonDecode(sentMessages.first));
      expect(cmd.type, 'LOAD_ROOM');
      expect(cmd.payload['floorMaterialColor'], '#ff0000');
      expect(cmd.payload['openDoorIds'], contains('door_1'));
      expect(cmd.payload['walls'].first['x1'], 0.0);
    });
  });

  group('Interactive Object Editing Events in ViewportController', () {
    late StubBridgeClient mockBridge;
    late ProviderContainer container;

    setUp(() {
      mockBridge = StubBridgeClient();
    });

    tearDown(() {
      container.dispose();
    });

    test('Receiving OBJECT_SELECTED and OBJECT_DESELECTED updates designer selection state', () async {
      final sentMessages = <String>[];
      final controllerBridge = _TestBridgeClient(mockBridge, (payload) {
        sentMessages.add(payload);
      });

      container = ProviderContainer(
        overrides: [
          bridgeClientProvider.overrideWithValue(controllerBridge),
        ],
      );

      container.read(viewportControllerProvider.notifier);
      await Future.value(); // microtask

      // Complete handshake
      final helloCmd = RendererCommand.fromJson(jsonDecode(sentMessages.first));
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'READY',
        transactionId: helloCmd.transactionId,
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      // 1. Simulate selection from viewport
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'OBJECT_SELECTED',
        payload: {'id': 'sofa_01'},
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      expect(container.read(designerProvider).selectedFurnitureId, 'sofa_01');

      // 2. Simulate deselection
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'OBJECT_DESELECTED',
        payload: {'id': 'sofa_01'},
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      expect(container.read(designerProvider).selectedFurnitureId, isNull);
    });

    test('Receiving OBJECT_MOVED, OBJECT_ROTATED, and OBJECT_SCALED updates furniture transform', () async {
      final sentMessages = <String>[];
      final controllerBridge = _TestBridgeClient(mockBridge, (payload) {
        sentMessages.add(payload);
      });

      container = ProviderContainer(
        overrides: [
          bridgeClientProvider.overrideWithValue(controllerBridge),
        ],
      );

      container.read(viewportControllerProvider.notifier);
      await Future.value(); // microtask

      // Complete handshake
      final helloCmd = RendererCommand.fromJson(jsonDecode(sentMessages.first));
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'READY',
        transactionId: helloCmd.transactionId,
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      // Pre-populate furniture in the designer
      final designerNotifier = container.read(designerProvider.notifier);
      
      // Add a piece of furniture using the standard addFurniture API with MockAsset
      designerNotifier.addFurniture(
        MockAsset(id: 'sofa_asset', name: 'Sofa', width: 100.0, depth: 100.0, height: 80.0),
        0.0,
        0.0,
      );

      final newId = container.read(designerProvider).selectedFurnitureId!;

      // 1. OBJECT_MOVED event
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'OBJECT_MOVED',
        payload: {
          'id': newId,
          'x': 150.0,
          'y': 10.0,
          'z': 250.0,
        },
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      var sofa = container.read(designerProvider).furniture.firstWhere((f) => f.id == newId);
      expect(sofa.x, 150.0);
      expect(sofa.y, 10.0);
      expect(sofa.z, 250.0);

      // 2. OBJECT_ROTATED event
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'OBJECT_ROTATED',
        payload: {
          'id': newId,
          'rotationX': 1.1,
          'rotationY': 2.2,
          'rotationZ': 3.3,
        },
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      sofa = container.read(designerProvider).furniture.firstWhere((f) => f.id == newId);
      expect(sofa.rotationX, 1.1);
      expect(sofa.rotationY, 2.2);
      expect(sofa.rotationZ, 3.3);

      // 3. OBJECT_SCALED event
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'OBJECT_SCALED',
        payload: {
          'id': newId,
          'scaleX': 1.5,
          'scaleY': 1.2,
          'scaleZ': 1.8,
        },
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      sofa = container.read(designerProvider).furniture.firstWhere((f) => f.id == newId);
      expect(sofa.scaleX, 1.5);
      expect(sofa.scaleY, 1.2);
      expect(sofa.scaleZ, 1.8);
    });

    test('Receiving light source interactive events updates lighting state', () async {
      final sentMessages = <String>[];
      final controllerBridge = _TestBridgeClient(mockBridge, (payload) {
        sentMessages.add(payload);
      });

      container = ProviderContainer(
        overrides: [
          bridgeClientProvider.overrideWithValue(controllerBridge),
        ],
      );

      container.read(viewportControllerProvider.notifier);
      await Future.value(); // microtask

      // Complete handshake
      final helloCmd = RendererCommand.fromJson(jsonDecode(sentMessages.first));
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'READY',
        transactionId: helloCmd.transactionId,
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      // 1. OBJECT_SELECTED event for a light source ID
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'OBJECT_SELECTED',
        payload: {'id': 'light_12345'},
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      expect(container.read(lightingProvider).selectedLightId, 'light_12345');
      expect(container.read(designerProvider).selectedFurnitureId, isNull);

      // Pre-add a light source in lighting provider with ID 'light_12345'
      final lightingNotifier = container.read(lightingProvider.notifier);
      lightingNotifier.updateLight('sun_global', rotationX: 0.1, rotationY: 0.2);

      // 2. OBJECT_MOVED event for 'sun_global'
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'OBJECT_MOVED',
        payload: {
          'id': 'sun_global',
          'x': 100.0,
          'y': 200.0,
          'z': 300.0,
        },
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      final sunLightMoved = container.read(lightingProvider).lights.firstWhere((l) => l.id == 'sun_global');
      expect(sunLightMoved.x, 100.0);
      expect(sunLightMoved.y, 200.0);
      expect(sunLightMoved.z, 300.0);

      // 3. OBJECT_ROTATED event for 'sun_global'
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'OBJECT_ROTATED',
        payload: {
          'id': 'sun_global',
          'rotationX': 0.5,
          'rotationY': 0.6,
          'rotationZ': 0.7,
        },
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      final sunLightRotated = container.read(lightingProvider).lights.firstWhere((l) => l.id == 'sun_global');
      expect(sunLightRotated.rotationX, 0.5);
      expect(sunLightRotated.rotationY, 0.6);
      expect(sunLightRotated.rotationZ, 0.7);

      // 4. OBJECT_DESELECTED event
      mockBridge.simulateMessageFromRenderer(RendererEvent(
        type: 'OBJECT_DESELECTED',
        payload: {'id': 'light_12345'},
      ).toJsonString());
      await Future.delayed(const Duration(milliseconds: 10));

      expect(container.read(lightingProvider).selectedLightId, isNull);
    });
  });
}

class _TestBridgeClient implements BridgeClient {
  final StubBridgeClient _inner;
  final void Function(String payload) _onSend;

  _TestBridgeClient(this._inner, this._onSend);

  @override
  Stream<String> get onMessage => _inner.onMessage;

  @override
  void initialize() => _inner.initialize();

  @override
  void initialization() => _inner.initialization();

  @override
  void sendJson(String payload) {
    _onSend(payload);
    _inner.sendJson(payload);
  }

  @override
  void send(String message) {
    _onSend(message);
    _inner.send(message);
  }

  @override
  Stream<String> receive() => _inner.receive();

  @override
  Widget buildViewport(BuildContext context) => _inner.buildViewport(context);

  @override
  void dispose() => _inner.dispose();
}

class MockAsset {
  final String id;
  final String name;
  final double width;
  final double depth;
  final double height;
  MockAsset({
    required this.id,
    required this.name,
    required this.width,
    required this.depth,
    required this.height,
  });
}
