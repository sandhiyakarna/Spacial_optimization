import 'dart:convert';

class RendererEvent {
  final String type;
  final String? transactionId;
  final String version;
  final Map<String, dynamic> payload;
  final int timestamp;

  RendererEvent({
    required this.type,
    this.transactionId,
    this.version = '1.0.0',
    this.payload = const {},
    int? timestamp,
  }) : this.timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  factory RendererEvent.fromJson(Map<String, dynamic> json) {
    return RendererEvent(
      type: json['type'] as String,
      transactionId: json['transactionId'] as String?,
      version: json['version'] as String? ?? '1.0.0',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
      timestamp: json['timestamp'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (transactionId != null) 'transactionId': transactionId,
      'version': version,
      'payload': payload,
      'timestamp': timestamp,
    };
  }

  String toJsonString() {
    return jsonEncode(toJson());
  }

  @override
  String toString() {
    return 'RendererEvent(type: $type, transactionId: $transactionId, version: $version, payload: $payload, timestamp: $timestamp)';
  }
}
