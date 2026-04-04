/// Stub service that simulates Gemma LLM inference.
/// Takes gloss tokens and returns refined Bahasa Indonesia sentences.
class GemmaService {
  static final GemmaService _instance = GemmaService._internal();
  factory GemmaService() => _instance;
  GemmaService._internal();

  static const Map<String, String> _glossMap = {
    'NAMA_SAYA_APA': 'Siapa nama kamu?',
    'TERIMA_KASIH': 'Terima kasih banyak!',
    'TOLONG_BANTU': 'Tolong bantu saya.',
    'SAYA_SENANG': 'Saya senang bertemu denganmu!',
    'HALO_APA_KABAR': 'Halo, apa kabar?',
    'NAMA': 'Nama...',
    'NAMA_SAYA': 'Nama saya...',
    'HALO': 'Halo!',
    'HALO_APA': 'Halo, apa...',
    'TERIMA': 'Terima...',
    'TOLONG': 'Tolong...',
    'SAYA': 'Saya...',
  };

  static const String _defaultResponse = 'Maaf, saya tidak mengerti. Bisa diulang?';

  /// Simulates Gemma inference to refine gloss tokens into a natural sentence.
  /// Waits 800ms to simulate model inference time.
  Future<String> refineGloss(List<String> gloss) async {
    await Future.delayed(Duration(milliseconds: 800));

    if (gloss.isEmpty) return '';

    final key = gloss.join('_');
    return _glossMap[key] ?? _defaultResponse;
  }

  /// Simulates Gemma inference to summarize raw speech text.
  /// Waits 1200ms to simulate model inference time.
  Future<String> summarizeSpeech(String rawText) async {
    await Future.delayed(Duration(milliseconds: 1200));

    // Simple mock summarization
    if (rawText.toLowerCase().contains('stasiun')) {
      return 'Halo, Budi ingin tahu jalan ke stasiun.';
    }
    if (rawText.toLowerCase().contains('rumah sakit')) {
      return 'Dia sedang mencari rumah sakit terdekat.';
    }
    if (rawText.toLowerCase().contains('terima kasih')) {
      return 'Dia mengucapkan terima kasih.';
    }

    // Default: take first 10 words
    final words = rawText.split(' ');
    if (words.length > 10) {
      return '${words.take(10).join(' ')}...';
    }
    return rawText;
  }
}
