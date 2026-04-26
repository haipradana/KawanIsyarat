import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
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

  // Vision prompt dikecilkan — setiap token prompt = tambah KV cache RAM.
  // Pixel 6a (6GB) OOM kalau prompt terlalu panjang + gambar besar.
  static const _visionCoachSystemPrompt = '''
Kamu pelatih isyarat BISINDO/SIBI. Beri umpan balik singkat (maks 2 kalimat) dalam Bahasa Indonesia.
BENAR: apresiasi + 1 tips kecil. SALAH: sebutkan 1 hal yang meleset + cara perbaiki.
Percobaan >2x gagal: semangati. Langsung saran praktis, jangan teori.
''';

  /// Text-only coach prompt — dipakai kalau vision dinonaktifkan (device RAM rendah).
  /// Gemma bicara LANGSUNG ke pengguna sebagai pelatih. JANGAN mention CNN/model/deteksi.
  static const _textCoachSystemPrompt = '''
Kamu pelatih isyarat BISINDO/SIBI yang ramah. Kamu berbicara LANGSUNG kepada pengguna.
JANGAN pernah menyebut kata: "CNN", "model", "AI", "deteksi", "output", "input". Pengguna tidak tahu istilah itu.
Pakai kata ganti "kamu" — seolah kamu melihat pengguna membuat isyarat.

Kalau status BENAR → puji pengguna (contoh: "Bagus, isyarat kamu sudah tepat!") + 1 tips untuk lebih mantap.
Kalau status SALAH → tunjuk 1 perbedaan bentuk yang perlu diperbaiki + cara memperbaikinya (contoh: "Tanganmu masih membentuk huruf E. Untuk A, kepalkan tangan lalu dekatkan ibu jari kedua tangan sampai menempel").

Maks 2 kalimat. Bahasa Indonesia santai. Jangan pakai bullet, markdown, atau bold.
''';

  /// Vision dinonaktifkan default karena memakan ~300MB extra RAM untuk
  /// vision encoder weights + prefill peak. Pixel 6a sering crash dengan
  /// system-wide memory pressure event saat path ini dipakai.
  /// Bisa di-toggle via setter kalau user ingin coba.
  static bool useVisionCoach = false;

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
Kamu menjelaskan kata Bahasa Indonesia untuk teman Tuli.
ATURAN PENTING:
- Gunakan kata-kata yang SANGAT SEDERHANA, seperti bicara ke anak SD-SMP.
- Kalimat PENDEK, maksimal 10 kata per kalimat.
- Jangan pakai kata sulit atau istilah rumit.
- Contoh harus situasi sehari-hari yang mudah dibayangkan.
Format jawaban:
Arti: [penjelasan singkat dan mudah]
Contoh: [1 kalimat pendek, situasi sehari-hari]
Jangan tambah baris lain.
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
      // - n_ctx: 512 → cukup untuk vision di image 168×168 (≈144 image tokens)
      //   + prompt pendek + response. n_ctx tinggi tidak membuat lebih akurat,
      //   hanya tambah KV cache RAM & prefill peak.
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

  /// Versi _infer lebih ringan untuk vocab helper.
  /// maxTokens dikurangi, tapi stop sequences tidak pakai \n\n
  /// supaya baris Contoh tetap bisa digenerate.
  Future<String?> _inferShort(String systemPrompt, String userMessage) async {
    if (!_isLoaded || _model == null) return null;
    try {
      _model!.reset();
      final response = await _model!.complete(
        [
          ChatMessage(role: 'system', content: systemPrompt),
          ChatMessage(role: 'user', content: userMessage),
        ],
        maxTokens: 80,
        temperature: 0.3,
        stopSequences: ['\n\n\n'], // toleran — tidak potong Contoh

      );
      if (response.success) {
        final cleaned = _cleanResponse(response.text);
        debugPrint('[GemmaService] Short inference OK: ${cleaned.length} chars, '
            '${response.decodeTps.toStringAsFixed(1)} tok/s, '
            '${response.totalTimeMs.toStringAsFixed(0)}ms');
        return cleaned;
      }
      return null;
    } catch (e) {
      debugPrint('[GemmaService] Short inference exception: $e');
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

  // ---- Image crop+resize helper ----

  /// Crop gambar ke bounding box tangan (+ padding), resize ke maxDim, encode JPEG.
  /// KRUSIAL untuk menghindari OOM pada Gemma 4 vision encoder.
  ///
  /// Gemma 4 (SigLIP-base) tokenize gambar jadi ~16×16 = 256 patch tokens terlepas
  /// dari input resolution. Jadi resize ke 224×224 cukup — tidak ada gain untuk
  /// resolusi lebih tinggi, malah tambah memory vision encoder.
  ///
  /// Dipakai `image` package (pure Dart) untuk:
  ///   decode JPEG → crop → resize → encode JPEG.
  /// Lebih cepat + predictable memory dibanding Canvas GPU roundtrip + PNG encode.
  ///
  /// [handBbox] — normalized bounding box [0,1] dari landmark detector.
  ///   Jika null, fallback ke center-crop 70% dengan sedikit bias atas (tangan biasanya di atas tengah).
  /// [padding] — persentase padding sekeliling bbox (0.25 = 25% setiap sisi).
  static Future<String> _cropAndResizeForVision(
    String sourcePath, {
    Rect? handBbox,
    int maxDim = 224,
    double padding = 0.25,
    int jpegQuality = 82,
  }) async {
    final sw = DateTime.now();
    final bytes = await File(sourcePath).readAsBytes();

    // Decode via image package — lossless dari JPEG → RGBA in-memory
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      debugPrint('[GemmaService] decodeImage null, using original');
      return sourcePath;
    }
    final imgW = decoded.width;
    final imgH = decoded.height;

    // Hitung crop region dalam pixel
    late int cropX, cropY, cropW, cropH;

    if (handBbox != null && handBbox.width > 0.01 && handBbox.height > 0.01) {
      // Expand bbox ke square supaya resize 224×224 tidak stretching
      final bboxCx = (handBbox.left + handBbox.right) / 2.0;
      final bboxCy = (handBbox.top + handBbox.bottom) / 2.0;
      final bboxSide =
          (handBbox.width > handBbox.height ? handBbox.width : handBbox.height) *
              (1.0 + padding * 2);

      final halfSide = bboxSide / 2.0;
      final leftN = (bboxCx - halfSide).clamp(0.0, 1.0);
      final topN = (bboxCy - halfSide).clamp(0.0, 1.0);
      final rightN = (bboxCx + halfSide).clamp(0.0, 1.0);
      final bottomN = (bboxCy + halfSide).clamp(0.0, 1.0);

      cropX = (leftN * imgW).round().clamp(0, imgW - 1);
      cropY = (topN * imgH).round().clamp(0, imgH - 1);
      cropW = ((rightN - leftN) * imgW).round().clamp(1, imgW - cropX);
      cropH = ((bottomN - topN) * imgH).round().clamp(1, imgH - cropY);

      debugPrint('[GemmaService] Crop (square) to hand bbox: '
          '${cropX},${cropY} ${cropW}x$cropH px '
          '(bbox ${handBbox.width.toStringAsFixed(2)}x${handBbox.height.toStringAsFixed(2)})');
    } else {
      // Fallback: square center-crop 70%, bias ke atas 10% (tangan biasanya upper)
      final side = ((imgW < imgH ? imgW : imgH) * 0.70).round();
      cropW = side;
      cropH = side;
      cropX = (imgW - side) ~/ 2;
      cropY = ((imgH - side) ~/ 2 - side * 0.1).round().clamp(0, imgH - side);
      debugPrint('[GemmaService] No hand bbox, square center-crop: ${cropW}x$cropH px');
    }

    // Crop → resize → JPEG (pure Dart, 1 pass)
    final cropped = img.copyCrop(decoded,
        x: cropX, y: cropY, width: cropW, height: cropH);
    final resized = img.copyResize(cropped,
        width: maxDim,
        height: maxDim,
        interpolation: img.Interpolation.linear);
    final jpegBytes = img.encodeJpg(resized, quality: jpegQuality);

    final dir = File(sourcePath).parent;
    final outPath =
        '${dir.path}/sign_v_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(outPath).writeAsBytes(jpegBytes);

    final elapsed = DateTime.now().difference(sw).inMilliseconds;
    debugPrint('[GemmaService] vision img: ${bytes.length ~/ 1024}KB → '
        '${jpegBytes.length ~/ 1024}KB @ ${maxDim}x$maxDim JPEG q$jpegQuality '
        '(${elapsed}ms)');

    return outPath;
  }

  /// Hapus file sign_v_*.jpg lama dari temp dir untuk mencegah akumulasi.
  /// Dipanggil sebelum crop baru.
  static Future<void> _cleanStaleVisionTemps(Directory tempDir) async {
    try {
      final entries = tempDir.listSync();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final e in entries) {
        if (e is File) {
          final name = e.path.split('/').last;
          if ((name.startsWith('sign_v_') || name.startsWith('sign_cropped_')) &&
              (name.endsWith('.jpg') || name.endsWith('.png'))) {
            final stat = e.statSync();
            // Hapus yang lebih dari 60 detik — aman karena inference ≤ 30s
            if (now - stat.modified.millisecondsSinceEpoch > 60000) {
              try { e.deleteSync(); } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
  }

  /// Gemma 4 Vision — Sign Coach. Evaluasi foto tangan pengguna dan berikan tips.
  ///
  /// [imagePath] — absolute path ke JPEG/PNG hasil CameraController.takePicture.
  /// [targetLabel] — huruf/kata yang seharusnya diperagakan (mis. "A", "TERIMA_KASIH").
  /// [detectedLabel] — hasil prediksi CNN (null jika tidak terdeteksi).
  /// [mode] — "sibi" | "bisindo_alfabet" | "bisindo_kata" untuk konteks prompt.
  /// [attemptCount] — percobaan ke-berapa untuk target yang sama (mulai dari 1).
  ///   Dipakai Gemma untuk menyesuaikan tone (makin banyak gagal → makin menyemangati).
  /// [handBbox] — normalized bounding box [0,1] dari hand landmark detector.
  ///   Jika tersedia, gambar akan di-crop ke area tangan saja sebelum dikirim ke Gemma.
  Future<String?> reviewSignImage({
    required String imagePath,
    required String targetLabel,
    String? detectedLabel,
    String mode = 'bisindo_alfabet',
    int attemptCount = 1,
    Rect? handBbox,
  }) async {
    if (!_isLoaded || _model == null) return null;

    // Default: text-only coach (vision nonaktif → hindari OOM di device low-RAM).
    // Kualitas tetap bagus karena CNN + referensi bentuk di-inject ke prompt.
    if (!useVisionCoach) {
      return _reviewSignTextOnly(
        targetLabel: targetLabel,
        detectedLabel: detectedLabel,
        mode: mode,
        attemptCount: attemptCount,
      );
    }

    final file = File(imagePath);
    if (!await file.exists()) {
      debugPrint('[GemmaService] reviewSignImage: file not found $imagePath');
      return null;
    }

    // ── Crop ke hand bbox + resize + JPEG encode SEBELUM kirim ke vision encoder ──
    // Tanpa ini, Pixel 6a (6GB) OOM karena vision encoder allocate 300MB+
    // untuk patch embeddings dari gambar full-res.
    // Bersihkan file crop lama dulu (mencegah akumulasi dari percobaan berulang).
    unawaited(_cleanStaleVisionTemps(File(imagePath).parent));
    String visionImagePath;
    try {
      // 168 = 12×14 (multiple of SigLIP patch=14) → 144 image tokens (vs 256 @ 224).
      // Hemat ~45% working RAM di attention + prefill, kritis di Pixel 6a.
      visionImagePath = await _cropAndResizeForVision(
        imagePath,
        handBbox: handBbox,
        maxDim: 168,
        jpegQuality: 80,
      );
    } catch (e) {
      debugPrint('[GemmaService] crop+resize failed, using original: $e');
      visionImagePath = imagePath;
    }

    final isCorrect = detectedLabel != null &&
        detectedLabel.toUpperCase() == targetLabel.toUpperCase();
    final cnnResult = detectedLabel == null
        ? 'CNN: tidak terdeteksi'
        : (isCorrect
            ? 'CNN: BENAR ($detectedLabel)'
            : 'CNN: SALAH ($detectedLabel, target $targetLabel)');

    final reference = _referenceFor(targetLabel, mode);
    final attemptNote = attemptCount > 2 ? ' Percobaan ke-$attemptCount, semangati.' : '';

    // User message dikecilkan drastis — setiap karakter = token = RAM.
    final userMessage =
        'Target: $targetLabel. Referensi: $reference. $cnnResult.$attemptNote'
        ' Evaluasi foto, maks 2 kalimat.';

    try {
      _model!.reset();
      debugPrint('[GemmaService] reviewSignImage: target=$targetLabel detected=$detectedLabel '
          'bbox=${handBbox != null ? "${handBbox.left.toStringAsFixed(2)},${handBbox.top.toStringAsFixed(2)}-${handBbox.right.toStringAsFixed(2)},${handBbox.bottom.toStringAsFixed(2)}" : "none"} '
          'img=$visionImagePath');

      final response = await _model!.complete(
        [
          ChatMessage(role: 'system', content: _visionCoachSystemPrompt),
          ChatMessage(
            role: 'user',
            content: userMessage,
            images: [visionImagePath],
          ),
        ],
        maxTokens: 60, // 2 kalimat = ~40 token, 60 cukup dengan margin
        temperature: 0.3,
        stopSequences: ['\n\n'],
      );

      // Cleanup temp file
      if (visionImagePath != imagePath) {
        try { File(visionImagePath).deleteSync(); } catch (_) {}
      }

      if (response.success && response.text.isNotEmpty) {
        final cleaned = _cleanResponse(response.text);
        debugPrint('[GemmaService] reviewSignImage OK: ${cleaned.length} chars, '
            '${response.decodeTps.toStringAsFixed(1)} tok/s, '
            '${response.totalTimeMs.toStringAsFixed(0)}ms, '
            '${response.ramUsageMb.toStringAsFixed(0)}MB RAM');
        return cleaned;
      }
      debugPrint('[GemmaService] reviewSignImage failed: ${response.error}');
      return null;
    } catch (e) {
      debugPrint('[GemmaService] reviewSignImage exception: $e');
      // Cleanup on error too
      if (visionImagePath != imagePath) {
        try { File(visionImagePath).deleteSync(); } catch (_) {}
      }
      return null;
    }
  }

  /// Text-only coach — alternatif `reviewSignImage` tanpa vision encoder.
  /// Pakai hasil CNN + referensi bentuk target & bentuk yang terdeteksi
  /// supaya Gemma bisa kontras dua deskripsi tanpa lihat foto.
  /// RAM stabil (~1.9GB), tidak OOM di Pixel 6a.
  Future<String?> _reviewSignTextOnly({
    required String targetLabel,
    String? detectedLabel,
    required String mode,
    required int attemptCount,
  }) async {
    if (!_isLoaded || _model == null) return null;

    final isCorrect = detectedLabel != null &&
        detectedLabel.toUpperCase() == targetLabel.toUpperCase();
    final targetRef = _referenceFor(targetLabel, mode);

    String statusSection;
    if (detectedLabel == null) {
      statusSection =
          'Status: tangan pengguna belum terlihat jelas. Minta dia memposisikan tangan lebih ke tengah frame.';
    } else if (isCorrect) {
      statusSection = 'Status: BENAR — isyarat pengguna sudah sesuai target "$targetLabel".';
    } else {
      final detectedRef = _referenceFor(detectedLabel, mode);
      statusSection =
          'Status: SALAH — pengguna membuat bentuk yang lebih mirip huruf "$detectedLabel" ($detectedRef), '
          'padahal target huruf "$targetLabel" ($targetRef). '
          'Bandingkan dua deskripsi itu, tunjukkan 1 perbedaan kunci yang harus diperbaiki pengguna.';
    }

    final attemptNote = attemptCount > 2
        ? ' Ini percobaan ke-$attemptCount — tambahkan kalimat menyemangati.'
        : '';

    // Pesan ke Gemma: hanya info status + referensi target, tidak bocor istilah internal.
    final userMessage =
        'Pengguna sedang belajar huruf "$targetLabel".\n'
        'Referensi bentuk "$targetLabel" yang benar: $targetRef\n\n'
        '$statusSection$attemptNote\n\n'
        'Balas dengan 1-2 kalimat langsung ke pengguna.';

    try {
      _model!.reset();
      debugPrint('[GemmaService] reviewSignTextOnly: target=$targetLabel '
          'detected=$detectedLabel attempt=$attemptCount');

      final response = await _model!.complete(
        [
          ChatMessage(role: 'system', content: _textCoachSystemPrompt),
          ChatMessage(role: 'user', content: userMessage),
        ],
        maxTokens: 80,
        temperature: 0.35,
        stopSequences: ['\n\n'],
      );

      if (response.success && response.text.isNotEmpty) {
        final cleaned = _cleanResponse(response.text);
        debugPrint('[GemmaService] reviewSignTextOnly OK: ${cleaned.length} chars, '
            '${response.decodeTps.toStringAsFixed(1)} tok/s, '
            '${response.totalTimeMs.toStringAsFixed(0)}ms');
        return cleaned;
      }
      debugPrint('[GemmaService] reviewSignTextOnly failed: ${response.error}');
      return null;
    } catch (e) {
      debugPrint('[GemmaService] reviewSignTextOnly exception: $e');
      return null;
    }
  }

  /// Deaf Vocabulary Helper — jelaskan kata/frasa dengan bahasa sederhana.
  /// Return VocabularyExplanation(meaning, example) atau null jika gagal.
  Future<VocabularyExplanation?> explainVocabulary(String word) async {
    final q = word.trim();
    if (q.isEmpty) return null;
    if (!_isLoaded || _model == null) return null;

    // _inferShort: maxTokens dikurangi, stop lebih awal → ~30% lebih cepat
    final raw = await _inferShort(_vocabularyHelperPrompt, q);
    if (raw == null || raw.isEmpty) return null;

    String? meaning;
    String? example;
    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.startsWith('arti:')) {
        meaning = line.substring(line.indexOf(':') + 1).trim();
      } else if (lower.startsWith('contoh:')) {
        // Strip kutip awal/akhir kalau ada
        var ex = line.substring(line.indexOf(':') + 1).trim();
        ex = ex.replaceAll(RegExp(r'^["\u201c\u201d]+|["\u201c\u201d]+$'), '');
        example = ex;
      }
    }

    // Fallback toleran: model kadang tidak output prefix "Arti:" / "Contoh:"
    if (meaning == null || meaning.isEmpty) {
      if (lines.length >= 2) {
        // Baris pertama = arti, baris kedua = contoh
        meaning = lines[0];
        example ??= lines[1];
      } else {
        meaning = raw.trim();
      }
    }
    // Kalau example masih null dan ada baris ke-2 yang belum dipakai
    if (example == null && lines.length >= 2 && meaning == lines[0]) {
      example = lines[1];
    }

    return VocabularyExplanation(
      word: q,
      meaning: meaning,
      example: example,
    );
  }

  // ─── Artikulasi Feedback ──────────────────────────────────────────────────

  static const _artikulasiFeedbackPrompt = '''
Kamu membantu orang belajar mengucapkan kata Bahasa Indonesia dengan jelas.
Berikan feedback singkat (1-2 kalimat) untuk membantu mereka memperbaiki pengucapan.
Bahasa Indonesia, santai, tidak menghakimi.
''';

  /// Berikan feedback pengucapan: target kata vs yang terdeteksi STT.
  /// Kalau [detected] == [target] → pujian singkat.
  /// Kalau berbeda → tips perbaikan spesifik.
  Future<String> feedbackArtikulasi(String target, String detected) async {
    final isCorrect = detected.trim().toLowerCase() == target.trim().toLowerCase();
    if (isCorrect) {
      return 'Pengucapanmu sudah tepat dan jelas! Lanjutkan ke kata berikutnya.';
    }
    final prompt = 'Target: "$target". Yang terdengar: "$detected". '
        'Berikan 1-2 kalimat tips memperbaiki pengucapan kata "$target".';
    final result = await _inferShort(_artikulasiFeedbackPrompt, prompt);
    if (result == null || result.trim().isEmpty) {
      return 'Kata yang terdengar adalah "$detected". Coba ucapkan lebih pelan, '
          'perhatikan setiap suku kata pada "$target".';
    }
    return result.trim();
  }

  // ─── Idiom Explanation ────────────────────────────────────────────────────

  static const _idiomPrompt = '''
Kamu membantu teman Tuli memahami idiom dan ungkapan Bahasa Indonesia.
ATURAN PENTING:
- Jelaskan dengan kata-kata SANGAT SEDERHANA, seperti bicara ke anak SD.
- Jangan pakai kata sulit. Gunakan bahasa sehari-hari.
- Contoh harus situasi nyata yang mudah dipahami.
Format jawaban:
Arti: [1 kalimat pendek, makna sebenarnya, bukan makna harfiah]
Contoh: [1 kalimat pendek, percakapan sehari-hari]
Jangan tambah baris lain.
''';

  /// Jelaskan idiom/ungkapan untuk teman Tuli.
  Future<({String arti, String contoh})> explainIdiom(String idiom) async {
    final result = await _inferShort(_idiomPrompt,
        'Jelaskan idiom: "$idiom"');
    final raw = result ?? '';
    String arti = '';
    String contoh = '';
    for (final line in raw.split('\n').where((l) => l.isNotEmpty)) {
      final lower = line.toLowerCase();
      if (lower.startsWith('arti:')) {
        arti = line.substring(line.indexOf(':') + 1).trim();
      } else if (lower.startsWith('contoh:')) {
        contoh = line.substring(line.indexOf(':') + 1).trim();
      }
    }
    if (arti.isEmpty) arti = raw.trim();
    return (arti: arti, contoh: contoh);
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
