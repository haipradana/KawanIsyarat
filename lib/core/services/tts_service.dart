import 'package:flutter_tts/flutter_tts.dart';

/// TTS service that wraps flutter_tts for text-to-speech functionality.
class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isEnabled = true;

  bool get isEnabled => _isEnabled;

  Future<void> init() async {
    if (_isInitialized) return;

    await _flutterTts.setLanguage('id-ID');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _isInitialized = true;
  }

  Future<void> speak(String text) async {
    if (!_isEnabled) return;
    await init();
    await _flutterTts.speak(text);
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (!enabled) {
      stop();
    }
  }

  void dispose() {
    _flutterTts.stop();
  }
}
