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

  static const _empathyTipsPrompt = '''
Kamu asisten empati untuk orang dengar yang sedang ngobrol dengan teman Tuli.
Orang Tuli baru saja menyampaikan pesan. Buat 3 tips singkat (maksimal 12 kata per tips) yang bisa membantu orang dengar merespon dengan empati, sabar, dan inklusif.
Format: tiap tips di baris terpisah, diawali dengan tanda "-". Jangan pakai nomor. Jangan tambahkan kalimat pembuka atau penutup.
Jawab HANYA 3 baris tips.

Contoh input: "Saya pusing, butuh obat."
Contoh output:
- Tanyakan apakah dia butuh diantar ke ruang kesehatan.
- Bicara perlahan dan hadap wajah saat merespon.
- Tawarkan air putih atau tempat duduk yang nyaman.
''';

  static const _visionCoachSystemPrompt = '''
Kamu pelatih bahasa isyarat Indonesia (BISINDO & SIBI) yang ramah dan sabar.

Kamu akan menerima:
- Foto tangan pengguna
- Huruf/kata target yang sedang dipelajari
- Referensi bentuk isyarat yang BENAR untuk target tersebut
- Hasil CNN detector (benar/salah) + jumlah percobaan

Tugasmu: bandingkan foto dengan referensi, lalu beri umpan balik singkat (maks. 2 kalimat) dalam Bahasa Indonesia.

Aturan:
- Jika CNN bilang BENAR: beri apresiasi tulus + 1 tips penyempurnaan kecil (kejelasan, kemantapan, kecepatan).
- Jika CNN bilang SALAH: bandingkan foto ke referensi, sebutkan SATU bagian paling jelas yang meleset (jari mana, arah mana, posisi mana), lalu cara perbaikinya.
- Jika percobaan sudah >2 kali gagal: tambahkan kalimat penyemangat lembut, jangan menghakimi.
- JANGAN mengarang referensi baru. Pakai deskripsi referensi yang diberikan.
- JANGAN jelaskan teori. Langsung ke saran praktis.
- Gunakan kata "kamu" yang hangat, seperti teman yang mendampingi.
''';

  /// Referensi bentuk isyarat per huruf/kata.
  /// Dipakai sebagai ground-truth yang di-inject ke prompt — Gemma 4 tidak tahu
  /// bentuk pasti huruf BISINDO/SIBI dari training dasarnya, jadi harus dikasih
  /// tahu eksplisit supaya koreksinya tidak ngawur.
  ///
  /// Sumber deskripsi: konvensi BISINDO (2 tangan) dan SIBI (1 tangan) standar.
  static const Map<String, String> _bisindoAlphabetReference = {
    'A': 'Dua tangan mengepal, ibu jari kedua tangan saling bertemu/menempel di ujung, posisi horizontal.',
    'B': 'Tangan kiri terbuka tegak (empat jari rapat, ibu jari menekuk), telapak menghadap depan. Jari telunjuk tangan kanan menyentuh telapak tangan kiri.',
    'C': 'Kedua tangan membentuk setengah lingkaran huruf "C" yang saling berhadapan, jari-jari melengkung.',
    'D': 'Telunjuk tangan kiri lurus ke atas. Tangan kanan membentuk huruf C melingkari telunjuk kiri.',
    'E': 'Dua tangan mengepal, jari-jari ditekuk ke dalam. Kedua kepalan saling bertumpuk atau berdekatan.',
    'F': 'Telunjuk dan ibu jari membentuk lingkaran (OK sign) pada masing-masing tangan, dua tangan berdekatan di depan dada.',
    'G': 'Telunjuk tangan kiri menunjuk ke depan horizontal. Ibu jari dan telunjuk tangan kanan menjepit/paralel di sampingnya.',
    'H': 'Dua tangan membentuk "H": masing-masing tangan telunjuk dan jari tengah rapat mengarah ke depan, saling sejajar horizontal.',
    'I': 'Kedua kelingking tangan saling bertemu/berhadapan, jari lain mengepal.',
    'J': 'Kelingking tangan dominan membuat gerakan kurva menurun seperti bentuk huruf J (isyarat dinamis).',
    'K': 'Telunjuk dan jari tengah membentuk "V" pada kedua tangan, ibu jari menyentuh pangkal jari tengah, dua tangan bertemu.',
    'L': 'Telunjuk dan ibu jari membentuk "L" (siku-siku) pada tangan dominan, tangan lain mengepal atau datar sebagai alas.',
    'M': 'Tiga jari (telunjuk, tengah, manis) tangan kanan menjuntai ke bawah menyentuh punggung tangan kiri yang datar horizontal.',
    'N': 'Dua jari (telunjuk, tengah) tangan kanan menjuntai ke bawah menyentuh punggung tangan kiri yang datar.',
    'O': 'Kedua tangan membentuk lingkaran "O" dengan jari-jari melengkung, dua tangan bertemu membentuk bulatan utuh.',
    'P': 'Telunjuk tangan kanan mengarah ke bawah, jari tengah melengkung. Tangan kiri datar sebagai alas di bawahnya.',
    'Q': 'Ibu jari dan telunjuk tangan kanan menjepit ke bawah seperti cubitan. Tangan kiri datar sebagai alas.',
    'R': 'Telunjuk dan jari tengah menyilang pada kedua tangan, dua tangan bertemu di depan dada.',
    'S': 'Dua tangan mengepal penuh, ibu jari menutup di atas buku jari. Dua kepalan bertumpuk atau berdekatan.',
    'T': 'Ibu jari tangan kanan terselip di antara telunjuk & jari tengah (kepalan). Tangan kiri datar sebagai alas.',
    'U': 'Telunjuk dan jari tengah rapat tegak pada kedua tangan, dua tangan sejajar berhadapan.',
    'V': 'Telunjuk dan jari tengah membentuk "V" terbuka pada kedua tangan, dua tangan sejajar.',
    'W': 'Telunjuk, jari tengah, jari manis terbuka (tiga jari) pada kedua tangan, dua tangan bertemu.',
    'X': 'Telunjuk tangan kanan menekuk seperti kait. Tangan kiri menggenggam atau menjadi alas.',
    'Y': 'Ibu jari dan kelingking terbuka (tanda "call me") pada kedua tangan, dua tangan saling menyentuh.',
    'Z': 'Telunjuk tangan dominan menggambar huruf "Z" di udara (isyarat dinamis).',
  };

  static const Map<String, String> _sibiAlphabetReference = {
    'A': 'Tangan mengepal, ibu jari di samping (tidak menutup kepalan), telapak menghadap ke depan.',
    'B': 'Empat jari rapat tegak lurus, ibu jari ditekuk menempel ke telapak. Telapak menghadap depan.',
    'C': 'Tangan membentuk huruf "C" — jari-jari melengkung, ibu jari dan jari lain membentuk setengah lingkaran.',
    'D': 'Telunjuk tegak lurus, tiga jari lain bersentuhan dengan ibu jari membentuk lingkaran di pangkal.',
    'E': 'Empat jari ditekuk ke dalam menyentuh ibu jari yang ditekuk, membentuk kepalan longgar.',
    'F': 'Telunjuk dan ibu jari bersentuhan membentuk lingkaran (OK sign), tiga jari lain tegak.',
    'G': 'Telunjuk dan ibu jari sejajar mengarah ke samping, jari lain mengepal.',
    'H': 'Telunjuk dan jari tengah rapat mengarah ke samping horizontal, jari lain mengepal.',
    'I': 'Kelingking tegak lurus ke atas, jari lain mengepal, ibu jari menutup jari lain.',
    'K': 'Telunjuk tegak, jari tengah miring 45°, ibu jari menyentuh pangkal jari tengah.',
    'L': 'Telunjuk tegak dan ibu jari horizontal membentuk sudut siku-siku "L", jari lain mengepal.',
    'M': 'Ibu jari terselip di bawah tiga jari (telunjuk, tengah, manis) yang ditekuk ke bawah.',
    'N': 'Ibu jari terselip di bawah dua jari (telunjuk, tengah) yang ditekuk ke bawah.',
    'O': 'Semua jari melengkung membentuk lingkaran "O" bersama ibu jari.',
    'P': 'Seperti "K" tapi mengarah ke bawah — telunjuk dan jari tengah ke bawah, ibu jari di antaranya.',
    'Q': 'Telunjuk dan ibu jari sejajar mengarah ke bawah, jari lain mengepal.',
    'R': 'Telunjuk dan jari tengah bersilangan tegak, jari lain mengepal.',
    'S': 'Kepalan penuh dengan ibu jari menutup di depan buku jari.',
    'T': 'Ibu jari terselip di antara telunjuk dan jari tengah pada kepalan.',
    'U': 'Telunjuk dan jari tengah rapat tegak lurus, jari lain mengepal.',
    'V': 'Telunjuk dan jari tengah membentuk "V" terbuka, jari lain mengepal.',
    'W': 'Telunjuk, jari tengah, jari manis terbuka (tiga jari tegak), ibu jari dan kelingking bertemu.',
    'X': 'Telunjuk ditekuk membentuk kait, jari lain mengepal.',
    'Y': 'Ibu jari dan kelingking terbuka, tiga jari tengah mengepal (tanda "call me").',
  };

  String _referenceFor(String label, String mode) {
    final upper = label.toUpperCase();
    if (mode == 'sibi') {
      return _sibiAlphabetReference[upper] ?? '(referensi tidak tersedia — evaluasi berdasarkan bentuk umum huruf ini)';
    }
    if (mode == 'bisindo_alfabet') {
      return _bisindoAlphabetReference[upper] ?? '(referensi tidak tersedia)';
    }
    // bisindo_kata — deskripsi kata BISINDO umum
    return _bisindoWordReference[upper] ?? '(referensi kata tidak tersedia — evaluasi dari foto secara umum)';
  }

  static const Map<String, String> _bisindoWordReference = {
    'SAYA': 'Telunjuk tangan dominan menunjuk ke dada sendiri.',
    'MAAF': 'Telapak tangan dominan diusapkan melingkar di dada (area jantung).',
    'TERIMA_KASIH': 'Ujung jari tangan dominan menyentuh dagu lalu digerakkan ke depan menjauh dari wajah.',
    'TULI': 'Telunjuk menyentuh telinga, lalu menyentuh mulut (atau sebaliknya) — menandakan tidak dengar & tidak bicara lisan.',
    'DENGAR': 'Telunjuk dan ibu jari membuka-menutup di sisi telinga.',
    'RUMAH': 'Kedua tangan miring saling bertemu di atas membentuk atap, lalu ditarik turun membentuk dinding.',
  };

  static const _vocabularyHelperPrompt = '''
Kamu asisten yang menjelaskan kosakata Bahasa Indonesia kepada teman Tuli.
Gunakan kalimat sangat sederhana, pendek, dan jelas. Hindari istilah asing.
Jika katanya istilah teknis (hukum, keuangan, medis), beri analogi sehari-hari.

Format jawaban (wajib):
Arti: [1 kalimat singkat]
Contoh: [1 kalimat contoh penggunaan sehari-hari]

Jangan tambahkan kalimat lain di luar format itu.
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

  /// Contextual Empathy (bullet points) — multi-tip untuk orang dengar.
  /// Return list of 2-4 tips singkat yang bisa ditampilkan sebagai bullet di UI.
  Future<List<String>> getEmpathyTips(String sentence) async {
    if (sentence.trim().isEmpty) return const [];
    if (!_isLoaded || _model == null) return const [];

    final raw = await _infer(_empathyTipsPrompt, sentence);
    if (raw == null || raw.isEmpty) return const [];

    // Parse bullet lines: "- tip text"
    final tips = <String>[];
    for (final rawLine in raw.split('\n')) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;
      // Strip bullet markers (-, *, •, 1., 1))
      line = line.replaceFirst(
          RegExp(r'^[\-\*•]\s+|^\d+[\.\)]\s+'), '');
      if (line.isEmpty) continue;
      tips.add(line);
    }
    debugPrint('[GemmaService] empathyTips: ${tips.length} bullets');
    return tips.take(4).toList();
  }

  /// Gemma 4 Vision — Sign Coach. Evaluasi foto tangan pengguna dan berikan tips.
  ///
  /// [imagePath] — absolute path ke JPEG/PNG hasil CameraController.takePicture.
  /// [targetLabel] — huruf/kata yang seharusnya diperagakan (mis. "A", "TERIMA_KASIH").
  /// [detectedLabel] — hasil prediksi CNN (null jika tidak terdeteksi).
  /// [mode] — "sibi" | "bisindo_alfabet" | "bisindo_kata" untuk konteks prompt.
  /// [attemptCount] — percobaan ke-berapa untuk target yang sama (mulai dari 1).
  ///   Dipakai Gemma untuk menyesuaikan tone (makin banyak gagal → makin menyemangati).
  Future<String?> reviewSignImage({
    required String imagePath,
    required String targetLabel,
    String? detectedLabel,
    String mode = 'bisindo_alfabet',
    int attemptCount = 1,
  }) async {
    if (!_isLoaded || _model == null) return null;
    final file = File(imagePath);
    if (!await file.exists()) {
      debugPrint('[GemmaService] reviewSignImage: file not found $imagePath');
      return null;
    }

    final modeLabel = switch (mode) {
      'sibi' => 'SIBI (1 tangan)',
      'bisindo_kata' => 'BISINDO (kata/gerakan, 2 tangan)',
      _ => 'BISINDO (alfabet, 2 tangan)',
    };

    final isCorrect = detectedLabel != null &&
        detectedLabel.toUpperCase() == targetLabel.toUpperCase();
    final detectionLine = detectedLabel == null
        ? 'Hasil CNN: tangan belum terdeteksi dengan jelas.'
        : (isCorrect
            ? 'Hasil CNN: BENAR (terdeteksi "$detectedLabel", sesuai target).'
            : 'Hasil CNN: SALAH (terdeteksi "$detectedLabel", target seharusnya "$targetLabel").');

    final reference = _referenceFor(targetLabel, mode);

    String attemptLine;
    if (attemptCount <= 1) {
      attemptLine = 'Ini percobaan pertama.';
    } else if (attemptCount == 2) {
      attemptLine = 'Ini percobaan ke-2. Tetap rileks.';
    } else {
      attemptLine = 'Ini percobaan ke-$attemptCount. Pengguna sudah mencoba berulang — beri dorongan positif.';
    }

    final userMessage = '''
