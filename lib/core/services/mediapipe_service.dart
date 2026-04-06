import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Bounding box hasil dari MediaPipe hand landmarks (normalized 0.0–1.0).
class HandBoundingBox {
  final double xMin, yMin, xMax, yMax;

  const HandBoundingBox({
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
  });

  double get width => xMax - xMin;
  double get height => yMax - yMin;
  double get centerX => (xMin + xMax) / 2;
  double get centerY => (yMin + yMax) / 2;

  /// Expand box with padding (normalized) to not cut fingers/palm edge.
  HandBoundingBox expand({double padding = 0.08}) {
    return HandBoundingBox(
      xMin: (xMin - padding).clamp(0.0, 1.0),
      yMin: (yMin - padding).clamp(0.0, 1.0),
      xMax: (xMax + padding).clamp(0.0, 1.0),
      yMax: (yMax + padding).clamp(0.0, 1.0),
    );
  }

  /// Convert to pixel Rect for a given frame size.
  Rect toPixelRect(int frameWidth, int frameHeight) {
    return Rect.fromLTRB(
      xMin * frameWidth,
      yMin * frameHeight,
      xMax * frameWidth,
      yMax * frameHeight,
    );
  }
}

/// Result from cropping a hand region from a camera frame.
class CropResult {
  final Uint8List rgbaBytes;
  final int width;
  final int height;

  const CropResult({
    required this.rgbaBytes,
    required this.width,
    required this.height,
  });
}

/// MediaPipe hand landmark stub service.
///
/// When real MediaPipe is integrated via platform channel,
/// replace extractKeypoints() and the mock methods.
///
/// Keypoint layout (258 floats total):
///   [0..131]   = 33 pose landmarks × 4 (x, y, z, visibility)
///   [132..194] = 21 left hand landmarks × 3 (x, y, z)
///   [195..257] = 21 right hand landmarks × 3 (x, y, z)
class MediaPipeService {
  static final MediaPipeService _instance = MediaPipeService._internal();
  factory MediaPipeService() => _instance;
  MediaPipeService._internal();

  bool _isActive = false;
  final Random _random = Random();

  void startCapture() => _isActive = true;
  void stopCapture() => _isActive = false;
  bool get isActive => _isActive;

  /// Extract 258 keypoints from a camera frame.
  /// STUB — replace with MediaPipe Tasks platform channel.
  List<double> extractKeypoints(CameraImage frame) {
    if (!_isActive) return List.filled(258, 0.0);
    return _mockKeypoints();
  }

  /// Compute hand bounding box from MediaPipe keypoints.
  ///
  /// Tries right hand first (index 195–257), then left hand (132–194).
  /// Each hand has 21 landmarks × 3 values (x, y, z).
  HandBoundingBox? getBoundingBox(List<double> keypoints) {
    // Try right hand first
    var bbox = _bboxFromLandmarks(keypoints, startIdx: 195, stride: 3, count: 21);
    // Fallback to left hand
    bbox ??= _bboxFromLandmarks(keypoints, startIdx: 132, stride: 3, count: 21);
    return bbox?.expand(padding: 0.08);
  }

  HandBoundingBox? _bboxFromLandmarks(
    List<double> keypoints, {
    required int startIdx,
    required int stride,
    required int count,
  }) {
    final xCoords = <double>[];
    final yCoords = <double>[];

    for (int i = 0; i < count; i++) {
      final base = startIdx + i * stride;
      if (base + 1 >= keypoints.length) break;

      final x = keypoints[base];
      final y = keypoints[base + 1];

      // Skip zero-ed landmarks (hand not detected)
      if (x != 0.0 || y != 0.0) {
        xCoords.add(x);
        yCoords.add(y);
      }
    }

    if (xCoords.length < 5) return null; // need at least 5 valid landmarks

    return HandBoundingBox(
      xMin: xCoords.reduce(min),
      yMin: yCoords.reduce(min),
      xMax: xCoords.reduce(max),
      yMax: yCoords.reduce(max),
    );
  }

