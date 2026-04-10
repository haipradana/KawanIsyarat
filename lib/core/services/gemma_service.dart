import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../ffi/cactus_wrapper.dart';
import 'model_manager.dart';

// ============================================================
// NOTE: Gemma sekarang menggunakan Cactus SDK (INT4, ~4GB).
// Optimasi RAM untuk Pixel 6a (6GB):
// - n_ctx: 512 → kurangi KV cache (default 4096+ boros RAM)
// - memory_f32: false → KV cache FP16 (hemat 50% KV cache RAM)
// - batch_size: 1 → kurangi memory spike per batch
// - n_threads: 4 → pakai 4 dari 8 core (sisakan headroom)
//
// flutter_gemma (LiteRT LM) code dicomment di bawah sebagai STABLE FALLBACK.
// Jika Cactus OOM di Pixel 6a, uncomment kode flutter_gemma dan
// comment kode Cactus di atas.
// ============================================================

/// Hasil empati kontekstual dari Gemma untuk alur Tuli->Dengar.
class EmpathyResult {
  /// Kalimat lengkap terjemahan gloss untuk lawan bicara (orang dengar).
  final String sentence;

  /// Saran proaktif Gemma untuk lawan bicara agar komunikasi lebih empati.
  final String? aiSuggestion;

  const EmpathyResult({required this.sentence, this.aiSuggestion});
}

/// Cactus SDK Gemma service.
/// Uses Cactus FFI for on-device inference with optimized memory settings.
/// Handles gloss->sentence refinement, speech summarization, and gesture feedback.
class GemmaService {
  static final GemmaService _instance = GemmaService._internal();
  factory GemmaService() => _instance;
  GemmaService._internal();

  // Cactus model instance
  CactusModel? _model;
  bool _isLoaded = false;
  bool _isLoading = false;

  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;

  // ---- System prompts ----

  static const _systemPrompt = '''
Kamu asisten terjemahan BISINDO.
Input dari user adalah urutan kata gloss BISINDO yang sudah dibersihkan, bukan kalimat natural.
Tugasmu adalah merangkai gloss itu menjadi 1 kalimat Bahasa Indonesia yang natural, singkat, dan jelas.
Tambahkan kata sambung, imbuhan, atau preposisi seperlunya agar kalimat enak dibaca.
Pertahankan makna utama gloss. Jangan menambah detail baru yang tidak ada di gloss.
Jika urutannya terasa seperti frasa, ubah menjadi ucapan yang paling wajar dalam konteks percakapan sehari-hari.
Jangan jelaskan prosesnya.
Jangan menulis daftar kata.
Jawab HANYA satu kalimat hasil akhir.

Contoh:
SAYA MAKAN SIANG -> Saya mau makan siang.
SAYA PUSING OBAT -> Saya pusing, butuh obat.
MOTOR BELAJAR RUMAH -> Saya belajar motor di rumah.
TEMAN RUMAH JAUH -> Rumah teman saya jauh.
''';

  static const _empathySuggestionPrompt = '''
Berikan 1 saran singkat empatik untuk orang dengar yang berkomunikasi dengan orang Tuli yang mengatakan kalimat ini. Jawab 1 kalimat saja.
''';

  static const _simplifySystemPrompt = '''
Kamu membantu orang Tuli memahami ucapan orang dengar.
Sederhanakan kalimat berikut: hapus kata filler (eh, um, uh, jadi, gitu, kan),
perbaiki transkripsi yang tidak akurat, buat singkat dan jelas.
Jawab HANYA dengan kalimat hasil, tanpa penjelasan.

Contoh:
"eh jadi gitu, kamu itu eh mau makan apa hari ini?" -> "Kamu mau makan apa hari ini?"
"maaf ya aku terlambat, jalanan macet banget tadi" -> "Maaf terlambat, jalanan macet."
"aku cuma mau bilang makasih buat bantuannya kemarin loh" -> "Terima kasih atas bantuannya kemarin."
''';

  // System prompt untuk audio transcription via Gemma 4 audio encoder
  static const _audioTranscribePrompt = '''
Transkripsikan audio berikut ke dalam Bahasa Indonesia.
Jawab HANYA dengan teks transkripsi, tanpa penjelasan atau komentar.
''';

  // ---- Cactus SDK Implementation ----

