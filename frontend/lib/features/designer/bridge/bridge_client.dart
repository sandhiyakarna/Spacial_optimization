import 'package:flutter/widgets.dart';
import 'bridge_client_stub.dart'
    if (dart.library.html) 'bridge_client_web.dart'
    if (dart.library.io) 'bridge_client_native.dart';

abstract class BridgeClient {
  /// Stream of raw messages received from the renderer
  Stream<String> get onMessage;

  /// Initialize any event listeners or setups
  void initialize();

  /// Platform-independent initialization method
  void initialization();

  /// Send a command payload to the renderer
  void sendJson(String payload);

  /// Platform-independent send method
  void send(String message);

  /// Platform-independent receive method returning message stream
  Stream<String> receive();

  /// Build the widget containing the platform viewport (HtmlElementView or WebView)
  Widget buildViewport(BuildContext context);

  /// Dispose any resources/controllers
  void dispose();

  /// Factory constructor that returns the platform-specific implementation
  factory BridgeClient() => createBridgeClient();
}

