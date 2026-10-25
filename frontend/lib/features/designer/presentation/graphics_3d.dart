import '../../../app/themes/app_theme.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../models/light_source.dart';

class Vector3D {
  final double x, y, z;
  Vector3D(this.x, this.y, this.z);

  Vector3D operator +(Vector3D o) => Vector3D(x + o.x, y + o.y, z + o.z);
  Vector3D operator -(Vector3D o) => Vector3D(x - o.x, y - o.y, z - o.z);
  Vector3D operator *(double s) => Vector3D(x * s, y * s, z * s);
  
  double dot(Vector3D o) => x * o.x + y * o.y + z * o.z;
  
  Vector3D cross(Vector3D o) => Vector3D(
    y * o.z - z * o.y,
    z * o.x - x * o.z,
    x * o.y - y * o.x,
  );
  
  double get length => sqrt(x * x + y * y + z * z);
  
  Vector3D normalize() {
    final len = length;
    if (len == 0) return Vector3D(0, 0, 0);
    return Vector3D(x / len, y / len, z / len);
  }

  @override
  String toString() => 'Vector3D(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}

class Matrix4x4 {
  final List<double> m = List<double>.filled(16, 0.0);

  Matrix4x4() {
    m[0] = 1; m[5] = 1; m[10] = 1; m[15] = 1;
  }

  factory Matrix4x4.identity() => Matrix4x4();

  factory Matrix4x4.translation(double tx, double ty, double tz) {
    final mat = Matrix4x4();
    mat.m[12] = tx; mat.m[13] = ty; mat.m[14] = tz;
    return mat;
  }

  factory Matrix4x4.scale(double sx, double sy, double sz) {
    final mat = Matrix4x4();
    mat.m[0] = sx; mat.m[5] = sy; mat.m[10] = sz;
    return mat;
  }

  factory Matrix4x4.rotationY(double rad) {
    final mat = Matrix4x4();
    final c = cos(rad);
    final s = sin(rad);
    mat.m[0] = c;  mat.m[2] = -s;
    mat.m[8] = s;  mat.m[10] = c;
    return mat;
  }

  factory Matrix4x4.rotationX(double rad) {
    final mat = Matrix4x4();
    final c = cos(rad);
    final s = sin(rad);
    mat.m[5] = c;  mat.m[6] = s;
    mat.m[9] = -s; mat.m[10] = c;
    return mat;
  }

  factory Matrix4x4.rotationZ(double rad) {
    final mat = Matrix4x4();
    final c = cos(rad);
    final s = sin(rad);
    mat.m[0] = c;  mat.m[1] = s;
    mat.m[4] = -s; mat.m[5] = c;
    return mat;
  }

  static Matrix4x4 multiply(Matrix4x4 a, Matrix4x4 b) {
    final res = Matrix4x4();
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 4; col++) {
        double sum = 0.0;
        for (int i = 0; i < 4; i++) {
          sum += a.m[row * 4 + i] * b.m[i * 4 + col];
        }
        res.m[row * 4 + col] = sum;
      }
    }
    return res;
  }

  Vector3D transform(Vector3D v) {
    final x = v.x * m[0] + v.y * m[4] + v.z * m[8] + m[12];
    final y = v.x * m[1] + v.y * m[5] + v.z * m[9] + m[13];
    final z = v.x * m[2] + v.y * m[6] + v.z * m[10] + m[14];
    final w = v.x * m[3] + v.y * m[7] + v.z * m[11] + m[15];
    if (w != 1.0 && w != 0.0) {
      return Vector3D(x / w, y / w, z / w);
    }
    return Vector3D(x, y, z);
  }

  static Matrix4x4 lookAt(Vector3D position, Vector3D target, Vector3D up) {
    final zAxis = (position - target).normalize();
    var xAxis = up.cross(zAxis).normalize();
    if (xAxis.length == 0.0) {
      // collinear, choose a different up vector
      final newUp = (up.y.abs() > 0.9) ? Vector3D(0, 0, -1) : Vector3D(0, 1, 0);
      xAxis = newUp.cross(zAxis).normalize();
    }
    final yAxis = zAxis.cross(xAxis).normalize();

    final mat = Matrix4x4();
    mat.m[0] = xAxis.x;
    mat.m[4] = xAxis.y;
    mat.m[8] = xAxis.z;
    mat.m[12] = -xAxis.dot(position);

    mat.m[1] = yAxis.x;
    mat.m[5] = yAxis.y;
    mat.m[9] = yAxis.z;
    mat.m[13] = -yAxis.dot(position);

    mat.m[2] = zAxis.x;
    mat.m[6] = zAxis.y;
    mat.m[10] = zAxis.z;
    mat.m[14] = -zAxis.dot(position);

    mat.m[3] = 0; mat.m[7] = 0; mat.m[11] = 0; mat.m[15] = 1;
    return mat;
  }

  static Matrix4x4 perspective(double fovRad, double aspect, double near, double far) {
    final mat = Matrix4x4();
    final f = 1.0 / tan(fovRad / 2.0);
    mat.m[0] = f / aspect;
    mat.m[5] = f;
    mat.m[10] = (far + near) / (near - far);
    mat.m[11] = -1.0;
    mat.m[14] = (2.0 * far * near) / (near - far);
    mat.m[15] = 0.0;
    return mat;
  }
}