  /// Initialize the LLM model via Cactus SDK.
  /// Loads Gemma 4 E2B INT4 from extracted zip directory.
  Future<void> initialize({void Function(double)? onProgress}) async {
    debugPrint('[GemmaService] initialize() called — isLoaded=$_isLoaded, isLoading=$_isLoading');
    if (_isLoaded || _isLoading) return;
    _isLoading = true;

    try {
      onProgress?.call(0.1);

      final modelManager = ModelManager();
      final modelPath = await modelManager.getModelPath(ModelType.gemmaLLM);

      onProgress?.call(0.2);

      // Verify model directory exists
      final modelDir = Directory(modelPath);
      if (!await modelDir.exists()) {
        throw Exception('Model directory not found: $modelPath');
      }

      // Verify config.txt exists
      final configFile = File('$modelPath/config.txt');
      if (!await configFile.exists()) {
        final files = await modelDir.list().map((e) => e.path.split('/').last).toList();
        debugPrint('[GemmaService] Model dir contents: $files');
        throw Exception('config.txt not found in $modelPath. Files: $files');
      }

      debugPrint('[GemmaService] Loading Cactus Gemma model from: $modelPath');
      onProgress?.call(0.3);

      // Optimasi RAM untuk Pixel 6a (6GB):
      // - n_ctx: 512 → kurangi KV cache window (default 4096+)
      // - memory_f32: false → KV cache FP16 (hemat 50% KV cache RAM)
      // - batch_size: 1 → kurangi memory spike
      // - n_threads: 4 → pakai 4 dari 8 core
      final initOptions = jsonEncode({
        'n_ctx': 512,
        'memory_f32': false,
        'batch_size': 1,
        'n_threads': 4,
      });

      _model = CactusModel();
      await _model!.load(modelPath, optionsJson: initOptions);

      onProgress?.call(1.0);
      _isLoaded = true;
      _isLoading = false;
      debugPrint('[GemmaService] Cactus Gemma model loaded (INT4, optimized)');
    } catch (e) {
      debugPrint('[GemmaService] Failed to load Gemma model: $e');
      _isLoading = false;
      _model = null;
      rethrow;
    }
  }

  /// Run a single-turn inference with the given system prompt and user message.
  /// Uses Cactus complete() with optimized options for low-RAM devices.
  Future<String?> _infer(String systemPrompt, String userMessage) async {
    if (!_isLoaded || _model == null) return null;

    try {
      // Reset KV cache before each inference to avoid stale state
      _model!.reset();

      final response = await _model!.complete(
        [
          ChatMessage(role: 'system', content: systemPrompt),
          ChatMessage(role: 'user', content: userMessage),
        ],
        maxTokens: 80, // Thinking disabled — jawaban langsung, tidak perlu ruang ekstra
        temperature: 0.3,
        stopSequences: ['\n\n\n'], // Hanya stop di blank line ganda, bukan di <|channel>
      );

      if (response.success) {
        final cleaned = _cleanResponse(response.text);
        debugPrint('[GemmaService] Inference OK: ${cleaned.length} chars, '
            '${response.decodeTps.toStringAsFixed(1)} tok/s, '
            '${response.totalTimeMs.toStringAsFixed(0)}ms');
        return cleaned;
      } else {
        debugPrint('[GemmaService] Inference failed: ${response.error}');
        return null;
      }
    } catch (e) {
      debugPrint('[GemmaService] Exception during inference: $e');
      return null;
    }
  }

  /// Parse response — handle thinking mode output dari Gemma 4.
  ///
  /// Gemma 4 dengan thinking aktif menghasilkan:
  ///   `<|channel>thought\n[reasoning]<channel|>[jawaban]`
  ///
  /// Kalau thinking tidak aktif, langsung menghasilkan:
  ///   `[jawaban]`
  ///
  /// Kita ambil teks setelah `<channel|>` jika ada, otherwise full text.
  String _cleanResponse(String raw) {
    var text = raw.trim();

    // Kalau ada closing thinking tag, ambil teks setelahnya (jawaban asli)
    const closingTag = '<channel|>';
    final closeIdx = text.indexOf(closingTag);
    if (closeIdx >= 0) {
      text = text.substring(closeIdx + closingTag.length).trim();
      debugPrint('[GemmaService] Thinking detected & stripped, extracted answer');
    }

    // Bersihkan sisa special tokens kalau ada
    text = text.replaceAll(RegExp(r'<\|[^>|]+\|?>'), '').trim();
    return text;
  }

