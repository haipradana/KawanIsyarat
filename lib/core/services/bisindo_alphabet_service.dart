import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Result dari BISINDO alphabet detection (dua tangan).
class BisindoAlphabetResult {
  final String letter;
  final double confidence;

  const BisindoAlphabetResult({
    required this.letter,
    required this.confidence,
  });

  @override
  String toString() => '$letter (${(confidence * 100).toStringAsFixed(1)}%)';
}

/// BISINDO Alphabet classifier menggunakan dua tangan.
///
/// Pipeline: CameraImage → hand_landmarker (2 tangan) → 2×21 landmarks →
///           Boháček normalization per tangan + offset → 86 floats → Dense F32 → letter
///
/// Model: assets/models/bisindo_alphabet_model_f32.tflite (F32)
/// Labels: assets/models/bisindo_alphabet_labels.json (27 kelas: A-Z + NOTHING)
class BisindoAlphabetService {
  static final BisindoAlphabetService _instance =
      BisindoAlphabetService._internal();
  factory BisindoAlphabetService() => _instance;
  BisindoAlphabetService._internal();

  /// Letters yang didukung model BISINDO (A-Z, 26 huruf).
  /// Model juga punya kelas NOTHING sebagai guard — dikecualikan dari UI praktik
  /// (bukan huruf, hanya sinyal "tidak ada isyarat valid").
  static const List<String> supportedLetters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
    'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
    'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  Interpreter? _interpreter;
  HandLandmarkerPlugin? _handLandmarker;
  List<String> _labels = [];
  bool _isLoaded = false;

  static const int _numLandmarks = 21;
  static const int _numFeaturesPerHand = _numLandmarks * 2; // 42
  static const int _numFeatures = _numFeaturesPerHand * 2 + 2; // 86
  // Lower threshold for real-time camera (noisier than training photos).
  static const double _confThreshold = 0.40;
  // Single-hand fallback needs higher confidence (training data is mostly 2-hand).
  static const double _singleHandConfThreshold = 0.65;

  bool get isLoaded => _isLoaded;
  List<String> get labels => List.unmodifiable(_labels);

  Future<void> initialize() async {
    if (_isLoaded) return;

    _interpreter = await Interpreter.fromAsset(
      'assets/models/bisindo_alphabet_model_f32.tflite',
      options: InterpreterOptions()..threads = 2,
    );

    // Load labels JSON
    final labelsStr =
        await rootBundle.loadString('assets/models/bisindo_alphabet_labels.json');
    _labels = List<String>.from(jsonDecode(labelsStr));
    debugPrint('[BISINDO-ABC] Labels loaded: $_labels (${_labels.length} classes)');

    // Initialize hand landmarker — 2 hands
    try {
      _handLandmarker = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.3,
        delegate: HandLandmarkerDelegate.gpu,
      );
    } catch (e) {
      debugPrint('[BISINDO-ABC] GPU HandLandmarker failed, trying CPU: $e');
      try {
        _handLandmarker = HandLandmarkerPlugin.create(
          numHands: 2,
          minHandDetectionConfidence: 0.3,
          delegate: HandLandmarkerDelegate.cpu,
        );
      } catch (e2) {
        debugPrint('[BISINDO-ABC] HandLandmarker init failed: $e2');
      }
    }