class Polygon3D {
  final List<Vector3D> vertices;
  final Color baseColor;
  final Vector3D normal;
  final double metallic;
  final double roughness;
  final String? textureType; // 'wood', 'tile', 'carpet', 'fabric', etc.
  
  // Render-time fields
  List<Vector3D> projected = [];
  double depth = 0.0;
  Color? shadedColor;

  Polygon3D({
    required this.vertices,
    required this.baseColor,
    required this.normal,
    this.metallic = 0.0,
    this.roughness = 0.5,
    this.textureType,
  });

  Polygon3D copyTransformed(Matrix4x4 matrix) {
    final transVertices = vertices.map((v) => matrix.transform(v)).toList();
    final rotationOnly = Matrix4x4.multiply(matrix, Matrix4x4.translation(-matrix.m[12], -matrix.m[13], -matrix.m[14]));
    final transNormal = rotationOnly.transform(normal).normalize();
    return Polygon3D(
      vertices: transVertices,
      baseColor: baseColor,
      normal: transNormal,
      metallic: metallic,
      roughness: roughness,
      textureType: textureType,
    );
  }
}

// --- GLB BINARY MESH PARSER ---
class GlbBinaryMeshParser {
  static List<Polygon3D> parse(Uint8List bytes, Color defaultColor) {
    if (bytes.length < 20) return [];
    try {
      final byteData = ByteData.sublistView(bytes);
      
      final magic = ascii.decode(bytes.sublist(0, 4));
      if (magic != "glTF") return [];
      
      final version = byteData.getUint32(4, Endian.little);
      if (version != 2) return [];
      
      final jsonChunkLength = byteData.getUint32(12, Endian.little);
      final jsonChunkType = ascii.decode(bytes.sublist(16, 20)).trim();
      if (jsonChunkType != "JSON") return [];
      
      final jsonBytes = bytes.sublist(20, 20 + jsonChunkLength);
      final jsonStr = utf8.decode(jsonBytes);
      final Map<String, dynamic> jsonContent = jsonDecode(jsonStr);
      
      final binChunkOffset = 20 + jsonChunkLength;
      if (binChunkOffset + 8 > bytes.length) return [];
      
      final binChunkLength = byteData.getUint32(binChunkOffset, Endian.little);
      final binBytesOffset = binChunkOffset + 8;
      if (binBytesOffset + binChunkLength > bytes.length) return [];
      
      final binBytes = bytes.sublist(binBytesOffset, binBytesOffset + binChunkLength);
      final List<Polygon3D> polygons = [];
      
      final meshes = jsonContent['meshes'] as List?;
      if (meshes == null || meshes.isEmpty) return [];
      
      final accessors = jsonContent['accessors'] as List? ?? [];
      final bufferViews = jsonContent['bufferViews'] as List? ?? [];
      
      for (final mesh in meshes) {
        final primitives = mesh['primitives'] as List? ?? [];
        for (final prim in primitives) {
          final attrs = prim['attributes'] as Map<String, dynamic>?;
          if (attrs == null || !attrs.containsKey('POSITION')) continue;
          
          final posAccessorIdx = attrs['POSITION'] as int;
          final indicesAccessorIdx = prim['indices'] as int?;
          
          final posAccessor = accessors[posAccessorIdx] as Map<String, dynamic>;
          final posBufferViewIdx = posAccessor['bufferView'] as int;
          final posBufferView = bufferViews[posBufferViewIdx] as Map<String, dynamic>;
          
          final posOffset = (posAccessor['byteOffset'] as int? ?? 0) + (posBufferView['byteOffset'] as int? ?? 0);
          final posCount = posAccessor['count'] as int;
          
          final List<Vector3D> rawVertices = [];
          final posByteData = ByteData.sublistView(binBytes, posOffset);
          double maxCoord = 0.0;
          for (int i = 0; i < posCount; i++) {
            final x = posByteData.getFloat32(i * 12 + 0, Endian.little);
            final y = posByteData.getFloat32(i * 12 + 4, Endian.little);
            final z = posByteData.getFloat32(i * 12 + 8, Endian.little);
            maxCoord = max(maxCoord, max(x.abs(), max(y.abs(), z.abs())));
            rawVertices.add(Vector3D(x, y, z));
          }
          // If max vertex is < 10.0 (meters standard), scale to cm by * 100. If already in cm (>= 10.0), scale is 1.0.
          final double unitScale = (maxCoord < 10.0) ? 100.0 : 1.0;
          final List<Vector3D> vertices = rawVertices
              .map((v) => Vector3D(v.x * unitScale, v.y * unitScale, v.z * unitScale))
              .toList();
          
          final List<int> indices = [];
          if (indicesAccessorIdx != null) {
            final idxAccessor = accessors[indicesAccessorIdx] as Map<String, dynamic>;
            final idxBufferViewIdx = idxAccessor['bufferView'] as int;
            final idxBufferView = bufferViews[idxBufferViewIdx] as Map<String, dynamic>;
            final idxOffset = (idxAccessor['byteOffset'] as int? ?? 0) + (idxBufferView['byteOffset'] as int? ?? 0);
            final idxCount = idxAccessor['count'] as int;
            final idxCompType = idxAccessor['componentType'] as int;
            
            final idxByteData = ByteData.sublistView(binBytes, idxOffset);
            if (idxCompType == 5123) { // USHORT
              for (int i = 0; i < idxCount; i++) {
                indices.add(idxByteData.getUint16(i * 2, Endian.little));
              }
            } else if (idxCompType == 5125) { // UINT
              for (int i = 0; i < idxCount; i++) {
                indices.add(idxByteData.getUint32(i * 4, Endian.little));
              }
            } else if (idxCompType == 5121) { // BYTE
              for (int i = 0; i < idxCount; i++) {
                indices.add(idxByteData.getUint8(i));
              }
            }
          } else {
            for (int i = 0; i < posCount; i++) {
              indices.add(i);
            }
          }
          
          for (int i = 0; i < indices.length; i += 3) {
            if (i + 2 >= indices.length) break;
            final p1 = vertices[indices[i]];
            final p2 = vertices[indices[i + 1]];
            final p3 = vertices[indices[i + 2]];
            
            final v1 = p2 - p1;
            final v2 = p3 - p1;
            final normal = v1.cross(v2).normalize();
            
            polygons.add(Polygon3D(
              vertices: [p1, p2, p3],
              baseColor: defaultColor,
              normal: normal,
            ));
          }
        }
      }
      return polygons;
    } catch (_) {
      return [];
    }
  }
}

