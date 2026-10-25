import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../core/api/api_client.dart';
import '../../../core/storage/token_storage.dart';

import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'panorama_stitcher.dart';

/// In-memory cache for storing stitched images on Web or for local preview caching.
class PanoramaImageCache {
  static final Map<String, Uint8List> _cache = {};

  static void put(String key, Uint8List bytes) {
    _cache[key] = bytes;
  }

  static Uint8List? get(String key) {
    return _cache[key];
  }
}

/// A service to orchestrate 360° Panorama Capture and processing operations.
class PanoramaService {
  /// Stores the result of the last local stitching operation.
  static StitchingResult? lastStitchingResult;

  /// Request device camera permissions.
  static Future<bool> requestCameraPermission() async {
    // Permission is requested dynamically in the presentation layer using permission_handler on Android,
    // and automatically on Web when camera controller initializes.
    return true;
  }

  /// Capture a visual reference frame at a specific angle.
  static Future<String> captureAngleFrame(double angle) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return 'frame_${angle.round()}.jpg';
  }

  /// Stitch a series of captured frame files into a single equirectangular projection.
  static Future<String> stitchFrames(List<String> frames) async {
    await Future.delayed(const Duration(milliseconds: 900));
    return 'captured_panorama_room_360.jpg';
  }

  /// Upload a single frame to the backend.
  static Future<String> uploadFrame(String scanId, String filepath) async {
    final baseUrl = ApiClient.baseUrl;
    final token = await TokenStorage().getAccessToken();
    
    final uri = Uri.parse('$baseUrl/room/panorama/upload');
    final request = http.MultipartRequest('POST', uri);
    
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    
    request.fields['scan_id'] = scanId;
    
    final file = await http.MultipartFile.fromPath('file', filepath);
    request.files.add(file);
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['scan_id'];
    }
    throw Exception('Failed to upload frame: ${response.body}');
  }

  /// Triggers room reconstruction process on the backend.
  static Future<Map<String, dynamic>> processPanorama(
    String scanId,
    String roomId,
    String roomType,
    double? knownWidth,
    double? knownDepth,
    double? knownHeight
  ) async {
    final baseUrl = ApiClient.baseUrl;
    final token = await TokenStorage().getAccessToken();
    
    final uri = Uri.parse('$baseUrl/room/panorama/process');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'scan_id': scanId,
        'room_id': roomId,
        'room_type': roomType,
        'known_width_cm': knownWidth,
        'known_depth_cm': knownDepth,
        'known_height_cm': knownHeight,
      }),
    );
    
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['detail'] ?? 'Failed to process panorama.');
  }

  /// Upload the stitched panorama image to the server.
  static Future<String> uploadPanorama(String roomId, String localPath) async {
    await Future.delayed(const Duration(milliseconds: 750));
    return localPath; // Return the path directly to preserve local storage path
  }

  /// Stitch a series of captured frame image paths horizontally into a single panorama image.
  static Future<String> stitchFramesLocally(List<String> framePaths, String outputPath) async {
    // Read and resize all images sequentially to optimize memory usage.
    final List<img.Image> images = [];
    for (final path in framePaths) {
      try {
        final xfile = XFile(path);
        final bytes = await xfile.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          // Resize to a height of 320px to be fast and memory-efficient on mobile devices.
          final resized = img.copyResize(decoded, height: 320);
          images.add(resized);
        }
      } catch (e) {
        debugPrint("Error reading/decoding frame at $path: $e");
      }
    }

    if (images.isEmpty) {
      lastStitchingResult = StitchingResult(
        stitchedImage: null,
        quality: StitchingQuality.failed,
        statusMessage: "No valid camera frames captured for stitching.",
        averageConfidence: 0.0,
        matchedPairsCount: 0,
      );
      throw Exception("No valid frames captured for stitching");
    }

    if (images.length != 6) {
      lastStitchingResult = StitchingResult(
        stitchedImage: null,
        quality: StitchingQuality.failed,
        statusMessage: "Requires exactly 6 captured camera frames.",
        averageConfidence: 0.0,
        matchedPairsCount: 0,
      );
      throw Exception("Stitching requires exactly 6 frames.");
    }

    // Call the pure Dart panorama stitcher
    final result = await PanoramaStitcher.stitch(images);
    lastStitchingResult = result;

    if (result.quality == StitchingQuality.poor || result.quality == StitchingQuality.failed || result.stitchedImage == null) {
      throw Exception(result.statusMessage);
    }

    // Encode stitched image as JPEG
    final jpegBytes = img.encodeJpg(result.stitchedImage!);

    if (kIsWeb || outputPath.startsWith('memory:')) {
      // Save in cache
      PanoramaImageCache.put(outputPath, jpegBytes);
      return outputPath;
    } else {
      // Save to local file system
      final file = File(outputPath);
      await file.writeAsBytes(jpegBytes);
      return outputPath;
    }
  }
}