  /// Gloss list -> natural Bahasa Indonesia sentence.
  /// ["NAMA", "SAYA", "APA"] -> "Siapa nama kamu?"
  Future<String> refineGloss(List<String> glossList) async {
    if (glossList.isEmpty) return '';

    final preparedGloss = _prepareGlossTokens(glossList);
    if (preparedGloss.isEmpty) return '';

    final directKey = preparedGloss.join(' ').toUpperCase();
    final direct = _directMap[directKey];
    if (direct != null) {
      return direct;
    }

    if (preparedGloss.length == 1) {
      final singleWordDirect = _directMap[preparedGloss.first.toUpperCase()];
      if (singleWordDirect != null) return singleWordDirect;
    }

    if (!_isLoaded || _model == null) return preparedGloss.join(' ');

    final promptInput = 'Gloss BISINDO: ${preparedGloss.join(' ')}';
    debugPrint('[GemmaService] refineGloss input: $promptInput');

    final result = await _infer(_systemPrompt, promptInput);
    return result?.isNotEmpty == true ? result! : preparedGloss.join(' ');
  }

  List<String> _prepareGlossTokens(List<String> glossList) {
    final prepared = <String>[];

    for (final rawToken in glossList) {
      final token = rawToken.trim();
      if (token.isEmpty || token == '|') continue;

      final normalized = token.toUpperCase();
      final last = prepared.isNotEmpty ? prepared.last.toUpperCase() : null;
      if (normalized == last) continue;

      prepared.add(token);
    }

    return prepared;
  }

  /// Gloss -> kalimat + saran empatik untuk lawan bicara (Contextual Empathy).
  /// Step 1: refineGloss (kalimat) — same _infer as simplifyForDeaf, cepat.
  /// Step 2: getEmpathySuggestion (saran AI) — panggilan _infer kedua, opsional.
  Future<EmpathyResult> refineGlossWithEmpathy(List<String> glossList) async {
    // Step 1: kalimat
    final sentence = await refineGloss(glossList);
    if (sentence.isEmpty) return EmpathyResult(sentence: '');

    // Step 2: saran empatik (skip jika single-word direct map)
    if (glossList.length == 1 && _directMap.containsKey(glossList.first.toUpperCase())) {
      return EmpathyResult(sentence: sentence);
    }

    final suggestion = await getEmpathySuggestion(sentence);
    return EmpathyResult(sentence: sentence, aiSuggestion: suggestion);
  }

  /// Saran empatik singkat untuk orang dengar berdasarkan kalimat terjemahan.
  Future<String?> getEmpathySuggestion(String sentence) async {
    return _infer(_empathySuggestionPrompt, sentence);
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
    'SELAMAT PAGI': 'Selamat pagi.',
    'SELAMAT SIANG': 'Selamat siang.',
    'SELAMAT MALAM': 'Selamat malam.',
    'TOLONG': 'Tolong.',
    'OKE': 'Oke.',
    'BAGUS': 'Bagus!',
    'NAMA': 'Nama...',
    'SAYA': 'Saya...',
    'TERIMA': 'Terima...',
  };

  /// [EKSPERIMEN] Transkripsikan audio menggunakan Gemma 4 audio encoder.
  /// Mengirim raw PCM (16-bit, 16kHz, mono) langsung ke cactusComplete via pcmData.
  /// Jika berhasil, bisa menggantikan Whisper STT sepenuhnya.
  Future<String> transcribeAudio(Uint8List pcmData) async {
    if (pcmData.isEmpty) return '';
    if (!_isLoaded || _model == null) {
      debugPrint('[GemmaService] transcribeAudio: model NOT loaded');
      return '';
    }

    try {
      _model!.reset();

      debugPrint('[GemmaService] transcribeAudio: ${pcmData.length} bytes PCM');

      final response = await _model!.complete(
        [
          ChatMessage(role: 'system', content: _audioTranscribePrompt),
          ChatMessage(role: 'user', content: '<|audio|>'),
        ],
        maxTokens: 200,
        temperature: 0.1, // Low temperature for accurate transcription
        stopSequences: ['\n\n', '<|channel>'],
        pcmData: pcmData,
      );

      if (response.success && response.text.isNotEmpty) {
        final cleaned = _cleanResponse(response.text);
        debugPrint('[GemmaService] transcribeAudio OK: "$cleaned" '
            '(${response.decodeTps.toStringAsFixed(1)} tok/s, '
            '${response.totalTimeMs.toStringAsFixed(0)}ms)');
        return cleaned;
      } else {
        debugPrint('[GemmaService] transcribeAudio failed: ${response.error}');
        return '';
      }
    } catch (e) {
      debugPrint('[GemmaService] transcribeAudio exception: $e');
      return '';
    }
  }

