import 'dart:math';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart';

/// YOLO11n-based BISINDO alphabet sign detector.
///
/// One-shot pipeline: full image → 320×320 → YOLO → letter + bbox
/// Model: yolo_alphabet_sign_int8.tflite
/// Input:  [1, 320, 320, 3] float32, normalized [0, 1]
/// Output: [1, 30, 2100] — 2100 anchors × (4 bbox + 26 class scores)
///   Layout per anchor: [cx, cy, w, h, p_A, p_B, ..., p_Z]
///   All coords normalized to [0, 1] in 320×320 space (letterbox)
///
/// Classes: A–Z (26 total, indices 0–25)
class YoloAlphabetService {
  static final YoloAlphabetService _instance = YoloAlphabetService._internal();
  factory YoloAlphabetService() => _instance;
  YoloAlphabetService._internal();

  Interpreter? _interpreter;
  bool _isLoaded = false;

  static const int _inputSize = 320;
  static const int _numClasses = 26;
  static const int _numAnchors = 2100; // 40×40 + 20×20 + 10×10
  static const int _outputDim = 4 + _numClasses; // 30
  static const double _confThreshold = 0.10;
  static const double _iouThreshold = 0.45;

  // A–Z labels
  static const List<String> _labels = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
    'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
    'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  bool get isLoaded => _isLoaded;

  Future<void> initialize() async {
    if (_isLoaded) return;

    _interpreter = await Interpreter.fromAsset(
      'assets/models/yolo_alphabet_sign_int8.tflite',
      options: InterpreterOptions()..threads = 4,
    );

    final inShape = _interpreter!.getInputTensor(0).shape;
    final outShape = _interpreter!.getOutputTensor(0).shape;
    debugPrint('[YOLO] Loaded. Input: $inShape  Output: $outShape');

    _isLoaded = true;
  }

  /// Detect alphabet sign from an RGBA image.
  ///
  /// [rgbaBytes]: RGBA flat pixel data (width × height × 4 bytes)
  /// [imageWidth], [imageHeight]: original image dimensions
  ///
  /// Returns the best detection, or null if none found.
  YoloDetectionResult? detect({
    required Uint8List rgbaBytes,
    required int imageWidth,
    required int imageHeight,
  }) {
    if (!_isLoaded || _interpreter == null) return null;

    final stopwatch = Stopwatch()..start();

    // 1. Letterbox resize → [1, 320, 320, 3] float32
    final inputData = _preprocessLetterbox(rgbaBytes, imageWidth, imageHeight);

    // 2. Run inference
    // Output shape: [1, 30, 2100]
    final rawOutput = List.generate(
      1,
      (_) => List.generate(
        _outputDim,
        (_) => List.filled(_numAnchors, 0.0),
      ),
    );

    _interpreter!.run(inputData, rawOutput);

    // 3. Decode: transpose [1, 30, 2100] → [2100, 30]
    final detections = _decodeOutput(rawOutput[0]);

    // 4. NMS — if nothing passes threshold, fall back to best anchor
    final best = _nms(detections) ?? _bestAnchor(rawOutput[0]);

    stopwatch.stop();

    if (best == null) return null;

    // 5. De-letterbox bbox back to original image space
    final bbox = _deLettterbox(best.cx, best.cy, best.w, best.h, imageWidth, imageHeight);

    debugPrint('[YOLO] Detected: ${best.letter} (${(best.confidence * 100).toStringAsFixed(1)}%) in ${stopwatch.elapsedMilliseconds}ms');

    return YoloDetectionResult(
      letter: best.letter,
      confidence: best.confidence,
      classIndex: best.classIndex,
      bbox: bbox,
    );
  }

  // ─── Preprocessing ──────────────────────────────────────────

  /// Letterbox resize: maintain aspect ratio, pad with 0.5 (grey).
  /// Output: [1][320][320][3] float32 normalized [0, 1]
  List<List<List<List<double>>>> _preprocessLetterbox(
    Uint8List rgba,
    int srcW,
    int srcH,
  ) {
    const int dstSize = _inputSize;
    const double padVal = 0.5;

    // Scale to fit in dstSize×dstSize preserving aspect ratio
    final double scale = min(dstSize / srcW, dstSize / srcH);
    final int scaledW = (srcW * scale).round();
    final int scaledH = (srcH * scale).round();
    final int padX = (dstSize - scaledW) ~/ 2;
    final int padY = (dstSize - scaledH) ~/ 2;

    // Build output tensor [1][dstSize][dstSize][3] — preallocate as flat then reshape
    final input = List.generate(
      1,
      (_) => List.generate(
        dstSize,
        (y) => List.generate(
          dstSize,
          (x) {
            // Is this pixel in the scaled image region?
            final int srcPixX = x - padX;
            final int srcPixY = y - padY;

            if (srcPixX < 0 || srcPixX >= scaledW || srcPixY < 0 || srcPixY >= scaledH) {
              return [padVal, padVal, padVal];
            }

            // Bilinear source coords
            final double srcXf = srcPixX / scale;
            final double srcYf = srcPixY / scale;
            final int sx = srcXf.toInt().clamp(0, srcW - 1);
            final int sy = srcYf.toInt().clamp(0, srcH - 1);

            final int idx = (sy * srcW + sx) * 4;
            final double r = rgba[idx] / 255.0;
            final double g = rgba[idx + 1] / 255.0;
            final double b = rgba[idx + 2] / 255.0;
            return [r, g, b];
          },
        ),
      ),
    );

    return input;
  }

