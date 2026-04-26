import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/constants.dart';
import '../../../core/services/gesture_service.dart';
import '../widgets/bisindo_video_preview.dart';

/// Practice screen untuk Belajar Kata BISINDO.
///
/// Flow:
/// 1. Tampilkan video referensi BISINDO untuk kata target.
/// 2. Buka kamera depan + initialize GestureService (TFLite WL-BISINDO).
/// 3. User tekan tombol REKAM → kumpulkan 30 frame → predict.
/// 4. Bandingkan prediksi vs target → tampilkan feedback (benar / salah).
class LearnKataScreen extends ConsumerStatefulWidget {
  /// Kata target yang ingin dipelajari (mis. "terima_kasih"). Harus salah satu
  /// label di `assets/models/bisindo_wl_labels.json`.
  final String word;

  const LearnKataScreen({super.key, required this.word});

  @override
  ConsumerState<LearnKataScreen> createState() => _LearnKataScreenState();
}

class _LearnKataScreenState extends ConsumerState<LearnKataScreen>
    with WidgetsBindingObserver {
  // ── Camera ─────────────────────────────────────────────────────────────
  CameraController? _cameraController;
  bool _isCameraReady = false;
  int _sensorOrientation = 90;

  // ── Gesture service ────────────────────────────────────────────────────
  final GestureService _gesture = GestureService();
  bool _modelReady = false;

  // ── Practice state ─────────────────────────────────────────────────────
  bool _isRecording = false;
  int _bufferProgress = 0;
  int _attemptCount = 0;
  GestureResult? _lastResult;
  bool _isCorrect = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAll();
  }

  Future<void> _initAll() async {
    await _gesture.initialize();
    if (!mounted) return;
    setState(() => _modelReady = _gesture.isModelLoaded);
    await _initCamera();
    if (mounted && _isCameraReady) {
      _gesture.startGestureCapture();
      _startImageStream();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _sensorOrientation = cam.sensorOrientation;
      _cameraController = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() => _isCameraReady = true);
    } catch (e) {
      debugPrint('[LearnKata] Camera init failed: $e');
    }
  }

  void _startImageStream() {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized || c.value.isStreamingImages) {
      return;
    }
    c.startImageStream((CameraImage image) async {
      // Hanya forward ke GestureService — buffering hanya aktif saat recording.
      try {
        await _gesture.addFrameFromCameraAsync(image, _sensorOrientation);
      } catch (_) {}
    });
  }

  void _stopImageStream() {
    final c = _cameraController;
    if (c != null && c.value.isInitialized && c.value.isStreamingImages) {
      c.stopImageStream();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.paused) {
      _stopImageStream();
      c.dispose();
      _cameraController = null;
      if (mounted) setState(() => _isCameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera().then((_) {
        if (mounted && _isCameraReady) _startImageStream();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopImageStream();
    _cameraController?.dispose();
    _gesture.cancelSignRecording();
    _gesture.stopGestureCapture();
    super.dispose();
  }

  // ── Recording control ────────────────────────────────────────────────────

  void _startRecording() {
    if (!_modelReady || _isRecording) return;
    setState(() {
      _isRecording = true;
      _bufferProgress = 0;
      _lastResult = null;
    });
    _attemptCount++;
    _gesture.startSignRecording(
      onSignDetected: (result) {
        if (!mounted) return;
        final correct =
            result.word.toLowerCase() == widget.word.toLowerCase() &&
                result.confidence >= 0.30;
        setState(() {
          _isRecording = false;
          _bufferProgress = 0;
          _lastResult = result;
          _isCorrect = correct;
        });
      },
      onProgress: (count) {
        if (!mounted) return;
        setState(() => _bufferProgress = count);
      },
    );
  }

  void _cancelRecording() {
    _gesture.cancelSignRecording();
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _bufferProgress = 0;
    });
  }

  void _resetForNextAttempt() {
    setState(() {
      _lastResult = null;
      _bufferProgress = 0;
    });
  }

  String _pretty(String raw) => raw
      .split('_')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final target = widget.word;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Belajar Kata BISINDO',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          if (_attemptCount > 0)
            Container(
              margin: EdgeInsets.only(right: 16),
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              alignment: Alignment.center,
              child: Text(
                'Percobaan #$_attemptCount',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: AppSpacing.lg),
            Text(
              _pretty(target),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ).animate().fadeIn(duration: 300.ms),
            SizedBox(height: 4),
            Text(
              'Tonton video referensi, lalu peragakan di kamera.',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 80.ms),
            SizedBox(height: AppSpacing.xl),

            // ── Reference video ────────────────────────────────────────────
            _sectionLabel('REFERENSI'),
            SizedBox(height: AppSpacing.sm),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border:
                    Border.all(color: AppColors.primary.withOpacity(0.18)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: BisindoVideoPreview(word: target, aspectRatio: 16 / 10),
              ),
            ).animate().fadeIn(duration: 350.ms, delay: 120.ms),

            SizedBox(height: AppSpacing.xl),

            // ── Live camera ────────────────────────────────────────────────
            _sectionLabel('KAMERA KAMU'),
            SizedBox(height: AppSpacing.sm),
            _buildCameraView()
                .animate()
                .fadeIn(duration: 350.ms, delay: 180.ms),

            SizedBox(height: AppSpacing.xl),

            // ── Result feedback ────────────────────────────────────────────
            if (_lastResult != null)
              _buildResultCard(_lastResult!)
                  .animate()
                  .fadeIn(duration: 300.ms)
                  .slideY(begin: 0.05, end: 0),

            SizedBox(height: AppSpacing.xl),

            // ── Record button ──────────────────────────────────────────────
            Center(child: _buildRecordButton()),
            SizedBox(height: AppSpacing.md),
            Center(
              child: Text(
                _isRecording
                    ? 'Merekam... $_bufferProgress/30 frame'
                    : !_modelReady
                        ? 'Memuat model AI...'
                        : !_isCameraReady
                            ? 'Memuat kamera...'
                            : 'Ketuk untuk rekam isyarat',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: _isRecording
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontWeight:
                      _isRecording ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildCameraView() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Container(
          decoration: BoxDecoration(
            color: Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Stack(
            children: [
              if (_isCameraReady && _cameraController != null)
                Positioned.fill(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width:
                          _cameraController!.value.previewSize?.height ?? 480,
                      height:
                          _cameraController!.value.previewSize?.width ?? 640,
                      child: CameraPreview(_cameraController!),
                    ),
                  ),
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2.5),
                      SizedBox(height: 12),
                      Text(
                        'Memuat kamera...',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              // Status pill
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _isRecording
                              ? Colors.red
                              : (_isCameraReady && _modelReady
                                  ? AppColors.success
                                  : Colors.grey),
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        _isRecording
                            ? 'REC $_bufferProgress/30'
                            : _isCameraReady && _modelReady
                                ? 'SIAP'
                                : 'LOADING',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Target tag
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    'TARGET · ${_pretty(widget.word).toUpperCase()}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordButton() {
    final canRecord = _modelReady && _isCameraReady;
    final progress = _bufferProgress / 30.0;
    return GestureDetector(
      onTap: () {
        if (!canRecord) return;
        if (_isRecording) {
          _cancelRecording();
        } else {
          if (_lastResult != null) _resetForNextAttempt();
          _startRecording();
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: CircularProgressIndicator(
              value: _isRecording ? progress : 0.0,
              strokeWidth: 4,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation(
                _isRecording ? AppColors.primary : Colors.transparent,
              ),
            ),
          ),
          AnimatedContainer(
            duration: Duration(milliseconds: 120),
            width: _isRecording ? 78 : 82,
            height: _isRecording ? 78 : 82,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: !canRecord
                  ? AppColors.outlineVariant
                  : _isRecording
                      ? AppColors.primary
                      : AppColors.primary.withOpacity(0.15),
              border: Border.all(
                color: !canRecord
                    ? AppColors.outlineVariant
                    : AppColors.primary.withOpacity(0.6),
                width: 2,
              ),
              boxShadow: _isRecording
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.35),
                        blurRadius: 18,
                        spreadRadius: 4,
                      )
                    ]
                  : [],
            ),
            child: Icon(
              _isRecording
                  ? Icons.fiber_manual_record
                  : Icons.pan_tool_alt_rounded,
              color: _isRecording
                  ? Colors.white
                  : (canRecord ? AppColors.primary : Colors.white70),
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(GestureResult result) {
    final correct = _isCorrect;
    final color = correct ? AppColors.success : AppColors.error;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: color,
                size: 22,
              ),
              SizedBox(width: 8),
              Text(
                correct ? 'Benar! Mantap.' : 'Belum tepat — coba lagi',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Terdeteksi: ${_pretty(result.word)}  '
            '(${(result.confidence * 100).toStringAsFixed(0)}%)',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: AppColors.textPrimary.withOpacity(0.85),
              height: 1.4,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Target: ${_pretty(widget.word)}',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resetForNextAttempt,
                  icon: Icon(Icons.refresh_rounded, size: 18),
                  label: Text('Coba Lagi'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                ),
              ),
              if (correct) ...[
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => context.pop(),
                    icon: Icon(Icons.check_rounded, size: 18),
                    label: Text('Selesai'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
