import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Bounding box from palm detection, normalized [0,1].
class HandBoundingBox {
  final double xCenter, yCenter, width, height;
  final double score;

  const HandBoundingBox({
    required this.xCenter,
    required this.yCenter,
    required this.width,
    required this.height,
    required this.score,
  });

  double get xMin => xCenter - width / 2;
  double get yMin => yCenter - height / 2;
  double get xMax => xCenter + width / 2;
  double get yMax => yCenter + height / 2;

  /// Expand bbox by a factor for better cropping.
  HandBoundingBox expand(double factor) {
    final newW = width * factor;
    final newH = height * factor;
    return HandBoundingBox(
      xCenter: xCenter,
      yCenter: yCenter,
      width: newW,
      height: newH,
      score: score,
    );
  }

  /// Clamp to [0,1] range.
  HandBoundingBox clamp01() {
    final x1 = xMin.clamp(0.0, 1.0);
    final y1 = yMin.clamp(0.0, 1.0);
    final x2 = xMax.clamp(0.0, 1.0);
    final y2 = yMax.clamp(0.0, 1.0);
    return HandBoundingBox(
      xCenter: (x1 + x2) / 2,
      yCenter: (y1 + y2) / 2,
      width: x2 - x1,
      height: y2 - y1,
      score: score,
    );
  }

  @override
  String toString() =>
      'HandBBox(center: ${xCenter.toStringAsFixed(2)},${yCenter.toStringAsFixed(2)}, '
      'size: ${width.toStringAsFixed(2)}×${height.toStringAsFixed(2)}, '
      'score: ${score.toStringAsFixed(2)})';
}

/// Real MediaPipe Palm Detection using tflite_flutter.
///
/// Model: palm_detection_lite.tflite (1.9 MB)
/// Input: [1, 192, 192, 3] float32, normalized to [-1, 1]
/// Output:
///   - regressors: [1, 2016, 18] — bbox + 7 keypoint coords per anchor
///   - classificators: [1, 2016, 1] — confidence scores
///
/// Uses SSD anchors for decoding bounding boxes.
class HandDetectorService {
  static final HandDetectorService _instance = HandDetectorService._internal();
  factory HandDetectorService() => _instance;
  HandDetectorService._internal();

  Interpreter? _interpreter;
  bool _isLoaded = false;
  late List<_Anchor> _anchors;

  static const int _inputSize = 192;
  static const double _scoreThreshold = 0.5;
  static const double _nmsThreshold = 0.3;

  Future<void> initialize() async {
    if (_isLoaded) return;

    _interpreter = await Interpreter.fromAsset(
      'assets/models/palm_detection_lite.tflite',
      options: InterpreterOptions()..threads = 2,
    );

    // Generate SSD anchors for palm detection model
    _anchors = _generateAnchors();

    final inShape = _interpreter!.getInputTensor(0).shape;
    final outShapes = List.generate(
      _interpreter!.getOutputTensors().length,
      (i) => _interpreter!.getOutputTensor(i).shape,
    );
    debugPrint('[HandDetector] Loaded. Input: $inShape, Outputs: $outShapes');
    debugPrint('[HandDetector] Anchors: ${_anchors.length}');

    _isLoaded = true;
  }

  bool get isLoaded => _isLoaded;

