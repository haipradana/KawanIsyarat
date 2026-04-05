import 'dart:typed_data';
import 'dart:math';
import 'package:tflite_flutter/tflite_flutter.dart';

/// YOLO-based BISINDO alphabet letter detector.
/// Uses YOLO11n INT8 TFLite model for letter-by-letter hand sign detection.
/// Used in Education Mode (learn_alfabet_screen) only.
class AlphabetService {
  static final AlphabetService _instance = AlphabetService._internal();
  factory AlphabetService() => _instance;
  AlphabetService._internal();

  Interpreter? _yoloInterpreter;
  bool _isLoaded = false;

  static const int _inputSize = 320;
  static const double _confThreshold = 0.5;

  // 26 huruf alfabet A–Z
  static const List<String> _labels = [
    'A','B','C','D','E','F','G','H','I','J','K','L','M',
    'N','O','P','Q','R','S','T','U','V','W','X','Y','Z',
  ];

  Future<void> initialize() async {
    if (_isLoaded) return;

    _yoloInterpreter = await Interpreter.fromAsset(
      'models/best_int8.tflite',
      options: InterpreterOptions()..threads = 4,
    );

    _isLoaded = true;
  }

  bool get isLoaded => _isLoaded;

  /// Detect letter from raw image bytes (already preprocessed to 320×320×3).
  /// Returns null if no letter detected with sufficient confidence.
  AlphabetResult? detectFromRGB(Float32List rgbInput) {
    if (!_isLoaded || _yoloInterpreter == null) return null;

    final outputShape = _yoloInterpreter!.getOutputTensor(0).shape;
    final outputSize = outputShape.reduce((a, b) => a * b);
    final output = List.filled(outputSize, 0.0).reshape(outputShape);

    _yoloInterpreter!.run(
      rgbInput.buffer.asFloat32List().reshape([1, _inputSize, _inputSize, 3]),
      output,
    );

    return _parseOutput(output);
  }

  /// Preprocess raw RGBA pixel bytes (e.g. from camera) to model input.
  /// [pixels]: RGBA byte data, [width]/[height]: source dimensions.
  /// Returns 320×320×3 Float32List normalized to [0, 1].
  Float32List? preprocessRGBA(Uint8List pixels, int width, int height) {
    try {
      final input = Float32List(_inputSize * _inputSize * 3);
      final scaleX = width / _inputSize;
      final scaleY = height / _inputSize;

      int idx = 0;
      for (int y = 0; y < _inputSize; y++) {
        for (int x = 0; x < _inputSize; x++) {
          final srcX = (x * scaleX).toInt().clamp(0, width - 1);
          final srcY = (y * scaleY).toInt().clamp(0, height - 1);
          final srcIdx = (srcY * width + srcX) * 4; // RGBA stride

          if (srcIdx + 2 < pixels.length) {
            input[idx++] = pixels[srcIdx] / 255.0;     // R
            input[idx++] = pixels[srcIdx + 1] / 255.0; // G
            input[idx++] = pixels[srcIdx + 2] / 255.0; // B
          } else {
            input[idx++] = 0.0;
            input[idx++] = 0.0;
            input[idx++] = 0.0;
          }
        }
      }

      return input;
    } catch (e) {
      return null;
    }
  }

  AlphabetResult? _parseOutput(dynamic output) {
    try {
      List<double> probs;

      if (output is List && output[0] is List) {
        probs = (output[0] as List).cast<double>();
      } else {
        return null;
      }

      if (probs.isEmpty) return null;

      final maxIdx = probs.indexOf(probs.reduce(max));
      final confidence = probs[maxIdx];

      if (confidence < _confThreshold) return null;
      if (maxIdx >= _labels.length) return null;

      return AlphabetResult(
        letter: _labels[maxIdx],
        confidence: confidence,
      );
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _yoloInterpreter?.close();
    _isLoaded = false;
  }
}

class AlphabetResult {
  final String letter;
  final double confidence;

  const AlphabetResult({
    required this.letter,
    required this.confidence,
  });

  @override
  String toString() => '$letter (${(confidence * 100).toStringAsFixed(1)}%)';
}
