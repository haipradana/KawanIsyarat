import 'dart:typed_data';
import 'dart:math';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

/// CNN-based BISINDO alphabet classifier.
///
/// Pipeline: MediaPipe hand crop (RGBA) → 28×28 grayscale → CNN → letter
/// Model: alphabet_cnn_int8.tflite (466 KB)
/// Input: [1, 28, 28, 1] float32 grayscale
/// Output: [1, 24] probabilities (no J, Z — those need motion)
class AlphabetService {
  static final AlphabetService _instance = AlphabetService._internal();
  factory AlphabetService() => _instance;
  AlphabetService._internal();

  Interpreter? _cnnInterpreter;
  Map<int, String> _labelMap = {};
  bool _isLoaded = false;

  static const int _inputSize = 28;
  static const double _confThreshold = 0.5;

  Future<void> initialize() async {
    if (_isLoaded) return;

    _cnnInterpreter = await Interpreter.fromAsset(
      'assets/models/alphabet_cnn_int8.tflite',
      options: InterpreterOptions()..threads = 2,
    );

    final jsonStr = await rootBundle.loadString(
      'assets/models/alphabet_labels.json',
    );
    final Map<String, dynamic> raw = json.decode(jsonStr);
    _labelMap = raw.map((k, v) => MapEntry(int.parse(k), v as String));

    final outShape = _cnnInterpreter!.getOutputTensor(0).shape;
    debugPrint('[CNN] Model loaded. Output shape: $outShape, Labels: $_labelMap');

    _isLoaded = true;
  }

  bool get isLoaded => _isLoaded;
  int get numClasses => _labelMap.length;

  /// Classify a hand crop.
  ///
  /// [rgbaBytes]: RGBA pixel data of the cropped hand region.
  /// [cropWidth], [cropHeight]: dimensions of the crop.
  ///
  /// Returns the detected letter or null if confidence < threshold.
  AlphabetResult? classifyFromCrop({
    required Uint8List rgbaBytes,
    required int cropWidth,
    required int cropHeight,
  }) {
    if (!_isLoaded || _cnnInterpreter == null) return null;

    // Preprocess: RGBA → grayscale 28×28 normalized [0, 1]
    final input = _preprocessToGrayscale(rgbaBytes, cropWidth, cropHeight);
    if (input == null) return null;

    // Shape: [1, 28, 28, 1]
    final inputReshaped = input.reshape([1, _inputSize, _inputSize, 1]);

    // Use actual model output shape
    final outShape = _cnnInterpreter!.getOutputTensor(0).shape;
    final numOut = outShape.last; // e.g. [1, 24] → 24
    final output = List.filled(numOut, 0.0).reshape([1, numOut]);

    _cnnInterpreter!.run(inputReshaped, output);

    final probs = (output[0] as List).cast<double>();
    final maxIdx = probs.indexOf(probs.reduce(max));
    final confidence = probs[maxIdx];

    if (confidence < _confThreshold) return null;
    if (!_labelMap.containsKey(maxIdx)) return null;

    return AlphabetResult(
      letter: _labelMap[maxIdx]!,
      confidence: confidence,
      allProbs: probs,
    );
  }

  /// Convert RGBA crop → Float32List [28×28], grayscale normalized [0,1]
  /// Formula: 0.299R + 0.587G + 0.114B
  Float32List? _preprocessToGrayscale(
    Uint8List rgba,
    int width,
    int height,
  ) {
    try {
      final output = Float32List(_inputSize * _inputSize);
      final scaleX = width / _inputSize;
      final scaleY = height / _inputSize;

      for (int y = 0; y < _inputSize; y++) {
        for (int x = 0; x < _inputSize; x++) {
          final srcX = (x * scaleX).toInt().clamp(0, width - 1);
          final srcY = (y * scaleY).toInt().clamp(0, height - 1);
          final srcIdx = (srcY * width + srcX) * 4;

          if (srcIdx + 2 < rgba.length) {
            final r = rgba[srcIdx] / 255.0;
            final g = rgba[srcIdx + 1] / 255.0;
            final b = rgba[srcIdx + 2] / 255.0;
            output[y * _inputSize + x] = 0.299 * r + 0.587 * g + 0.114 * b;
          }
        }
      }
      return output;
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _cnnInterpreter?.close();
    _isLoaded = false;
  }
}

class AlphabetResult {
  final String letter;
  final double confidence;
  final List<double> allProbs;

  const AlphabetResult({
    required this.letter,
    required this.confidence,
    required this.allProbs,
  });

  /// Top 3 predictions for debug
  List<MapEntry<int, double>> get top3 {
    final indexed = allProbs.asMap().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return indexed.take(3).toList();
  }

  @override
  String toString() => '$letter (${(confidence * 100).toStringAsFixed(1)}%)';
}
