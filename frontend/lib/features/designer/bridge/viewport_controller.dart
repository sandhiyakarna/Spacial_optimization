import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'bridge_client.dart';
import 'renderer_command.dart';
import 'renderer_event.dart';
import '../providers/designer_provider.dart';
import '../providers/lighting_provider.dart';

enum RendererState {
  READY,
  LOADING,
  BUSY,
  ERROR,
  DISCONNECTED,
}

// Provider for BridgeClient so it can be overridden in tests
final bridgeClientProvider = Provider<BridgeClient>((ref) {
  final client = BridgeClient();
  ref.onDispose(() => client.dispose());
  return client;
});

@immutable
class ViewportState {
  final RendererState status;
  final String? lastError;
  final int reconnectAttempts;
  final String? generatedImageDataUrl;

  const ViewportState({
    this.status = RendererState.DISCONNECTED,
    this.lastError,
    this.reconnectAttempts = 0,
    this.generatedImageDataUrl,
  });

  bool get isRendererReady => status == RendererState.READY || status == RendererState.BUSY;
  bool get isConnecting => status == RendererState.LOADING;

  ViewportState copyWith({
    RendererState? status,
    bool? isRendererReady,
    bool? isConnecting,
    String? lastError,
    int? reconnectAttempts,
    String? generatedImageDataUrl,
  }) {
    RendererState resolvedStatus = status ?? this.status;
    if (status == null) {
      if (isRendererReady == true) {
        resolvedStatus = RendererState.READY;
      } else if (isConnecting == true) {
        resolvedStatus = RendererState.LOADING;
      } else if (isRendererReady == false && isConnecting == false && resolvedStatus == RendererState.READY) {
        resolvedStatus = RendererState.DISCONNECTED;
      }
    }
    return ViewportState(
      status: resolvedStatus,
      lastError: lastError ?? this.lastError,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      generatedImageDataUrl: generatedImageDataUrl ?? this.generatedImageDataUrl,
    );
  }

  @override
  String toString() {
    return 'ViewportState(status: $status, lastError: $lastError, reconnectAttempts: $reconnectAttempts)';
  }
}

class ViewportController extends Notifier<ViewportState> {
  late BridgeClient _bridge;
  StreamSubscription<String>? _bridgeSubscription;

  Duration handshakeTimeout = const Duration(seconds: 5);
  Duration ackTimeout = const Duration(seconds: 2);

  // Handshake and connection timers
  Timer? _handshakeTimer;
  final Map<String, Timer> _transactionTimers = {};

  // Queues and transaction states
  final List<RendererCommand> _commandQueue = [];
  final List<RendererEvent> _eventQueue = [];
  final Set<String> _pendingTransactions = {};

  int _transactionCounter = 0;
  bool _disposed = false;

  // Getters for testing and debugging
  List<RendererCommand> get commandQueue => List.unmodifiable(_commandQueue);
  List<RendererEvent> get eventQueue => List.unmodifiable(_eventQueue);
  Set<String> get pendingTransactions => Set.unmodifiable(_pendingTransactions);
  BridgeClient get bridge => _bridge;

  @override
  ViewportState build() {
    _bridge = ref.watch(bridgeClientProvider);
    _bridge.initialization();

    _bridgeSubscription = _bridge.receive().listen(
      _handleRawMessage,
      onError: (err) {
        state = state.copyWith(status: RendererState.DISCONNECTED);
        _setError('Bridge stream error: $err');
        _triggerReconnect();
      },
      onDone: () {
        if (!_disposed) {
          state = state.copyWith(status: RendererState.DISCONNECTED);
          _setError('Bridge stream closed.');
          _triggerReconnect();
        }
      },
    );

    // Start handshake on next microtask loop to avoid modifying state during provider build
    scheduleMicrotask(() {
      startHandshake();
    });

    ref.onDispose(() {
      _disposed = true;
      _cleanupTimersAndPending();
      _bridgeSubscription?.cancel();
    });

    return const ViewportState();
  }

  void startHandshake() {
    if (_disposed) return;
    _cancelHandshakeTimer();

    state = state.copyWith(
      status: RendererState.LOADING,
    );

    _transactionCounter++;
    final handshakeTxId = 'hs_$_transactionCounter';
    final handshakePing = RendererCommand(
      type: 'HELLO',
      transactionId: handshakeTxId,
      payload: {'clientVersion': '1.0.0'},
    );

    // Send immediately bypasses command queue
    _sendDirect(handshakePing);

    // Handshake timeout
    _handshakeTimer = Timer(handshakeTimeout, () {
      _handleHandshakeTimeout();
    });
  }

