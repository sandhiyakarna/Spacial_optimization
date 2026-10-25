import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// A quality score representing the result of the stitching process.
enum StitchingQuality {
  excellent,
  good,
  acceptable,
  poor,
  failed,
}

class StitchingResult {
  final img.Image? stitchedImage;
  final StitchingQuality quality;
  final String statusMessage;
  final double averageConfidence;
  final int matchedPairsCount;

  StitchingResult({
    required this.stitchedImage,
    required this.quality,
    required this.statusMessage,
    required this.averageConfidence,
    required this.matchedPairsCount,
  });
}

class PanoramaStitcher {
  /// Warp an image onto a cylindrical surface.
  /// W_d and H_d are destination dimensions, f is focal length.
  static img.Image warpCylindrical(img.Image src, {double? focalLength}) {
    final int width = src.width;
    final int height = src.height;
    
    // Estimate focal length if not provided. FOV around 60 degrees.
    // f = width / (2 * tan(fov_rad / 2))
    final double f = focalLength ?? (width / (2.0 * math.tan(math.pi / 6.0)));
    final int xc = width ~/ 2;
    final int yc = height ~/ 2;

    final img.Image dst = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Compute angle theta and height h on the cylinder
        final double theta = (x - xc) / f;
        final double h = (y - yc) / f;

        // Map back to flat perspective coordinates
        final double xsDouble = f * math.tan(theta) + xc;
        final double ysDouble = f * h / math.cos(theta) + yc;

        final int xs = xsDouble.round();
        final int ys = ysDouble.round();

        // Sample if within bounds (nearest-neighbor interpolation for speed/reliability in Dart)
        if (xs >= 0 && xs < width && ys >= 0 && ys < height) {
          final pixel = src.getPixel(xs, ys);
          dst.setPixelRgba(x, y, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt(), pixel.a.toInt());
        } else {
          // Set black/transparent for out of bounds
          dst.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }
    return dst;
  }

  /// Convert a pixel to grayscale luminance value (0-255).
  static double _getLuminance(img.Pixel pixel) {
    return 0.299 * pixel.r.toDouble() + 0.587 * pixel.g.toDouble() + 0.114 * pixel.b.toDouble();
  }