  /// [EKSPERIMEN] Transkripsikan audio + langsung sederhanakan untuk orang Tuli.
  /// Menggabungkan transcribe + simplify dalam 1 inference (hemat latency).
  Future<String> transcribeAndSimplifyAudio(Uint8List pcmData) async {
    if (pcmData.isEmpty) return '';
    if (!_isLoaded || _model == null) return '';

    try {
      _model!.reset();

      debugPrint('[GemmaService] transcribeAndSimplify: ${pcmData.length} bytes PCM');

      final response = await _model!.complete(
        [
          ChatMessage(
            role: 'system',
            content: 'Dengarkan audio berikut, lalu tuliskan transkripsinya dalam Bahasa Indonesia '
                'yang singkat dan jelas. Hapus kata filler (eh, um, jadi, gitu). '
                'Jawab HANYA dengan kalimat hasil.',
          ),
          ChatMessage(role: 'user', content: '<|audio|>'),
        ],
        maxTokens: 150,
        temperature: 0.1,
        stopSequences: ['\n\n', '<|channel>'],
        pcmData: pcmData,
      );

      if (response.success && response.text.isNotEmpty) {
        final cleaned = _cleanResponse(response.text);
        debugPrint('[GemmaService] transcribeAndSimplify OK: "$cleaned" '
            '(${response.decodeTps.toStringAsFixed(1)} tok/s, '
            '${response.totalTimeMs.toStringAsFixed(0)}ms)');
        return cleaned;
      }
      return '';
    } catch (e) {
      debugPrint('[GemmaService] transcribeAndSimplify exception: $e');
      return '';
    }
  }

  Future<void> dispose() async {
    await _model?.dispose();
    _model = null;
    _isLoaded = false;
  }
}

// ============================================================
// STABLE FALLBACK — flutter_gemma (LiteRT LM) code.
// Jika Cactus OOM di Pixel 6a, uncomment kode di bawah dan
// comment kode Cactus di atas.
// flutter_gemma menggunakan MediaPipe GenAI (LiteRT) — ~676MB RAM GPU,
// terbukti jalan di Pixel 6a via AI Edge Gallery.
// ============================================================
//
// import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
//
// // In main.dart, add:
// // await FlutterGemma.initialize();
//
// // Model: .litertlm format (~2.58GB)
// // URL: https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm
// // model_manager.dart: ModelType.gemmaLLM dir = 'gemma-4-e2b-it.litertlm' (single file)
//
// gemma.InferenceModel? _model;
//
// Future<void> initialize({void Function(double)? onProgress}) async {
//   onProgress?.call(0.1);
//   final modelManager = ModelManager();
//   final modelPath = await modelManager.getModelPath(ModelType.gemmaLLM);
//   onProgress?.call(0.2);
//
//   await gemma.FlutterGemma.installModel(
//     modelType: gemma.ModelType.gemmaIt,
//   ).fromFile(modelPath).install();
//
//   onProgress?.call(0.6);
//
//   _model = await gemma.FlutterGemma.getActiveModel(
//     maxTokens: 1024,
//     preferredBackend: gemma.PreferredBackend.gpu,
//   );
//
//   onProgress?.call(1.0);
//   _isLoaded = true;
// }
//
// Future<String?> _infer(String systemPrompt, String userMessage) async {
//   if (!_isLoaded || _model == null) return null;
//   final chat = await _model!.createChat(systemInstruction: systemPrompt);
//   try {
//     await chat.addQueryChunk(
//       gemma.Message.text(text: userMessage, isUser: true),
//     );
//     final buffer = StringBuffer();
//     await for (final chunk in chat.generateChatResponseAsync()) {
//       if (chunk is gemma.TextResponse) {
//         buffer.write(chunk.token);
//       }
//     }
//     return buffer.toString().trim();
//   } finally {
//     await chat.close();
//   }
// }
//
// Future<void> dispose() async {
//   await _model?.close();
//   _model = null;
//   _isLoaded = false;
// }
// ============================================================
