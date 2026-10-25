import 'dart:async';
import 'package:flutter/widgets.dart';
import 'bridge_client.dart';

BridgeClient createBridgeClient() => StubBridgeClient();

class StubBridgeClient implements BridgeClient {
  final StreamController<String> _messageController = StreamController<String>.broadcast();

  @override
  Stream<String> get onMessage => _messageController.stream;

  @override
  void initialize() {
    // No-op stub
  }

  @override
  void initialization() {
    initialize();
  }

  @override
  void sendJson(String payload) {
    // No-op stub
  }

  @override
  void send(String message) {
    sendJson(message);
  }

  @override
  Stream<String> receive() {
    return onMessage;
  }

  @override
  Widget buildViewport(BuildContext context) {
    return const Center(
      child: Text('GPU Viewport is not supported on this platform.'),
    );
  }

  @override
  void dispose() {
    _messageController.close();
  }

  /// Helper to simulate messages for testing
  void simulateMessageFromRenderer(String payload) {
    if (!_messageController.isClosed) {
      _messageController.add(payload);
    }
  }
}