// --- PROCEDURAL 3D MESH GENERATOR (FALLBACK ENGINE) ---
class ProceduralMeshGenerator {
  static List<Polygon3D> createBox(
    double cx, double cy, double cz,
    double dx, double dy, double dz,
    Color color, {
      double metallic = 0.0,
      double roughness = 0.5,
      String? texture,
    }) {
    final List<Vector3D> v = [
      Vector3D(cx - dx / 2, cy - dy / 2, cz - dz / 2),
      Vector3D(cx + dx / 2, cy - dy / 2, cz - dz / 2),
      Vector3D(cx + dx / 2, cy + dy / 2, cz - dz / 2),
      Vector3D(cx - dx / 2, cy + dy / 2, cz - dz / 2),
      Vector3D(cx - dx / 2, cy - dy / 2, cz + dz / 2),
      Vector3D(cx + dx / 2, cy - dy / 2, cz + dz / 2),
      Vector3D(cx + dx / 2, cy + dy / 2, cz + dz / 2),
      Vector3D(cx - dx / 2, cy + dy / 2, cz + dz / 2),
    ];

    final List<Polygon3D> polys = [];
    
    // Bottom: 0, 4, 5, 1
    polys.add(Polygon3D(vertices: [v[0], v[4], v[5], v[1]], baseColor: color, normal: Vector3D(0, -1, 0), metallic: metallic, roughness: roughness, textureType: texture));
    // Top: 3, 7, 6, 2
    polys.add(Polygon3D(vertices: [v[3], v[7], v[6], v[2]], baseColor: color, normal: Vector3D(0, 1, 0), metallic: metallic, roughness: roughness, textureType: texture));
    // Left: 0, 3, 7, 4
    polys.add(Polygon3D(vertices: [v[0], v[3], v[7], v[4]], baseColor: color, normal: Vector3D(-1, 0, 0), metallic: metallic, roughness: roughness, textureType: texture));
    // Right: 1, 5, 6, 2
    polys.add(Polygon3D(vertices: [v[1], v[5], v[6], v[2]], baseColor: color, normal: Vector3D(1, 0, 0), metallic: metallic, roughness: roughness, textureType: texture));
    // Back: 0, 1, 2, 3
    polys.add(Polygon3D(vertices: [v[0], v[1], v[2], v[3]], baseColor: color, normal: Vector3D(0, 0, -1), metallic: metallic, roughness: roughness, textureType: texture));
    // Front: 4, 7, 6, 5
    polys.add(Polygon3D(vertices: [v[4], v[7], v[6], v[5]], baseColor: color, normal: Vector3D(0, 0, 1), metallic: metallic, roughness: roughness, textureType: texture));

    return polys;
  }