    _isLoaded = true;
    debugPrint('[BISINDO-ABC] Service initialized (${_labels.length} classes, $_numFeatures features)');
  }

  /// Detect BISINDO alphabet letter from camera frame.
  ///
  /// Supports 1 or 2 hands:
  /// - 2 hands: full 86-dim features
  /// - 1 hand: zero-pad second hand slot (matches training)
  /// - 0 hands: returns null
  BisindoAlphabetResult? detectFromCameraImage(
    CameraImage frame,
    int sensorOrientation,
    bool isFrontCamera,
  ) {
    if (!_isLoaded || _interpreter == null || _handLandmarker == null) return null;

    try {
      // 1. Detect hand landmarks
      final hands = _handLandmarker!.detect(frame, sensorOrientation);
      if (hands.isEmpty) return null;

      // 2. Build 86-dim feature vector.
      //
      // CRITICAL: Training script (prepare_bisindo_alphabet.py) uses MediaPipe
      // handedness labels to put LEFT hand in slot1 and RIGHT hand in slot2,
      // making `dx_offset = right_center - left_center` ALWAYS positive.
      // Augmentation (flip+swap) maintains this invariant.
      //
      // hand_landmarker plugin doesn't expose handedness — so we sort by
      // portrait-x position (leftmost on screen → slot1). For typical poses
      // where both hands are visible side-by-side, this matches training.
      final isTwoHand = hands.length >= 2;
      List<double>? features;
      if (isTwoHand) {
        final coords1 = _extractCoords(hands[0].landmarks, sensorOrientation, isFrontCamera);
        final coords2 = _extractCoords(hands[1].landmarks, sensorOrientation, isFrontCamera);
        if (coords1 == null || coords2 == null) return null;

        // Sort: leftmost (smaller mean x in portrait space) → slot1
        final cx1 = _meanX(coords1);
        final cx2 = _meanX(coords2);
        final leftCoords = cx1 <= cx2 ? coords1 : coords2;
        final rightCoords = cx1 <= cx2 ? coords2 : coords1;

        features = _buildTwoHandFeaturesFromCoords(leftCoords, rightCoords);
      } else {
        // Single hand detected — fallback path.
        // BISINDO alphabet uses 2 hands, but training augment_single_hand
        // generated some 1-hand samples (when hands overlap in source images).
        // Apply higher confidence threshold to avoid false positives.
        features = _buildSingleHandFeatures(
            hands[0].landmarks, sensorOrientation, isFrontCamera);
      }

      if (features == null) return null;

      // 3. Run inference
      final input = [features]; // [1, 86]
      final output = [List<double>.filled(_labels.length, 0.0)];
      _interpreter!.run(input, output);
      final scores = output[0];

      // 4. Get best prediction
      double maxScore = 0.0;
      int maxIdx = 0;
      for (int i = 0; i < scores.length; i++) {
        if (scores[i] > maxScore) {
          maxScore = scores[i];
          maxIdx = i;
        }
      }

      // Apply mode-specific threshold
      final threshold = isTwoHand ? _confThreshold : _singleHandConfThreshold;
      if (maxScore < threshold) return null;

      // Skip NOTHING class
      if (_labels[maxIdx] == 'NOTHING') return null;

      return BisindoAlphabetResult(
        letter: _labels[maxIdx],
        confidence: maxScore,
      );
    } catch (e) {
      debugPrint('[BISINDO-ABC] Detection error: $e');
      return null;
    }
  }

  /// Mean of x-coordinates (every other element starting at 0).
  double _meanX(List<double> coords) {
    double sum = 0;
    for (int i = 0; i < _numLandmarks; i++) {
      sum += coords[i * 2];
    }
    return sum / _numLandmarks;
  }

  /// Build 86-dim features from already-extracted left/right coords.
  /// Matches training: [left_norm, right_norm, dx, dy] where dx = right_cx - left_cx.
  List<double> _buildTwoHandFeaturesFromCoords(
      List<double> left, List<double> right) {
    final leftNorm = _normalizeHand(left);
    final rightNorm = _normalizeHand(right);

    double cxL = 0, cyL = 0, cxR = 0, cyR = 0;
    for (int i = 0; i < _numLandmarks; i++) {
      cxL += left[i * 2];
      cyL += left[i * 2 + 1];
      cxR += right[i * 2];
      cyR += right[i * 2 + 1];
    }
    cxL /= _numLandmarks;
    cyL /= _numLandmarks;
    cxR /= _numLandmarks;
    cyR /= _numLandmarks;

    // dx = right_center - left_center (always >= 0 after sorting)
    final dx = cxR - cxL;
    final dy = cyR - cyL;

    return [...leftNorm, ...rightNorm, dx, dy];
  }

  /// Build 86-dim features from single hand (zero-pad second slot).
  List<double>? _buildSingleHandFeatures(
    List landmarks,
    int sensorOrientation,
    bool isFrontCamera,
  ) {
    final coords = _extractCoords(landmarks, sensorOrientation, isFrontCamera);
    if (coords == null) return null;

    final handNorm = _normalizeHand(coords);
    final zeros = List<double>.filled(42, 0.0);

    return [...handNorm, ...zeros, 0.0, 0.0];
  }

  /// Extract (x, y) coords from landmarks and orient to portrait space.
  List<double>? _extractCoords(
      List landmarks, int sensorOrientation, bool isFrontCamera) {
    if (landmarks.length < _numLandmarks) return null;

    final coords = List<double>.filled(_numLandmarks * 2, 0.0);
    for (int i = 0; i < _numLandmarks; i++) {
      final rawX = (landmarks[i].x as num).toDouble();
      final rawY = (landmarks[i].y as num).toDouble();
      final oriented = _toPortraitSpace(rawX, rawY, sensorOrientation, isFrontCamera);
      coords[i * 2] = oriented.$1;
      coords[i * 2 + 1] = oriented.$2;
    }
    return coords;
  }

  /// Boháček bbox normalization: flatten coords → 42 floats in [0,1].
  List<double> _normalizeHand(List<double> coords) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (int i = 0; i < _numLandmarks; i++) {
      final x = coords[i * 2];
      final y = coords[i * 2 + 1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    final w = (maxX - minX).abs();
    final h = (maxY - minY).abs();
    final scaleW = w < 1e-6 ? 1e-6 : w;
    final scaleH = h < 1e-6 ? 1e-6 : h;

    final norm = List<double>.filled(42, 0.0);
    for (int i = 0; i < _numLandmarks; i++) {
      norm[i * 2] = (coords[i * 2] - minX) / scaleW;
      norm[i * 2 + 1] = (coords[i * 2 + 1] - minY) / scaleH;
    }
    return norm;
  }

  (double, double) _toPortraitSpace(
    double x, double y, int sensorOrientation, bool isFrontCamera,
  ) {
    switch (sensorOrientation) {
      case 90:
        return isFrontCamera ? (1.0 - y, x) : (1.0 - y, x);
      case 270:
        return isFrontCamera ? (y, 1.0 - x) : (y, 1.0 - x);
      case 180:
        return isFrontCamera ? (1.0 - x, 1.0 - y) : (1.0 - x, 1.0 - y);
      default:
        return isFrontCamera ? (x, y) : (x, y);
    }
  }

  void dispose() {
    _interpreter?.close();
    _handLandmarker?.dispose();
    _interpreter = null;
    _handLandmarker = null;
    _isLoaded = false;
  }
}
