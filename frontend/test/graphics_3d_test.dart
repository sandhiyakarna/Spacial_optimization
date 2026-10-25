import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowspace_frontend/features/designer/presentation/graphics_3d.dart';

void main() {
  group('3D Math Engine Tests', () {
    test('Vector3D operations', () {
      final v1 = Vector3D(1.0, 2.0, 3.0);
      final v2 = Vector3D(4.0, 5.0, 6.0);

      // Addition
      final add = v1 + v2;
      expect(add.x, 5.0);
      expect(add.y, 7.0);
      expect(add.z, 9.0);

      // Subtraction
      final sub = v2 - v1;
      expect(sub.x, 3.0);
      expect(sub.y, 3.0);
      expect(sub.z, 3.0);

      // Dot Product
      expect(v1.dot(v2), 32.0); // 1*4 + 2*5 + 3*6 = 32

      // Length and Normalize
      final vZero = Vector3D(0, 0, 0);
      expect(vZero.length, 0.0);
      expect(vZero.normalize().x, 0.0);

      final vNorm = Vector3D(3.0, 0.0, 0.0).normalize();
      expect(vNorm.x, 1.0);
      expect(vNorm.y, 0.0);
      expect(vNorm.z, 0.0);

      // Cross Product
      final xAxis = Vector3D(1, 0, 0);
      final yAxis = Vector3D(0, 1, 0);
      final zAxis = xAxis.cross(yAxis);
      expect(zAxis.x, 0.0);
      expect(zAxis.y, 0.0);
      expect(zAxis.z, 1.0);
    });

    test('Matrix4x4 transformations', () {
      final matScale = Matrix4x4.scale(2.0, 3.0, 4.0);
      final pt = Vector3D(1.0, 1.0, 1.0);
      final scaled = matScale.transform(pt);

      expect(scaled.x, 2.0);
      expect(scaled.y, 3.0);
      expect(scaled.z, 4.0);

      final matTrans = Matrix4x4.translation(10.0, -5.0, 20.0);
      final trans = matTrans.transform(pt);
      expect(trans.x, 11.0);
      expect(trans.y, -4.0);
      expect(trans.z, 21.0);

      // Matrix multiply (Identity * Scale)
      final identity = Matrix4x4.identity();
      final mult = Matrix4x4.multiply(identity, matScale);
      expect(mult.m[0], 2.0);
      expect(mult.m[5], 3.0);
      expect(mult.m[10], 4.0);
    });

    test('Camera projection views', () {
      final camera = Camera();
      camera.position = Vector3D(0, 100, 300);
      camera.target = Vector3D(0, 0, 0);
      camera.aspect = 1.0;
      camera.fov = pi / 4.0; // 45 degrees

      final viewMat = camera.getViewMatrix();
      final projMat = camera.getProjectionMatrix();
      final viewProj = Matrix4x4.multiply(viewMat, projMat);

      // Project point at target
      final projTarget = camera.projectPoint(Vector3D(0, 0, 0), viewProj, const Size(800, 600));
      expect(projTarget, isNotNull);
      // Target should map to center of screen (400, 300)
      expect(projTarget!.dx, closeTo(400.0, 0.1));
      expect(projTarget.dy, closeTo(300.0, 0.1));

      // Project point far behind camera
      final projBehind = camera.projectPoint(Vector3D(0, 100, 1000), viewProj, const Size(800, 600));
      // Should be clipped (returns null)
      expect(projBehind, isNull);
    });

    test('GLB binary mock parser fails gracefully on invalid glb', () {
      final invalidBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final parsed = GlbBinaryMeshParser.parse(invalidBytes, Colors.blue);
      expect(parsed, isEmpty);
    });
  });
}