  /// Perform template/patch matching between two images to find translation (dx, dy).
  /// Returns the offset (dx, dy) and a confidence score between 0.0 and 1.0.
  static Map<String, dynamic> matchFrames(img.Image img1, img.Image img2) {
    final int w = img1.width;
    final int h = img1.height;

    // We expect the overlap to be in the range [10%, 40%] of the image width.
    final int maxOverlap = (w * 0.40).round();
    final int minOverlap = (w * 0.10).round();

    // Horizontal search range for displacement dx:
    // dx is the offset of img2 relative to img1.
    // Since img2 is to the right of img1, its left edge aligns with img1 at x = dx.
    // So dx should be in the range [w - maxOverlap, w - minOverlap].
    final int minDx = w - maxOverlap;
    final int maxDx = w - minOverlap;

    // Vertical search range dy (compensate for minor camera tilt/shake)
    const int maxDy = 16;

    // Define 5 patches in the overlap region of img1
    // The overlap region in img1 is at its right side, near x = w - (maxOverlap + minOverlap) / 2
    final int patchWidth = 16;
    final int patchHeight = 16;
    final int patchX = w - (maxOverlap + minOverlap) ~/ 2;

    final List<int> patchYCenters = [
      h ~/ 4,
      3 * h ~/ 8,
      h ~/ 2,
      5 * h ~/ 8,
      3 * h ~/ 4,
    ];

    final List<Map<String, int>> bestOffsets = [];
    final List<double> patchConfidences = [];

    for (final yc in patchYCenters) {
      int bestXOffset = minDx;
      int bestYOffset = 0;
      double minError = double.infinity;

      // Extract patch pixels from img1
      final List<List<double>> patchLums = List.generate(patchHeight, (_) => List.filled(patchWidth, 0.0));
      double sumLums = 0.0;
      for (int py = 0; py < patchHeight; py++) {
        for (int px = 0; px < patchWidth; px++) {
          final pixel = img1.getPixel(patchX + px, yc - patchHeight ~/ 2 + py);
          final lum = _getLuminance(pixel);
          patchLums[py][px] = lum;
          sumLums += lum;
        }
      }

      // Calculate mean and variance to detect flat/uniform patches
      final double mean = sumLums / (patchWidth * patchHeight);
      double variance = 0.0;
      for (int py = 0; py < patchHeight; py++) {
        for (int px = 0; px < patchWidth; px++) {
          final diff = patchLums[py][px] - mean;
          variance += diff * diff;
        }
      }
      variance /= (patchWidth * patchHeight);

      // If the patch has very low texture (variance < 16.0), skip matching it
      if (variance < 16.0) {
        bestOffsets.add({'dx': minDx, 'dy': 0});
        patchConfidences.add(0.0);
        continue;
      }

      // Search in img2
      for (int dx = minDx; dx <= maxDx; dx += 2) { // step by 2 for performance
        // Expected overlap position in img2: x_img2 = x_img1 - dx
        final int targetStartX = patchX - dx;
        if (targetStartX < 0 || targetStartX + patchWidth > w) continue;

        for (int dy = -maxDy; dy <= maxDy; dy += 2) {
          final int targetStartY = yc - patchHeight ~/ 2 - dy;
          if (targetStartY < 0 || targetStartY + patchHeight > h) continue;

          double sumDiff = 0.0;
          for (int py = 0; py < patchHeight; py++) {
            for (int px = 0; px < patchWidth; px++) {
              final pixel2 = img2.getPixel(targetStartX + px, targetStartY + py);
              final double lum2 = _getLuminance(pixel2);
              sumDiff += (patchLums[py][px] - lum2).abs();
            }
          }

          final double avgDiff = sumDiff / (patchWidth * patchHeight);
          if (avgDiff < minError) {
            minError = avgDiff;
            bestXOffset = dx;
            bestYOffset = dy;
          }
        }
      }

      bestOffsets.add({'dx': bestXOffset, 'dy': bestYOffset});
      // Confidence score: low error -> high confidence
      // E.g. average pixel difference of 0 is 1.0 confidence, difference of 20 is 0.0 confidence.
      final double confidence = (1.0 - (minError / 20.0)).clamp(0.0, 1.0);
      patchConfidences.add(confidence);
      debugPrint("Patch yc=$yc variance=$variance bestOffset=($bestXOffset, $bestYOffset) minError=$minError conf=$confidence");
    }

    // Consensus voting (RANSAC-style) to filter outliers
    int bestConsensusCount = 0;
    int finalDx = bestOffsets[0]['dx']!;
    int finalDy = bestOffsets[0]['dy']!;
    double totalWeight = 0.0;

    for (int i = 0; i < bestOffsets.length; i++) {
      final int dxI = bestOffsets[i]['dx']!;
      final int dyI = bestOffsets[i]['dy']!;

      int consensusCount = 0;
      double sumDx = 0;
      double sumDy = 0;
      double groupWeight = 0.0;

      for (int j = 0; j < bestOffsets.length; j++) {
        final int dxJ = bestOffsets[j]['dx']!;
        final int dyJ = bestOffsets[j]['dy']!;

        // Group together if within 6 pixels horizontally and 3 pixels vertically
        if ((dxI - dxJ).abs() <= 6 && (dyI - dyJ).abs() <= 3) {
          consensusCount++;
          sumDx += dxJ;
          sumDy += dyJ;
          groupWeight += patchConfidences[j];
        }
      }

      if (consensusCount > bestConsensusCount) {
        bestConsensusCount = consensusCount;
        finalDx = (sumDx / consensusCount).round();
        finalDy = (sumDy / consensusCount).round();
        totalWeight = groupWeight / consensusCount;
      }
    }

    final double confidence = (bestConsensusCount / bestOffsets.length) * totalWeight;

    return {
      'success': bestConsensusCount >= 3 && confidence >= 0.25,
      'dx': finalDx,
      'dy': finalDy,
      'confidence': confidence,
    };
  }

