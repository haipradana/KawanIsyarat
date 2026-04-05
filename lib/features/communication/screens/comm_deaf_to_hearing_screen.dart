import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
    extends ConsumerState<CommDeafToHearingScreen> {
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
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          children: [
            SizedBox(height: AppSpacing.lg),
            // Camera viewfinder with skeleton overlay
            _buildCameraView(state)
                .animate()
                .fadeIn(duration: 400.ms),
            SizedBox(height: AppSpacing.xl),
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
            SizedBox(height: AppSpacing.xxxl),
            // Push to start button
            PushToStartButton(
              isActive: state.isCapturing,
              icon: Icons.pan_tool_rounded,
              label: 'TAHAN UNTUK ISYARAT',
              onStart: () =>
                  ref.read(deafToHearingProvider.notifier).startCapture(),
              onStop: () =>
                  ref.read(deafToHearingProvider.notifier).stopCapture(),
            ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
            SizedBox(height: AppSpacing.xxxl),
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
        aspectRatio: 4 / 3,
        child: Container(
          decoration: BoxDecoration(
            color: Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Stack(
            children: [
              // Camera background (simulated)
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
                              : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        state.isCapturing ? 'LIVE' : 'KAMERA',
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
              // Skeleton overlay — real or mock hand landmarks
              if (state.isCapturing)
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Use skeleton from provider if available, fallback to mock
                    final landmarks = state.skeletonPoints.isNotEmpty
                        ? state.skeletonPoints
                        : _getMockLandmarks(
                            constraints.maxWidth, constraints.maxHeight);
                    return CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: SkeletonOverlayPainter(
                        landmarks: landmarks,
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
              if (!state.isCapturing && !state.isProcessing)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_outlined,
                          color: Colors.white.withOpacity(0.3), size: 48),
                      SizedBox(height: 8),
                      Text(
                        'Tekan tombol untuk mulai',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fallback mock landmarks when provider doesn't have skeleton data.
  List<Offset> _getMockLandmarks(double w, double h) {
    final centerX = w * 0.5;
    final centerY = h * 0.45;
    final spread = w * 0.12;

    // Generate a simple hand shape
    return [
      Offset(centerX, centerY + h * 0.12), // wrist
      // Thumb
      Offset(centerX - spread * 1.2, centerY + h * 0.05),
      Offset(centerX - spread * 1.5, centerY - h * 0.02),
      Offset(centerX - spread * 1.7, centerY - h * 0.06),
      Offset(centerX - spread * 1.8, centerY - h * 0.10),
      // Index
      Offset(centerX - spread * 0.5, centerY),
      Offset(centerX - spread * 0.5, centerY - h * 0.08),
      Offset(centerX - spread * 0.5, centerY - h * 0.14),
      Offset(centerX - spread * 0.5, centerY - h * 0.18),
      // Middle
      Offset(centerX + spread * 0.1, centerY - h * 0.01),
      Offset(centerX + spread * 0.1, centerY - h * 0.10),
      Offset(centerX + spread * 0.1, centerY - h * 0.16),
      Offset(centerX + spread * 0.1, centerY - h * 0.20),
      // Ring
      Offset(centerX + spread * 0.7, centerY),
      Offset(centerX + spread * 0.7, centerY - h * 0.07),
      Offset(centerX + spread * 0.7, centerY - h * 0.12),
      Offset(centerX + spread * 0.7, centerY - h * 0.16),
      // Pinky
      Offset(centerX + spread * 1.3, centerY + h * 0.02),
      Offset(centerX + spread * 1.3, centerY - h * 0.04),
      Offset(centerX + spread * 1.3, centerY - h * 0.08),
      Offset(centerX + spread * 1.3, centerY - h * 0.11),
    ];
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