Mode: $modeLabel
Target: $targetLabel
$attemptLine

Referensi bentuk "$targetLabel" yang BENAR:
$reference

$detectionLine

Bandingkan foto tangan pengguna dengan referensi di atas. Beri evaluasi singkat (maks. 2 kalimat) dalam Bahasa Indonesia.
''';

    try {
      _model!.reset();
      debugPrint('[GemmaService] reviewSignImage: target=$targetLabel detected=$detectedLabel img=$imagePath');

      final response = await _model!.complete(
        [
          ChatMessage(role: 'system', content: _visionCoachSystemPrompt),
          ChatMessage(
            role: 'user',
            content: userMessage,
            images: [file.absolute.path],
          ),
        ],
        maxTokens: 120,
        temperature: 0.4,
        stopSequences: ['\n\n\n'],
      );

      if (response.success && response.text.isNotEmpty) {
        final cleaned = _cleanResponse(response.text);
        debugPrint('[GemmaService] reviewSignImage OK: ${cleaned.length} chars, '
            '${response.decodeTps.toStringAsFixed(1)} tok/s, '
            '${response.totalTimeMs.toStringAsFixed(0)}ms');
        return cleaned;
      }
      debugPrint('[GemmaService] reviewSignImage failed: ${response.error}');
      return null;
    } catch (e) {
      debugPrint('[GemmaService] reviewSignImage exception: $e');
      return null;
    }
  }

  /// Deaf Vocabulary Helper — jelaskan kata/frasa dengan bahasa sederhana.
  /// Return VocabularyExplanation(meaning, example) atau null jika gagal.
  Future<VocabularyExplanation?> explainVocabulary(String word) async {
    final q = word.trim();
    if (q.isEmpty) return null;
    if (!_isLoaded || _model == null) return null;

    final raw = await _infer(_vocabularyHelperPrompt, q);
    if (raw == null || raw.isEmpty) return null;

    String? meaning;
    String? example;
    for (final rawLine in raw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final lower = line.toLowerCase();
      if (lower.startsWith('arti:')) {
        meaning = line.substring(line.indexOf(':') + 1).trim();
      } else if (lower.startsWith('contoh:')) {
        example = line.substring(line.indexOf(':') + 1).trim();
      }
    }

    // Fallback: kalau format tidak pas, taruh semuanya ke meaning.
    if (meaning == null || meaning.isEmpty) {
      meaning = raw.trim();
    }

    return VocabularyExplanation(
      word: q,
      meaning: meaning,
      example: example,
    );
  }

  Future<void> dispose() async {
    await _model?.dispose();
    _model = null;
    _isLoaded = false;
  }
}

/// Hasil penjelasan kosakata untuk fitur Deaf Vocabulary Helper.
class VocabularyExplanation {
  final String word;
  final String meaning;
  final String? example;

  const VocabularyExplanation({
    required this.word,
    required this.meaning,
    this.example,
  });
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
