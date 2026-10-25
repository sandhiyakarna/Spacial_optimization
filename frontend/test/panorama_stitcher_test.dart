import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:flowspace_frontend/features/room/data/panorama_stitcher.dart';

/// Helper to pre-warp coordinates so they become clean square boxes after cylindrical warp.
void paintWarpedBox(img.Image src, double targetXd, double targetYd, int size) {
  final int width = src.width;
  final int height = src.height;
  final double f = width / (2.0 * math.tan(math.pi / 6.0));
  final double xc = width / 2;
  final double yc = height / 2;

  final int half = size ~/ 2;
  for (int dy = -half; dy <= half; dy++) {
    for (int dx = -half; dx <= half; dx++) {
      final double xd = targetXd + dx;
      final double yd = targetYd + dy;

      final double theta = (xd - xc) / f;
      final double hVal = (yd - yc) / f;

      final double xsDouble = f * math.tan(theta) + xc;
      final double ysDouble = f * hVal / math.cos(theta) + yc;

      final int xs = xsDouble.round();
      final int ys = ysDouble.round();

      if (xs >= 0 && xs < width && ys >= 0 && ys < height) {
        src.setPixelRgb(xs, ys, 250, 250, 250);
      }
    }
  }
}

void main() {
  group('PanoramaStitcher Cylindrical Warping Tests', () {
    test('Verify warpCylindrical returns image with same dimensions', () {
      final src = img.Image(width: 100, height: 100);
      final dst = PanoramaStitcher.warpCylindrical(src);
      expect(dst.width, equals(100));
      expect(dst.height, equals(100));
    });
  });

  group('PanoramaStitcher Feature Matching & Alignment Tests', () {
    test('Verify matchFrames finds correct horizontal translation', () {
      final img1 = img.Image(width: 200, height: 100);
      final img2 = img.Image(width: 200, height: 100);

      // Fill with black background
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 200; x++) {
          img1.setPixelRgb(x, y, 10, 10, 10);
          img2.setPixelRgb(x, y, 10, 10, 10);
        }
      }

      // Draw distinct 2D square boxes at patch centers to prevent vertical aperture ambiguity
      const int dx = 120;
      final List<int> patchYCenters = [25, 37, 50, 62, 75];
      for (final yc in patchYCenters) {
        for (int my = -3; my <= 3; my++) {
          for (int mx = -3; mx <= 3; mx++) {
            img1.setPixelRgb(158 + mx, yc + my, 255, 255, 255);
            img2.setPixelRgb(158 - dx + mx, yc + my, 255, 255, 255);
          }
        }
      }

      final match = PanoramaStitcher.matchFrames(img1, img2);
      expect(match['success'], isTrue);
      // Allow minor offset deviation
      expect(((match['dx'] as int) - dx).abs(), lessThanOrEqualTo(2));
      expect(match['confidence'], greaterThan(0.5));
    });

    test('Verify matchFrames returns failure on non-overlapping features', () {
      final img1 = img.Image(width: 200, height: 100);
      final img2 = img.Image(width: 200, height: 100);

      // Fill with black background
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 200; x++) {
          img1.setPixelRgb(x, y, 10, 10, 10);
          img2.setPixelRgb(x, y, 10, 10, 10);
        }
      }

      // Draw mismatching feature boxes
      final List<int> patchYCenters = [25, 37, 50, 62, 75];
      for (final yc in patchYCenters) {
        for (int my = -3; my <= 3; my++) {
          for (int mx = -3; mx <= 3; mx++) {
            img1.setPixelRgb(158 + mx, yc + my, 255, 255, 255);
            img2.setPixelRgb(100 + mx, yc + my, 255, 255, 255); // mismatch
          }
        }
      }

      final match = PanoramaStitcher.matchFrames(img1, img2);
      expect(match['success'], isFalse);
    });
  });

  group('PanoramaStitcher Pipeline Tests', () {
    test('Verify stitch returns failed when frames length is invalid', () async {
      final List<img.Image> rawFrames = [
        img.Image(width: 100, height: 100),
      ];

      final result = await PanoramaStitcher.stitch(rawFrames);
      expect(result.quality, equals(StitchingQuality.failed));
      expect(result.stitchedImage, isNull);
    });

    test('Verify stitch performs successfully with overlapping feature frames', () async {
      final List<img.Image> rawFrames = List.generate(6, (_) => img.Image(width: 200, height: 100));

      // Paint mock pre-warped overlapping features in all 6 adjacent images
      final List<int> patchYCenters = [25, 37, 50, 62, 75];
      for (int i = 0; i < 6; i++) {
        // Fill frame with gray background
        for (int y = 0; y < 100; y++) {
          for (int x = 0; x < 200; x++) {
            rawFrames[i].setPixelRgb(x, y, 10, 10, 10);
          }
        }
        for (final yc in patchYCenters) {
          paintWarpedBox(rawFrames[i], 158, yc.toDouble(), 6);
          paintWarpedBox(rawFrames[i], 38, yc.toDouble(), 6);
        }
      }

      final result = await PanoramaStitcher.stitch(rawFrames);
      expect(result.quality, isIn([StitchingQuality.excellent, StitchingQuality.good, StitchingQuality.acceptable]));
      expect(result.stitchedImage, isNotNull);
      expect(result.stitchedImage!.width, greaterThan(0));
      expect(result.stitchedImage!.width, equals(result.stitchedImage!.height * 2));
      expect(result.matchedPairsCount, equals(6));
    });

    test('Verify stitch detects quality failure when features do not match', () async {
      final List<img.Image> rawFrames = List.generate(6, (_) => img.Image(width: 200, height: 100));
      // No features painted - matching will fail
      final result = await PanoramaStitcher.stitch(rawFrames);
      expect(result.quality, equals(StitchingQuality.failed));
      expect(result.stitchedImage, isNull);
    });
  });
}
