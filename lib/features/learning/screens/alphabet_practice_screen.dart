import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../app/constants.dart';
import '../../../core/services/sibi_alphabet_service.dart';
import '../../../core/services/bisindo_alphabet_service.dart';
import '../../../core/services/gemma_service.dart';
import '../../../core/providers/learning_progress_provider.dart';

/// Alphabet practice screen — single-shot capture + Gemma 4 Vision Sign Coach.
///
/// Flow:
/// 1. `ready`     — user hadapkan tangan, live detection muncul kecil di pojok
/// 2. `holding`   — deteksi stabil 2 detik → auto trigger capture
/// 3. `capturing` — takePicture + CNN freeze
/// 4. `coaching`  — kirim foto ke Gemma vision untuk evaluasi
/// 5. `reviewed`  — tampilkan hasil CNN + tips Gemma, tombol "Coba Lagi"
///
/// User bisa tekan tombol capture manual kapanpun di fase `ready` / `holding`.
enum AlphabetMode { sibi, bisindo }

class AlphabetPracticeScreen extends ConsumerStatefulWidget {
  final String targetLetter;
  final AlphabetMode mode;

  const AlphabetPracticeScreen({
    super.key,
    required this.targetLetter,
    this.mode = AlphabetMode.sibi,
  });

  @override
  ConsumerState<AlphabetPracticeScreen> createState() =>
      _AlphabetPracticeScreenState();
}

class _AbcDetection {
  final String letter;
  final double confidence;
  const _AbcDetection(this.letter, this.confidence);
}

enum _Phase { preparing, ready, holding, capturing, coaching, reviewed }

