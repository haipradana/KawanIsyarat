import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../app/constants.dart';
import '../../../core/services/sibi_alphabet_service.dart';
import '../../../core/services/bisindo_alphabet_service.dart';

/// Alphabet practice screen — MediaPipe + Dense classifier.
///
/// Mendukung dua sistem alfabet:
/// - **SIBI** (1 tangan, 24 kelas A-Y skip J & Z) — sibi_alphabet_model_f32.tflite
/// - **BISINDO** (2 tangan, 22 kelas A-V) — bisindo_alphabet_model_f32.tflite
///
/// Pipeline: imageStream → hand_landmarker → Boháček normalization →
///           Dense TFLite → letter
enum AlphabetMode { sibi, bisindo }

class AlphabetPracticeScreen extends StatefulWidget {
  final String targetLetter;
  final AlphabetMode mode;

  const AlphabetPracticeScreen({
    super.key,
    required this.targetLetter,
    this.mode = AlphabetMode.sibi,
  });

  @override
  State<AlphabetPracticeScreen> createState() => _AlphabetPracticeScreenState();
}

/// Lightweight result wrapper so screen logic doesn't care about source service.
class _AbcDetection {
  final String letter;
  final double confidence;
  const _AbcDetection(this.letter, this.confidence);
}

enum _Phase { preparing, countdown, capturing, result }

