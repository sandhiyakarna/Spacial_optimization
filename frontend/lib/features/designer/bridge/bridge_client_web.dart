// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';
import 'bridge_client.dart';
import 'renderer_command.dart';

BridgeClient createBridgeClient() => WebBridgeClient();

class WebBridgeClient implements BridgeClient {
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  html.IFrameElement? _iframeElement;
  StreamSubscription<html.Event>? _messageSubscription;
  static const String _viewType = 'gpu-viewport-iframe';
  static bool _factoryRegistered = false;

  @override
  Stream<String> get onMessage => _messageController.stream;

  @override
  void initialize() {
    // Register the iframe view factory if not already registered
    if (!_factoryRegistered) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final iframe = html.IFrameElement()
          ..src = 'renderer_sandbox.html'
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.backgroundColor = 'transparent'
          ..attributes['allow'] = 'webgl'
          ..id = 'gpu-viewport-iframe-el';
        _iframeElement = iframe;
        return iframe;
      });
      _factoryRegistered = true;
    }

    // Set up the listener on window messages
    _messageSubscription = html.window.onMessage.listen((html.MessageEvent event) {
      final Object? data = event.data;
      if (data is String) {
        // Pass to the stream controller if it's active
        if (!_messageController.isClosed) {
          _messageController.add(data);
        }
      }
    });
  }

  @override
  void initialization() {
    initialize();
  }

  @override
  void sendJson(String payload) {
    if (_iframeElement != null && _iframeElement!.contentWindow != null) {
      _iframeElement!.contentWindow!.postMessage(payload, '*');
    } else {
      // If the iframe element is not ready or cached yet, try to find it in the DOM
      final element = html.document.getElementById('gpu-viewport-iframe-el');
      if (element is html.IFrameElement && element.contentWindow != null) {
        element.contentWindow!.postMessage(payload, '*');
      }
    }
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
    if (_iframeElement != null) {
      _iframeElement!
        ..style.backgroundColor = 'transparent'
        ..attributes['allow'] = 'webgl';
    }
    return const HtmlElementView(viewType: _viewType);
  }

  @override
  void dispose() {
    try {
      final disposeCmd = RendererCommand(
        type: 'DISPOSE',
        transactionId: 'disp_${DateTime.now().millisecondsSinceEpoch}',
        payload: {},
      );
      sendJson(disposeCmd.toJsonString());
    } catch (_) {}
    _messageSubscription?.cancel();
    _messageController.close();
  }
}
