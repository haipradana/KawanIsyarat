import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../ffi/cactus_wrapper.dart';
import 'model_manager.dart';

/// Real Cactus-powered Whisper STT (Speech-to-Text) service.
/// Uses on-device Whisper Tiny ID model for Indonesian speech transcription.
class SttService {
  static final SttService _instance = SttService._internal();
  factory SttService() => _instance;
  SttService._internal();

  CactusTranscriber? _transcriber;
  bool _isLoaded = false;
  bool _isLoading = false;

  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;

  /// Initialize the STT model.
  /// Requires model weights to be already downloaded via ModelManager.
  Future<void> initialize({void Function(double)? onProgress}) async {
    if (_isLoaded || _isLoading) return;
    _isLoading = true;

    try {
      onProgress?.call(0.1);

      final modelManager = ModelManager();
      final modelPath = await modelManager.getModelPath(ModelType.whisperSTT);

      onProgress?.call(0.3);

      // Verify model directory exists and has config.txt
      final modelDir = Directory(modelPath);
      if (!await modelDir.exists()) {
        throw Exception('Model directory not found: $modelPath');
      }
      final configFile = File('$modelPath/config.txt');
      if (!await configFile.exists()) {
        // List what's actually in the directory for debugging
        final files = await modelDir.list().map((e) => e.path.split('/').last).toList();
        debugPrint('[SttService] Model dir contents: $files');
        throw Exception('config.txt not found in $modelPath. Files: $files');
      }
      debugPrint('[SttService] Loading Whisper model from: $modelPath');

      _transcriber = CactusTranscriber();
      await _transcriber!.load(modelPath);

      onProgress?.call(1.0);
      _isLoaded = true;
      debugPrint('[SttService] Whisper model loaded successfully');
    } catch (e) {
      debugPrint('[SttService] Failed to load Whisper model: $e');
      _isLoading = false;
      _transcriber = null;
      rethrow;
    }

    _isLoading = false;
  }

  /// Transcribe audio from raw PCM data (16-bit, 16kHz, mono).
  /// [audioData] is the raw PCM bytes from the microphone.
  Future<String> transcribe(Uint8List? audioData) async {
    if (!_isLoaded || _transcriber == null) return '';
    if (audioData == null || audioData.isEmpty) return '';

    try {
      final result = await _transcriber!.transcribePcm(audioData);
      if (result.success && result.text.isNotEmpty) {
        return result.text.trim();
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  /// Transcribe audio from a file path.
  Future<String> transcribeFile(String audioPath) async {
    debugPrint('[SttService] transcribeFile called, isLoaded=$_isLoaded, transcriber=${_transcriber != null}');

    if (!_isLoaded || _transcriber == null) {
      debugPrint('[SttService] Model NOT loaded — cannot transcribe');
      return '';
    }

    try {
      debugPrint('[SttService] Calling cactus transcribeFile($audioPath)...');
      final result = await _transcriber!.transcribeFile(audioPath);
      debugPrint('[SttService] Result: success=${result.success}, text="${result.text}", error=${result.error}, segments=${result.segments.length}');

      if (result.success && result.text.isNotEmpty) {
        return result.text.trim();
      }

      debugPrint('[SttService] Transcription returned empty/failed');
      return '';
    } catch (e) {
      debugPrint('[SttService] Exception: $e');
      return '';
    }
  }

  Future<void> dispose() async {
    await _transcriber?.dispose();
    _transcriber = null;
    _isLoaded = false;
  }
}
