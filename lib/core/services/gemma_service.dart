import '../ffi/cactus_wrapper.dart';
import 'model_manager.dart';

/// Real Cactus-powered Gemma LLM service for on-device inference.
/// Handles gloss→sentence refinement, speech summarization, and gesture feedback.
class GemmaService {
  static final GemmaService _instance = GemmaService._internal();
  factory GemmaService() => _instance;
  GemmaService._internal();

  CactusModel? _model;
  bool _isLoaded = false;
  bool _isLoading = false;

  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;

  static const _systemPrompt = '''
Kamu adalah asisten terjemahan BISINDO KawanIsyarat.
Tugasmu HANYA mengubah kata-kata gloss isyarat menjadi kalimat Bahasa Indonesia natural.
Gloss dipisahkan tanda |. Jawab HANYA dengan kalimat hasil, tanpa penjelasan.

Contoh:
NAMA | SAYA | APA → Siapa nama kamu?
TERIMA KASIH | BANTU → Terima kasih sudah membantu.
MAKAN | BELUM | SAYA → Saya belum makan.
HALO → Halo!
MAAF → Maaf.
''';

  /// Initialize the LLM model.
  /// Requires model weights to be already downloaded via ModelManager.
  Future<void> initialize({void Function(double)? onProgress}) async {
    if (_isLoaded || _isLoading) return;
    _isLoading = true;

    try {
      onProgress?.call(0.1);

      final modelManager = ModelManager();
      final modelPath = await modelManager.getModelPath(ModelType.gemmaLLM);

      onProgress?.call(0.3);

      _model = CactusModel();
      await _model!.load(modelPath);

      onProgress?.call(1.0);
      _isLoaded = true;
    } catch (e) {
      _isLoading = false;
      _model = null;
      rethrow;
    }

    _isLoading = false;
  }

  /// Gloss list → natural Bahasa Indonesia sentence.
  /// ["NAMA", "SAYA", "APA"] → "Siapa nama kamu?"
  Future<String> refineGloss(List<String> glossList) async {
    if (glossList.isEmpty) return '';

    // SMART ROUTING — skip LLM for single simple words
    if (glossList.length == 1) {
      final direct = _directMap[glossList.first.toUpperCase()];
      if (direct != null) return direct;
    }

    // If model not loaded, fallback to simple join
    if (!_isLoaded || _model == null) return glossList.join(' ');

    final glossStr = glossList.join(' | ');

    try {
      final response = await _model!.complete(
        [
          ChatMessage(role: 'system', content: _systemPrompt),
          ChatMessage(role: 'user', content: glossStr),
        ],
        maxTokens: 80,
        temperature: 0.3,
        stopSequences: ['\n', 'Input:', '→'],
      );

      if (response.success && response.text.isNotEmpty) {
        return response.text.trim();
      }
      return glossList.join(' ');
    } catch (e) {
      // Fallback to simple join on model error
      return glossList.join(' ');
    }
  }

  /// Summarize long STT output into a short sentence for Deaf users.
  Future<String> summarizeSpeech(String rawText) async {
    if (rawText.isEmpty) return '';
    if (!_isLoaded || _model == null) return rawText;
    if (rawText.length < 50) return rawText; // Already short, skip LLM

    try {
      final response = await _model!.complete(
        [
          ChatMessage(role: 'system', content: _systemPrompt),
          ChatMessage(
            role: 'user',
            content: 'Ringkas menjadi 1 kalimat singkat: $rawText',
          ),
        ],
        maxTokens: 60,
        temperature: 0.2,
      );

      if (response.success && response.text.isNotEmpty) {
        return response.text.trim();
      }
      return rawText;
    } catch (e) {
      return rawText;
    }
  }

  /// Corrective feedback for education/learning mode.
  Future<String> getGestureFeedback({
    required String targetWord,
    required String detectedIssue,
  }) async {
    if (!_isLoaded || _model == null) return 'Coba lagi ya!';

    try {
      final response = await _model!.complete(
        [
          ChatMessage(
            role: 'system',
            content:
                'Kamu guru BISINDO yang sabar. Beri feedback singkat 1 kalimat, encouraging.',
          ),
          ChatMessage(
            role: 'user',
            content: 'Kata: $targetWord. Masalah: $detectedIssue',
          ),
        ],
        maxTokens: 50,
        temperature: 0.5,
      );

      if (response.success && response.text.isNotEmpty) {
        return response.text.trim();
      }
      return 'Hampir benar, coba lagi!';
    } catch (e) {
      return 'Hampir benar, coba lagi!';
    }
  }

  // Direct map for single words — bypass LLM, <1ms
  static const _directMap = {
    'YA': 'Ya.',
    'TIDAK': 'Tidak.',
    'HALO': 'Halo!',
    'MAAF': 'Maaf.',
    'TERIMA KASIH': 'Terima kasih.',
    'TOLONG': 'Tolong.',
    'OKE': 'Oke.',
    'BAGUS': 'Bagus!',
    'NAMA': 'Nama...',
    'SAYA': 'Saya...',
    'TERIMA': 'Terima...',
  };

  Future<void> dispose() async {
    await _model?.dispose();
    _model = null;
    _isLoaded = false;
  }
}
