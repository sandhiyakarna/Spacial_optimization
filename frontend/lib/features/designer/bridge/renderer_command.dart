import 'dart:convert';

class RendererCommand {
  final String type;
  final String transactionId;
  final String version;
  final Map<String, dynamic> payload;
  final int timestamp;

  RendererCommand({
    required this.type,
    required this.transactionId,
    this.version = '1.0.0',
    this.payload = const {},
    int? timestamp,
  }) : this.timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  factory RendererCommand.fromJson(Map<String, dynamic> json) {
    return RendererCommand(
      type: json['type'] as String,
      transactionId: json['transactionId'] as String,
      version: json['version'] as String? ?? '1.0.0',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
      timestamp: json['timestamp'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'transactionId': transactionId,
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
    return 'RendererCommand(type: $type, transactionId: $transactionId, version: $version, payload: $payload, timestamp: $timestamp)';
  }
}
