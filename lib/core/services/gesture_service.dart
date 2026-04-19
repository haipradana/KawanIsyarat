import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'mediapipe_service.dart';

/// BISINDO gesture recognition service — WL-BISINDO v3.
///
/// Pipeline:
///   Camera → MediaPipe (pose + hands) → 100-float nose-centered features
///   → Per-sequence std-normalization → Temporal derivatives (100 → 300)
///   → TFLite Conv1D+ECA+Transformer model → N-class prediction
///
/// Feature vector layout (100 floats per frame):
///   [0:42]   = Right hand 21×(x,y) nose-centered
///   [42:84]  = Left hand  21×(x,y) nose-centered
///   [84:86]  = Nose position (always 0,0 after centering)
///   [86:88]  = Left shoulder nose-centered
///   [88:90]  = Right shoulder nose-centered
///   [90:92]  = Left ear nose-centered
///   [92:94]  = Right ear nose-centered
///   [94:96]  = Left elbow nose-centered
///   [96:98]  = Right elbow nose-centered
///   [98]     = has_right_hand (1.0 if detected, NaN otherwise)
///   [99]     = has_left_hand  (1.0 if detected, NaN otherwise)
///
/// Normalization:
///   1. Nose-centered: all coords -= nose position
///   2. Per-sequence std normalization: (x - mean) / std
///   3. Temporal derivatives: position + velocity + acceleration = 300
class GestureService {
  static final GestureService _instance = GestureService._internal();
  factory GestureService() => _instance;
  GestureService._internal();

  Interpreter? _interpreter;
  Map<int, String> _labelMap = {};
  bool _isModelLoaded = false;

  final _glossController = StreamController<List<String>>.broadcast();
  Timer? _timer;
  final List<String> _currentGloss = [];
  bool _isCapturing = false;

  // ── Buffer config matching training ──────────────────────────────────────
  // Raw 98-dim nose-centered features (NOT yet std-normalized or derivatives)
  final List<List<double>> _rawFrameBuffer = [];
  static const int _sequenceLength = 30;
  static const int _rawFeatureDim = 100;      // matches training FEATURE_DIM
  // _derivFeatureDim = 300 (100 × 3: pos+vel+acc) — computed in _addTemporalDerivatives
  static const double _confidenceThreshold = 0.30;

  // Frame decimation: training used uniform-30 from ~2s gesture (≈15fps effective).
  // Camera runs at ~30fps → keep every 2nd frame so buffer covers ~2s = matches training.
  int _frameCounter = 0;
  static const int _frameSkipRate = 2; // add 1 frame every 2 camera frames

  // ── Per-sign recording state (matches test_video.py: collect 30 → predict once) ──
  bool _isRecordingSign = false;
  void Function(GestureResult)? _onSignDetected;
  void Function(int frameCount)? _onBufferProgress;
  List<double>? _lastGoodHandFrame; // for forward/backward fill

  final _mediaPipe = MediaPipeService();
  int _debugExtractCount = 0;
  List<double> _lastRawFeaturesForDebug =
      List<double>.filled(_rawFeatureDim, double.nan);

  Stream<List<String>> get glossStream => _glossController.stream;
  bool get isCapturing => _isCapturing;
  bool get isRecordingSign => _isRecordingSign;
  bool get isModelLoaded => _isModelLoaded;
  int get bufferLength => _rawFrameBuffer.length;
  List<double> get lastRawFeaturesForDebug => List<double>.from(_lastRawFeaturesForDebug);

  // ════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ════════════════════════════════════════════════════════════════════════

