import 'dart:async';
import 'dart:math';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'mediapipe_service.dart';

/// Two-stage gesture recognition service:
/// Stage 1 — MediaPipe: extracts 258 keypoints per camera frame
/// Stage 2 — LSTM: receives 30-frame buffer → outputs word prediction
///
/// Also maintains backward compatibility (glossStream, startGestureCapture)
/// for existing providers.
class GestureService {
  static final GestureService _instance = GestureService._internal();
  factory GestureService() => _instance;
  GestureService._internal();

  Interpreter? _lstmInterpreter;
  Map<int, String> _labelMap = {};
  bool _isModelLoaded = false;

  final _glossController = StreamController<List<String>>.broadcast();
  Timer? _timer;
  final List<String> _currentGloss = [];
  bool _isCapturing = false;

  // Sliding window buffer — 30 frames × 258 keypoints
  final List<List<double>> _frameBuffer = [];
  static const int _sequenceLength = 30;
  static const int _featureDim = 258;
  static const double _confidenceThreshold = 0.65;

  final _mediaPipe = MediaPipeService();

  Stream<List<String>> get glossStream => _glossController.stream;
  bool get isCapturing => _isCapturing;
  bool get isModelLoaded => _isModelLoaded;

  /// Load the LSTM model and label map from assets.
  Future<void> initialize() async {
    if (_isModelLoaded) return;

    try {
      // Load LSTM model
      _lstmInterpreter = await Interpreter.fromAsset(
        'models/bisindo_gesture.tflite',
        options: InterpreterOptions()..threads = 4,
      );

      // Load label map
      final jsonStr = await rootBundle.loadString(
        'assets/models/bisindo_labels.json',
      );
      final Map<String, dynamic> raw = json.decode(jsonStr);
      _labelMap = raw.map((k, v) => MapEntry(int.parse(k), v as String));

      _isModelLoaded = true;
    } catch (e) {
      // Model files not yet present — service will work in mock mode
      _isModelLoaded = false;
    }
  }

  /// Add one frame of keypoints to the sliding buffer.
  /// Call this from camera stream while capturing.
  ///
  /// keypoints: flat array of 258 floats
  ///   [0..131]   = pose (33 × 4: x,y,z,vis)
  ///   [132..194] = left hand (21 × 3: x,y,z)
  ///   [195..257] = right hand (21 × 3: x,y,z)
  void addFrame(List<double> keypoints) {
    if (keypoints.length != _featureDim) return;

    _frameBuffer.add(List<double>.from(keypoints));

    // Keep only last 30 frames (sliding window)
    if (_frameBuffer.length > _sequenceLength) {
      _frameBuffer.removeAt(0);
    }
  }

  /// Add a frame from a raw camera image via MediaPipe extraction.
  void addFrameFromCamera(dynamic cameraImage) {
    final keypoints = _mediaPipe.extractKeypoints(cameraImage);
    addFrame(keypoints);
  }

  /// Predict gesture from current buffer using LSTM.
  /// Returns null if buffer not full or confidence too low.
  GestureResult? predict() {
    if (_lstmInterpreter == null) return null;

    // Pad with zeros if buffer not full
    final paddedBuffer = List<List<double>>.from(_frameBuffer);
    while (paddedBuffer.length < _sequenceLength) {
      paddedBuffer.insert(0, List.filled(_featureDim, 0.0));
    }

    // Build input tensor: shape (1, 30, 258)
    final input = [paddedBuffer];

    // Output tensor: shape (1, numClasses)
    final numClasses = _labelMap.isNotEmpty ? _labelMap.length : 32;
    final output = List.filled(numClasses, 0.0).reshape([1, numClasses]);

    _lstmInterpreter!.run(input, output);

    final probs = (output[0] as List).cast<double>();
    final maxIdx = probs.indexOf(probs.reduce(max));
    final confidence = probs[maxIdx];

    if (confidence < _confidenceThreshold) return null;

    return GestureResult(
      word: _labelMap[maxIdx] ?? 'Unknown',
      confidence: confidence,
      labelIndex: maxIdx,
    );
  }

  /// Clear keypoint buffer — call when starting new gesture session.
  void clearBuffer() => _frameBuffer.clear();

  // ======================================
  // Backward-compatible API for existing providers
  // ======================================

  /// Simulated sequence data for when LSTM model is not loaded.
  static const List<List<String>> _mockSequences = [
    ['NAMA', 'SAYA', 'APA'],
    ['TERIMA', 'KASIH'],
    ['TOLONG', 'BANTU'],
    ['SAYA', 'SENANG'],
    ['HALO', 'APA', 'KABAR'],
  ];

  /// Start gesture capture — maintains backward compat.
  /// If LSTM is loaded: starts MediaPipe + frame buffering.
  /// If not loaded: falls back to mock gloss stream.
  void startGestureCapture() {
    if (_isCapturing) return;
    _isCapturing = true;
    _currentGloss.clear();
    clearBuffer();

    if (_isModelLoaded) {
      _mediaPipe.startCapture();
      // Real capture happens by caller pushing camera frames via addFrame()
      return;
    }

    // Fallback: mock stream
    int idx = 0;
    final random = Random();
    final seq = _mockSequences[random.nextInt(_mockSequences.length)];

    _timer = Timer.periodic(Duration(milliseconds: 1500), (timer) {
      if (idx < seq.length) {
        _currentGloss.add(seq[idx]);
        _glossController.add(List.from(_currentGloss));
        idx++;
      } else {
        _currentGloss.clear();
        idx = 0;
        final newSeq = _mockSequences[random.nextInt(_mockSequences.length)];
        _currentGloss.add(newSeq[idx]);
        _glossController.add(List.from(_currentGloss));
        idx++;
      }
    });
  }

  /// Stop gesture capture.
  void stopGestureCapture() {
    _isCapturing = false;
    _mediaPipe.stopCapture();
    _timer?.cancel();
    _timer = null;
  }

  List<String> getCurrentGloss() => List.from(_currentGloss);

  /// Returns hand landmark positions for overlay painter.
  List<Offset> getHandLandmarks(double width, double height) {
    if (_frameBuffer.isNotEmpty) {
      return _mediaPipe.getHandLandmarkPositions(
        _frameBuffer.last,
        Size(width, height),
      );
    }

    // Fallback: mock landmarks
    final random = Random(42);
    final centerX = width * 0.5;
    final centerY = height * 0.45;
    final spread = width * 0.15;

    return List.generate(21, (index) {
      final angle = (index / 21) * 2 * 3.14159;
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
    _lstmInterpreter?.close();
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
