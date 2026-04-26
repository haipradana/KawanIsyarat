import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:camera/camera.dart';
import '../../../app/constants.dart';
import '../../../shared/widgets/kawan_app_bar.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../../shared/widgets/skeleton_overlay_painter.dart';
import '../../../core/providers/communication_provider.dart';
import '../widgets/gloss_chip_row.dart';
import '../widgets/ai_sentence_card.dart';
import '../../../core/services/tts_service.dart';
import 'package:go_router/go_router.dart';

class CommDeafToHearingScreen extends ConsumerStatefulWidget {
  const CommDeafToHearingScreen({super.key});

  @override
  ConsumerState<CommDeafToHearingScreen> createState() =>
      _CommDeafToHearingScreenState();
}

class _CommDeafToHearingScreenState
    extends ConsumerState<CommDeafToHearingScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  int _sensorOrientation = 90;
  CameraLensDirection _lensDirection = CameraLensDirection.front;
  bool _switchingCamera = false;
  // Dev flag — set true untuk munculkan panel input fitur (debug skeleton model).
  static const bool _showModelInputPanel = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    // Initialize LSTM model after first frame — ensures provider is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[Screen] Calling initializeServices...');
      ref.read(deafToHearingProvider.notifier).initializeServices();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopImageStream();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.paused) {
      // App benar-benar ke background — matikan kamera
      _stopImageStream();
      _cameraController?.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      // App kembali ke foreground — nyalakan lagi
      _initCamera();
    }
    // AppLifecycleState.inactive (notif shade, volume, dll) → biarkan, jangan matikan kamera
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      // Pilih kamera sesuai _lensDirection. Kalau tidak ada, fallback ke kamera
      // dengan arah berlawanan, baru fallback ke yang pertama tersedia.
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == _lensDirection,
        orElse: () => cameras.firstWhere(
          (c) =>
              c.lensDirection == CameraLensDirection.front ||
              c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        ),
      );
      _lensDirection = camera.lensDirection;

      _sensorOrientation = camera.sensorOrientation;

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isCameraReady = true);
      }
    } catch (e) {
      debugPrint('[Camera] Init error: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_switchingCamera) return;
    setState(() => _switchingCamera = true);
    try {
      // Stop stream dulu, dispose controller lama
      _stopImageStream();
      await _cameraController?.dispose();
      _cameraController = null;
      if (mounted) setState(() => _isCameraReady = false);

      // Flip lens direction
      _lensDirection = _lensDirection == CameraLensDirection.front
          ? CameraLensDirection.back
          : CameraLensDirection.front;

      await _initCamera();

      // Kalau sebelumnya lagi capture / record, biarkan user tekan lagi — aman,
      // karena state notifier detach saat recording dihentikan di tombol switch.
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  void _startImageStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (_cameraController!.value.isStreamingImages) return;

    _cameraController!.startImageStream((CameraImage image) {
      final notifier = ref.read(deafToHearingProvider.notifier);
      // Get preview size for skeleton overlay mapping
      final previewSize = _cameraController!.value.previewSize;
      final previewW = previewSize?.width ?? image.width.toDouble();
      final previewH = previewSize?.height ?? image.height.toDouble();

      final isFront = _cameraController!.description.lensDirection ==
          CameraLensDirection.front;

      notifier.onCameraFrame(
        image,
        previewW,
        previewH,
        sensorOrientation: _sensorOrientation,
        isFrontCamera: isFront,
      );
    });
  }

  void _stopImageStream() {
    if (_cameraController != null &&
        _cameraController!.value.isInitialized &&
        _cameraController!.value.isStreamingImages) {
      _cameraController!.stopImageStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deafToHearingProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: KawanAppBar(
        title: 'Isyarat ke Teks',
        showBackButton: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: BouncingScrollPhysics(),
              child: Column(
                children: [
                  // ── Mode toggle ─────────────────────────────────────────────
                  _buildModeToggle(state),
                  SizedBox(height: AppSpacing.md),
                  // Camera full-width tanpa padding samping
                  _buildCameraView(state)
                      .animate()
                      .fadeIn(duration: 400.ms),
                  if (_showModelInputPanel &&
                      state.isCapturing &&
                      state.detectionMode == DetectionMode.sign &&
                      state.modelInputFeatures.length >= 100)
                    Padding(
                      padding: EdgeInsets.only(
                        top: AppSpacing.md,
                        left: AppSpacing.xxl,
                        right: AppSpacing.xxl,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _buildModelInputPanel(state),
                      ),
                    ).animate().fadeIn(duration: 250.ms),
                  SizedBox(height: AppSpacing.xl),
                  // Konten di bawah kamera dengan padding normal
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                    child: Column(
                      children: [
                  // Error message
                  if (state.errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      margin: EdgeInsets.only(bottom: AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: AppColors.error.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_rounded,
                              color: AppColors.error, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              state.errorMessage!,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 300.ms).shake(
                          duration: 400.ms,
                          hz: 3,
                          offset: Offset(2, 0),
                        ),
                  // Gloss chips
                  GlossChipRow(glossTokens: state.currentGloss),
                  SizedBox(height: AppSpacing.lg),
                  // AI Sentence Card
                  AiSentenceCard(
                    sentence: state.refinedSentence,
                    isProcessing: state.isProcessing,
                    onSpeak: () =>
                        ref.read(deafToHearingProvider.notifier).speakSentence(),
                  ),
                  // Contextual Empathy — bullet tips dari Gemma 4
                  if (state.empathyTips.isNotEmpty)
                    _AiSuggestionCard(tips: state.empathyTips)
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 100.ms)
                        .slideY(begin: 0.1, end: 0)
                  else if (state.aiSuggestion != null && state.aiSuggestion!.isNotEmpty)
                    _AiSuggestionCard(tips: [state.aiSuggestion!])
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 100.ms)
                        .slideY(begin: 0.1, end: 0),
                  SizedBox(height: AppSpacing.xxxl),
                  // ── Per-sign recording controls ──────────────────────────────────
                  _buildControls(state),
                  SizedBox(height: AppSpacing.lg),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Sticky "Kirim ke AI" button ─────────────────────────────────
          if (state.isCapturing && state.currentGloss.isNotEmpty && !state.isProcessing)
            _buildStickyAIButton(state),
        ],
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTap: (index) => _handleNavTap(context, index),
      ),
    );
  }

  Widget _buildCameraView(DeafToHearingState state) {
    // Aspect ratio 4:3 — mendekati format training data (video landscape upper-body).
    // FittedBox.cover akan crop bagian atas/bawah frame portrait sensor,
    // menyisakan area tengah (kepala + badan + tangan) yang relevan untuk BISINDO.
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
              // Real camera preview or placeholder
              if (_isCameraReady && _cameraController != null)
                Positioned.fill(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _cameraController!.value.previewSize?.height ?? 480,
                      height: _cameraController!.value.previewSize?.width ?? 640,
                      child: CameraPreview(_cameraController!),
                    ),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        Color(0xFF2A2A4A),
                        Color(0xFF1A1A2E),
                      ],
                      center: Alignment.center,
                      radius: 0.8,
                    ),
                  ),
                ),
              // Camera label (status dot + mode tag)
              Positioned(
                top: 12,
                left: 12,
                child: Row(
                  children: [
                    // Status pill (LIVE / REC / KAMERA)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
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
                              color: state.isRecordingSign
                                  ? Colors.red
                                  : state.isCapturing
                                      ? AppColors.success
                                      : (_isCameraReady ? Colors.blue : Colors.grey),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            state.isRecordingSign
                                ? 'REC ${(state.bufferProgress / 1000).toStringAsFixed(1)}s'
                                : state.isCapturing
                                    ? 'LIVE'
                                    : (_isCameraReady ? 'KAMERA' : 'LOADING'),
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
                    const SizedBox(width: 6),
                    // Mode tag (SIGN / SIBI / BISINDO)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        _modeBadgeText(state.detectionMode),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Live alphabet letter overlay (big letter on camera)
              if (state.isCapturing &&
                  state.detectionMode != DetectionMode.sign &&
                  state.currentAlphabetLetter != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: _buildLetterOverlay(state.currentAlphabetLetter!),
                ),
              // Camera switch button (front ↔ back)
              if (!(state.isCapturing &&
                      state.detectionMode != DetectionMode.sign &&
                      state.currentAlphabetLetter != null) &&
                  !state.isRecordingSign)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Material(
                    color: Colors.black.withOpacity(0.45),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _switchingCamera ? null : _switchCamera,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _switchingCamera
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _lensDirection == CameraLensDirection.front
                                    ? Icons.cameraswitch_rounded
                                    : Icons.flip_camera_android_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                      ),
                    ),
                  ),
                ),
              // Processing indicator
              if (state.isProcessing)
                Center(
                  child: Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 3,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'AI sedang memproses...',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Center hint when inactive
              if (!state.isCapturing && !state.isProcessing && !_isCameraReady)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_outlined,
                          color: Colors.white.withOpacity(0.3), size: 48),
                      SizedBox(height: 8),
                      Text(
                        'Memuat kamera...',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!state.isCapturing && !state.isProcessing && _isCameraReady)
                Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      'Tekan tombol untuk mulai',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ),
                ),
              // ── Live alphabet letter overlay with vote progress ring ──────
              if (state.isCapturing &&
                  state.detectionMode != DetectionMode.sign &&
                  state.currentAlphabetLetter != null)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: _buildLetterWithProgress(
                    state.currentAlphabetLetter!,
                    state.alphabetVoteProgress,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelInputPanel(DeafToHearingState state) {
    // Check if any hand data exists for status indicator
    bool hasHandData = false;
    if (state.modelInputFeatures.length >= 84) {
      for (int i = 0; i < 84; i++) {
        if (state.modelInputFeatures[i].abs() > 1e-6) {
          hasHandData = true;
          break;
        }
      }
    }

    return Container(
      width: 150,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.68),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'MODEL INPUT',
                style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withOpacity(0.9),
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: hasHandData
                      ? const Color(0xFF1D9E75)
                      : Colors.grey.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 170,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: CustomPaint(
              size: const Size(150, 170),
              painter: ModelInputPainter(
                features: state.modelInputFeatures,
                isActive: state.isCapturing,
              ),
            ),
          ),
          if (!hasHandData)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Tidak ada tangan',
                style: GoogleFonts.robotoMono(
                  fontSize: 8,
                  color: Colors.white.withOpacity(0.35),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _modeBadgeText(DetectionMode mode) {
    switch (mode) {
      case DetectionMode.sign:
        return 'SIGN';
      case DetectionMode.sibiAlphabet:
        return 'SIBI · 1H';
      case DetectionMode.bisindoAlphabet:
        return 'BISINDO · 2H';
    }
  }

  /// Big animated letter overlay shown on the camera during alphabet mode.
  Widget _buildLetterOverlay(String letter) {
    return Container(
      key: ValueKey('letter-$letter'),
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.4),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Text(
          letter,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.0,
          ),
        ),
      ),
    ).animate().fadeIn(duration: 120.ms).scale(
          begin: const Offset(0.8, 0.8),
          end: const Offset(1.0, 1.0),
          duration: 180.ms,
          curve: Curves.easeOutBack,
        );
  }

  /// Bottom-right camera overlay: letter chip wrapped with circular vote progress.
  /// Progress ring fills up as majority vote approaches the commit threshold (9/15).
  Widget _buildLetterWithProgress(String letter, double voteProgress) {
    final isReady = voteProgress >= 1.0;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer progress ring
        SizedBox(
          width: 68,
          height: 68,
          child: CircularProgressIndicator(
            value: voteProgress,
            strokeWidth: 3.5,
            backgroundColor: Colors.white.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation(
              isReady ? AppColors.success : Colors.white.withOpacity(0.85),
            ),
          ),
        ),
        // Inner letter box
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: isReady
                ? AppColors.success.withOpacity(0.9)
                : AppColors.primary.withOpacity(0.85),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: (isReady ? AppColors.success : AppColors.primary)
                    .withOpacity(0.4),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            letter,
            style: GoogleFonts.robotoMono(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  /// Segmented toggle: SIGN | SIBI | BISINDO.
  Widget _buildModeToggle(DeafToHearingState state) {
    final notifier = ref.read(deafToHearingProvider.notifier);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        padding: EdgeInsets.all(3),
        child: Row(
          children: [
            _buildModeTab(
              label: 'SIGN',
              icon: Icons.pan_tool_alt_rounded,
              isActive: state.detectionMode == DetectionMode.sign,
              onTap: () => notifier.switchDetectionMode(DetectionMode.sign),
            ),
            _buildModeTab(
              label: 'SIBI',
              icon: Icons.abc_rounded,
              isActive: state.detectionMode == DetectionMode.sibiAlphabet,
              onTap: () => notifier.switchDetectionMode(DetectionMode.sibiAlphabet),
            ),
            _buildModeTab(
              label: 'BISINDO',
              icon: Icons.sign_language_rounded,
              isActive: state.detectionMode == DetectionMode.bisindoAlphabet,
              onTap: () => notifier.switchDetectionMode(DetectionMode.bisindoAlphabet),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTab({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive
                    ? AppColors.onPrimary
                    : AppColors.textSecondary,
              ),
              SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? AppColors.onPrimary
                      : AppColors.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Per-sign recording UI: start/stop session + record one sign per press.
  Widget _buildControls(DeafToHearingState state) {
    final notifier = ref.read(deafToHearingProvider.notifier);
    final progress = state.bufferTotalMs == 0
        ? 0.0
        : (state.bufferProgress / state.bufferTotalMs).clamp(0.0, 1.0);

    return Column(
      children: [
        // ── Row 1: Session toggle + optional gloss actions ──────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Start / Stop session
            _ControlButton(
              icon: state.isCapturing ? Icons.stop_rounded : Icons.videocam_rounded,
              label: state.isCapturing ? 'STOP' : 'MULAI',
              color: state.isCapturing ? AppColors.error : AppColors.primary,
              onTap: () {
                if (state.isCapturing) {
                  _stopImageStream();
                  notifier.stopCapture();
                } else {
                  notifier.startCapture();
                  _startImageStream();
                }
              },
            ),
            if (state.isCapturing && state.currentGloss.isNotEmpty) ...([
              SizedBox(width: AppSpacing.md),
              // Remove last word
              _ControlButton(
                icon: Icons.backspace_rounded,
                label: 'HAPUS',
                color: Colors.orange,
                onTap: () => notifier.removeLastWord(),
              ),
              SizedBox(width: AppSpacing.md),
              // Clear all
              _ControlButton(
                icon: Icons.clear_all_rounded,
                label: 'RESET',
                color: Colors.grey,
                onTap: () => notifier.clearGloss(),
              ),
            ]),
          ],
        ),

        if (state.isCapturing) ...(
          [
            SizedBox(height: AppSpacing.xl),

            // ── Mode-specific controls ────────────────────────────────────
            if (state.detectionMode == DetectionMode.sign)
              _buildBisindoRecordButton(state, notifier, progress)
            else
              _buildAlphabetControls(state, notifier),
          ]
        ),
      ],
    );
  }

  /// Sticky "Kirim ke AI" button — always visible above bottom nav.
  Widget _buildStickyAIButton(DeafToHearingState state) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () =>
                ref.read(deafToHearingProvider.notifier).sendToAI(),
            icon: Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(
              'Kirim ke AI  [${_formatGlossForButton(state)}]',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6B48FF),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// BISINDO mode: tap-to-record sign button with circular progress.
  Widget _buildBisindoRecordButton(
      DeafToHearingState state, DeafToHearingNotifier notifier, double progress) {
    return Column(
      children: [
        GestureDetector(
          onTap: () {
            if (state.isRecordingSign) {
              notifier.cancelSignRecording();
            } else {
              notifier.startSignRecording();
            }
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 88,
                height: 88,
                child: CircularProgressIndicator(
                  value: state.isRecordingSign ? progress : 0.0,
                  strokeWidth: 4,
                  backgroundColor: Colors.white.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation(
                    state.isRecordingSign
                        ? AppColors.primary
                        : Colors.transparent,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: state.isRecordingSign ? 72 : 76,
                height: state.isRecordingSign ? 72 : 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state.isRecordingSign
                      ? AppColors.primary
                      : AppColors.primary.withOpacity(0.15),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.6),
                    width: 2,
                  ),
                  boxShadow: state.isRecordingSign
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.35),
                            blurRadius: 18,
                            spreadRadius: 4,
                          )
                        ]
                      : [],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      state.isRecordingSign
                          ? Icons.fiber_manual_record
                          : Icons.pan_tool_alt_rounded,
                      color: state.isRecordingSign
                          ? Colors.white
                          : AppColors.primary,
                      size: 22,
                    ),
                    if (state.isRecordingSign)
                      Text(
                        '${(state.bufferProgress / 1000).toStringAsFixed(1)}s',
                        style: GoogleFonts.robotoMono(
                          fontSize: 10,
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.md),
        Text(
          state.isRecordingSign
              ? 'Merekam... ${(state.bufferProgress / 1000).toStringAsFixed(1)}s / ${(state.bufferTotalMs / 1000).toStringAsFixed(1)}s'
              : 'Ketuk untuk rekam satu isyarat',
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            color: state.isRecordingSign
                ? AppColors.primary
                : AppColors.textSecondary,
            fontWeight: state.isRecordingSign
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  /// Alphabet mode: auto-detect (no manual tap), show live status + SPASI.
  /// Progress ring is on the camera overlay (bottom-right corner).
  Widget _buildAlphabetControls(
      DeafToHearingState state, DeafToHearingNotifier notifier) {
    final isBisindo = state.detectionMode == DetectionMode.bisindoAlphabet;
    final hasLetter = state.currentAlphabetLetter != null;

    return Column(
      children: [
        // ── Status text ─────────────────────────────────────────────────
        Text(
          hasLetter
              ? 'Tahan posisi\u2026 lihat progress di kamera'
              : isBisindo
                  ? 'Tunjukkan 2 tangan ke kamera'
                  : 'Tunjukkan 1 tangan ke kamera',
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: hasLetter ? AppColors.primary : AppColors.textSecondary,
            fontWeight: hasLetter ? FontWeight.w600 : FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),

        SizedBox(height: AppSpacing.md),

        // ── Space button ────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ControlButton(
              icon: Icons.space_bar_rounded,
              label: 'SPASI',
              color: AppColors.primary,
              onTap: () => notifier.addSpace(),
            ),
          ],
        ),

        SizedBox(height: AppSpacing.sm),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timer_outlined,
                  size: 12, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                'Auto-simpan setelah stabil ~2 detik',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatGlossForButton(DeafToHearingState state) {
    if (state.detectionMode != DetectionMode.sign) {
      // In alphabet mode (SIBI/BISINDO), join letters into word(s)
      return state.currentGloss.join('');
    }
    return state.currentGloss.map((w) => w.toUpperCase()).join(' | ');
  }

  void _handleNavTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.push('/history');
        break;
      case 2:
        context.push('/learn');
        break;
      case 3:
        context.push('/settings');
        break;
    }
  }
}

/// Small round icon button used in per-sign control row.
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.5), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              fontSize: 8,
              color: color.withOpacity(0.7),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// Contextual Empathy — tips empatik dari Gemma 4 untuk orang dengar.
/// Format bullet points, muncul di bawah kalimat terjemahan pada alur Deaf→Hearing.
class _AiSuggestionCard extends StatefulWidget {
  final List<String> tips;
  const _AiSuggestionCard({required this.tips});

  @override
  State<_AiSuggestionCard> createState() => _AiSuggestionCardState();
}

class _AiSuggestionCardState extends State<_AiSuggestionCard> {
  final TtsService _tts = TtsService();
  bool _speaking = false;

  Future<void> _speakAll() async {
    if (_speaking) {
      await _tts.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    final combined = widget.tips
        .map((t) => t.trim().endsWith('.') ? t.trim() : '${t.trim()}.')
        .join(' ');
    setState(() => _speaking = true);
    await _tts.init();
    await _tts.stop();
    await _tts.speak(combined);
    // Heuristic: reset flag setelah estimasi durasi selesai
    final estMs = (combined.length * 55).clamp(2000, 30000);
    await Future.delayed(Duration(milliseconds: estMs));
    if (mounted) setState(() => _speaking = false);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: AppSpacing.lg),
      padding: EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF6B48FF).withOpacity(0.12),
            Color(0xFF8B5CF6).withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: Color(0xFF6B48FF).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Color(0xFF6B48FF).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 12, color: Color(0xFF8B5CF6)),
                    SizedBox(width: 4),
                    Text(
                      'TIPS EMPATI AI',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8B5CF6),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Untuk kamu yang mendengar',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    color: AppColors.textPrimary.withOpacity(0.5),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _speakAll,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _speaking
                          ? Color(0xFF8B5CF6).withOpacity(0.25)
                          : Color(0xFF8B5CF6).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Color(0xFF8B5CF6).withOpacity(0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _speaking
                              ? Icons.stop_rounded
                              : Icons.volume_up_rounded,
                          size: 14,
                          color: Color(0xFF6B48FF),
                        ),
                        SizedBox(width: 4),
                        Text(
                          _speaking ? 'Berhenti' : 'Dengarkan',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6B48FF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          ...widget.tips.asMap().entries.map((entry) {
            final i = entry.key;
            final text = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                  bottom: i == widget.tips.length - 1 ? 0 : AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: EdgeInsets.only(top: 6, right: 10),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Color(0xFF8B5CF6),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      text,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textPrimary.withOpacity(0.88),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
