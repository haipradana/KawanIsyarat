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
    if (state == AppLifecycleState.inactive) {
      _stopImageStream();
      _cameraController?.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      // Prefer front camera for sign language
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

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

      notifier.onCameraFrame(
        image,
        previewW,
        previewH,
        sensorOrientation: _sensorOrientation,
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
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        child: Column(
          children: [
            // Camera full-width tanpa padding samping
            _buildCameraView(state)
                .animate()
                .fadeIn(duration: 400.ms),
            if (state.isCapturing && state.modelInputFeatures.length >= 98)
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
            // Contextual Empathy — AI Suggestion Card
            if (state.aiSuggestion != null && state.aiSuggestion!.isNotEmpty)
              _AiSuggestionCard(suggestion: state.aiSuggestion!)
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 100.ms)
                  .slideY(begin: 0.1, end: 0),
            SizedBox(height: AppSpacing.xxxl),
            // ── Per-sign recording controls ──────────────────────────────────
            _buildControls(state),
            SizedBox(height: AppSpacing.xxxl),
                ],
              ),
            ),
          ],
        ),
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
              // Camera label
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                      SizedBox(width: 6),
                      Text(
                        state.isRecordingSign
                            ? 'REC ${state.bufferProgress}/30'
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

  /// Per-sign recording UI: start/stop session + record one sign per press.
  Widget _buildControls(DeafToHearingState state) {
    final notifier = ref.read(deafToHearingProvider.notifier);
    const seqLen = 30;
    final progress = state.bufferProgress / seqLen;

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

            // ── Row 2: Record sign button with circular progress ─────────
            // Tap to start recording, tap again to cancel.
            // Auto-completes when 30 frames collected.
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
                  // Circular progress ring
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
                  // Inner button
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
                            '${state.bufferProgress}/30',
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
                  ? 'Merekam... ${state.bufferProgress}/30 frame'
                  : 'Ketuk untuk rekam satu isyarat',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: Colors.white.withOpacity(state.isRecordingSign ? 0.9 : 0.5),
                fontWeight: state.isRecordingSign
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),

            // ── Row 3: Send to AI ────────────────────────────────────────
            if (state.currentGloss.isNotEmpty && !state.isProcessing)
              Padding(
                padding: EdgeInsets.only(top: AppSpacing.lg),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => notifier.sendToAI(),
                    icon: Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text(
                      'Kirim ke AI  [${state.currentGloss.map((w) => w.toUpperCase()).join(" | ")}]',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
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
          ]
        ),
      ],
    );
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

/// Card saran empatik dari Gemma untuk lawan bicara (orang dengar).
/// Ditampilkan di bawah kalimat terjemahan pada alur Deaf→Hearing.
class _AiSuggestionCard extends StatelessWidget {
  final String suggestion;
  const _AiSuggestionCard({required this.suggestion});

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
                      'SARAN AI',
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
            ],
          ),
          SizedBox(height: AppSpacing.md),
          Text(
            suggestion,
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.textPrimary.withOpacity(0.85),
              height: 1.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