  void _handleHandshakeTimeout() {
    state = state.copyWith(status: RendererState.ERROR);
    _setError('Handshake timed out.');
    _triggerReconnect();
  }

  void _triggerReconnect() {
    if (_disposed) return;

    final nextAttempt = state.reconnectAttempts + 1;
    if (nextAttempt <= 3) {
      state = state.copyWith(
        reconnectAttempts: nextAttempt,
        status: RendererState.LOADING,
      );
      _cleanupTimersAndPending();
      _bridge.initialization();
      startHandshake();
    } else {
      state = state.copyWith(
        status: RendererState.ERROR,
        lastError: 'Connection failed after max reconnect attempts.',
      );
    }
  }

  void reconnect() {
    state = state.copyWith(reconnectAttempts: 0);
    _cleanupTimersAndPending();
    _bridge.initialization();
    startHandshake();
  }

  void _cleanupTimersAndPending() {
    _cancelHandshakeTimer();
    for (final timer in _transactionTimers.values) {
      timer.cancel();
    }
    _transactionTimers.clear();
    _pendingTransactions.clear();
  }

  void _cancelHandshakeTimer() {
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
  }

  /// Sends a command to the renderer, queueing it if the connection is not yet ready.
  String sendCommand(String type, Map<String, dynamic> payload) {
    if (_disposed) return '';

    _transactionCounter++;
    final txId = 'tx_$_transactionCounter';
    final command = RendererCommand(
      type: type,
      transactionId: txId,
      payload: payload,
    );

    if (state.isRendererReady) {
      _sendDirect(command);
    } else {
      _commandQueue.add(command);
    }

    return txId;
  }

  void _sendDirect(RendererCommand command) {
    try {
      _bridge.send(command.toJsonString());

      // Start ACK timeout timer for non-handshake and non-ACK commands
      if (command.type != 'HELLO' && command.type != 'ACK') {
        _pendingTransactions.add(command.transactionId);
        _transactionTimers[command.transactionId] = Timer(ackTimeout, () {
          _handleTransactionTimeout(command.transactionId);
        });

        // Transition to BUSY when we have active transactions
        if (state.status == RendererState.READY) {
          state = state.copyWith(status: RendererState.BUSY);
        }
      }
    } catch (e) {
      _setError('Failed to send command: $e');
    }
  }

  void _handleTransactionTimeout(String txId) {
    if (_pendingTransactions.contains(txId)) {
      _pendingTransactions.remove(txId);
      _transactionTimers.remove(txId)?.cancel();
      _setError('Transaction $txId ACK timed out.');
      state = state.copyWith(status: RendererState.ERROR);
      _triggerReconnect();
    }
  }

  void _handleRawMessage(String rawJson) {
    try {
      final Map<String, dynamic> data = jsonDecode(rawJson) as Map<String, dynamic>;
      final event = RendererEvent.fromJson(data);
      _handleEvent(event);
    } catch (e) {
      _setError('JSON decode error on message: $e');
    }
  }

