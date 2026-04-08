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
import '../widgets/push_to_start_button.dart';
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
            // Push to start button
            PushToStartButton(
              isActive: state.isCapturing,
              icon: Icons.pan_tool_rounded,
              label: 'TAHAN UNTUK ISYARAT',
              onStart: () {
                ref.read(deafToHearingProvider.notifier).startCapture();
                _startImageStream();
              },
              onStop: () {
                _stopImageStream();
                ref.read(deafToHearingProvider.notifier).stopCapture();
              },
            ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AspectRatio(
        aspectRatio: 3 / 4,
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
                          color: state.isCapturing
                              ? AppColors.success
                              : (_isCameraReady ? Colors.blue : Colors.grey),
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        state.isCapturing ? 'LIVE' : (_isCameraReady ? 'KAMERA' : 'LOADING'),
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
              // Skeleton overlay — real hand landmarks
              if (state.isCapturing && state.skeletonPoints.isNotEmpty)
                LayoutBuilder(
                  builder: (context, constraints) {
                    return CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: SkeletonOverlayPainter(
                        landmarks: state.skeletonPoints,
                        isActive: state.isCapturing,
                      ),
                    );
                  },
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