  static List<Polygon3D> generateFurnitureMesh(
    String category,
    double w, double d, double h,
    Color baseColor, {
      double metallic = 0.0,
      double roughness = 0.5,
    }) {
    final List<Polygon3D> polys = [];
    final catLower = category.toLowerCase();
    
    if (catLower.contains('sofa') || catLower.contains('couch') || catLower.contains('living')) {
      // 1. Base cushion frame
      polys.addAll(createBox(0, h * 0.15, 0, w, h * 0.2, d * 0.9, baseColor, metallic: metallic, roughness: roughness));
      // 2. Seating cushion (split left & right)
      polys.addAll(createBox(-w * 0.22, h * 0.35, d * 0.05, w * 0.44, h * 0.15, d * 0.8, baseColor, metallic: metallic, roughness: roughness + 0.1));
      polys.addAll(createBox(w * 0.22, h * 0.35, d * 0.05, w * 0.44, h * 0.15, d * 0.8, baseColor, metallic: metallic, roughness: roughness + 0.1));
      // 3. Backrest
      polys.addAll(createBox(0, h * 0.65, -d * 0.38, w, h * 0.6, d * 0.2, baseColor, metallic: metallic, roughness: roughness + 0.1));
      // 4. Armrests
      polys.addAll(createBox(-w * 0.45, h * 0.45, 0, w * 0.1, h * 0.5, d, baseColor, metallic: metallic, roughness: roughness));
      polys.addAll(createBox(w * 0.45, h * 0.45, 0, w * 0.1, h * 0.5, d, baseColor, metallic: metallic, roughness: roughness));
      // 5. Metal / Wood Legs
      final legColor = Colors.grey.shade800;
      polys.addAll(createBox(-w * 0.42, h * 0.05, -d * 0.38, w * 0.06, h * 0.1, d * 0.06, legColor, metallic: 0.8, roughness: 0.2));
      polys.addAll(createBox(w * 0.42, h * 0.05, -d * 0.38, w * 0.06, h * 0.1, d * 0.06, legColor, metallic: 0.8, roughness: 0.2));
      polys.addAll(createBox(-w * 0.42, h * 0.05, d * 0.38, w * 0.06, h * 0.1, d * 0.06, legColor, metallic: 0.8, roughness: 0.2));
      polys.addAll(createBox(w * 0.42, h * 0.05, d * 0.38, w * 0.06, h * 0.1, d * 0.06, legColor, metallic: 0.8, roughness: 0.2));
      
    } else if (catLower.contains('chair') || catLower.contains('office') || catLower.contains('seating')) {
      // Office/Desk Chair
      // 1. Seat cushion
      polys.addAll(createBox(0, h * 0.45, 0, w * 0.9, h * 0.08, d * 0.9, baseColor, metallic: metallic, roughness: roughness));
      // 2. Mesh backrest
      polys.addAll(createBox(0, h * 0.78, -d * 0.38, w * 0.8, h * 0.5, d * 0.06, baseColor.withOpacity(0.85), metallic: metallic, roughness: roughness + 0.2));
      // 3. Bottom metallic post
      final postColor = Colors.grey.shade400;
      polys.addAll(createBox(0, h * 0.22, 0, w * 0.15, h * 0.38, d * 0.15, postColor, metallic: 0.9, roughness: 0.1));
      // 4. Base Star Wheels legs
      polys.addAll(createBox(0, h * 0.03, 0, w * 0.8, h * 0.06, d * 0.12, postColor, metallic: 0.9, roughness: 0.1));
      polys.addAll(createBox(0, h * 0.03, 0, w * 0.12, h * 0.06, d * 0.8, postColor, metallic: 0.9, roughness: 0.1));
      // 5. Armrests
      polys.addAll(createBox(-w * 0.45, h * 0.62, d * 0.08, w * 0.06, h * 0.28, d * 0.6, Colors.black, metallic: 0.1, roughness: 0.8));
      polys.addAll(createBox(w * 0.45, h * 0.62, d * 0.08, w * 0.06, h * 0.28, d * 0.6, Colors.black, metallic: 0.1, roughness: 0.8));
      
    } else if (catLower.contains('table') || catLower.contains('dining') || catLower.contains('coffee')) {
      // Wood dining / coffee table
      final woodColor = baseColor == Colors.white ? Colors.brown.shade700 : baseColor;
      // 1. Table Top Planks
      polys.addAll(createBox(0, h - h * 0.04, 0, w, h * 0.08, d, woodColor, metallic: 0.0, roughness: 0.6, texture: 'wood'));
      // 2. Thick Wood Legs
      polys.addAll(createBox(-w * 0.44, h * 0.46, -d * 0.44, w * 0.08, h * 0.92, d * 0.08, woodColor, metallic: 0.0, roughness: 0.6, texture: 'wood'));
      polys.addAll(createBox(w * 0.44, h * 0.46, -d * 0.44, w * 0.08, h * 0.92, d * 0.08, woodColor, metallic: 0.0, roughness: 0.6, texture: 'wood'));
      polys.addAll(createBox(-w * 0.44, h * 0.46, d * 0.44, w * 0.08, h * 0.92, d * 0.08, woodColor, metallic: 0.0, roughness: 0.6, texture: 'wood'));
      polys.addAll(createBox(w * 0.44, h * 0.46, d * 0.44, w * 0.08, h * 0.92, d * 0.08, woodColor, metallic: 0.0, roughness: 0.6, texture: 'wood'));
      
    } else if (catLower.contains('bed') || catLower.contains('bedroom') || catLower.contains('sleep')) {
      // Bed
      final woodColor = Colors.brown.shade800;
      final sheetColor = baseColor == Colors.white ? AppTheme.primary.shade50 : baseColor;
      // 1. Wood Frame Base
      polys.addAll(createBox(0, h * 0.25, 0, w * 0.98, h * 0.4, d * 0.98, woodColor, metallic: 0.1, roughness: 0.7));
      // 2. Mattress
      polys.addAll(createBox(0, h * 0.65, d * 0.02, w * 0.94, h * 0.4, d * 0.94, sheetColor, metallic: 0.0, roughness: 0.9, texture: 'carpet'));
      // 3. Headboard
      polys.addAll(createBox(0, h * 0.9, -d * 0.48, w, h * 0.9, d * 0.06, woodColor, metallic: 0.1, roughness: 0.7));
      // 4. Pillows (2 items at head)
      polys.addAll(createBox(-w * 0.22, h * 0.88, -d * 0.35, w * 0.35, h * 0.1, d * 0.2, Colors.white, metallic: 0.0, roughness: 0.9));
      polys.addAll(createBox(w * 0.22, h * 0.88, -d * 0.35, w * 0.35, h * 0.1, d * 0.2, Colors.white, metallic: 0.0, roughness: 0.9));
      
    } else if (catLower.contains('stair') || catLower.contains('step') || catLower.contains('climb')) {
      // Procedural staircase mesh generator
      const int stepCount = 5;
      final stepHeight = h / stepCount;
      final stepDepth = d / stepCount;
      for (int i = 0; i < stepCount; i++) {
        final sH = (i + 1) * stepHeight;
        final sCenterY = sH / 2.0;
        final sCenterZ = -d / 2.0 + i * stepDepth + stepDepth / 2.0;
        polys.addAll(createBox(0.0, sCenterY, sCenterZ, w, sH, stepDepth, baseColor, metallic: metallic, roughness: roughness, texture: 'wood'));
      }
      
    } else {
      // Desk / Study Desk / Storage cabinet
      final topColor = baseColor == Colors.white ? Colors.orange.shade800 : baseColor;
      polys.addAll(createBox(0, h - h * 0.02, 0, w, h * 0.04, d, topColor, metallic: 0.1, roughness: 0.5, texture: 'wood'));
      final metalColor = Colors.grey.shade700;
      polys.addAll(createBox(-w * 0.46, h * 0.49, 0, w * 0.05, h * 0.98, d * 0.94, metalColor, metallic: 0.8, roughness: 0.3));
      polys.addAll(createBox(w * 0.46, h * 0.49, 0, w * 0.05, h * 0.98, d * 0.94, metalColor, metallic: 0.8, roughness: 0.3));
      polys.addAll(createBox(0, h * 0.25, -d * 0.44, w * 0.88, w * 0.02, w * 0.02, metalColor, metallic: 0.8, roughness: 0.3));
    }
    
    return polys;
  }
}