  /// Detect hands from RGBA image bytes.
  ///
  /// Returns list of bounding boxes sorted by confidence (best first).
  List<HandBoundingBox> detect(Uint8List rgba, int width, int height) {
    if (!_isLoaded || _interpreter == null) return [];

    final input = _preprocess(rgba, width, height);
    final numAnchors = _anchors.length;

    // Check actual output tensor shapes to determine order
    final outTensor0 = _interpreter!.getOutputTensor(0);
    final outTensor1 = _interpreter!.getOutputTensor(1);
    debugPrint('[HandDetector] Output0 shape: ${outTensor0.shape}, Output1 shape: ${outTensor1.shape}');

    // Auto-detect which output is regressors (18) vs classificators (1)
    final bool output0IsRegressor = outTensor0.shape.last == 18;

    final regressors = List.generate(1, (_) => List.generate(numAnchors, (_) => List.filled(18, 0.0)));
    final classificators = List.generate(1, (_) => List.generate(numAnchors, (_) => List.filled(1, 0.0)));

    final outputs = <int, Object>{};
    if (output0IsRegressor) {
      outputs[0] = regressors;
      outputs[1] = classificators;
    } else {
      outputs[0] = classificators;
      outputs[1] = regressors;
    }

    _interpreter!.runForMultipleInputs([input.reshape([1, _inputSize, _inputSize, 3])], outputs);

    // Debug: analyze raw scores
    double maxRawScore = -999;
    double maxSigmoidScore = 0;
    final allScores = <double>[];

    for (int i = 0; i < numAnchors; i++) {
      final raw = classificators[0][i][0];
      final sig = _sigmoid(raw);
      allScores.add(sig);
      if (raw > maxRawScore) maxRawScore = raw;
      if (sig > maxSigmoidScore) maxSigmoidScore = sig;
    }

    allScores.sort((a, b) => b.compareTo(a));
    final top5 = allScores.take(5).map((s) => s.toStringAsFixed(3)).join(', ');
    debugPrint('[HandDetector] Raw max: ${maxRawScore.toStringAsFixed(2)}, '
        'Sigmoid max: ${maxSigmoidScore.toStringAsFixed(4)}, '
        'Top5: [$top5]');

    // Decode detections
    final detections = <HandBoundingBox>[];

    for (int i = 0; i < numAnchors; i++) {
      final score = _sigmoid(classificators[0][i][0]);
      if (score < _scoreThreshold) continue;

      final anchor = _anchors[i];

      // Decode in letterbox coordinate space [0,1]
      // MediaPipe order: [y_center, x_center, height, width, kp0_y, kp0_x, ...]
      final lcy = regressors[0][i][0] / _inputSize + anchor.y;  // Y center
      final lcx = regressors[0][i][1] / _inputSize + anchor.x;  // X center
      final lh  = regressors[0][i][2] / _inputSize;              // Height
      final lw  = regressors[0][i][3] / _inputSize;              // Width

      // Remap from letterbox coords to original image coords
      final cx = (lcx * _inputSize - _letterboxOffsetX) / (_inputSize - 2 * _letterboxOffsetX);
      final cy = (lcy * _inputSize - _letterboxOffsetY) / (_inputSize - 2 * _letterboxOffsetY);
      final w  = lw * _inputSize / (_inputSize - 2 * _letterboxOffsetX);
      final h  = lh * _inputSize / (_inputSize - 2 * _letterboxOffsetY);

      detections.add(HandBoundingBox(
        xCenter: cx,
        yCenter: cy,
        width: w,
        height: h,
        score: score,
      ));
    }

    debugPrint('[HandDetector] Detections before NMS: ${detections.length}');
    if (detections.isNotEmpty) {
      debugPrint('[HandDetector] Best: ${detections.first}');
    }

    if (detections.isEmpty) return [];
    return _nms(detections);
  }

  // Letterbox state for remapping output coords
  double _letterboxScale = 1.0;
  double _letterboxOffsetX = 0.0;
  double _letterboxOffsetY = 0.0;

