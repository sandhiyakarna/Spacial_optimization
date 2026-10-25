import 'dart:math';
import 'package:flutter/material.dart';
import '../presentation/graphics_3d.dart';

enum LightType {
  ambient,
  directional,
  point,
  spot,
}

class LightSource {
  final String id;
  final String name;
  final LightType type;
  final double x; // x position in cm
  final double y; // y position in cm
  final double z; // z position in cm
  final double rotationX; // in radians
  final double rotationY; // in radians
  final double rotationZ; // in radians
  final double intensity; // intensity multiplier (e.g. 1.0)
  final Color color;
  final double temperature; // temperature in Kelvin (1000K to 12000K)
  final bool castShadow;
  final double radius; // light range/falloff in cm
  final double spotAngle; // spot cone angle in radians

  LightSource({
    required this.id,
    required this.name,
    required this.type,
    this.x = 0.0,
    this.y = 150.0,
    this.z = 0.0,
    this.rotationX = 0.0,
    this.rotationY = 0.0,
    this.rotationZ = 0.0,
    this.intensity = 1.0,
    this.color = Colors.white,
    this.temperature = 6500.0,
    this.castShadow = true,
    this.radius = 500.0,
    this.spotAngle = 0.785, // ~45 degrees in radians
  });

  LightSource copyWith({
    String? name,
    LightType? type,
    double? x,
    double? y,
    double? z,
    double? rotationX,
    double? rotationY,
    double? rotationZ,
    double? intensity,
    Color? color,
    double? temperature,
    bool? castShadow,
    double? radius,
    double? spotAngle,
  }) {
    return LightSource(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      rotationX: rotationX ?? this.rotationX,
      rotationY: rotationY ?? this.rotationY,
      rotationZ: rotationZ ?? this.rotationZ,
      intensity: intensity ?? this.intensity,
      color: color ?? this.color,
      temperature: temperature ?? this.temperature,
      castShadow: castShadow ?? this.castShadow,
      radius: radius ?? this.radius,
      spotAngle: spotAngle ?? this.spotAngle,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.index,
    'x': x,
    'y': y,
    'z': z,
    'rotationX': rotationX,
    'rotationY': rotationY,
    'rotationZ': rotationZ,
    'intensity': intensity,
    'color': color.value,
    'temperature': temperature,
    'castShadow': castShadow,
    'radius': radius,
    'spotAngle': spotAngle,
  };

  factory LightSource.fromJson(Map<String, dynamic> json) => LightSource(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Light',
    type: LightType.values[json['type'] as int? ?? 0],
    x: (json['x'] as num? ?? 0.0).toDouble(),
    y: (json['y'] as num? ?? 150.0).toDouble(),
    z: (json['z'] as num? ?? 0.0).toDouble(),
    rotationX: (json['rotationX'] as num? ?? 0.0).toDouble(),
    rotationY: (json['rotationY'] as num? ?? 0.0).toDouble(),
    rotationZ: (json['rotationZ'] as num? ?? 0.0).toDouble(),
    intensity: (json['intensity'] as num? ?? 1.0).toDouble(),
    color: Color(json['color'] as int? ?? Colors.white.value),
    temperature: (json['temperature'] as num? ?? 6500.0).toDouble(),
    castShadow: json['castShadow'] as bool? ?? true,
    radius: (json['radius'] as num? ?? 500.0).toDouble(),
    spotAngle: (json['spotAngle'] as num? ?? 0.785).toDouble(),
  );
}

/// Convert Kelvin to RGB color approximation (Tanner Helland's algorithm)
Color colorFromTemperature(double tempKelvin) {
  double kelvin = tempKelvin / 100;
  double r, g, b;

  if (kelvin <= 66) {
    r = 255;
    g = kelvin;
    g = 99.4708025861 * log(g) - 161.1195681661;
    if (kelvin <= 19) {
      b = 0;
    } else {
      b = kelvin - 10;
      b = 138.5177312231 * log(b) - 305.0447927307;
    }
  } else {
    r = kelvin - 60;
    r = 329.698727446 * pow(r, -0.1332047592);
    g = kelvin - 60;
    g = 288.1221695283 * pow(g, -0.0755148492);
    b = 255;
  }

  return Color.fromARGB(
    255,
    r.clamp(0, 255).round(),
    g.clamp(0, 255).round(),
    b.clamp(0, 255).round(),
  );
}

/// Helper to get the 3D forward direction vector of a light from its rotation values.
/// Assuming default direction is pointing downwards: (0, -1, 0)
Vector3D getLightDirection(double rotX, double rotY, double rotZ) {
  final m = Matrix4x4.multiply(
    Matrix4x4.rotationY(rotY),
    Matrix4x4.rotationX(rotX),
  );
  return m.transform(Vector3D(0, -1, 0)).normalize();
}