class _AlphabetPracticeScreenState extends State<AlphabetPracticeScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  final SibiAlphabetService _sibi = SibiAlphabetService();
  final BisindoAlphabetService _bisindo = BisindoAlphabetService();

  bool _isInitialized = false;
  String? _error;
  bool _disposed = false;

  _Phase _phase = _Phase.preparing;
  _AbcDetection? _liveResult;   // deteksi realtime dari stream
  _AbcDetection? _lastResult;   // difreeze saat capture
  final Queue<_AbcDetection> _recentPredictions = Queue<_AbcDetection>();
  bool _isCorrect = false;
  int _correctCount = 0;
  int _totalCount = 0;

  int _sensorOrientation = 90;
  bool _isFrontCamera = true;
  bool _isProcessingFrame = false;    // throttle stream
  int _missedFrames = 0;

  late AnimationController _countdownController;
  Timer? _phaseTimer;

  static const _countdownDuration = Duration(milliseconds: 2500);
  static const _resultDuration = Duration(milliseconds: 2000);
  static const _maxPredictionWindow = 12;
  static const _minStableVotes = 4;

  @override
  void initState() {
    super.initState();
    _countdownController = AnimationController(
      vsync: this,
      duration: _countdownDuration,
    );
    _init();
  }

  Future<void> _init() async {
    try {
      final supportedLetters = widget.mode == AlphabetMode.sibi
          ? SibiAlphabetService.supportedLetters
          : BisindoAlphabetService.supportedLetters;
      if (!supportedLetters.contains(widget.targetLetter)) {
        setState(() {
          _error =
              'Huruf "${widget.targetLetter}" belum didukung model $_modeLabel saat ini.';
        });
        return;
      }

      final status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() => _error = 'Izin kamera diperlukan untuk fitur ini');
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'Tidak ada kamera tersedia');
        return;
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _sensorOrientation = camera.sensorOrientation;
      _isFrontCamera = camera.lensDirection == CameraLensDirection.front;

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420, // YUV diperlukan hand_landmarker
      );

      await _cameraController!.initialize();

      // Load model sesuai mode
      if (widget.mode == AlphabetMode.sibi) {
        await _sibi.initialize();
      } else {
        await _bisindo.initialize();
      }

      // Mulai stream untuk deteksi realtime
      await _cameraController!.startImageStream(_onCameraFrame);

      if (mounted && !_disposed) {
        setState(() {
          _isInitialized = true;
          _phase = _Phase.countdown;
        });
        _startCountdown();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Gagal memulai: ${e.toString()}');
      }
    }
  }

  // ─── Stream frame handler ──────────────────────────────────────────────────

  void _onCameraFrame(CameraImage frame) {
    // Skip jika sedang processing atau di fase result
    if (_isProcessingFrame || _phase == _Phase.result || _disposed) return;
    _isProcessingFrame = true;

    try {
      _AbcDetection? result;
      if (widget.mode == AlphabetMode.sibi) {
        final r = _sibi.detectFromCameraImage(
          frame,
          _sensorOrientation,
          _isFrontCamera,
        );
        if (r != null) result = _AbcDetection(r.letter, r.confidence);
      } else {
        final r = _bisindo.detectFromCameraImage(
          frame,
          _sensorOrientation,
          _isFrontCamera,
        );
        if (r != null) result = _AbcDetection(r.letter, r.confidence);
      }
      final smoothed = _pushPrediction(result);
      if (mounted && !_disposed) {
        setState(() => _liveResult = smoothed);
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  String get _modeLabel => widget.mode == AlphabetMode.sibi ? 'SIBI' : 'BISINDO';
  String get _modeHint => widget.mode == AlphabetMode.sibi
      ? '1 tangan'
      : '2 tangan';

  // ─── Phase management ──────────────────────────────────────────────────────

  void _startCountdown() {
    if (_disposed) return;
    _recentPredictions.clear();
    _missedFrames = 0;
    _liveResult = null;
    _countdownController.reset();
    _countdownController.forward();

    _phaseTimer?.cancel();
    _phaseTimer = Timer(_countdownDuration, () {
      if (!_disposed && mounted) _capture();
    });
  }

  void _capture() {
    if (_disposed || !mounted) return;

    setState(() {
      _phase = _Phase.capturing;
    });

    // Freeze deteksi saat ini — brief pause untuk UX
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_disposed || !mounted) return;
      _showResult(
        _resolveStablePrediction(requireConsensus: true) ??
            _resolveStablePrediction(requireConsensus: false),
      );
    });
  }

  void _showResult(_AbcDetection? result) {
    if (_disposed || !mounted) return;

    _totalCount++;
    final correct = result != null && result.letter == widget.targetLetter;
    if (correct) _correctCount++;

    setState(() {
      _phase = _Phase.result;
      _lastResult = result;
      _isCorrect = correct;
    });

    // Auto-retry setelah delay
    _phaseTimer?.cancel();
    _phaseTimer = Timer(_resultDuration, () {
      if (!_disposed && mounted) {
        setState(() {
          _phase = _Phase.countdown;
          _liveResult = null;
        });
        _startCountdown();
      }
    });
  }

  _AbcDetection? _pushPrediction(_AbcDetection? result) {
    if (result == null) {
      _missedFrames++;
      if (_missedFrames >= 3) {
        _recentPredictions.clear();
        return null;
      }
      return _resolveStablePrediction(requireConsensus: false);
    }

    _missedFrames = 0;
    _recentPredictions.addLast(result);
    while (_recentPredictions.length > _maxPredictionWindow) {
      _recentPredictions.removeFirst();
    }
    return _resolveStablePrediction(requireConsensus: false);
  }

  _AbcDetection? _resolveStablePrediction({required bool requireConsensus}) {
    if (_recentPredictions.isEmpty) return null;

    final grouped = <String, List<double>>{};
    for (final prediction in _recentPredictions) {
      grouped.putIfAbsent(prediction.letter, () => <double>[]).add(prediction.confidence);
    }

    String? bestLetter;
    List<double> bestScores = const [];

    for (final entry in grouped.entries) {
      if (bestLetter == null) {
        bestLetter = entry.key;
        bestScores = entry.value;
        continue;
      }

      if (entry.value.length > bestScores.length) {
        bestLetter = entry.key;
        bestScores = entry.value;
        continue;
      }

      if (entry.value.length == bestScores.length) {
        final currentAvg = entry.value.reduce((a, b) => a + b) / entry.value.length;
        final bestAvg = bestScores.reduce((a, b) => a + b) / bestScores.length;
        if (currentAvg > bestAvg) {
          bestLetter = entry.key;
          bestScores = entry.value;
        }
      }
    }

    if (bestLetter == null || bestScores.isEmpty) return null;

    final avgConfidence = bestScores.reduce((a, b) => a + b) / bestScores.length;
    final voteRatio = bestScores.length / _recentPredictions.length;

    if (requireConsensus && (bestScores.length < _minStableVotes || voteRatio < 0.5)) {
      return null;
    }

    return _AbcDetection(bestLetter, avgConfidence);
  }

  @override
  void dispose() {
    _disposed = true;
    _phaseTimer?.cancel();
    _countdownController.dispose();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    if (widget.mode == AlphabetMode.sibi) {
      _sibi.dispose();
    } else {
      _bisindo.dispose();
    }
    super.dispose();
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera preview
            if (_isInitialized && _cameraController != null)
              Positioned.fill(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _cameraController!.value.previewSize?.height ?? 1,
                    height: _cameraController!.value.previewSize?.width ?? 1,
                    child: CameraPreview(_cameraController!),
                  ),
                ),
              ),

            // Live detection badge (sudut kanan bawah frame)
            if (_isInitialized && _phase == _Phase.countdown && _liveResult != null)
              Positioned(
                top: 72,
                right: 16,
                child: _liveDetectionBadge(_liveResult!),
              ),

            // Countdown indicator
            if (_isInitialized && _phase == _Phase.countdown)
              Center(child: _buildCountdown()),

            // Capturing indicator
            if (_isInitialized && _phase == _Phase.capturing)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),

            // Loading
            if (!_isInitialized && _error == null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Memuat model AI...',
                      style: GoogleFonts.beVietnamPro(
                          color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'MediaPipe + Dense Classifier',
                      style: GoogleFonts.jetBrainsMono(
                          color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),

            // Error
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: AppColors.error, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: GoogleFonts.beVietnamPro(
                            color: Colors.white, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => context.pop(),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white),
                        child: const Text('Kembali'),
                      ),
                    ],
                  ),
                ),
              ),

            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                      onPressed: () => context.pop(),
                    ),
                    const Spacer(),
                    _targetBadge(),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_correctCount/$_totalCount',
                        style: GoogleFonts.jetBrainsMono(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom panel
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.9),
                      Colors.black.withOpacity(0.5),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: _buildResultPanel(),
              ),
            ),

            // Success flash
            if (_phase == _Phase.result && _isCorrect)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                          color: AppColors.success.withOpacity(0.12))
                      .animate()
                      .fadeIn(duration: 200.ms)
                      .then()
                      .fadeOut(duration: 600.ms, delay: 800.ms),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Widgets ───────────────────────────────────────────────────────────────

  /// Badge kecil yang menampilkan deteksi realtime (saat countdown berlangsung)
  Widget _liveDetectionBadge(_AbcDetection result) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.greenAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            result.letter,
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${(result.confidence * 100).toInt()}%',
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 150.ms);
  }

  Widget _buildCountdown() {
    return AnimatedBuilder(
      animation: _countdownController,
      builder: (_, __) => SizedBox(
        width: 52,
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: _countdownController.value,
              strokeWidth: 3,
              color: Colors.white.withOpacity(0.6),
              backgroundColor: Colors.white.withOpacity(0.12),
            ),
            Icon(Icons.front_hand_rounded,
                color: Colors.white.withOpacity(0.4), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _targetBadge() {
    final isOk = _isCorrect && _phase == _Phase.result;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isOk
            ? AppColors.success.withOpacity(0.3)
            : Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(
            color:
                isOk ? AppColors.success.withOpacity(0.6) : Colors.white30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _modeLabel,
              style: GoogleFonts.jetBrainsMono(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(widget.targetLetter,
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          if (isOk) ...[
            const SizedBox(width: 4),
            Icon(Icons.check_circle, color: AppColors.success, size: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildResultPanel() {
    switch (_phase) {
      case _Phase.preparing:
        return _pill(Icons.hourglass_top_rounded, 'Mempersiapkan...',
            Colors.white60);

      case _Phase.countdown:
        return _pill(
          Icons.front_hand_rounded,
          'Tunjukkan isyarat "${widget.targetLetter}" ($_modeHint) ke kamera',
          Colors.white60,
        );

      case _Phase.capturing:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white54),
            ),
            const SizedBox(width: 10),
            Text('Menganalisis...',
                style: GoogleFonts.beVietnamPro(
                    color: Colors.white60, fontSize: 14)),
          ],
        );

      case _Phase.result:
        if (_lastResult == null) {
          return _resultCard(
            Icons.pan_tool_outlined,
            Colors.white54,
            'Tangan tidak terdeteksi',
            'Pastikan tangan terlihat jelas di kamera',
          );
        }
        if (_isCorrect) {
          return _resultCard(
            Icons.check_circle_rounded,
            AppColors.success,
            'Benar! "${_lastResult!.letter}" ✨',
            '${(_lastResult!.confidence * 100).toStringAsFixed(1)}% confidence',
          );
        }
        return _resultCard(
          Icons.close_rounded,
          AppColors.error,
          'Terdeteksi: "${_lastResult!.letter}"',
          'Target "${widget.targetLetter}" — ${(_lastResult!.confidence * 100).toStringAsFixed(1)}%',
        );
    }
  }

  Widget _pill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Text(text,
                style: GoogleFonts.beVietnamPro(color: color, fontSize: 14),
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(IconData icon, Color c, String title, String sub) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: c, size: 28),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: GoogleFonts.plusJakartaSans(
                        color: c == Colors.white54 ? Colors.white : c,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                Text(sub,
                    style: GoogleFonts.beVietnamPro(
                        color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).scale(
        begin: const Offset(0.97, 0.97), duration: 250.ms);
  }
}
