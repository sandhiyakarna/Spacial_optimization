import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/light_source.dart';

class LightingState {
  final bool showShadows;
  final bool showCeiling;
  final double sunAzimuth;
  final double ambientLight;
  final double sunAltitude;
  final List<LightSource> lights;
  final String? selectedLightId;

  const LightingState({
    this.showShadows = true,
    this.showCeiling = false,
    this.sunAzimuth = pi / 3.0,
    this.ambientLight = 0.45,
    this.sunAltitude = pi / 4.0,
    this.lights = const [],
    this.selectedLightId,
  });

  LightingState copyWith({
    bool? showShadows,
    bool? showCeiling,
    double? sunAzimuth,
    double? ambientLight,
    double? sunAltitude,
    List<LightSource>? lights,
    String? selectedLightId,
    bool clearSelectedLight = false,
  }) {
    return LightingState(
      showShadows: showShadows ?? this.showShadows,
      showCeiling: showCeiling ?? this.showCeiling,
      sunAzimuth: sunAzimuth ?? this.sunAzimuth,
      ambientLight: ambientLight ?? this.ambientLight,
      sunAltitude: sunAltitude ?? this.sunAltitude,
      lights: lights ?? this.lights,
      selectedLightId: clearSelectedLight ? null : (selectedLightId ?? this.selectedLightId),
    );
  }
}

class LightingNotifier extends Notifier<LightingState> {
  @override
  LightingState build() {
    final defaultLights = [
      LightSource(
        id: 'ambient_global',
        name: 'Ambient Light',
        type: LightType.ambient,
        intensity: 0.45,
        color: Colors.white,
        castShadow: false,
      ),
      LightSource(
        id: 'sun_global',
        name: 'Sun Light',
        type: LightType.directional,
        intensity: 1.0,
        color: const Color(0xFFFFFDF6),
        rotationX: pi / 4.0, // sunAltitude
        rotationY: pi / 3.0, // sunAzimuth
        castShadow: true,
      ),
    ];
    return LightingState(
      lights: defaultLights,
      sunAzimuth: pi / 3.0,
      ambientLight: 0.45,
      sunAltitude: pi / 4.0,
    );
  }

  void toggleShadows(bool value) => state = state.copyWith(showShadows: value);
  void toggleCeiling(bool value) => state = state.copyWith(showCeiling: value);

  void setSunAzimuth(double value) {
    final updatedLights = state.lights.map((l) {
      if (l.id == 'sun_global') {
        return l.copyWith(rotationY: value);
      }
      return l;
    }).toList();
    state = state.copyWith(sunAzimuth: value, lights: updatedLights);
  }

  void setSunAltitude(double value) {
    final updatedLights = state.lights.map((l) {
      if (l.id == 'sun_global') {
        return l.copyWith(rotationX: value);
      }
      return l;
    }).toList();
    state = state.copyWith(sunAltitude: value, lights: updatedLights);
  }

  void setAmbientLight(double value) {
    final updatedLights = state.lights.map((l) {
      if (l.id == 'ambient_global') {
        return l.copyWith(intensity: value);
      }
      return l;
    }).toList();
    state = state.copyWith(ambientLight: value, lights: updatedLights);
  }

  void addLight(LightType type) {
    final id = 'light_${DateTime.now().millisecondsSinceEpoch}';
    final name = '${type.name[0].toUpperCase()}${type.name.substring(1)} Light';
    final newLight = LightSource(
      id: id,
      name: name,
      type: type,
      x: 200.0,
      y: 150.0,
      z: 200.0,
      intensity: 1.0,
      color: Colors.white,
      radius: 500.0,
      spotAngle: 0.785,
    );
    state = state.copyWith(
      lights: [...state.lights, newLight],
      selectedLightId: id,
    );
  }

  void deleteLight(String id) {
    state = state.copyWith(
      lights: state.lights.where((l) => l.id != id).toList(),
      selectedLightId: state.selectedLightId == id ? null : state.selectedLightId,
    );
  }

  void selectLight(String? id) {
    state = state.copyWith(selectedLightId: id);
  }

  void updateLight(String id, {
    String? name,
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
    double? nextSunAzimuth = state.sunAzimuth;
    double? nextSunAltitude = state.sunAltitude;
    double? nextAmbientLight = state.ambientLight;

    if (id == 'ambient_global' && intensity != null) {
      nextAmbientLight = intensity;
    }
    if (id == 'sun_global') {
      if (rotationY != null) nextSunAzimuth = rotationY;
      if (rotationX != null) nextSunAltitude = rotationX;
    }

    final updated = state.lights.map((l) {
      if (l.id == id) {
        return l.copyWith(
          name: name,
          x: x,
          y: y,
          z: z,
          rotationX: rotationX,
          rotationY: rotationY,
          rotationZ: rotationZ,
          intensity: intensity,
          color: color,
          temperature: temperature,
          castShadow: castShadow,
          radius: radius,
          spotAngle: spotAngle,
        );
      }
      return l;
    }).toList();

    state = state.copyWith(
      lights: updated,
      sunAzimuth: nextSunAzimuth,
      sunAltitude: nextSunAltitude,
      ambientLight: nextAmbientLight,
    );
  }

  void clearSelection() {
    state = state.copyWith(clearSelectedLight: true);
  }
}

final lightingProvider = NotifierProvider<LightingNotifier, LightingState>(() {
  return LightingNotifier();
});
