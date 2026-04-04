import 'dart:typed_data';

/// Stub service that simulates Whisper STT (Speech-to-Text).
/// Returns mock transcription strings.
class SttService {
  static final SttService _instance = SttService._internal();
  factory SttService() => _instance;
  SttService._internal();

  static const List<String> _mockTranscriptions = [
    'Halo apa kabar nama saya Budi, saya sedang mencari jalan menuju stasiun terdekat dari sini',
    'Selamat pagi, apakah Anda bisa membantu saya menemukan toko buku terdekat',
    'Permisi, saya ingin bertanya tentang jadwal kereta api sore ini',
    'Terima kasih banyak atas bantuan Anda, saya sangat menghargainya',
    'Maaf mengganggu, bisakah Anda menunjukkan arah ke rumah sakit',
  ];

  int _currentIndex = 0;

  /// Simulates Whisper STT transcription.
  /// Waits 600ms to simulate inference time.
  /// [audioData] is ignored in the stub.
  Future<String> transcribe(Uint8List? audioData) async {
    await Future.delayed(Duration(milliseconds: 600));
    final transcription = _mockTranscriptions[_currentIndex];
    _currentIndex = (_currentIndex + 1) % _mockTranscriptions.length;
    return transcription;
  }
}