  void _handleEvent(RendererEvent event) {
    // Add to event queue history
    _eventQueue.add(event);

    // Check protocol version
    if (event.version != '1.0.0') {
      _setError('Received event with unsupported protocol version: ${event.version}');
      return;
    }

    final txId = event.transactionId;

    // Handle ACKs
    if (event.type == 'ACK' && txId != null) {
      _pendingTransactions.remove(txId);
      _transactionTimers.remove(txId)?.cancel();

      // Return to READY if all pending transaction ACKs have been received
      if (_pendingTransactions.isEmpty && state.status == RendererState.BUSY) {
        state = state.copyWith(status: RendererState.READY);
      }
      return;
    }

    // Handle Handshake (READY event)
    if (event.type == 'READY') {
      _cancelHandshakeTimer();

      // Send ACK command to Renderer
      final ackCmd = RendererCommand(
        type: 'ACK',
        transactionId: txId ?? 'hs_ack',
        payload: {},
      );
      _sendDirect(ackCmd);

      state = state.copyWith(
        status: RendererState.READY,
        reconnectAttempts: 0,
      );
      _flushCommandQueue();
      return;
    }

    // Handle Legacy Handshake (HANDSHAKE_PONG) for backward compatibility
    if (event.type == 'HANDSHAKE_PONG') {
      _cancelHandshakeTimer();
      state = state.copyWith(
        status: RendererState.READY,
        reconnectAttempts: 0,
      );
      _flushCommandQueue();
      return;
    }

    // Handle standard PING command/event and respond with PONG
    if (event.type == 'PING') {
      final pongCmd = RendererCommand(
        type: 'PONG',
        transactionId: event.transactionId ?? 'pong_${DateTime.now().millisecondsSinceEpoch}',
        payload: {},
      );
      _sendDirect(pongCmd);
      return;
    }

    // Handle high-resolution image generated event
    if (event.type == 'IMAGE_GENERATED') {
      final dataUrl = event.payload['dataUrl'] as String?;
      if (dataUrl != null) {
        state = state.copyWith(generatedImageDataUrl: dataUrl);
      }
      return;
    }

    // Handle standard errors
    if (event.type == 'ERROR') {
      _setError('Renderer Error event: ${event.payload}');
      state = state.copyWith(status: RendererState.ERROR);
      return;
    }

    // Handle object selection from viewport
    if (event.type == 'OBJECT_SELECTED') {
      final id = event.payload['id'] as String?;
      if (id != null && id.isNotEmpty) {
        final isLight = id.startsWith('light_') || id == 'sun_global' || id == 'ambient_global';
        if (isLight) {
          ref.read(lightingProvider.notifier).selectLight(id);
          ref.read(designerProvider.notifier).deselectFurniture();
        } else {
          ref.read(designerProvider.notifier).selectFurniture(id);
          ref.read(lightingProvider.notifier).clearSelection();
        }
      } else {
        ref.read(designerProvider.notifier).deselectFurniture();
        ref.read(lightingProvider.notifier).clearSelection();
      }
      return;
    }

    // Handle object deselection from viewport
    if (event.type == 'OBJECT_DESELECTED') {
      ref.read(designerProvider.notifier).deselectFurniture();
      ref.read(lightingProvider.notifier).clearSelection();
      return;
    }

    // Handle object transform updates from viewport
    if (event.type == 'UPDATE_TRANSFORM') {
      final payload = event.payload;
      final id = payload['id'] as String?;
      final isLight = id != null && (id.startsWith('light_') || id == 'sun_global' || id == 'ambient_global');
      if (isLight) {
        ref.read(lightingProvider.notifier).updateLight(
          id,
          x: (payload['x'] as num?)?.toDouble(),
          y: (payload['y'] as num?)?.toDouble(),
          z: (payload['z'] as num?)?.toDouble(),
          rotationX: (payload['rotationX'] as num?)?.toDouble(),
          rotationY: (payload['rotationY'] as num?)?.toDouble(),
          rotationZ: (payload['rotationZ'] as num?)?.toDouble(),
        );
      } else {
        ref.read(designerProvider.notifier).updateSelectedFurnitureTransform(
          x: (payload['x'] as num?)?.toDouble(),
          y: (payload['y'] as num?)?.toDouble(),
          z: (payload['z'] as num?)?.toDouble(),
          rotationX: (payload['rotationX'] as num?)?.toDouble(),
          rotationY: (payload['rotationY'] as num?)?.toDouble(),
          rotationZ: (payload['rotationZ'] as num?)?.toDouble(),
          scaleX: (payload['scaleX'] as num?)?.toDouble(),
          scaleY: (payload['scaleY'] as num?)?.toDouble(),
          scaleZ: (payload['scaleZ'] as num?)?.toDouble(),
        );
      }
      return;
    }

    // Handle object translation
    if (event.type == 'OBJECT_MOVED') {
      final payload = event.payload;
      final id = payload['id'] as String?;
      final isLight = id != null && (id.startsWith('light_') || id == 'sun_global' || id == 'ambient_global');
      
      final positionMap = payload['position'] as Map?;
      final x = payload['x'] ?? positionMap?['x'];
      final y = payload['y'] ?? positionMap?['y'];
      final z = payload['z'] ?? positionMap?['z'];

      if (isLight) {
        ref.read(lightingProvider.notifier).updateLight(
          id,
          x: (x as num?)?.toDouble(),
          y: (y as num?)?.toDouble(),
          z: (z as num?)?.toDouble(),
        );
      } else {
        final selectedId = ref.read(designerProvider).selectedFurnitureId;
        if (id == selectedId || selectedId == null) {
          ref.read(designerProvider.notifier).updateSelectedFurnitureTransform(
            x: (x as num?)?.toDouble(),
            y: (y as num?)?.toDouble(),
            z: (z as num?)?.toDouble(),
          );
        }
      }
      return;
    }

    // Handle continuous drag moving
    if (event.type == 'OBJECT_MOVING') {
      final payload = event.payload;
      final x = (payload['x'] as num?)?.toDouble();
      final y = (payload['y'] as num?)?.toDouble();
      final z = (payload['z'] as num?)?.toDouble();
      if (x != null && z != null) {
        ref.read(designerProvider.notifier).updateSelectedFurnitureTransform(
          x: x,
          y: y,
          z: z,
        );
      }
      return;
    }

    // Handle placement blocked (revert)
    if (event.type == 'PLACEMENT_BLOCKED') {
      final payload = event.payload;
      final rx = (payload['revertedX'] as num?)?.toDouble();
      final ry = (payload['revertedY'] as num?)?.toDouble();
      final rz = (payload['revertedZ'] as num?)?.toDouble();
      if (rx != null && rz != null) {
        ref.read(designerProvider.notifier).updateSelectedFurnitureTransform(
          x: rx,
          y: ry,
          z: rz,
        );
      }
      return;
    }

    // Handle duplicate request from viewport
    if (event.type == 'DUPLICATE_REQUESTED') {
      ref.read(designerProvider.notifier).duplicateSelectedFurniture();
      return;
    }

    // Handle delete request from viewport
    if (event.type == 'DELETE_REQUESTED') {
      ref.read(designerProvider.notifier).deleteSelected();
      return;
    }

    // Handle object rotation
    if (event.type == 'OBJECT_ROTATED') {
      final payload = event.payload;
      final id = payload['id'] as String?;
      final isLight = id != null && (id.startsWith('light_') || id == 'sun_global' || id == 'ambient_global');

      final rotationMap = payload['rotation'] as Map?;
      final rx = payload['rotationX'] ?? rotationMap?['x'] ?? rotationMap?['rotationX'];
      final ry = payload['rotationY'] ?? rotationMap?['y'] ?? rotationMap?['rotationY'];
      final rz = payload['rotationZ'] ?? rotationMap?['z'] ?? rotationMap?['rotationZ'];

      if (isLight) {
        ref.read(lightingProvider.notifier).updateLight(
          id,
          rotationX: (rx as num?)?.toDouble(),
          rotationY: (ry as num?)?.toDouble(),
          rotationZ: (rz as num?)?.toDouble(),
        );
      } else {
        final selectedId = ref.read(designerProvider).selectedFurnitureId;
        if (id == selectedId || selectedId == null) {
          ref.read(designerProvider.notifier).updateSelectedFurnitureTransform(
            rotationX: (rx as num?)?.toDouble(),
            rotationY: (ry as num?)?.toDouble(),
            rotationZ: (rz as num?)?.toDouble(),
          );
        }
      }
      return;
    }

    // Handle object scale
    if (event.type == 'OBJECT_SCALED') {
      final payload = event.payload;
      final id = payload['id'] as String?;
      final selectedId = ref.read(designerProvider).selectedFurnitureId;
      if (id == selectedId || selectedId == null) {
        final scaleMap = payload['scale'] as Map?;
        final sx = payload['scaleX'] ?? scaleMap?['x'] ?? scaleMap?['scaleX'];
        final sy = payload['scaleY'] ?? scaleMap?['y'] ?? scaleMap?['scaleY'];
        final sz = payload['scaleZ'] ?? scaleMap?['z'] ?? scaleMap?['scaleZ'];
        ref.read(designerProvider.notifier).updateSelectedFurnitureTransform(
          scaleX: (sx as num?)?.toDouble(),
          scaleY: (sy as num?)?.toDouble(),
          scaleZ: (sz as num?)?.toDouble(),
        );
      }
      return;
    }
  }

  void _flushCommandQueue() {
    while (_commandQueue.isNotEmpty) {
      final cmd = _commandQueue.removeAt(0);
      _sendDirect(cmd);
    }
  }

  void _setError(String error) {
    if (state.lastError != error) {
      state = state.copyWith(lastError: error);
    }
    debugPrint('GPU Viewport Bridge Error: $error');
  }

  void clearError() {
    state = state.copyWith(lastError: null);
  }
}

final viewportControllerProvider = NotifierProvider<ViewportController, ViewportState>(() {
  return ViewportController();
});