  /// Stitches 6 camera frames into a single equirectangular 2:1 panorama.
  static Future<StitchingResult> stitch(List<img.Image> rawFrames) async {
    if (rawFrames.length != 6) {
      return StitchingResult(
        stitchedImage: null,
        quality: StitchingQuality.failed,
        statusMessage: "Requires exactly 6 camera frames for a 360° panorama.",
        averageConfidence: 0.0,
        matchedPairsCount: 0,
      );
    }

    try {
      // 1. Preprocessing & Cylindrical Warping
      final List<img.Image> warped = [];
      for (int i = 0; i < 6; i++) {
        warped.add(warpCylindrical(rawFrames[i]));
      }

      final int w = warped[0].width;
      final int h = warped[0].height;

      // 2. Feature/Patch Matching
      final List<int> dxs = List.filled(6, 0);
      final List<int> dys = List.filled(6, 0);
      final List<double> confidences = [];
      int matchedCount = 0;

      for (int i = 0; i < 6; i++) {
        final int next = (i + 1) % 6;
        final match = matchFrames(warped[i], warped[next]);
        
        final bool success = match['success'] as bool;
        final int dx = match['dx'] as int;
        final int dy = match['dy'] as int;
        final double confidence = match['confidence'] as double;

        dxs[i] = dx;
        dys[i] = dy;
        confidences.add(confidence);

        if (success) {
          matchedCount++;
        } else {
          // Fallback if matching fails completely, use default overlap (20%)
          dxs[i] = (w * 0.8).round();
          dys[i] = 0;
        }
      }

      // Calculate average confidence
      final double avgConfidence = confidences.reduce((a, b) => a + b) / 6.0;

      // Determine Stitching Quality Score
      StitchingQuality quality;
      String statusMessage;

      if (matchedCount == 6 && avgConfidence >= 0.7) {
        quality = StitchingQuality.excellent;
        statusMessage = "Excellent 360° stitch achieved.";
      } else if (matchedCount >= 5 && avgConfidence >= 0.5) {
        quality = StitchingQuality.good;
        statusMessage = "Good quality panorama. Minor alignment variations adjusted.";
      } else if (matchedCount >= 4 && avgConfidence >= 0.35) {
        quality = StitchingQuality.acceptable;
        statusMessage = "Acceptable panorama. Turn slower and keep level for better results.";
      } else if (matchedCount >= 3) {
        quality = StitchingQuality.poor;
        statusMessage = "Panorama quality is insufficient. Please recapture.";
      } else {
        quality = StitchingQuality.failed;
        statusMessage = "Stitching failed. Insufficient feature matches or camera moved too rapidly.";
      }

      // If quality is poor or failed, do not generate a misleading panorama
      if (quality == StitchingQuality.poor || quality == StitchingQuality.failed) {
        return StitchingResult(
          stitchedImage: null,
          quality: quality,
          statusMessage: statusMessage,
          averageConfidence: avgConfidence,
          matchedPairsCount: matchedCount,
        );
      }

      // 3. Loop Closure & Drift Distribution
      // The cumulative vertical drift: sum of all dys
      final int totalVerticalDrift = dys.reduce((a, b) => a + b);
      
      // Distribute the vertical drift error across the frames to prevent sudden jump at closure
      final List<double> correctedDys = List.filled(6, 0.0);
      for (int i = 0; i < 6; i++) {
        correctedDys[i] = dys[i].toDouble() - (totalVerticalDrift / 6.0);
      }

      // Calculate total width of the horizontal strip
      // totalWidth = dx0 + dx1 + dx2 + dx3 + dx4 + dx5
      final int stripWidth = dxs.reduce((a, b) => a + b);
      final int stripHeight = h;

      // 4. Stitched Canvas Coordinates
      final List<int> accumX = List.filled(6, 0);
      final List<int> accumY = List.filled(6, 0);
      int currentX = 0;
      double currentY = 0.0;

      for (int i = 1; i < 6; i++) {
        currentX += dxs[i - 1];
        currentY += correctedDys[i - 1];
        accumX[i] = currentX;
        accumY[i] = currentY.round();
      }

      // 5. Exposure Normalization
      // Normalize subsequent frames' brightness relative to Frame 0
      final List<double> brightnessScales = List.filled(6, 1.0);
      for (int i = 0; i < 5; i++) {
        final int next = i + 1;
        final int overlapStart = accumX[next];
        final int overlapEnd = accumX[i] + w;
        final int overlapW = overlapEnd - overlapStart;

        if (overlapW > 10) {
          double sumLum1 = 0.0;
          double sumLum2 = 0.0;
          int count = 0;

          // Sample central overlap strip to avoid boundary artifacts
          final int sampleStep = 4;
          for (int ox = overlapStart + 5; ox < overlapEnd - 5; ox += sampleStep) {
            for (int oy = h ~/ 4; oy < 3 * h ~/ 4; oy += sampleStep) {
              final p1 = warped[i].getPixel(ox - accumX[i], oy - accumY[i]);
              final p2 = warped[next].getPixel(ox - accumX[next], oy - accumY[next]);
              sumLum1 += _getLuminance(p1);
              sumLum2 += _getLuminance(p2);
              count++;
            }
          }

          if (count > 0 && sumLum2 > 0.0) {
            final double ratio = sumLum1 / sumLum2;
            // Clamp ratio to avoid extreme lighting blowups
            final double clampedRatio = ratio.clamp(0.7, 1.3);
            brightnessScales[next] = brightnessScales[i] * clampedRatio;
          } else {
            brightnessScales[next] = brightnessScales[i];
          }
        } else {
          brightnessScales[next] = brightnessScales[i];
        }
      }

      // 6. Draw and Blend Frames onto Stitched Strip
      final img.Image strip = img.Image(width: stripWidth, height: stripHeight);

      for (int x = 0; x < stripWidth; x++) {
        // Find which frame(s) cover this column x
        final List<int> coveringFrames = [];
        for (int i = 0; i < 6; i++) {
          final int xStart = accumX[i];
          final int xEnd = xStart + w;
          if (x >= xStart && x < xEnd) {
            coveringFrames.add(i);
          }
        }

        // Support wrapping check for columns near the right edge of frame 5 that overlap frame 0
        if (x >= accumX[5] && x < stripWidth) {
          final int wrapX = x - stripWidth;
          if (wrapX >= 0 && wrapX < w) {
            coveringFrames.add(0); // Frame 0 overlaps at the end wrapping
          }
        }

        for (int y = 0; y < stripHeight; y++) {
          if (coveringFrames.isEmpty) continue;

          if (coveringFrames.length == 1) {
            final int fIdx = coveringFrames[0];
            int frameX = x - accumX[fIdx];
            if (fIdx == 0 && x >= accumX[5]) {
              frameX = x - stripWidth; // wrap frame 0
            }
            final int frameY = y - accumY[fIdx];

            if (frameX >= 0 && frameX < w && frameY >= 0 && frameY < h) {
              final p = warped[fIdx].getPixel(frameX, frameY);
              final double scale = brightnessScales[fIdx];
              final int r = (p.r.toDouble() * scale).round().clamp(0, 255);
              final int g = (p.g.toDouble() * scale).round().clamp(0, 255);
              final int b = (p.b.toDouble() * scale).round().clamp(0, 255);
              strip.setPixelRgba(x, y, r, g, b, p.a.toInt());
            }
          } else {
            // Blend adjacent overlapping frames
            final int f1 = coveringFrames[0];
            final int f2 = coveringFrames[1];

            int f1X = x - accumX[f1];
            if (f1 == 0 && x >= accumX[5]) f1X = x - stripWidth;
            final int f1Y = y - accumY[f1];

            int f2X = x - accumX[f2];
            if (f2 == 0 && x >= accumX[5]) f2X = x - stripWidth;
            final int f2Y = y - accumY[f2];

            // Determine blending weight based on horizontal position in the overlap
            final int overlapStart = accumX[f2];
            final int overlapEnd = accumX[f1] + w;
            final double range = (overlapEnd - overlapStart).toDouble();
            
            double weight = 0.5;
            if (range > 0.0) {
              weight = (x - overlapStart) / range;
            }
            weight = weight.clamp(0.0, 1.0);

            // Read colors
            int r1 = 0, g1 = 0, b1 = 0, a1 = 0;
            if (f1X >= 0 && f1X < w && f1Y >= 0 && f1Y < h) {
              final p1 = warped[f1].getPixel(f1X, f1Y);
              final double scale1 = brightnessScales[f1];
              r1 = (p1.r.toDouble() * scale1).round().clamp(0, 255);
              g1 = (p1.g.toDouble() * scale1).round().clamp(0, 255);
              b1 = (p1.b.toDouble() * scale1).round().clamp(0, 255);
              a1 = p1.a.toInt();
            }

            int r2 = 0, g2 = 0, b2 = 0, a2 = 0;
            if (f2X >= 0 && f2X < w && f2Y >= 0 && f2Y < h) {
              final p2 = warped[f2].getPixel(f2X, f2Y);
              final double scale2 = brightnessScales[f2];
              r2 = (p2.r.toDouble() * scale2).round().clamp(0, 255);
              g2 = (p2.g.toDouble() * scale2).round().clamp(0, 255);
              b2 = (p2.b.toDouble() * scale2).round().clamp(0, 255);
              a2 = p2.a.toInt();
            }

            // Linear interpolation blend
            final int r = ((1.0 - weight) * r1 + weight * r2).round().clamp(0, 255);
            final int g = ((1.0 - weight) * g1 + weight * g2).round().clamp(0, 255);
            final int b = ((1.0 - weight) * b1 + weight * b2).round().clamp(0, 255);
            final int a = ((1.0 - weight) * a1 + weight * a2).round().clamp(0, 255);

            strip.setPixelRgba(x, y, r, g, b, a);
          }
        }
      }

      // 7. Place on 2:1 canvas & Mark captured field of view
      final int canvasWidth = stripWidth;
      final int canvasHeight = stripWidth ~/ 2;
      final img.Image canvas = img.Image(width: canvasWidth, height: canvasHeight);

      // Fill canvas background with app dark theme slate color (RGB: 7, 12, 22)
      for (int cy = 0; cy < canvasHeight; cy++) {
        for (int cx = 0; cx < canvasWidth; cx++) {
          canvas.setPixelRgba(cx, cy, 7, 12, 22, 255);
        }
      }

      final int yOffset = (canvasHeight - stripHeight) ~/ 2;

      // Draw the stitched panoramic strip onto the centered band of the canvas
      for (int sy = 0; sy < stripHeight; sy++) {
        final int cy = yOffset + sy;
        if (cy < 0 || cy >= canvasHeight) continue;
        for (int cx = 0; cx < canvasWidth; cx++) {
          final p = strip.getPixel(cx, sy);
          canvas.setPixelRgba(cx, cy, p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt());
        }
      }

      // Draw horizontal dashed lines at the boundaries of the captured field of view
      // We will draw a green dashed line (RGB: 74, 222, 128)
      final int dashLength = 8;
      final int gapLength = 6;
      final int topY = yOffset;
      final int bottomY = yOffset + stripHeight - 1;

      for (int cx = 0; cx < canvasWidth; cx++) {
        final bool isDash = (cx % (dashLength + gapLength)) < dashLength;
        if (isDash) {
          if (topY >= 0 && topY < canvasHeight) {
            canvas.setPixelRgba(cx, topY, 74, 222, 128, 255);
          }
          if (bottomY >= 0 && bottomY < canvasHeight) {
            canvas.setPixelRgba(cx, bottomY, 74, 222, 128, 255);
          }
        }
      }

      return StitchingResult(
        stitchedImage: canvas,
        quality: quality,
        statusMessage: statusMessage,
        averageConfidence: avgConfidence,
        matchedPairsCount: matchedCount,
      );
    } catch (e, stackTrace) {
      debugPrint("Stitching exception occurred: $e\n$stackTrace");
      return StitchingResult(
        stitchedImage: null,
        quality: StitchingQuality.failed,
        statusMessage: "Critical stitching error: ${e.toString()}",
        averageConfidence: 0.0,
        matchedPairsCount: 0,
      );
    }
  }
}