// --- SHADOW & LIGHTING CALCULATION ENGINE ---
class ShadingEngine {
  static Color calculateShading(
    Polygon3D poly,
    Vector3D directionalLight,
    Color lightColor,
    Color ambientColor,
    {bool isSelected = false}
  ) {
    double dot = poly.normal.dot(directionalLight);
    double diffuse = max(dot, 0.0);
    
    double specular = 0.0;
    if (diffuse > 0.0 && poly.roughness < 0.8) {
      specular = pow(diffuse, (1.0 - poly.roughness) * 64.0) * poly.metallic * 0.4;
    }

    final double ambientR = ambientColor.red / 255.0;
    final double ambientG = ambientColor.green / 255.0;
    final double ambientB = ambientColor.blue / 255.0;

    final double lightR = lightColor.red / 255.0;
    final double lightG = lightColor.green / 255.0;
    final double lightB = lightColor.blue / 255.0;

    int r = ((poly.baseColor.red / 255.0) * (ambientR + diffuse * lightR + specular) * 255).round().clamp(0, 255);
    int g = ((poly.baseColor.green / 255.0) * (ambientG + diffuse * lightG + specular) * 255).round().clamp(0, 255);
    int b = ((poly.baseColor.blue / 255.0) * (ambientB + diffuse * lightB + specular) * 255).round().clamp(0, 255);
    
    if (isSelected) {
      return Color.fromARGB(poly.baseColor.alpha, 
        (r * 0.8 + 255 * 0.2).round().clamp(0, 255), 
        (g * 0.7 + 120 * 0.3).round().clamp(0, 255), 
        (b * 0.6).round().clamp(0, 255)
      );
    }
    
    return Color.fromARGB(poly.baseColor.alpha, r, g, b);
  }

