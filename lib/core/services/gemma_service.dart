import 'dart:io';
import 'package:flutter/foundation.dart';
import '../ffi/cactus_wrapper.dart';
import 'model_manager.dart';

/// Hasil empati kontekstual dari Gemma untuk alur Tuli→Dengar.
class EmpathyResult {
  /// Kalimat lengkap terjemahan gloss untuk lawan bicara (orang dengar).
  final String sentence;
  /// Saran proaktif Gemma untuk lawan bicara agar komunikasi lebih empati.
  final String? aiSuggestion;

  const EmpathyResult({required this.sentence, this.aiSuggestion});
}

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

  /// Untuk fitur Contextual Empathy — Deaf→Hearing.
  /// Menghasilkan terjemahan gloss + saran empatik untuk orang dengar.
  static const _empathySystemPrompt = '''
Kamu adalah jembatan komunikasi empatik antara orang Tuli dan orang dengar di KawanIsyarat.
Diberikan gloss BISINDO (kata-kata isyarat), lakukan DUA hal:
1. Terjemahkan menjadi kalimat Bahasa Indonesia natural (1 baris).
2. Berikan saran singkat empatik untuk lawan bicara (orang dengar), dimulai dengan "(Saran AI):".

Format jawaban TEPAT seperti ini (2 baris, tanpa tambahan apapun):
[kalimat terjemahan]
(Saran AI): [saran untuk lawan bicara]

Contoh:
SAYA | PUSING | OBAT
Saya merasa pusing dan butuh obat.
(Saran AI): Tanyakan apakah dia butuh diantar ke ruang kesehatan atau minta air putih.

TERIMA KASIH | BANTU
Terima kasih sudah membantu.
(Saran AI): Balas dengan senyum dan tanyakan apakah ada hal lain yang bisa dibantu.
''';

  /// Untuk fitur Hearing→Deaf — menyederhanakan transkripsi suara.
  /// Menghapus kata pengisi, filler, dan memperjelas untuk orang Tuli.
  static const _simplifySystemPrompt = '''
Kamu membantu orang Tuli memahami ucapan orang dengar.
Sederhanakan kalimat berikut: hapus kata filler (eh, um, uh, jadi, gitu, kan),
perbaiki transkripsi yang tidak akurat, buat singkat dan jelas.
Jawab HANYA dengan kalimat hasil, tanpa penjelasan.

Contoh:
"eh jadi gitu, kamu itu eh mau makan apa hari ini?" → "Kamu mau makan apa hari ini?"
"maaf ya aku terlambat, jalanan macet banget tadi" → "Maaf terlambat, jalanan macet."
"aku cuma mau bilang makasih buat bantuannya kemarin loh" → "Terima kasih atas bantuannya kemarin."
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

      // Verify model directory
      final modelDir = Directory(modelPath);
      if (!await modelDir.exists()) {
        throw Exception('Model directory not found: $modelPath');
      }
      debugPrint('[GemmaService] Loading Gemma model from: $modelPath');

      _model = CactusModel();
      await _model!.load(modelPath);

      onProgress?.call(1.0);
      _isLoaded = true;
      debugPrint('[GemmaService] Gemma model loaded successfully');
    } catch (e) {
      debugPrint('[GemmaService] Failed to load Gemma model: $e');
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

  /// Gloss → kalimat + saran empatik untuk lawan bicara (Contextual Empathy).
  /// Fallback: EmpathyResult dengan kalimat join gloss, tanpa saran.
  Future<EmpathyResult> refineGlossWithEmpathy(List<String> glossList) async {
    if (glossList.isEmpty) return EmpathyResult(sentence: '');

    // SMART ROUTING — single word
    if (glossList.length == 1) {
      final direct = _directMap[glossList.first.toUpperCase()];
      if (direct != null) return EmpathyResult(sentence: direct);
    }

    if (!_isLoaded || _model == null) {
      return EmpathyResult(sentence: glossList.join(' '));
    }

    final glossStr = glossList.join(' | ');
    try {
      final response = await _model!.complete(
        [
          ChatMessage(role: 'system', content: _empathySystemPrompt),
          ChatMessage(role: 'user', content: glossStr),
        ],
        maxTokens: 120,
        temperature: 0.4,
        stopSequences: ['\n\n', 'Input:'],
      );

      if (response.success && response.text.isNotEmpty) {
        final lines = response.text.trim().split('\n');
        final sentence = lines.isNotEmpty ? lines[0].trim() : glossList.join(' ');
        String? suggestion;
        for (final line in lines.skip(1)) {
          if (line.contains('(Saran AI):')) {
            suggestion = line.replaceFirst(RegExp(r'\(Saran AI\):\s*'), '').trim();
            break;
          }
        }
        return EmpathyResult(sentence: sentence, aiSuggestion: suggestion);
      }
      return EmpathyResult(sentence: glossList.join(' '));
    } catch (e) {
      return EmpathyResult(sentence: glossList.join(' '));
    }
  }

  /// Sederhanakan transkripsi suara untuk ditampilkan ke orang Tuli.
  /// Menghapus filler words, memperbaiki transkripsi tidak akurat.
  /// Tidak ada batas panjang — semua teks diproses Gemma.
  Future<String> simplifyForDeaf(String rawText) async {
    if (rawText.isEmpty) return '';
    if (!_isLoaded || _model == null) return rawText;

    try {
      final response = await _model!.complete(
        [
          ChatMessage(role: 'system', content: _simplifySystemPrompt),
          ChatMessage(role: 'user', content: '"$rawText"'),
        ],
        maxTokens: 80,
        temperature: 0.2,
        stopSequences: ['\n', 'Input:', '"'],
      );

      if (response.success && response.text.isNotEmpty) {
        return response.text.trim().replaceAll('"', '');
      }
      return rawText;
    } catch (e) {
      return rawText;
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
