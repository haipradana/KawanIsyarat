import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'cactus.dart';

/// A chat message for Cactus completion.
class ChatMessage {
  final String role;
  final String content;

  const ChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// Parsed response from cactusComplete.
class CactusResponse {
  final bool success;
  final String? error;
  final String text;
  final double confidence;
  final double totalTimeMs;
  final double decodeTps;
  final double ramUsageMb;

  const CactusResponse({
    required this.success,
    this.error,
    required this.text,
    this.confidence = 0.0,
    this.totalTimeMs = 0.0,
    this.decodeTps = 0.0,
    this.ramUsageMb = 0.0,
  });

  factory CactusResponse.fromJson(Map<String, dynamic> json) {
    return CactusResponse(
      success: json['success'] ?? false,
      error: json['error'] as String?,
      text: (json['response'] ?? '') as String,
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      totalTimeMs: (json['total_time_ms'] ?? 0.0).toDouble(),
      decodeTps: (json['decode_tps'] ?? 0.0).toDouble(),
      ramUsageMb: (json['ram_usage_mb'] ?? 0.0).toDouble(),
    );
  }

  factory CactusResponse.error(String message) {
    return CactusResponse(success: false, error: message, text: '');
  }
}

/// Parsed response from cactusTranscribe.
class CactusTranscriptionResult {
  final bool success;
  final String? error;
  final String text;
  final List<TranscriptionSegment> segments;
  final double confidence;
  final double totalTimeMs;

  const CactusTranscriptionResult({
    required this.success,
    this.error,
    required this.text,
    this.segments = const [],
    this.confidence = 0.0,
    this.totalTimeMs = 0.0,
  });

  factory CactusTranscriptionResult.fromJson(Map<String, dynamic> json) {
    final segList = (json['segments'] as List?)
            ?.map((s) => TranscriptionSegment.fromJson(s))
            .toList() ??
        [];
    return CactusTranscriptionResult(
      success: json['success'] ?? false,
      error: json['error'] as String?,
      text: (json['response'] ?? '') as String,
      segments: segList,
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      totalTimeMs: (json['total_time_ms'] ?? 0.0).toDouble(),
    );
  }
}

class TranscriptionSegment {
  final double start;
  final double end;
  final String text;

  const TranscriptionSegment({
    required this.start,
    required this.end,
    required this.text,
  });

  factory TranscriptionSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptionSegment(
      start: (json['start'] ?? 0.0).toDouble(),
      end: (json['end'] ?? 0.0).toDouble(),
      text: (json['text'] ?? '') as String,
    );
  }
}

/// High-level wrapper for Cactus LLM model.
/// Runs FFI calls in an isolate to avoid blocking the main UI thread.
class CactusModel {
  CactusModelT? _handle;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  /// Loads a model from the given directory path.
  /// This is a blocking FFI call wrapped in an isolate.
  Future<void> load(String modelPath) async {
    if (_isLoaded) return;
    try {
      _handle = await Isolate.run(() {
        return cactusInit(modelPath, null, false);
      });
      _isLoaded = true;
    } catch (e) {
      _isLoaded = false;
      rethrow;
    }
  }

  /// Runs chat completion with the given messages.
  Future<CactusResponse> complete(
    List<ChatMessage> messages, {
    int maxTokens = 100,
    double temperature = 0.3,
    List<String>? stopSequences,
  }) async {
    if (!_isLoaded || _handle == null) {
      return CactusResponse.error('Model not loaded');
    }

    final messagesJson = jsonEncode(messages.map((m) => m.toJson()).toList());
    final options = <String, dynamic>{
      'max_tokens': maxTokens,
      'temperature': temperature,
    };
    if (stopSequences != null && stopSequences.isNotEmpty) {
      options['stop_sequences'] = stopSequences;
    }
    final optionsJson = jsonEncode(options);

    try {
      // Run in isolate to avoid blocking UI
      final handle = _handle!;
      final resultJson = await Isolate.run(() {
        return cactusComplete(handle, messagesJson, optionsJson, null, null);
      });

      final parsed = jsonDecode(resultJson) as Map<String, dynamic>;
      return CactusResponse.fromJson(parsed);
    } catch (e) {
      return CactusResponse.error(e.toString());
    }
  }

  /// Resets the KV cache.
  void reset() {
    if (_handle != null) {
      cactusReset(_handle!);
    }
  }

  /// Disposes of the model and frees resources.
  Future<void> dispose() async {
    if (_handle != null) {
      final handle = _handle!;
      await Isolate.run(() {
        cactusDestroy(handle);
      });
      _handle = null;
      _isLoaded = false;
    }
  }
}

/// High-level wrapper for Cactus audio transcription.
class CactusTranscriber {
  CactusModelT? _handle;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  /// Loads a transcription model (Whisper, Moonshine, etc.).
  Future<void> load(String modelPath) async {
    if (_isLoaded) return;
    try {
      _handle = await Isolate.run(() {
        return cactusInit(modelPath, null, false);
      });
      _isLoaded = true;
    } catch (e) {
      _isLoaded = false;
      rethrow;
    }
  }

  /// Whisper prompt template with language token.
  static String _whisperPrompt(String language) =>
      '<|startoftranscript|><|$language|><|transcribe|><|notimestamps|>';

  /// Transcribes audio from a file path.
  Future<CactusTranscriptionResult> transcribeFile(String audioPath, {String language = 'id'}) async {
    if (!_isLoaded || _handle == null) {
      return CactusTranscriptionResult(
        success: false,
        error: 'Model not loaded',
        text: '',
      );
    }

    try {
      final handle = _handle!;
      final prompt = _whisperPrompt(language);
      final options = jsonEncode({'language': language});
      debugPrint('[CactusTranscriber] Using prompt: $prompt');
      final resultJson = await Isolate.run(() {
        return cactusTranscribe(handle, audioPath, prompt, options, null, null);
      });

      debugPrint('[CactusTranscriber] Raw JSON: $resultJson');
      final parsed = jsonDecode(resultJson) as Map<String, dynamic>;
      return CactusTranscriptionResult.fromJson(parsed);
    } catch (e) {
      debugPrint('[CactusTranscriber] Exception: $e');
      return CactusTranscriptionResult(
        success: false,
        error: e.toString(),
        text: '',
      );
    }
  }

  /// Transcribes audio from raw PCM data (16-bit, 16kHz, mono).
  Future<CactusTranscriptionResult> transcribePcm(Uint8List pcmData, {String language = 'id'}) async {
    if (!_isLoaded || _handle == null) {
      return CactusTranscriptionResult(
        success: false,
        error: 'Model not loaded',
        text: '',
      );
    }

    try {
      final handle = _handle!;
      final prompt = _whisperPrompt(language);
      final options = jsonEncode({'language': language});
      final resultJson = await Isolate.run(() {
        return cactusTranscribe(handle, null, prompt, options, null, pcmData);
      });

      final parsed = jsonDecode(resultJson) as Map<String, dynamic>;
      return CactusTranscriptionResult.fromJson(parsed);
    } catch (e) {
      return CactusTranscriptionResult(
        success: false,
        error: e.toString(),
        text: '',
      );
    }
  }

  /// Disposes of the model and frees resources.
  Future<void> dispose() async {
    if (_handle != null) {
      final handle = _handle!;
      await Isolate.run(() {
        cactusDestroy(handle);
      });
      _handle = null;
      _isLoaded = false;
    }
  }
}
