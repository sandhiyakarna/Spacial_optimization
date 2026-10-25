import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowspace_frontend/features/designer/bridge/renderer_command.dart';
import 'package:flowspace_frontend/features/designer/bridge/renderer_event.dart';
import 'package:flowspace_frontend/features/designer/bridge/bridge_client_stub.dart';
import 'package:flowspace_frontend/features/designer/bridge/viewport_controller.dart';
import 'package:flowspace_frontend/features/designer/bridge/bridge_client.dart';

void main() {
  group('GPU Performance Optimization Command Tests', () {
    late StubBridgeClient mockBridge;
    late ProviderContainer container;

    setUp(() {
      mockBridge = StubBridgeClient();
    });

    tearDown(() {
      container.dispose();
    });

    test('Sending CLEANUP_MEMORY command dispatches correct payload', () async {
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

      // Simulate handshake complete
      final readyEvent = RendererEvent(
        type: 'READY',
        transactionId: 'hs_1',
        payload: {'status': 'ready'},
      );
      mockBridge.simulateMessageFromRenderer(readyEvent.toJsonString());
      await Future.value(); // process microtasks

      sentMessages.clear(); // Clear initial messages (HELLO, ACKs)

      controller.sendCommand('CLEANUP_MEMORY', {});

      expect(sentMessages.length, 1);
      final cmd = RendererCommand.fromJson(jsonDecode(sentMessages.first));
      expect(cmd.type, 'CLEANUP_MEMORY');
      expect(cmd.payload, isEmpty);
    });

    test('Sending TOGGLE_FPS command dispatches correct payload', () async {
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
      await Future.value();

      final readyEvent = RendererEvent(
        type: 'READY',
        transactionId: 'hs_1',
        payload: {'status': 'ready'},
      );
      mockBridge.simulateMessageFromRenderer(readyEvent.toJsonString());
      await Future.value();

      sentMessages.clear();

      controller.sendCommand('TOGGLE_FPS', {'enabled': true});

      expect(sentMessages.length, 1);
      final cmd = RendererCommand.fromJson(jsonDecode(sentMessages.first));
      expect(cmd.type, 'TOGGLE_FPS');
      expect(cmd.payload['enabled'], isTrue);
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