  /// Preprocess RGBA → Float32 [192×192×3] normalized to [-1, 1].
  /// Uses LETTERBOX (pad to square, preserve aspect ratio).
  Float32List _preprocess(Uint8List rgba, int width, int height) {
    final input = Float32List(_inputSize * _inputSize * 3);

    // Letterbox: scale to fit 192×192, pad the rest with black (0/gray)
    final scale = _inputSize / max(width, height);
    final newW = (width * scale).round();
    final newH = (height * scale).round();
    final offsetX = (_inputSize - newW) ~/ 2;
    final offsetY = (_inputSize - newH) ~/ 2;

    // Store for bbox remapping
    _letterboxScale = scale;
    _letterboxOffsetX = offsetX.toDouble();
    _letterboxOffsetY = offsetY.toDouble();

    debugPrint('[HandDetector] Letterbox: ${width}×$height → ${newW}×$newH, offset=($offsetX,$offsetY), scale=${scale.toStringAsFixed(4)}');

    // Fill with -1.0 (black in [-1,1] range)
    for (int i = 0; i < input.length; i++) {
      input[i] = -1.0;
    }

    // Copy pixels with bilinear-ish sampling
    for (int y = 0; y < newH; y++) {
      for (int x = 0; x < newW; x++) {
        final srcX = (x / scale).toInt().clamp(0, width - 1);
        final srcY = (y / scale).toInt().clamp(0, height - 1);
        final srcIdx = (srcY * width + srcX) * 4;

        final dstX = x + offsetX;
        final dstY = y + offsetY;
        final dstIdx = (dstY * _inputSize + dstX) * 3;

        if (srcIdx + 2 < rgba.length && dstIdx + 2 < input.length) {
          input[dstIdx]     = rgba[srcIdx] / 127.5 - 1.0;
          input[dstIdx + 1] = rgba[srcIdx + 1] / 127.5 - 1.0;
          input[dstIdx + 2] = rgba[srcIdx + 2] / 127.5 - 1.0;
        }
      }
    }

    return input;
  }

  double _sigmoid(double x) => 1.0 / (1.0 + exp(-x));

  /// Non-maximum suppression.
  List<HandBoundingBox> _nms(List<HandBoundingBox> detections) {
    detections.sort((a, b) => b.score.compareTo(a.score));
    final kept = <HandBoundingBox>[];

    for (final det in detections) {
      bool suppress = false;
      for (final k in kept) {
        if (_iou(det, k) > _nmsThreshold) {
          suppress = true;
          break;
        }
      }
      if (!suppress) {
        kept.add(det);
      }
    }

    return kept;
  }

  /// Intersection over Union.
  double _iou(HandBoundingBox a, HandBoundingBox b) {
    final x1 = max(a.xMin, b.xMin);
    final y1 = max(a.yMin, b.yMin);
    final x2 = min(a.xMax, b.xMax);
    final y2 = min(a.yMax, b.yMax);

    final intersection = max(0.0, x2 - x1) * max(0.0, y2 - y1);
    final aArea = a.width * a.height;
    final bArea = b.width * b.height;
    final union = aArea + bArea - intersection;

    return union > 0 ? intersection / union : 0;
  }

  /// Generate SSD anchors for MediaPipe palm detection.
  ///
  /// Config from MediaPipe palm_detection_lite:
  /// - strides: [8, 16, 16, 16]
  /// - numLayers: 4
  /// - inputSize: 192
  /// - anchorOffsetX/Y: 0.5
  /// - interpolatedScaleAspectRatio: 1.0
  List<_Anchor> _generateAnchors() {
    final anchors = <_Anchor>[];

    // Palm detection anchor config: 2 anchors per cell for all layers
    // Layer 0: stride 8 → 24×24×2 = 1152
    // Layer 1-3: stride 16 → 12×12×2 = 288 each
    // Total: 1152 + 288×3 = 2016
    const strides = [8, 16, 16, 16];
    const anchorsPerStride = [2, 2, 2, 2];

    for (int layerIdx = 0; layerIdx < strides.length; layerIdx++) {
      final stride = strides[layerIdx];
      final gridSize = _inputSize ~/ stride;
      final numAnchorsPerCell = anchorsPerStride[layerIdx];

      for (int y = 0; y < gridSize; y++) {
        for (int x = 0; x < gridSize; x++) {
          for (int a = 0; a < numAnchorsPerCell; a++) {
            anchors.add(_Anchor(
              x: (x + 0.5) / gridSize,
              y: (y + 0.5) / gridSize,
              w: 1.0,
              h: 1.0,
            ));
          }
        }
      }
    }

    return anchors;
  }

  void dispose() {
    _interpreter?.close();
    _isLoaded = false;
  }
}

class _Anchor {
  final double x, y, w, h;
  const _Anchor({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });
}