class _AlphabetPracticeScreenState extends ConsumerState<AlphabetPracticeScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  final SibiAlphabetService _sibi = SibiAlphabetService();
  final BisindoAlphabetService _bisindo = BisindoAlphabetService();
  final GemmaService _gemma = GemmaService();

  bool _isInitialized = false;
  String? _error;
  bool _disposed = false;

  _Phase _phase = _Phase.preparing;
  _AbcDetection? _liveResult;
  _AbcDetection? _capturedDetection;
  String? _capturedImagePath;
  String? _coachText;
  String? _coachError;
  final Queue<_AbcDetection> _recentPredictions = Queue<_AbcDetection>();

  int _sensorOrientation = 90;
  bool _isFrontCamera = true;
  bool _isProcessingFrame = false;
  int _missedFrames = 0;

  DateTime? _stableSince;
  late AnimationController _holdController;
  Timer? _holdCheckTimer;

  /// Hitungan percobaan untuk huruf target saat ini.
  /// Direset ke 0 saat screen dibuka, di-increment setiap `_triggerCapture`.
  /// Dikirim ke Gemma supaya coach tahu kapan perlu menyemangati.
  int _attemptCount = 0;

  static const Duration _holdDuration = Duration(milliseconds: 2200);
  static const int _maxPredictionWindow = 12;
  static const int _minStableVotes = 5;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(vsync: this, duration: _holdDuration);
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
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      if (widget.mode == AlphabetMode.sibi) {
        await _sibi.initialize();
      } else {
        await _bisindo.initialize();
      }

      await _cameraController!.startImageStream(_onCameraFrame);

      // Timer untuk cek stable hold (tiap 150ms)
      _holdCheckTimer = Timer.periodic(
          const Duration(milliseconds: 150), (_) => _checkStableHold());

      if (mounted && !_disposed) {
        setState(() {
          _isInitialized = true;
          _phase = _Phase.ready;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Gagal memulai: ${e.toString()}');
      }
    }
  }

  // ─── Frame handler & stable-hold detection ────────────────────────────────

  void _onCameraFrame(CameraImage frame) {
    if (_isProcessingFrame || _disposed) return;
    if (_phase != _Phase.ready && _phase != _Phase.holding) return;
    _isProcessingFrame = true;

    try {
      _AbcDetection? result;
      if (widget.mode == AlphabetMode.sibi) {
        final r = _sibi.detectFromCameraImage(
            frame, _sensorOrientation, _isFrontCamera);
        if (r != null) result = _AbcDetection(r.letter, r.confidence);
      } else {
        final r = _bisindo.detectFromCameraImage(
            frame, _sensorOrientation, _isFrontCamera);
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

  _AbcDetection? _pushPrediction(_AbcDetection? result) {
    if (result == null) {
      _missedFrames++;
      if (_missedFrames >= 3) {
        _recentPredictions.clear();
        _stableSince = null;
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
    for (final p in _recentPredictions) {
      grouped.putIfAbsent(p.letter, () => <double>[]).add(p.confidence);
    }
    String? bestLetter;
    List<double> bestScores = const [];
    for (final e in grouped.entries) {
      if (bestLetter == null ||
          e.value.length > bestScores.length ||
          (e.value.length == bestScores.length &&
              e.value.reduce((a, b) => a + b) / e.value.length >
                  bestScores.reduce((a, b) => a + b) / bestScores.length)) {
        bestLetter = e.key;
        bestScores = e.value;
      }
    }
    if (bestLetter == null || bestScores.isEmpty) return null;
    final avg = bestScores.reduce((a, b) => a + b) / bestScores.length;
    final ratio = bestScores.length / _recentPredictions.length;
    if (requireConsensus && (bestScores.length < _minStableVotes || ratio < 0.55)) {
      return null;
    }
    return _AbcDetection(bestLetter, avg);
  }

  /// Check apakah deteksi sudah stabil (target letter konsisten > 2 detik).
  void _checkStableHold() {
    if (_disposed) return;
    if (_phase != _Phase.ready && _phase != _Phase.holding) return;

    final stable = _resolveStablePrediction(requireConsensus: true);
    // Hanya counting bila stable letter == target
    if (stable != null && stable.letter == widget.targetLetter) {
      _stableSince ??= DateTime.now();
      final held = DateTime.now().difference(_stableSince!);

      if (_phase != _Phase.holding && mounted) {
        _holdController.forward(from: 0.0);
        setState(() => _phase = _Phase.holding);
      }

      if (held >= _holdDuration) {
        _triggerCapture();
      } else if (mounted) {
        setState(() {}); // update progress
      }
    } else {
      if (_stableSince != null) {
        _stableSince = null;
        _holdController.reset();
        if (_phase == _Phase.holding && mounted) {
          setState(() => _phase = _Phase.ready);
        }
      }
    }
  }

  // ─── Capture & Gemma coaching ─────────────────────────────────────────────

  Future<void> _triggerCapture() async {
    if (_disposed || _phase == _Phase.capturing || _phase == _Phase.coaching) {
      return;
    }

    final frozenDetection = _resolveStablePrediction(requireConsensus: false);
    // Grab hand bounding box BEFORE stopping image stream
    final handBbox = widget.mode == AlphabetMode.sibi
        ? _sibi.lastHandBbox
        : _bisindo.lastHandBbox;
    _attemptCount++;
    setState(() {
      _phase = _Phase.capturing;
      _capturedDetection = frozenDetection;
    });
    _holdController.stop();

    try {
      // Stop stream supaya takePicture tidak konflik
      await _cameraController?.stopImageStream();

      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final savePath = '${dir.path}/sign_capture_$ts.jpg';

      final xfile = await _cameraController!.takePicture();
      final savedFile = await File(xfile.path).copy(savePath);

      if (_disposed) return;

      // ── FREE MEMORY: Dispose camera + TFLite SEBELUM Gemma inference ──
      // Pixel 6a (6GB): Camera+TFLite+MediaPipe = ~400MB.
      // Gemma 4 vision encoder membutuhkan RAM ini.
      debugPrint('[AlphabetPractice] Releasing camera+TFLite for Gemma vision...');
      _holdCheckTimer?.cancel();
      await _cameraController?.dispose();
      _cameraController = null;
      if (widget.mode == AlphabetMode.sibi) {
        _sibi.dispose();
      } else {
        _bisindo.dispose();
      }

      setState(() {
        _phase = _Phase.coaching;
        _capturedImagePath = savedFile.path;
        _isInitialized = false; // camera disposed, prevent preview render
      });

      await _runGemmaCoach(savedFile.path, frozenDetection, handBbox);
    } catch (e) {
      if (!_disposed && mounted) {
        setState(() {
          _phase = _Phase.reviewed;
          _coachError = 'Gagal mengambil foto: $e';
        });
      }
    }
  }

  Future<void> _runGemmaCoach(
      String imagePath, _AbcDetection? detection, Rect? handBbox) async {
    String? tips;
    String? err;
    try {
      if (_gemma.isLoaded) {
        tips = await _gemma.reviewSignImage(
          imagePath: imagePath,
          targetLabel: widget.targetLetter,
          detectedLabel: detection?.letter,
          mode: widget.mode == AlphabetMode.sibi ? 'sibi' : 'bisindo_alfabet',
          attemptCount: _attemptCount,
          handBbox: handBbox,
        );
      } else {
        err = 'Model Gemma belum siap. Tips AI tidak tersedia saat ini.';
      }
    } catch (e) {
      err = 'Tips AI gagal: $e';
    }
    if (_disposed) return;
    setState(() {
      _phase = _Phase.reviewed;
      _coachText = tips;
      _coachError = err;
    });
    // Tandai selesai bila CNN mendeteksi huruf target dengan benar.
    if (_isCorrect) {
      final moduleKey = widget.mode == AlphabetMode.sibi
          ? LearningModule.alfabetSibi
          : LearningModule.alfabetBisindo;
      ref
          .read(learningProgressProvider.notifier)
          .markDone(moduleKey, widget.targetLetter.toUpperCase());
    }
  }

  /// Reinit camera + TFLite setelah Gemma inference selesai.
  Future<void> _retake() async {
    if (_disposed) return;
    setState(() {
      _phase = _Phase.preparing;
      _capturedDetection = null;
      _capturedImagePath = null;
      _coachText = null;
      _coachError = null;
      _liveResult = null;
    });
    _recentPredictions.clear();
    _stableSince = null;
    _holdController.reset();

    // Re-init camera + TFLite (yang sudah di-dispose saat capture)
    try {
      debugPrint('[AlphabetPractice] Re-init camera+TFLite after Gemma...');
      final cameras = await availableCameras();
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
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      if (widget.mode == AlphabetMode.sibi) {
        await _sibi.initialize();
      } else {
        await _bisindo.initialize();
      }

      await _cameraController!.startImageStream(_onCameraFrame);

      _holdCheckTimer = Timer.periodic(
          const Duration(milliseconds: 150), (_) => _checkStableHold());

      if (mounted && !_disposed) {
        setState(() {
          _isInitialized = true;
          _phase = _Phase.ready;
        });
      }
    } catch (e) {
      debugPrint('[AlphabetPractice] Re-init failed: $e');
      if (mounted && !_disposed) {
        setState(() {
          _error = 'Gagal memulai ulang kamera: $e';
        });
      }
    }
  }

  String get _modeLabel => widget.mode == AlphabetMode.sibi ? 'SIBI' : 'BISINDO';
  String get _modeHint => widget.mode == AlphabetMode.sibi ? '1 tangan' : '2 tangan';

  bool get _isCorrect =>
      _capturedDetection != null &&
      _capturedDetection!.letter.toUpperCase() ==
          widget.targetLetter.toUpperCase();

  @override
  void dispose() {
    _disposed = true;
    _holdCheckTimer?.cancel();
    _holdController.dispose();
    _cameraController?.stopImageStream().catchError((_) {});
    _cameraController?.dispose();
    if (widget.mode == AlphabetMode.sibi) {
      _sibi.dispose();
    } else {
      _bisindo.dispose();
    }
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera preview (hidden saat reviewed — show foto hasil capture)
            if (_isInitialized && _cameraController != null &&
                _phase != _Phase.reviewed && _phase != _Phase.coaching)
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

            // Captured photo (saat coaching/reviewed)
            if ((_phase == _Phase.reviewed || _phase == _Phase.coaching) &&
                _capturedImagePath != null)
              Positioned.fill(
                child: Image.file(
                  File(_capturedImagePath!),
                  fit: BoxFit.cover,
                ),
              ),

            // Dim overlay saat reviewed
            if (_phase == _Phase.reviewed || _phase == _Phase.coaching)
              Positioned.fill(
                child: Container(color: Colors.black.withOpacity(0.35)),
              ),

            // Live detection badge (ready/holding)
            if (_isInitialized &&
                (_phase == _Phase.ready || _phase == _Phase.holding) &&
                _liveResult != null)
              Positioned(top: 72, right: 16, child: _liveBadge(_liveResult!)),

            // Hold progress ring (saat holding)
            if (_phase == _Phase.holding) Center(child: _holdRing()),

            // Loading — hanya saat benar-benar init awal/re-init, BUKAN saat coaching/reviewed
            if (!_isInitialized &&
                _error == null &&
                _phase != _Phase.coaching &&
                _phase != _Phase.reviewed)
              _loadingView(),

            // Error
            if (_error != null) _errorView(),

            // Top bar
            _topBar(),

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
                      Colors.black.withOpacity(0.92),
                      Colors.black.withOpacity(0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: _bottomPanel(),
              ),
            ),

            // Success flash
            if (_phase == _Phase.reviewed && _isCorrect)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: AppColors.success.withOpacity(0.12),
                  )
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

  // ─── Sub-widgets ──────────────────────────────────────────────────────────

  Widget _loadingView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text('Memuat model AI...',
                style: GoogleFonts.beVietnamPro(
                    color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 8),
            Text(GemmaService.useVisionCoach
                ? 'MediaPipe + Dense + Gemma Vision'
                : 'MediaPipe + Dense + Gemma Coach',
                style: GoogleFonts.jetBrainsMono(
                    color: Colors.white38, fontSize: 11)),
          ],
        ),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  color: AppColors.error, size: 48),
              const SizedBox(height: 16),
              Text(_error!,
                  style: GoogleFonts.beVietnamPro(
                      color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center),
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
      );

  Widget _topBar() => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => context.pop(),
              ),
              const Spacer(),
              _targetBadge(),
              const Spacer(),
              const SizedBox(width: 48),
            ],
          ),
        ),
      );

  Widget _targetBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: Colors.white30),
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
            child: Text(_modeLabel,
                style: GoogleFonts.jetBrainsMono(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6)),
          ),
          const SizedBox(width: 8),
          Text(widget.targetLetter,
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _liveBadge(_AbcDetection r) {
    final onTarget = r.letter.toUpperCase() == widget.targetLetter.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: onTarget ? AppColors.success : Colors.white24,
            width: onTarget ? 1.5 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: onTarget ? AppColors.success : Colors.amberAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(r.letter,
              style: GoogleFonts.jetBrainsMono(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text('${(r.confidence * 100).toInt()}%',
              style: GoogleFonts.jetBrainsMono(
                  color: Colors.white54, fontSize: 11)),
        ],
      ),
    ).animate().fadeIn(duration: 150.ms);
  }

  Widget _holdRing() {
    return AnimatedBuilder(
      animation: _holdController,
      builder: (_, __) {
        final v = _stableSince == null
            ? 0.0
            : (DateTime.now().difference(_stableSince!).inMilliseconds /
                    _holdDuration.inMilliseconds)
                .clamp(0.0, 1.0);
        return SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: v,
                strokeWidth: 4,
                color: AppColors.success,
                backgroundColor: Colors.white.withOpacity(0.18),
              ),
              Icon(Icons.camera_alt_rounded,
                  color: Colors.white.withOpacity(0.85), size: 28),
            ],
          ),
        );
      },
    );
  }

  Widget _bottomPanel() {
    switch (_phase) {
      case _Phase.preparing:
        return _pill(
            Icons.hourglass_top_rounded, 'Mempersiapkan...', Colors.white60);

      case _Phase.ready:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pill(
              Icons.front_hand_rounded,
              'Tunjukkan isyarat "${widget.targetLetter}" ($_modeHint) — tahan ~2 detik',
              Colors.white70,
            ),
            const SizedBox(height: 12),
            _captureButton(),
          ],
        );

      case _Phase.holding:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pill(
              Icons.radio_button_checked,
              'Tahan posisi ini... mengambil foto',
              AppColors.success,
            ),
            const SizedBox(height: 12),
            _captureButton(),
          ],
        );

      case _Phase.capturing:
        return _pill(
            Icons.photo_camera_rounded, 'Menjepret foto...', Colors.white70);

      case _Phase.coaching:
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white70),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Gemma 4 Vision menganalisis isyaratmu...',
                  style: GoogleFonts.beVietnamPro(
                      color: Colors.white, fontSize: 13.5),
                ),
              ),
            ],
          ),
        );

      case _Phase.reviewed:
        return _reviewCard();
    }
  }

  Widget _captureButton() {
    return ElevatedButton.icon(
      onPressed: (_phase == _Phase.ready || _phase == _Phase.holding)
          ? _triggerCapture
          : null,
      icon: const Icon(Icons.camera_alt_rounded),
      label: Text('Jepret Sekarang',
          style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700, fontSize: 14)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full)),
      ),
    );
  }

  Widget _reviewCard() {
    final detectionLine = _capturedDetection == null
        ? 'Tangan tidak terdeteksi'
        : 'Terdeteksi: ${_capturedDetection!.letter} '
            '(${(_capturedDetection!.confidence * 100).toStringAsFixed(0)}%)';

    final headerColor = _isCorrect
        ? AppColors.success
        : (_capturedDetection == null ? Colors.white54 : AppColors.error);
    final headerIcon = _isCorrect
        ? Icons.check_circle_rounded
        : (_capturedDetection == null
            ? Icons.pan_tool_outlined
            : Icons.close_rounded);
    final headerTitle = _isCorrect
        ? 'Keren! Isyarat "${widget.targetLetter}" sudah tepat'
        : (_capturedDetection == null
            ? 'Tangan kurang jelas'
            : 'Belum pas — target "${widget.targetLetter}"');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: headerColor.withOpacity(0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(headerIcon, color: headerColor, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  headerTitle,
                  style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(detectionLine,
              style: GoogleFonts.jetBrainsMono(
                  color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 12),

          // Gemma tips card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_rounded,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(GemmaService.useVisionCoach
                          ? 'Tips dari Gemma 4 Vision'
                          : 'Tips dari Gemma 4',
                          style: GoogleFonts.plusJakartaSans(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3)),
                      const SizedBox(height: 4),
                      Text(
                        _coachError ??
                            _coachText ??
                            'Tidak ada tips dari AI.',
                        style: GoogleFonts.beVietnamPro(
                            color: Colors.white, fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Selesai'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white30),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _retake,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text('Coba Lagi',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(
        begin: 0.05, end: 0, duration: 250.ms, curve: Curves.easeOut);
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
}
