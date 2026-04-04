import 'dart:async';
import 'dart:math';
import 'dart:ui';

/// Stub service that simulates MediaPipe gesture recognition.
/// Returns mock gloss words via a stream.
class GestureService {
  static final GestureService _instance = GestureService._internal();
  factory GestureService() => _instance;
  GestureService._internal();

  final _glossController = StreamController<List<String>>.broadcast();
  Timer? _timer;
  final List<String> _currentGloss = [];
  int _currentIndex = 0;
  bool _isCapturing = false;

  static const List<List<String>> _sequences = [
    ['NAMA', 'SAYA', 'APA'],
    ['TERIMA', 'KASIH'],
    ['TOLONG', 'BANTU'],
    ['SAYA', 'SENANG'],
    ['HALO', 'APA', 'KABAR'],
  ];

  Stream<List<String>> get glossStream => _glossController.stream;
  bool get isCapturing => _isCapturing;

  void startGestureCapture() {
    if (_isCapturing) return;
    _isCapturing = true;
    _currentGloss.clear();
    _currentIndex = 0;

    final random = Random();
    final selectedSequence = _sequences[random.nextInt(_sequences.length)];

    _timer = Timer.periodic(Duration(milliseconds: 1500), (timer) {
      if (_currentIndex < selectedSequence.length) {
        _currentGloss.add(selectedSequence[_currentIndex]);
        _glossController.add(List.from(_currentGloss));
        _currentIndex++;
      } else {
        // Restart with a new sequence after a pause
        _currentGloss.clear();
        _currentIndex = 0;
        final newSequence = _sequences[random.nextInt(_sequences.length)];
        _currentGloss.add(newSequence[_currentIndex]);
        _glossController.add(List.from(_currentGloss));
        _currentIndex++;
      }
    });
  }

  void stopGestureCapture() {
    _isCapturing = false;
    _timer?.cancel();
    _timer = null;
  }

  List<String> getCurrentGloss() => List.from(_currentGloss);

  /// Returns mock hand landmark positions for CustomPainter overlay.
  /// 21 landmarks representing hand joints.
  List<Offset> getMockHandLandmarks(double width, double height) {
    final random = Random();
    final centerX = width * 0.5;
    final centerY = height * 0.45;
    final spread = width * 0.15;

    // Generate 21 landmarks in a rough hand shape
    return List.generate(21, (index) {
      final angle = (index / 21) * 2 * pi;
      final radius = spread * (0.5 + random.nextDouble() * 0.5);
      return Offset(
        centerX + radius * cos(angle) + (random.nextDouble() - 0.5) * 20,
        centerY + radius * sin(angle) + (random.nextDouble() - 0.5) * 20,
      );
    });
  }

  void dispose() {
    _timer?.cancel();
    _glossController.close();
  }
}