  static Color calculateMultiLightShading(
    Polygon3D poly,
    Vector3D polyCenter,
    List<LightSource> lights,
    Vector3D cameraPosition,
    {bool isSelected = false}
  ) {
    double totalR = 0.0;
    double totalG = 0.0;
    double totalB = 0.0;

    final baseR = poly.baseColor.red / 255.0;
    final baseG = poly.baseColor.green / 255.0;
    final baseB = poly.baseColor.blue / 255.0;

    final N = poly.normal.normalize();
    final V = (cameraPosition - polyCenter).normalize();

    for (final light in lights) {
      final lightColorR = light.color.red / 255.0;
      final lightColorG = light.color.green / 255.0;
      final lightColorB = light.color.blue / 255.0;

      if (light.type == LightType.ambient) {
        totalR += baseR * lightColorR * light.intensity;
        totalG += baseG * lightColorG * light.intensity;
        totalB += baseB * lightColorB * light.intensity;
      } 
      
      else if (light.type == LightType.directional) {
        final L = (getLightDirection(light.rotationX, light.rotationY, light.rotationZ) * -1.0).normalize();
        double dot = N.dot(L);
        double diffuse = max(dot, 0.0);

        double specular = 0.0;
        if (diffuse > 0.0 && poly.roughness < 0.8) {
          final H = (L + V).normalize();
          double specDot = max(N.dot(H), 0.0);
          specular = pow(specDot, (1.0 - poly.roughness) * 64.0) * poly.metallic * 0.4;
        }

        totalR += baseR * (diffuse * lightColorR + specular) * light.intensity;
        totalG += baseG * (diffuse * lightColorG + specular) * light.intensity;
        totalB += baseB * (diffuse * lightColorB + specular) * light.intensity;
      } 
      
      else if (light.type == LightType.point) {
        final lightPos = Vector3D(light.x, light.y, light.z);
        final toLight = lightPos - polyCenter;
        final dist = toLight.length;

        if (dist < light.radius) {
          final L = toLight.normalize();
          double dot = N.dot(L);
          double diffuse = max(dot, 0.0);

          double attenuation = (1.0 - dist / light.radius).clamp(0.0, 1.0);

          double specular = 0.0;
          if (diffuse > 0.0 && poly.roughness < 0.8) {
            final H = (L + V).normalize();
            double specDot = max(N.dot(H), 0.0);
            specular = pow(specDot, (1.0 - poly.roughness) * 64.0) * poly.metallic * 0.4;
          }

          totalR += baseR * (diffuse * lightColorR + specular) * attenuation * light.intensity;
          totalG += baseG * (diffuse * lightColorG + specular) * attenuation * light.intensity;
          totalB += baseB * (diffuse * lightColorB + specular) * attenuation * light.intensity;
        }
      } 
      
      else if (light.type == LightType.spot) {
        final lightPos = Vector3D(light.x, light.y, light.z);
        final toLight = lightPos - polyCenter;
        final dist = toLight.length;

        if (dist < light.radius) {
          final L = toLight.normalize();
          final lightDir = getLightDirection(light.rotationX, light.rotationY, light.rotationZ).normalize();
          
          final cosAngle = (L * -1.0).dot(lightDir);
          final cosCone = cos(light.spotAngle);

          if (cosAngle > cosCone) {
            double spotFactor = ((cosAngle - cosCone) / (1.0 - cosCone)).clamp(0.0, 1.0);
            double dot = N.dot(L);
            double diffuse = max(dot, 0.0);

            double attenuation = (1.0 - dist / light.radius).clamp(0.0, 1.0);

            double specular = 0.0;
            if (diffuse > 0.0 && poly.roughness < 0.8) {
              final H = (L + V).normalize();
              double specDot = max(N.dot(H), 0.0);
              specular = pow(specDot, (1.0 - poly.roughness) * 64.0) * poly.metallic * 0.4;
            }

            totalR += baseR * (diffuse * lightColorR + specular) * attenuation * spotFactor * light.intensity;
            totalG += baseG * (diffuse * lightColorG + specular) * attenuation * spotFactor * light.intensity;
            totalB += baseB * (diffuse * lightColorB + specular) * attenuation * spotFactor * light.intensity;
          }
        }
      }
    }

    int r = (totalR * 255).round().clamp(0, 255);
    int g = (totalG * 255).round().clamp(0, 255);
    int b = (totalB * 255).round().clamp(0, 255);

    if (isSelected) {
      return Color.fromARGB(poly.baseColor.alpha, 
        (r * 0.8 + 255 * 0.2).round().clamp(0, 255), 
        (g * 0.7 + 120 * 0.3).round().clamp(0, 255), 
        (b * 0.6).round().clamp(0, 255)
      );
    }

    return Color.fromARGB(poly.baseColor.alpha, r, g, b);
  }

