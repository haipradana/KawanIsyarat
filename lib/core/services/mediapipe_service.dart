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
        minHandDetectionConfidence: 0.5,
        delegate: HandLandmarkerDelegate.gpu,
      );
    } catch (e) {
      debugPrint('[MediaPipe] Failed to create HandLandmarker (GPU), trying CPU: $e');
      try {
        _handLandmarker = HandLandmarkerPlugin.create(
          numHands: 2,
          minHandDetectionConfidence: 0.5,
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
            // Determine if left or right hand
            // hand_landmarker returns handedness — first hand goes to right (195), second to left (132)
            // If only one hand, put it in right hand slot (more common for signing)
            final int baseIdx;
            if (hands.length == 1) {
              baseIdx = 195; // right hand slot
            } else {
              baseIdx = handIdx == 0 ? 195 : 132; // first=right, second=left
            }

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

  /// Convert CameraImage to ML Kit InputImage.
  InputImage? _cameraImageToInputImage(CameraImage image, int sensorOrientation) {
    try {
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;

      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotationValue.fromRawValue(sensorOrientation) ??
              InputImageRotation.rotation0deg,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('[MediaPipe] InputImage conversion error: $e');
      return null;
    }
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
        if (keypoints[base] != 0.0 || keypoints[base + 1] != 0.0) {
          positions.add(Offset(x, y));
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