  Future<void> initialize() async {
    if (_isModelLoaded) return;

    try {
      // Load TFLite model
      _interpreter = await Interpreter.fromAsset(
        'assets/models/bisindo_wl_model.tflite',
        options: InterpreterOptions()..threads = 4,
      );
      debugPrint('[GestureService] Model loaded: bisindo_wl_model.tflite');
      debugPrint('[GestureService] Input: ${_interpreter!.getInputTensors()}');
      debugPrint('[GestureService] Output: ${_interpreter!.getOutputTensors()}');

      // Load label map
      final jsonStr = await rootBundle.loadString(
        'assets/models/bisindo_wl_labels.json',
      );
      final Map<String, dynamic> raw = json.decode(jsonStr);
      final Map<String, dynamic> i2l = raw['index_to_label'];
      _labelMap = i2l.map((k, v) => MapEntry(int.parse(k), v as String));
      debugPrint('[GestureService] Labels: ${_labelMap.length} classes');

      _isModelLoaded = true;
    } catch (e, st) {
      debugPrint('[GestureService] Load FAILED: $e');
      debugPrint('[GestureService] Stack: $st');
      _isModelLoaded = false;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // FEATURE EXTRACTION — 258 raw keypoints → 98 nose-centered features
  // ════════════════════════════════════════════════════════════════════════

  /// Convert 258 raw MediaPipe keypoints → 100-float nose-centered feature vector.
  ///
  /// This matches the training pipeline in kaggle_bisindo_wl.py:
  ///   - Nose-centered: all coords -= nose position
  ///   - NaN for undetected landmarks → handled during std-normalization
  ///   - Hand detection via hand_landmarker (already display-space)
  ///   - Pose via ML Kit (needs 90° rotation for portrait)
  ///   - Hand presence flags: features[98]=has_right, features[99]=has_left
  List<double> _extractBisindoFeatures(
    List<double> rawKeypoints,
    int sensorOrientation,
  ) {
    final features = List<double>.filled(_rawFeatureDim, double.nan);

    // ── Nose position (center point) ────────────────────────────────────────
    // ML Kit pose landmarks are already in portrait/display space after the
    // normalization fix in mediapipe_service.dart. No rotation needed here.
    double noseX = rawKeypoints[0 * 4];       // portrait x (0-1)
    double noseY = rawKeypoints[0 * 4 + 1];   // portrait y (0-1)

    // Training extractor only fills pose anchors when pose exists.
    final bool hasPose = noseX != 0.0 || noseY != 0.0;
    if (!hasPose) {
      noseX = 0.5;
      noseY = 0.5;
    }

    // ── Pose anchors [84:98] — 7 landmarks nose-centered ───────────────────
    // Indices: nose(0), left_shoulder(11), right_shoulder(12), left_ear(7), right_ear(8)
    if (hasPose) {
      const poseIndices = [0, 11, 12, 7, 8, 13, 14]; // nose, L_shoulder, R_shoulder, L_ear, R_ear, L_elbow, R_elbow
      for (int i = 0; i < poseIndices.length; i++) {
        final idx = poseIndices[i];
        // Coordinates already in portrait space — no rotation needed
        final px = rawKeypoints[idx * 4];
        final py = rawKeypoints[idx * 4 + 1];

        if (idx != 0 && px == 0.0 && py == 0.0) {
          continue;
        }

        features[84 + i * 2] = px - noseX;
        features[84 + i * 2 + 1] = py - noseY;
      }
    }

    // ── Hand landmarks nose-centered ────────────────────────────────────────
    // Raw keypoints layout:
    //   [132..194] = left hand  21 × 3 (x, y, z) — already in display space
    //   [195..257] = right hand 21 × 3 (x, y, z) — already in display space

    // Track which hands are detected for presence flags.
    bool hasRightHand = false;
    bool hasLeftHand = false;

    // Right hand → features[0:42]
    hasRightHand = _extractHandNoseCentered(
      rawKeypoints, 195, features, 0, noseX, noseY,
    );
    // Left hand → features[42:84]
    hasLeftHand = _extractHandNoseCentered(
      rawKeypoints, 132, features, 42, noseX, noseY,
    );

    // ── Hand presence flags [98:100] ────────────────────────────────────────
    // After std-normalization, NaN→0 is ambiguous. These binary flags give
    // the model an explicit signal to distinguish 1-hand vs 2-hand signs.
    features[98] = hasRightHand ? 1.0 : double.nan;
    features[99] = hasLeftHand  ? 1.0 : double.nan;

    // ── DEBUG: log nose + wrist positions (every 30th call) ─────────────────
    _debugExtractCount++;
    if (_debugExtractCount % 30 == 1) {
      // Right wrist from hand_landmarker (sensor space: lmX=sensor_x, lmY=sensor_y)
      final lmX = rawKeypoints[195];
      final lmY = rawKeypoints[196];
      // Right wrist nose-centered in portrait space (what model sees)
      final rwCX = features[0];
      final rwCY = features[1];
      debugPrint(
        '[GestureService] DEBUG coords: '
        'nose=(${noseX.toStringAsFixed(3)}, ${noseY.toStringAsFixed(3)}) '
        'R_wrist_sensor=(${lmX.toStringAsFixed(3)}, ${lmY.toStringAsFixed(3)}) '
        'R_wrist_portrait_centered=(${rwCX.toStringAsFixed(3)}, ${rwCY.toStringAsFixed(3)}) '
        'hasPose=$hasPose hasR=$hasRightHand hasL=$hasLeftHand',
      );
    }

    return features;
  }

  /// Extract one hand's 21 landmarks, nose-centered, into features array.
  /// Returns true if hand was detected (at least one non-zero landmark).
  ///
  /// hand_landmarker returns coordinates in sensor/landscape space:
  ///   lm.x = sensor horizontal (= portrait VERTICAL direction)
  ///   lm.y = sensor vertical   (= portrait HORIZONTAL direction)
  ///
  /// Training (Python) used portrait video space where x=horizontal, y=vertical.
  /// So we swap: feature_x = lm.y, feature_y = lm.x
  ///
  /// The nose (ML Kit) is already in portrait space, normalized by:
  ///   noseX = portrait_x_px / portrait_width_px  (frame.height for sensor 90°)
  ///   noseY = portrait_y_px / portrait_height_px (frame.width  for sensor 90°)
  /// lm.y is also normalized to portrait_width, lm.x to portrait_height → same scale ✓
  bool _extractHandNoseCentered(
    List<double> rawKeypoints,
    int srcStart,       // 132 for left, 195 for right
    List<double> features,
    int dstStart,       // 0 for right hand, 42 for left hand
    double noseX,
    double noseY,
  ) {
    bool hasHand = false;
    for (int i = 0; i < 21; i++) {
      final base = srcStart + i * 3;
      if (base + 1 >= rawKeypoints.length) break;

      final lmX = rawKeypoints[base];
      final lmY = rawKeypoints[base + 1];

      if (lmX != 0.0 || lmY != 0.0) {
        hasHand = true;
        // sensor space (sensorOrientation=90) → portrait display:
        //   portrait_x = lm.y  (sensor_y → portrait horizontal)
        //   portrait_y = 1 - lm.x  (sensor_x inverted → portrait vertical, 0=top)
        features[dstStart + i * 2]     = lmY - noseX;
        features[dstStart + i * 2 + 1] = (1.0 - lmX) - noseY;
      }
      // If not detected, stays NaN and is ignored during std-normalization.
    }
    return hasHand;
  }

  // ════════════════════════════════════════════════════════════════════════
  // NORMALIZATION & DERIVATIVES — matching training pipeline exactly
  // ════════════════════════════════════════════════════════════════════════

  /// Per-sequence std normalization.
  /// Matches training: x = (x - nanmean) / nanstd, then NaN -> 0.
  List<List<double>> _stdNormalize(List<List<double>> sequence) {
    double sum = 0.0;
    double sumSq = 0.0;
    int count = 0;

    for (final frame in sequence) {
      for (final val in frame) {
        if (!val.isFinite) continue;
        sum += val;
        sumSq += val * val;
        count++;
      }
    }

    if (count == 0) {
      return sequence.map((frame) => List<double>.filled(frame.length, 0.0)).toList();
    }

    final mean = sum / count;
    final variance = (sumSq / count) - (mean * mean);
    final std = variance > 1e-12 ? sqrt(variance) : 1.0;

    return sequence.map((frame) {
      return frame.map((val) {
        if (!val.isFinite) return 0.0;
        final normalized = (val - mean) / std;
        return normalized.isFinite ? normalized : 0.0;
      }).toList();
    }).toList();
  }

  /// Compute temporal derivatives: position + velocity + acceleration.
  /// (30, 98) → (30, 294)
  /// Matches training: vel[t] = x[t] - x[t-1], acc[t] = x[t] - x[t-2]
  List<List<double>> _addTemporalDerivatives(List<List<double>> sequence) {
    final int T = sequence.length;
    final int D = sequence[0].length;  // 98

    final result = <List<double>>[];

    for (int t = 0; t < T; t++) {
      final pos = sequence[t];
      final vel = List<double>.filled(D, 0.0);
      final acc = List<double>.filled(D, 0.0);

      if (t >= 1) {
        for (int d = 0; d < D; d++) {
          vel[d] = sequence[t][d] - sequence[t - 1][d];
        }
      }
      if (t >= 2) {
        for (int d = 0; d < D; d++) {
          acc[d] = sequence[t][d] - sequence[t - 2][d];
        }
      }

      // Concatenate: position + velocity + acceleration = 294
      result.add([...pos, ...vel, ...acc]);
    }

    return result;
  }

  // ════════════════════════════════════════════════════════════════════════
  // FRAME BUFFER MANAGEMENT
  // ════════════════════════════════════════════════════════════════════════

  /// Add one frame of raw features directly (for testing/external use).
  void addFrame(List<double> noseCenteredFeatures) {
    if (noseCenteredFeatures.length != _rawFeatureDim) return;
    _addFrameToBuffer(noseCenteredFeatures);
  }

  /// Internal: add one frame to buffer.
  /// Decimation is handled by addFrameFromCameraAsync (before MediaPipe).
  ///
  /// In per-sign recording mode: collects exactly [_sequenceLength] frames
  /// then auto-predicts once (matching test_video.py / training pipeline).
  void _addFrameToBuffer(List<double> noseCenteredFeatures) {
    if (noseCenteredFeatures.length != _rawFeatureDim) return;

    // Always update debug visualization (even outside recording)
    _lastRawFeaturesForDebug = List<double>.from(noseCenteredFeatures);

    if (!_isRecordingSign) return; // only collect during active sign recording

    // Check if this frame has valid hand data
    bool hasHandData = false;
    for (int i = 0; i < 84; i++) {
      if (noseCenteredFeatures[i].isFinite && noseCenteredFeatures[i].abs() > 1e-6) {
        hasHandData = true;
        break;
      }
    }

    // Forward-fill: if hands not detected this frame, use last known positions.
    // Prevents buffer from filling with NaN when hand detection briefly fails.
    final frameToAdd = List<double>.from(noseCenteredFeatures);
    if (!hasHandData && _lastGoodHandFrame != null) {
      for (int i = 0; i < 84; i++) {
        frameToAdd[i] = _lastGoodHandFrame![i];
      }
    } else if (hasHandData) {
      _lastGoodHandFrame = List<double>.from(frameToAdd.sublist(0, 84));
    }

    _rawFrameBuffer.add(frameToAdd);
    _onBufferProgress?.call(_rawFrameBuffer.length);

    final len = _rawFrameBuffer.length;
    if (len == 1 || len % 10 == 0 || len == _sequenceLength) {
      debugPrint('[GestureService] frame $len/$_sequenceLength (hands=$hasHandData)');
    }

    // When exactly 30 frames collected → predict once (matches test_video.py)
    if (len >= _sequenceLength) {
      _isRecordingSign = false;
      _onBufferProgress?.call(_sequenceLength);

      final result = predict();
      debugPrint('[GestureService] Sign predict: $result');
      if (result != null) {
        _onSignDetected?.call(result);
      } else {
        _onSignDetected?.call(GestureResult(word: '?', confidence: 0.0, labelIndex: -1));
      }
      clearBuffer();
    }
  }

  /// Add a frame from camera image via MediaPipe extraction.
  /// Returns raw 258 keypoints for overlay rendering.
  ///
  /// Frame decimation: only runs MediaPipe on every [_frameSkipRate]-th frame
  /// to save CPU/GPU. Skipped frames return the last cached keypoints.
  Future<List<double>> addFrameFromCameraAsync(
    dynamic cameraImage,
    int sensorOrientation,
  ) async {
    // Decimation: skip MediaPipe on odd frames (save ~50% CPU/GPU)
    _frameCounter++;
    if (_frameCounter % _frameSkipRate != 0) {
      return _mediaPipe.lastKeypoints; // reuse last for overlay
    }

    final rawKeypoints = await _mediaPipe.extractKeypointsAsync(
      cameraImage,
      sensorOrientation,
    );
    final bisindoFeatures = _extractBisindoFeatures(
      rawKeypoints,
      sensorOrientation,
    );
    _addFrameToBuffer(bisindoFeatures);
    return rawKeypoints;
  }

  // ════════════════════════════════════════════════════════════════════════
  // FILL — forward + backward fill for missing hand frames
  // ════════════════════════════════════════════════════════════════════════

  /// Fill frames where hands were not detected using adjacent detected frames.
  ///
  /// Forward fill: propagates last known hand position forward.
  /// Backward fill: fills leading NaN frames from first detected frame.
  ///
  /// Only fills hand slots (features[0:84]). Pose anchors (84:98) keep their
  /// original values (pose is usually more stable than hand detection).
  List<List<double>> _fillHandFrames(List<List<double>> buffer) {
    bool hasHands(List<double> frame) {
      for (int i = 0; i < 84; i++) {
        if (frame[i].isFinite && frame[i].abs() > 1e-6) return true;
      }
      return false;
    }

    final filled = buffer.map((f) => List<double>.from(f)).toList();

    // Forward fill
    List<double>? lastGood;
    for (int t = 0; t < filled.length; t++) {
      if (hasHands(filled[t])) {
        lastGood = filled[t].sublist(0, 84);
      } else if (lastGood != null) {
        for (int i = 0; i < 84; i++) {
          filled[t][i] = lastGood[i];
        }
      }
    }

    // Backward fill (frames before first detection)
    List<double>? firstGood;
    for (int t = 0; t < filled.length; t++) {
      if (hasHands(filled[t])) {
        firstGood = filled[t].sublist(0, 84);
        break;
      }
    }
    if (firstGood != null) {
      for (int t = 0; t < filled.length; t++) {
        if (!hasHands(filled[t])) {
          for (int i = 0; i < 84; i++) {
            filled[t][i] = firstGood[i];
          }
        } else {
          break; // stop at first real detection
        }
      }
    }

    return filled;
  }

  // ════════════════════════════════════════════════════════════════════════
  // PREDICTION
  // ════════════════════════════════════════════════════════════════════════

  /// Run inference on current buffer.
  ///
  /// Pipeline: raw buffer → fill missing hand frames → std-normalize → temporal derivatives → TFLite.
  GestureResult? predict() {
    if (_interpreter == null) return null;

    // Need at least a few genuine hand detections (before forward/backward fill)
    const minHandFrames = 3;
    final framesWithHands = _rawFrameBuffer.where((frame) {
      for (int i = 0; i < 84; i++) {
        final val = frame[i];
        if (val.isFinite && val.abs() > 1e-6) return true;
      }
      return false;
    }).length;

    if (framesWithHands < minHandFrames) {
      debugPrint(
        '[GestureService] skip: $framesWithHands/$minHandFrames genuine hand frames',
      );
      return null;
    }

    // Pad with NaN for sequences shorter than 30 (shouldn't happen in per-sign mode)
    final paddedBuffer = List<List<double>>.from(_rawFrameBuffer);
    while (paddedBuffer.length < _sequenceLength) {
      paddedBuffer.insert(0, List<double>.filled(_rawFeatureDim, double.nan));
    }

    // Fill missing hand frames (forward + backward fill) to avoid model seeing zeros
    // where hands should be. Matches training assumption that hands are present.
    final filledBuffer = _fillHandFrames(paddedBuffer);

    // 1. Std-normalize the sequence (matches training normalize_sequence_std)
    final normalized = _stdNormalize(filledBuffer);

    // 2. Add temporal derivatives: (30, 98) → (30, 294)
    final withDerivatives = _addTemporalDerivatives(normalized);

    // 3. Build input tensor: shape (1, 30, 294)
    final input = [withDerivatives];

    // 4. Run inference
    final numClasses = _labelMap.isNotEmpty ? _labelMap.length : 28;
    final output = List.filled(numClasses, 0.0).reshape([1, numClasses]);

    try {
      _interpreter!.run(input, output);
    } catch (e) {
      debugPrint('[GestureService] Inference error: $e');
      return null;
    }

    final probs = (output[0] as List).cast<double>();
    final maxIdx = probs.indexOf(probs.reduce(max));
    final confidence = probs[maxIdx];

    // Debug: top 3
    final indexed = probs.asMap().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top3 = indexed.take(3).map(
      (e) => '${_labelMap[e.key] ?? "?"}(${(e.value * 100).toStringAsFixed(1)}%)',
    );
    debugPrint(
      '[GestureService] predict: top3=[${top3.join(', ')}] buf=${_rawFrameBuffer.length}',
    );

    if (confidence < _confidenceThreshold) return null;

    return GestureResult(
      word: _labelMap[maxIdx] ?? 'Unknown',
      confidence: confidence,
      labelIndex: maxIdx,
    );
  }

  /// Clear keypoint buffer.
  void clearBuffer() {
    _rawFrameBuffer.clear();
    _frameCounter = 0;
    _lastGoodHandFrame = null;
  }

  // ════════════════════════════════════════════════════════════════════════
  // CAPTURE — per-sign mode matching test_video.py / training pipeline
  // ════════════════════════════════════════════════════════════════════════

  /// Start a gesture session (enables MediaPipe, camera stream).
  /// Call once when entering the screen.
  void startGestureCapture({void Function(GestureResult)? onWordCommitted}) {
    if (_isCapturing) return;
    _isCapturing = true;
    _currentGloss.clear();
    clearBuffer();
    _mediaPipe.startCapture();
  }

  /// Stop the gesture session (disables MediaPipe).
  void stopGestureCapture() {
    _isCapturing = false;
    _isRecordingSign = false;
    _mediaPipe.stopCapture();
    _timer?.cancel();
    _timer = null;
    _onSignDetected = null;
    _onBufferProgress = null;
  }

  /// Start recording ONE sign.
  ///
  /// Collects exactly [_sequenceLength] frames then auto-predicts (same as
  /// test_video.py). [onSignDetected] fires once with the result.
  /// [onProgress] fires each frame with current count (0..30).
  void startSignRecording({
    required void Function(GestureResult result) onSignDetected,
    void Function(int frameCount)? onProgress,
  }) {
    if (!_isModelLoaded || !_isCapturing) return;
    clearBuffer();
    _frameCounter = 0;
    _onSignDetected = onSignDetected;
    _onBufferProgress = onProgress;
    _isRecordingSign = true;
    debugPrint('[GestureService] startSignRecording');
  }

  /// Cancel current sign recording (e.g. user released button before 30 frames).
  void cancelSignRecording() {
    _isRecordingSign = false;
    _onSignDetected = null;
    _onBufferProgress = null;
    clearBuffer();
    debugPrint('[GestureService] cancelSignRecording');
  }

  List<String> getCurrentGloss() => List.from(_currentGloss);

  /// Returns hand landmark positions for overlay painter.
  List<Offset> getHandLandmarks(double width, double height) {
    // Use MediaPipe's cached raw keypoints for overlay
    final cachedKeypoints = _mediaPipe.lastKeypoints;
    final hasData = cachedKeypoints.any((v) => v != 0.0);

    if (hasData) {
      return _mediaPipe.getHandLandmarkPositions(
        cachedKeypoints,
        Size(width, height),
      );
    }

    // Fallback: procedural landmarks
    final random = Random(42);
    final centerX = width * 0.5;
    final centerY = height * 0.45;
    final spread = width * 0.15;

    return List.generate(21, (index) {
      final angle = (index / 21) * 2 * pi;
      final radius = spread * (0.5 + random.nextDouble() * 0.5);
      return Offset(
        centerX + radius * cos(angle) + (random.nextDouble() - 0.5) * 20,
        centerY + radius * sin(angle) + (random.nextDouble() - 0.5) * 20,
      );
    });
  }

  void dispose() {
    _timer?.cancel();
    _glossController.close();
    _interpreter?.close();
    _mediaPipe.stopCapture();
    _isModelLoaded = false;
  }
}

class GestureResult {
  final String word;
  final double confidence;
  final int labelIndex;

  const GestureResult({
    required this.word,
    required this.confidence,
    required this.labelIndex,
  });

  @override
  String toString() => '$word (${(confidence * 100).toStringAsFixed(1)}%)';
}