  /// Crop the hand region from a YUV420 camera frame.
  ///
  /// Extracts Y plane (grayscale) only → output as RGBA where R=G=B=Y.
  /// The result can be fed directly to AlphabetService.classifyFromCrop().
  CropResult? cropHand({
    required CameraImage frame,
    required HandBoundingBox bbox,
  }) {
    try {
      final w = frame.width;
      final h = frame.height;

      final x1 = (bbox.xMin * w).toInt().clamp(0, w - 1);
      final y1 = (bbox.yMin * h).toInt().clamp(0, h - 1);
      final x2 = (bbox.xMax * w).toInt().clamp(x1 + 1, w);
      final y2 = (bbox.yMax * h).toInt().clamp(y1 + 1, h);

      final cropW = x2 - x1;
      final cropH = y2 - y1;
      if (cropW <= 0 || cropH <= 0) return null;

      final yPlane = frame.planes[0].bytes;
      final yRowStride = frame.planes[0].bytesPerRow;

      final rgbaBytes = Uint8List(cropW * cropH * 4);
      int out = 0;

      for (int y = y1; y < y2; y++) {
        for (int x = x1; x < x2; x++) {
          final yVal = yPlane[y * yRowStride + x];
          rgbaBytes[out++] = yVal; // R
          rgbaBytes[out++] = yVal; // G
          rgbaBytes[out++] = yVal; // B
          rgbaBytes[out++] = 255; // A
        }
      }

      return CropResult(
        rgbaBytes: rgbaBytes,
        width: cropW,
        height: cropH,
      );
    } catch (e) {
      return null;
    }
  }

  /// Crop hand from a JPEG image (decoded to RGBA).
  /// For use with takePicture() fallback.
  CropResult? cropHandFromRGBA({
    required Uint8List rgba,
    required int imageWidth,
    required int imageHeight,
    required HandBoundingBox bbox,
  }) {
    try {
      final x1 = (bbox.xMin * imageWidth).toInt().clamp(0, imageWidth - 1);
      final y1 = (bbox.yMin * imageHeight).toInt().clamp(0, imageHeight - 1);
      final x2 = (bbox.xMax * imageWidth).toInt().clamp(x1 + 1, imageWidth);
      final y2 = (bbox.yMax * imageHeight).toInt().clamp(y1 + 1, imageHeight);

      final cropW = x2 - x1;
      final cropH = y2 - y1;
      if (cropW <= 0 || cropH <= 0) return null;

      final out = Uint8List(cropW * cropH * 4);
      int outIdx = 0;

      for (int y = y1; y < y2; y++) {
        for (int x = x1; x < x2; x++) {
          final srcIdx = (y * imageWidth + x) * 4;
          if (srcIdx + 3 < rgba.length) {
            out[outIdx++] = rgba[srcIdx];
            out[outIdx++] = rgba[srcIdx + 1];
            out[outIdx++] = rgba[srcIdx + 2];
            out[outIdx++] = rgba[srcIdx + 3];
          } else {
            out[outIdx++] = 0;
            out[outIdx++] = 0;
            out[outIdx++] = 0;
            out[outIdx++] = 255;
          }
        }
      }

      return CropResult(rgbaBytes: out, width: cropW, height: cropH);
    } catch (e) {
      return null;
    }
  }

  /// Get hand landmark screen positions for skeleton overlay.
  List<Offset> getHandLandmarkPositions(
    List<double> keypoints,
    Size canvasSize, {
    bool rightHand = true,
  }) {
    final start = rightHand ? 195 : 132;
    final positions = <Offset>[];
    for (int i = 0; i < 21; i++) {
      final base = start + i * 3;
      if (base + 1 < keypoints.length) {
        final x = keypoints[base] * canvasSize.width;
        final y = keypoints[base + 1] * canvasSize.height;
        positions.add(Offset(x, y));
      }
    }
    return positions;
  }

  // ── Mock keypoints for stub mode ───────────────────────────
  List<double> _mockKeypoints() {
    final kp = <double>[];
    // 33 pose landmarks × 4
    for (int i = 0; i < 33; i++) {
      kp.add(0.3 + _random.nextDouble() * 0.4); // x
      kp.add(0.2 + _random.nextDouble() * 0.6); // y
      kp.add(_random.nextDouble() * 0.1 - 0.05); // z
      kp.add(0.8 + _random.nextDouble() * 0.2); // visibility
    }
    // 21 left hand landmarks × 3
    for (int i = 0; i < 21; i++) {
      kp.add(0.2 + _random.nextDouble() * 0.3); // x
      kp.add(0.3 + _random.nextDouble() * 0.4); // y
      kp.add(_random.nextDouble() * 0.05);        // z
    }
    // 21 right hand landmarks × 3
    for (int i = 0; i < 21; i++) {
      kp.add(0.4 + _random.nextDouble() * 0.3); // x
      kp.add(0.3 + _random.nextDouble() * 0.4); // y
      kp.add(_random.nextDouble() * 0.05);        // z
    }
    return kp; // total 258
  }
}
