import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Result dari SIBI alphabet detection.
class SibiDetectionResult {
  final String letter;
  final double confidence;

  const SibiDetectionResult({
    required this.letter,
    required this.confidence,
  });

  @override
  String toString() => '$letter (${(confidence * 100).toStringAsFixed(1)}%)';
}

/// SIBI Alphabet classifier menggunakan MediaPipe hand landmarks + Dense TFLite.
///
/// Pipeline: CameraImage → hand_landmarker → 21 landmarks →
///           Boháček normalization → 42 floats → Dense F32 → letter
///
/// Model: assets/models/sibi_alphabet_model_f32.tflite (F32, 212KB)
/// Labels: assets/models/sibi_alphabet_labels.json (24 kelas, skip J & Z)
class SibiAlphabetService {
  static final SibiAlphabetService _instance = SibiAlphabetService._internal();
  factory SibiAlphabetService() => _instance;
  SibiAlphabetService._internal();

  static const List<String> supportedLetters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I',
    'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S',
    'T', 'U', 'V', 'W', 'X', 'Y',
  ];

  Interpreter? _interpreter;
  HandLandmarkerPlugin? _handLandmarker;
  List<String> _labels = [];
  bool _isLoaded = false;

  static const double _confThreshold = 0.5;

  bool get isLoaded => _isLoaded;
  List<String> get labels => List.unmodifiable(_labels);

  Future<void> initialize() async {
    if (_isLoaded) return;

    // Gunakan model F32 agar inferensi persis mengikuti output training script.
    _interpreter = await Interpreter.fromAsset(
      'assets/models/sibi_alphabet_model_f32.tflite',
      options: InterpreterOptions()..threads = 2,
    );

    // Load labels JSON
    final labelsStr = await rootBundle.loadString('assets/models/sibi_alphabet_labels.json');
    _labels = List<String>.from(jsonDecode(labelsStr));
    if (!listEquals(_labels, supportedLetters)) {
      debugPrint('[SIBI] Warning: labels JSON berbeda dari expected training labels: $_labels');
    }

    // Inisialisasi hand landmarker
    try {
      _handLandmarker = HandLandmarkerPlugin.create(
        numHands: 1,
        minHandDetectionConfidence: 0.3,
        delegate: HandLandmarkerDelegate.gpu,
      );
    } catch (e) {
      debugPrint('[SIBI] GPU HandLandmarker gagal, coba CPU: $e');
      try {
        _handLandmarker = HandLandmarkerPlugin.create(
          numHands: 1,
          minHandDetectionConfidence: 0.3,
          delegate: HandLandmarkerDelegate.cpu,
        );
      } catch (e2) {
        debugPrint('[SIBI] HandLandmarker init gagal: $e2');
      }
    }

    _isLoaded = true;
  }

  /// Deteksi huruf SIBI dari camera frame.
  ///
  /// [frame]: CameraImage dari imageStream (YUV420)
  /// [sensorOrientation]: orientasi sensor kamera (biasanya 90 untuk Pixel 6a)
  ///
  /// Returns null jika tangan tidak terdeteksi atau confidence < threshold.
  SibiDetectionResult? detectFromCameraImage(
    CameraImage frame,
    int sensorOrientation,
    bool isFrontCamera,
  ) {
    if (!_isLoaded || _interpreter == null || _handLandmarker == null) return null;

    try {
      // 1. Deteksi hand landmarks via hand_landmarker
      final hands = _handLandmarker!.detect(frame, sensorOrientation);
      if (hands.isEmpty) return null;

      final landmarks = hands.first.landmarks;
      if (landmarks.length < 21) return null;

      // 2. Boháček bbox normalization → 42 floats [0, 1]
      final features = _normalizeHand(landmarks, sensorOrientation, isFrontCamera);
      if (features == null) return null;

      // 3. Jalankan inference (float32)
      final input = [features]; // [1, 42]
      final output = [List<double>.filled(_labels.length, 0.0)]; // [1, 24]
      _interpreter!.run(input, output);
      final scores = output[0];

      // 4. Ambil prediksi terbaik
      double maxScore = 0.0;
      int maxIdx = 0;
      for (int i = 0; i < scores.length; i++) {
        if (scores[i] > maxScore) {
          maxScore = scores[i];
          maxIdx = i;
        }
      }

      if (maxScore < _confThreshold) return null;

      return SibiDetectionResult(
        letter: _labels[maxIdx],
        confidence: maxScore,
      );
    } catch (e) {
      debugPrint('[SIBI] Detection error: $e');
      return null;
    }
  }

  /// Boháček bbox normalization: 21 landmarks → 42 floats [0, 1].
  ///
  /// Semua koordinat digeser ke bounding box tangan,
  /// sehingga hasilnya scale-invariant dan position-invariant.
  List<double>? _normalizeHand(
    List landmarks,
    int sensorOrientation,
    bool isFrontCamera,
  ) {
    final xs = <double>[];
    final ys = <double>[];

    for (int i = 0; i < landmarks.length && i < 21; i++) {
      final rawX = (landmarks[i].x as num).toDouble();
      final rawY = (landmarks[i].y as num).toDouble();
      final oriented = _toPortraitSpace(
        rawX,
        rawY,
        sensorOrientation,
        isFrontCamera,
      );
      xs.add(oriented.$1);
      ys.add(oriented.$2);
    }

    if (xs.length < 21) return null;

    final minX = xs.reduce((a, b) => a < b ? a : b);
    final maxX = xs.reduce((a, b) => a > b ? a : b);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);

    final w = maxX - minX;
    final h = maxY - minY;

    // Tangan terlalu kecil — tidak valid
    if (w < 1e-4 && h < 1e-4) return null;

    final scaleW = w < 1e-6 ? 1e-6 : w;
    final scaleH = h < 1e-6 ? 1e-6 : h;

    final features = List<double>.filled(42, 0.0);
    for (int i = 0; i < 21; i++) {
      features[i * 2] = (xs[i] - minX) / scaleW;
      features[i * 2 + 1] = (ys[i] - minY) / scaleH;
    }
    return features;
  }

  (double, double) _toPortraitSpace(
    double x,
    double y,
    int sensorOrientation,
    bool isFrontCamera,
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
