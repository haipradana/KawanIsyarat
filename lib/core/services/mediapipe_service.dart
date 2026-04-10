import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

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

/// Real MediaPipe service using google_mlkit_pose_detection + hand_landmarker.
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
  bool _isInitialized = false;

  // ML Kit Pose Detector
  PoseDetector? _poseDetector;

  // Hand Landmarker plugin
  HandLandmarkerPlugin? _handLandmarker;

  // Cache last extracted keypoints for overlay
  List<double> _lastKeypoints = List.filled(258, 0.0);

  void startCapture() {
    _isActive = true;
    _initializeIfNeeded();
  }

  void stopCapture() {
    _isActive = false;
  }

  bool get isActive => _isActive;

  /// Initialize detectors lazily.
  void _initializeIfNeeded() {
    if (_isInitialized) return;

    // Pose detector — accurate mode for better quality
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
      ),
    );

    // Hand landmarker — detect up to 2 hands
    try {
      _handLandmarker = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.3,
        delegate: HandLandmarkerDelegate.gpu,
      );
    } catch (e) {
      debugPrint('[MediaPipe] Failed to create HandLandmarker (GPU), trying CPU: $e');
      try {
        _handLandmarker = HandLandmarkerPlugin.create(
          numHands: 2,
          minHandDetectionConfidence: 0.3,
          delegate: HandLandmarkerDelegate.cpu,
        );
      } catch (e2) {
        debugPrint('[MediaPipe] Failed to create HandLandmarker (CPU): $e2');
      }
    }

    _isInitialized = true;
    debugPrint('[MediaPipe] Initialized: pose=${_poseDetector != null}, hand=${_handLandmarker != null}');
  }

  /// Extract 258 keypoints from a camera frame.
  /// Uses ML Kit for pose + hand_landmarker for hands.
  ///
  /// Returns synchronously with cached result if detection is still processing.
  Future<List<double>> extractKeypointsAsync(CameraImage frame, int sensorOrientation) async {
    if (!_isActive) return List.filled(258, 0.0);

    final keypoints = List<double>.filled(258, 0.0);

    // --- Pose Detection (33 landmarks × 4) ---
    if (_poseDetector != null) {
      try {
        final inputImage = _cameraImageToInputImage(frame, sensorOrientation);
        if (inputImage != null) {
          final poses = await _poseDetector!.processImage(inputImage);
          if (poses.isNotEmpty) {
            final pose = poses.first;
            // Fill 33 pose landmarks
            for (final type in PoseLandmarkType.values) {
              final landmark = pose.landmarks[type];
              if (landmark != null) {
                final idx = type.index * 4;
                if (idx + 3 < 132) {
                  // Normalize to 0-1 range using frame dimensions
                  keypoints[idx] = (landmark.x / frame.width).clamp(0.0, 1.0);
                  keypoints[idx + 1] = (landmark.y / frame.height).clamp(0.0, 1.0);
                  keypoints[idx + 2] = landmark.z / 1000.0; // z is in mm, normalize
                  keypoints[idx + 3] = landmark.likelihood;
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[MediaPipe] Pose detection error: $e');
      }
    }

    // --- Hand Landmark Detection (21 landmarks × 3 per hand) ---
    if (_handLandmarker != null) {
      try {
        final hands = _handLandmarker!.detect(frame, sensorOrientation);
        if (hands.isNotEmpty) {
          for (int handIdx = 0; handIdx < hands.length && handIdx < 2; handIdx++) {
            final hand = hands[handIdx];
            // HandLandmarkerPlugin tidak expose handedness label.
            // Gunakan wrist x-position sebagai proxy — matches MediaPipe training behavior:
            //   wrist.x < 0.5 → kiri frame → "Left" di MediaPipe → slot lh (132-194)
            //   wrist.x >= 0.5 → kanan frame → "Right" di MediaPipe → slot rh (195-257)
            // Ini cocok dengan training code: label=="Left" → lh, else → rh.
            final wristX = hand.landmarks.isNotEmpty ? hand.landmarks[0].x : 0.5;
            final int baseIdx = wristX < 0.5 ? 132 : 195;

            final landmarks = hand.landmarks;
            for (int i = 0; i < landmarks.length && i < 21; i++) {
              final lm = landmarks[i];
              final idx = baseIdx + i * 3;
              if (idx + 2 < 258) {
                keypoints[idx] = lm.x;     // already normalized 0-1
                keypoints[idx + 1] = lm.y; // already normalized 0-1
                keypoints[idx + 2] = lm.z; // depth
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[MediaPipe] Hand detection error: $e');
      }
    }

    _lastKeypoints = keypoints;
    return keypoints;
  }

  /// Synchronous version — returns last cached keypoints.
  /// For backward compatibility with existing code that calls extractKeypoints.
  List<double> extractKeypoints(CameraImage frame) {
    // Return last cached keypoints since async detection runs separately
    return List.from(_lastKeypoints);
  }

  /// Convert CameraImage (YUV420) to ML Kit InputImage via NV21.
  /// ML Kit on Android requires NV21 format — YUV420 multi-plane must be merged.
  InputImage? _cameraImageToInputImage(CameraImage image, int sensorOrientation) {
    try {
      final rotation = InputImageRotationValue.fromRawValue(sensorOrientation) ??
          InputImageRotation.rotation0deg;

      // Merge YUV420 planes → NV21 (Y plane + interleaved VU)
      final nv21 = _yuv420ToNv21(image);

      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    } catch (e) {
      debugPrint('[MediaPipe] InputImage conversion error: $e');
      return null;
    }
  }

  /// Convert YUV420 CameraImage to NV21 byte array.
  Uint8List _yuv420ToNv21(CameraImage image) {
    final w = image.width;
    final h = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final nv21 = Uint8List(w * h + (w * h ~/ 2));

    // Copy Y plane row by row (handle row stride padding)
    int yOffset = 0;
    for (int row = 0; row < h; row++) {
      final srcStart = row * yPlane.bytesPerRow;
      nv21.setRange(yOffset, yOffset + w, yPlane.bytes, srcStart);
      yOffset += w;
    }

    // Interleave V and U into NV21 (VU order)
    final uvHeight = h ~/ 2;
    final uvWidth = w ~/ 2;
    int uvOffset = w * h;
    for (int row = 0; row < uvHeight; row++) {
      for (int col = 0; col < uvWidth; col++) {
        final vIdx = row * vPlane.bytesPerRow + col * vPlane.bytesPerPixel!;
        final uIdx = row * uPlane.bytesPerRow + col * uPlane.bytesPerPixel!;
        nv21[uvOffset++] = vPlane.bytes[vIdx];
        nv21[uvOffset++] = uPlane.bytes[uIdx];
      }
    }

    return nv21;
  }

  /// Compute hand bounding box from MediaPipe keypoints.
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

  /// Crop hand from RGBA image data.
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

  /// Normalize raw 258 keypoints to 108 Siformer features.
  ///
  /// Output layout: [body 24] + [left_hand 42] + [right_hand 42] = 108 floats
  ///
  /// [sensorOrientation] should be 90 for portrait Pixel 6a (default).
  List<double> normalizeSiformer(
    List<double> rawKeypoints, {
    int sensorOrientation = 90,
  }) {
    final features = List<double>.filled(108, 0.0);

    // ── Body normalization (12 keypoints × 2 = 24 floats) ──────────────────
    //
    // Pose is stored in landscape sensor space (sensorOrientation=90).
    // 90° CW rotation transform (landscape sensor → portrait display):
    //   portrait_x = landscape_y  = rawKeypoints[i*4 + 1]
    //   portrait_y = 1 - landscape_x = 1 - rawKeypoints[i*4]
    //
    // The "1 -" inversion is critical: without it, y-axis is flipped
    // (top of portrait maps to y≈1 instead of y≈0).

    double portraitX(int i) => rawKeypoints[i * 4 + 1];        // landscape_y → portrait_x
    double portraitY(int i) => 1.0 - rawKeypoints[i * 4];      // 1 - landscape_x → portrait_y

    // Neck = midpoint of left(11) + right(12) shoulders
    final neckX = (portraitX(11) + portraitX(12)) / 2.0;
    final neckY = (portraitY(11) + portraitY(12)) / 2.0;

    // Head metric = shoulder-to-shoulder distance
    double headMetric = sqrt(
      pow(portraitX(11) - portraitX(12), 2) + pow(portraitY(11) - portraitY(12), 2),
    );

    // Fallback: use nose(0) → neck distance if shoulders are too close
    if (headMetric < 1e-5) {
      headMetric = sqrt(
        pow(portraitX(0) - neckX, 2) + pow(portraitY(0) - neckY, 2),
      );
      if (headMetric < 1e-5) headMetric = 1e-5; // absolute fallback
    }

    // Bounding box for body normalization
    final startX = neckX - 3.0 * headMetric;
    final startY = portraitY(2) + headMetric; // left_eye.y + headMetric  (bottom)
    final endX = neckX + 3.0 * headMetric;
    final endY = startY - 6.0 * headMetric;   // top

    final bboxW = endX - startX; // > 0
    final bboxH = startY - endY; // startY > endY → positive

    // 12 body keypoint indices (matches Python training order):
    // nose(0), neck, right_eye(5), left_eye(2), right_ear(8), left_ear(7),
    // right_shoulder(12), left_shoulder(11), right_elbow(14), left_elbow(13),
    // right_wrist(16), left_wrist(15)
    const List<int> bodyIndices = [0, -1, 5, 2, 8, 7, 12, 11, 14, 13, 16, 15];

    for (int i = 0; i < bodyIndices.length; i++) {
      final idx = bodyIndices[i];
      double x, y;
      if (idx == -1) {
        // neck — synthetic keypoint
        x = neckX;
        y = neckY;
      } else {
        x = portraitX(idx);
        y = portraitY(idx);
      }

      final nx = bboxW.abs() > 1e-9 ? ((x - startX) / bboxW).clamp(0.0, 1.0) : 0.0;
      final ny = bboxH.abs() > 1e-9 ? ((y - endY) / bboxH).clamp(0.0, 1.0) : 0.0;
      features[i * 2] = nx;
      features[i * 2 + 1] = ny;
    }

    // ── Hand normalization (21 keypoints × 2 = 42 floats each) ────────────
    _normalizeHandInto(rawKeypoints, 132, features, 24);  // left hand
    _normalizeHandInto(rawKeypoints, 195, features, 66);  // right hand

    return features;
  }

  /// Normalize one hand's landmarks into [out] starting at [dstStart].
  ///
  /// [srcStart]: 132 for left hand, 195 for right hand.
  /// Hand coordinates are already in display space (hand_landmarker handles
  /// rotation), so no swap is needed here.
  void _normalizeHandInto(
    List<double> keypoints,
    int srcStart,
    List<double> out,
    int dstStart,
  ) {
    // Collect valid (non-zero) landmarks
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    int validCount = 0;

    for (int i = 0; i < 21; i++) {
      final base = srcStart + i * 3;
      final x = keypoints[base];
      final y = keypoints[base + 1];
      if (x != 0.0 || y != 0.0) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        validCount++;
      }
    }

    if (validCount < 5) return; // leave zeros — hand not reliably detected

    final width = maxX - minX;
    final height = maxY - minY;

    double deltaX, deltaY;
    if (width > height) {
      deltaX = 0.1 * width;
      deltaY = deltaX + (width - height) / 2.0;
    } else {
      deltaY = 0.1 * height;
      deltaX = deltaY + (height - width) / 2.0;
    }

    final bx1 = minX - deltaX;
    final bx2 = maxX + deltaX;
    final by1 = minY - deltaY;
    final by2 = maxY + deltaY;

    final bw = bx2 - bx1;
    final bh = by2 - by1;

    for (int i = 0; i < 21; i++) {
      final base = srcStart + i * 3;
      final x = keypoints[base];
      final y = keypoints[base + 1];
      final nx = bw > 1e-9 ? ((x - bx1) / bw).clamp(0.0, 1.0) : 0.0;
      final ny = bh > 1e-9 ? ((y - by1) / bh).clamp(0.0, 1.0) : 0.0;
      out[dstStart + i * 2] = nx;
      out[dstStart + i * 2 + 1] = ny;
    }
  }

  /// Get hand landmark positions for skeleton overlay (normalized 0-1).
  /// Hand landmarks dari hand_landmarker disimpan di sensor space.
  /// Untuk portrait display (sensorOrientation=90): swap x↔y sama seperti pose.
  /// LSTM tetap pakai keypoints asli (tidak berubah) — ini hanya untuk visual overlay.
  List<Offset> getHandLandmarkPositions(
    List<double> keypoints,
    Size canvasSize, {
    bool rightHand = true,
    int sensorOrientation = 90,
  }) {
    final start = rightHand ? 195 : 132;
    final positions = <Offset>[];
    final needSwap = sensorOrientation == 90 || sensorOrientation == 270;
    for (int i = 0; i < 21; i++) {
      final base = start + i * 3;
      if (base + 1 < keypoints.length) {
        final kx = keypoints[base];
        final ky = keypoints[base + 1];
        if (kx != 0.0 || ky != 0.0) {
          // 90° CW rotation: portrait_x = ky, portrait_y = 1 - kx
          final ox = needSwap ? ky * canvasSize.width  : kx * canvasSize.width;
          final oy = needSwap ? (1.0 - kx) * canvasSize.height : ky * canvasSize.height;
          positions.add(Offset(ox, oy));
        }
      }
    }
    return positions;
  }

  /// Dispose detectors.
  Future<void> dispose() async {
    _poseDetector?.close();
    _handLandmarker?.dispose();
    _poseDetector = null;
    _handLandmarker = null;
    _isInitialized = false;
    _isActive = false;
  }
}