  // ─── Post-processing ─────────────────────────────────────────

  /// Decode raw output [30][2100] → list of candidate detections.
  List<_RawDetection> _decodeOutput(List<List<double>> raw) {
    // raw has shape [30][2100] (outputDim × numAnchors)
    // We need [2100][30] — transpose
    final candidates = <_RawDetection>[];

    for (int a = 0; a < _numAnchors; a++) {
      // Collect 30 values for this anchor
      final double cx = raw[0][a];
      final double cy = raw[1][a];
      final double w  = raw[2][a];
      final double h  = raw[3][a];

      // Find best class score among indices 4..29
      double bestScore = 0.0;
      int bestClass = 0;
      for (int c = 0; c < _numClasses; c++) {
        final double score = raw[4 + c][a];
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }

      if (bestScore >= _confThreshold) {
        candidates.add(_RawDetection(
          cx: cx, cy: cy, w: w, h: h,
          confidence: bestScore,
          classIndex: bestClass,
          letter: _labels[bestClass],
        ));
      }
    }

    return candidates;
  }

  /// Simple greedy NMS: keep the single highest-confidence detection.
  /// For alphabet practice we only need one letter at a time.
  _RawDetection? _nms(List<_RawDetection> detections) {
    if (detections.isEmpty) return null;

    // Sort by confidence descending
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));

    // Return highest confidence
    return detections.first;
  }

  /// Find the absolute best anchor regardless of threshold.
  /// Used as fallback when nothing passes the threshold.
  _RawDetection? _bestAnchor(List<List<double>> raw) {
    double bestScore = 0.0;
    int bestClass = 0;
    double bestCx = 0, bestCy = 0, bestW = 0, bestH = 0;

    for (int a = 0; a < _numAnchors; a++) {
      for (int c = 0; c < _numClasses; c++) {
        final double score = raw[4 + c][a];
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
          bestCx = raw[0][a];
          bestCy = raw[1][a];
          bestW = raw[2][a];
          bestH = raw[3][a];
        }
      }
    }

    if (bestScore <= 0.0) return null;
    return _RawDetection(
      cx: bestCx, cy: bestCy, w: bestW, h: bestH,
      confidence: bestScore,
      classIndex: bestClass,
      letter: _labels[bestClass],
    );
  }

  /// Convert letterboxed [0,1] coords back to original image normalized [0,1].
  YoloBBox _deLettterbox(double cx, double cy, double w, double h, int srcW, int srcH) {
    const int dstSize = _inputSize;
    final double scale = min(dstSize / srcW, dstSize / srcH);
    final int scaledW = (srcW * scale).round();
    final int scaledH = (srcH * scale).round();
    final double padXn = ((dstSize - scaledW) / 2) / dstSize; // normalized pad
    final double padYn = ((dstSize - scaledH) / 2) / dstSize;

    // Remove padding and rescale back
    final double cxAdj = (cx - padXn) / (scaledW / dstSize);
    final double cyAdj = (cy - padYn) / (scaledH / dstSize);
    final double wAdj  = w / (scaledW / dstSize);
    final double hAdj  = h / (scaledH / dstSize);

    return YoloBBox(
      xMin: (cxAdj - wAdj / 2).clamp(0.0, 1.0),
      yMin: (cyAdj - hAdj / 2).clamp(0.0, 1.0),
      xMax: (cxAdj + wAdj / 2).clamp(0.0, 1.0),
      yMax: (cyAdj + hAdj / 2).clamp(0.0, 1.0),
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
  }
}

// ─── Data models ───────────────────────────────────────────────

class YoloDetectionResult {
  final String letter;
  final double confidence;
  final int classIndex;
  final YoloBBox bbox;

  const YoloDetectionResult({
    required this.letter,
    required this.confidence,
    required this.classIndex,
    required this.bbox,
  });

  @override
  String toString() => '$letter (${(confidence * 100).toStringAsFixed(1)}%)';
}

class YoloBBox {
  final double xMin;
  final double yMin;
  final double xMax;
  final double yMax;

  const YoloBBox({
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
  });

  double get width => xMax - xMin;
  double get height => yMax - yMin;
  double get centerX => (xMin + xMax) / 2;
  double get centerY => (yMin + yMax) / 2;
}

class _RawDetection {
  final double cx, cy, w, h;
  final double confidence;
  final int classIndex;
  final String letter;

  const _RawDetection({
    required this.cx, required this.cy,
    required this.w,  required this.h,
    required this.confidence,
    required this.classIndex,
    required this.letter,
  });
}