  static List<Vector3D> projectShadowVertices(List<Vector3D> vertices, Vector3D lightDir) {
    if (lightDir.y <= 0) return [];
    
    final List<Vector3D> projected = [];
    for (final v in vertices) {
      double factor = v.y / lightDir.y;
      double px = v.x - lightDir.x * factor;
      double pz = v.z - lightDir.z * factor;
      projected.add(Vector3D(px, 0.05, pz)); // offset slightly above floor to prevent z-fighting
    }
    return projected;
  }

  static List<Vector3D> projectShadowVerticesFromPoint(List<Vector3D> vertices, Vector3D lightPos) {
    if (lightPos.y <= 0.05) return [];
    
    final List<Vector3D> projected = [];
    for (final v in vertices) {
      if ((v.y - lightPos.y).abs() < 1e-6) continue;
      double t = (0.05 - lightPos.y) / (v.y - lightPos.y);
      if (t < 0) continue; // projects away from floor
      double px = lightPos.x + t * (v.x - lightPos.x);
      double pz = lightPos.z + t * (v.z - lightPos.z);
      projected.add(Vector3D(px, 0.05, pz)); // offset slightly above floor to prevent z-fighting
    }
    return projected;
  }
}

// --- ORBIT & PERSPECTIVE CAMERA CONTROLLERS ---
class Camera {
  Vector3D position = Vector3D(0, 300, 500);
  Vector3D target = Vector3D(0, 0, 0);
  Vector3D up = Vector3D(0, 1, 0);
  double fov = pi / 4.0;
  double aspect = 1.0;
  double near = 10.0;
  final double far = 8000.0;

