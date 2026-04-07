import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'model_manager.dart';

// ============================================================
// NOTE: Cactus SDK code has been commented out below.
// Alasan: Gemma 4 E2B INT4 via Cactus terlalu berat untuk Pixel 6a (~2GB RAM)
// → OOM/force close bahkan setelah Whisper di-unload.
// Solusi: flutter_gemma (LiteRT LM via MediaPipe GenAI backend) hanya
// menggunakan ~676MB RAM di GPU — terbukti jalan di Pixel 6a via AI Edge Gallery.
// Cactus tetap dipakai untuk Whisper STT (tidak ada alternatif LiteRT).
// Untuk mencoba kembali Cactus Gemma: uncomment kode di bawah dan
// comment out blok flutter_gemma. Butuh device ≥ 8GB RAM.
// ============================================================

// CACTUS IMPORT (disabled — too heavy for Pixel 6a):
// import '../ffi/cactus_wrapper.dart';

/// Hasil empati kontekstual dari Gemma untuk alur Tuli→Dengar.
class EmpathyResult {
  /// Kalimat lengkap terjemahan gloss untuk lawan bicara (orang dengar).
  final String sentence;

  /// Saran proaktif Gemma untuk lawan bicara agar komunikasi lebih empati.
  final String? aiSuggestion;

  const EmpathyResult({required this.sentence, this.aiSuggestion});
}

/// flutter_gemma (LiteRT LM) Gemma service.
/// Uses MediaPipe GenAI backend for on-device inference with GPU acceleration.
/// Handles gloss→sentence refinement, speech summarization, and gesture feedback.
class GemmaService {
  static final GemmaService _instance = GemmaService._internal();
  factory GemmaService() => _instance;
  GemmaService._internal();

  // flutter_gemma model instance (LiteRT LM)
  gemma.InferenceModel? _model;
  bool _isLoaded = false;
  bool _isLoading = false;

  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;

  // ---- System prompts (unchanged from Cactus version) ----

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

  // ---- flutter_gemma Implementation ----

  /// Initialize the LLM model via flutter_gemma (LiteRT LM).
  /// Registers the .task file with MediaPipe GenAI backend and loads into GPU memory.
  Future<void> initialize({void Function(double)? onProgress}) async {
    debugPrint('[GemmaService] initialize() called — isLoaded=$_isLoaded, isLoading=$_isLoading');
    if (_isLoaded || _isLoading) return;
    _isLoading = true;

    try {
      onProgress?.call(0.1);

      final modelManager = ModelManager();
      final modelPath = await modelManager.getModelPath(ModelType.gemmaLLM);

      onProgress?.call(0.2);
      debugPrint('[GemmaService] Installing flutter_gemma model from: $modelPath');

      // Register .task file with MediaPipe GenAI backend
      await gemma.FlutterGemma.installModel(
        modelType: gemma.ModelType.gemmaIt,
      ).fromFile(modelPath).install();

      onProgress?.call(0.6);

      // Load model — paksa GPU (XNNPack/CPU path punya bug DYNAMIC_UPDATE_SLICE
      // di Pixel 6a). AI Edge Gallery berhasil karena pakai GPU backend.
      _model = await gemma.FlutterGemma.getActiveModel(
        maxTokens: 1024,
        preferredBackend: gemma.PreferredBackend.gpu,
      );

      onProgress?.call(1.0);
      _isLoaded = true;
      _isLoading = false;
      debugPrint('[GemmaService] flutter_gemma model loaded (LiteRT GPU)');
    } catch (e) {
      debugPrint('[GemmaService] Failed to load Gemma model: $e');
      _isLoading = false;
      _model = null;
      rethrow;
    }
  }

  /// Run a single-turn inference with the given system prompt and user message.
  /// Creates a new chat session per call to avoid context bleed between prompts.
  Future<String?> _infer(String systemPrompt, String userMessage) async {
    if (!_isLoaded || _model == null) return null;

    final chat = await _model!.createChat(systemInstruction: systemPrompt);
    try {
      await chat.addQueryChunk(
        gemma.Message.text(text: userMessage, isUser: true),
      );

      final buffer = StringBuffer();
      await for (final chunk in chat.generateChatResponseAsync()) {
        if (chunk is gemma.TextResponse) {
          buffer.write(chunk.token);
        }
      }
      return buffer.toString().trim();
    } finally {
      await chat.close();
    }
  }

  /// Gloss list → natural Bahasa Indonesia sentence.
  /// ["NAMA", "SAYA", "APA"] → "Siapa nama kamu?"
  Future<String> refineGloss(List<String> glossList) async {
    if (glossList.isEmpty) return '';

    if (glossList.length == 1) {
      final direct = _directMap[glossList.first.toUpperCase()];
      if (direct != null) return direct;
    }

    if (!_isLoaded || _model == null) return glossList.join(' ');

    final result = await _infer(_systemPrompt, glossList.join(' | '));
    return result?.isNotEmpty == true ? result! : glossList.join(' ');
  }

  /// Gloss → kalimat + saran empatik untuk lawan bicara (Contextual Empathy).
  Future<EmpathyResult> refineGlossWithEmpathy(List<String> glossList) async {
    if (glossList.isEmpty) return EmpathyResult(sentence: '');

    if (glossList.length == 1) {
      final direct = _directMap[glossList.first.toUpperCase()];
      if (direct != null) return EmpathyResult(sentence: direct);
    }

    if (!_isLoaded || _model == null) {
      return EmpathyResult(sentence: glossList.join(' '));
    }

    final response = await _infer(_empathySystemPrompt, glossList.join(' | '));
    if (response == null || response.isEmpty) {
      return EmpathyResult(sentence: glossList.join(' '));
    }

    final lines = response.split('\n');
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

  /// Sederhanakan transkripsi suara untuk ditampilkan ke orang Tuli.
  Future<String> simplifyForDeaf(String rawText) async {
    if (rawText.isEmpty) return '';
    if (!_isLoaded || _model == null) {
      debugPrint('[GemmaService] simplifyForDeaf: model NOT loaded (isLoaded=$_isLoaded, model=${_model != null}) — returning raw text');
      return rawText;
    }

    final result = await _infer(_simplifySystemPrompt, '"$rawText"');
    return result?.replaceAll('"', '') ?? rawText;
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
    await _model?.close();
    _model = null;
    _isLoaded = false;
  }
}

// ============================================================
// CACTUS GEMMA CODE (disabled — terlalu berat untuk Pixel 6a):
// ============================================================
//
// import 'dart:io';
// import '../ffi/cactus_wrapper.dart';
//
// CactusModel? _model;
//
// Future<void> initialize({void Function(double)? onProgress}) async {
//   onProgress?.call(0.1);
//   final modelManager = ModelManager();
//   final modelPath = await modelManager.getModelPath(ModelType.gemmaLLM);
//   onProgress?.call(0.3);
//   final modelDir = Directory(modelPath);
//   if (!await modelDir.exists()) throw Exception('Model not found: $modelPath');
//   _model = CactusModel();
//   await _model!.load(modelPath);
//   onProgress?.call(1.0);
//   _isLoaded = true;
// }
//
// // Inference via CactusModel.complete():
// // final response = await _model!.complete(
// //   [ChatMessage(role: 'system', content: systemPrompt),
// //    ChatMessage(role: 'user', content: userMsg)],
// //   maxTokens: 80, temperature: 0.3, stopSequences: ['\n'],
// // );
// // return response.success ? response.text.trim() : fallback;
//
// // dispose:
// // await _model?.dispose();
// ============================================================