  // Orbit properties
  double orbitRadius = 900.0;
  double azimuth = pi / 4.0;
  double elevation = pi / 6.0;

  // Walkthrough properties
  double walkYaw = -pi / 2;
  double walkPitch = 0.0;
  double eyeHeight = 160.0;

  void updateOrbitPosition() {
    double cx = target.x + orbitRadius * cos(elevation) * cos(azimuth);
    double cy = target.y + orbitRadius * sin(elevation);
    double cz = target.z + orbitRadius * cos(elevation) * sin(azimuth);
    position = Vector3D(cx, cy, cz);
  }

  void updateWalkthroughPosition() {
    double dx = cos(walkPitch) * cos(walkYaw);
    double dy = sin(walkPitch);
    double dz = cos(walkPitch) * sin(walkYaw);
    target = position + Vector3D(dx, dy, dz) * 100.0;
  }

  Matrix4x4 getViewMatrix() {
    return Matrix4x4.lookAt(position, target, up);
  }

  Matrix4x4 getProjectionMatrix() {
    return Matrix4x4.perspective(fov, aspect, near, far);
  }

  Offset? projectPoint(Vector3D v, Matrix4x4 viewProjMat, Size viewportSize) {
    // Transform by view-projection matrix
    final x = v.x * viewProjMat.m[0] + v.y * viewProjMat.m[4] + v.z * viewProjMat.m[8] + viewProjMat.m[12];
    final y = v.x * viewProjMat.m[1] + v.y * viewProjMat.m[5] + v.z * viewProjMat.m[9] + viewProjMat.m[13];
    final w = v.x * viewProjMat.m[3] + v.y * viewProjMat.m[7] + v.z * viewProjMat.m[11] + viewProjMat.m[15];
    
    // Clip behind near plane
    if (w <= 0) return null;
    
    double ndcX = x / w;
    double ndcY = y / w;
    
    // Viewport mapping
    double sx = (ndcX + 1.0) * viewportSize.width / 2.0;
    double sy = (1.0 - ndcY) * viewportSize.height / 2.0;
    return Offset(sx, sy);
  }
}

// --- 3D BOUNDING BOX / SELECTION SYSTEM ---
class BoundingBox3D {
  final Vector3D min;
  final Vector3D max;

  BoundingBox3D(this.min, this.max);

  bool intersectsRay(Vector3D rayOrigin, Vector3D rayDir, List<double> outDistance) {
    double tmin = (min.x - rayOrigin.x) / (rayDir.x == 0 ? 1e-6 : rayDir.x);
    double tmax = (max.x - rayOrigin.x) / (rayDir.x == 0 ? 1e-6 : rayDir.x);
    if (tmin > tmax) { final t = tmin; tmin = tmax; tmax = t; }

    double tymin = (min.y - rayOrigin.y) / (rayDir.y == 0 ? 1e-6 : rayDir.y);
    double tymax = (max.y - rayOrigin.y) / (rayDir.y == 0 ? 1e-6 : rayDir.y);
    if (tymin > tymax) { final t = tymin; tymin = tymax; tymax = t; }

    if ((tmin > tymax) || (tymin > tmax)) return false;
    if (tymin > tmin) tmin = tymin;
    if (tymax < tmax) tmax = tymax;

    double tzmin = (min.z - rayOrigin.z) / (rayDir.z == 0 ? 1e-6 : rayDir.z);
    double tzmax = (max.z - rayOrigin.z) / (rayDir.z == 0 ? 1e-6 : rayDir.z);
    if (tzmin > tzmax) { final t = tzmin; tzmin = tzmax; tzmax = t; }

    if ((tmin > tzmax) || (tzmin > tmax)) return false;
    if (tzmin > tmin) tmin = tzmin;
    if (tzmax < tmax) tmax = tzmax;

    if (tmax < 0) return false;
    
    outDistance.clear();
    outDistance.add(tmin < 0 ? tmax : tmin);
    return true;
  }
}
