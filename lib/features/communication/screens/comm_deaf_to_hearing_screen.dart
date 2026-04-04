import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../app/constants.dart';
import '../../../shared/widgets/kawan_app_bar.dart';

import '../../../shared/widgets/bottom_nav_bar.dart';
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
            // Camera viewfinder
            _buildCameraView(state.isCapturing)
                .animate()
                .fadeIn(duration: 400.ms),
            SizedBox(height: AppSpacing.xl),
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

  Widget _buildCameraView(bool isActive) {
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
              // Simulated camera background
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
                          color: isActive ? AppColors.success : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        isActive ? 'LIVE' : 'KAMERA',
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
              // Mock hand landmarks
              if (isActive)
                CustomPaint(
                  size: Size.infinite,
                  painter: _HandLandmarkPainter(),
                ),
              // Center hint when inactive
              if (!isActive)
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

class _HandLandmarkPainter extends CustomPainter {
  final Random _random = Random(42); // Fixed seed for consistent rendering

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = AppColors.success.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final centerX = size.width * 0.5;
    final centerY = size.height * 0.45;

    // Generate 21 landmarks in a rough hand pattern
    final landmarks = <Offset>[];

    // Wrist
    landmarks.add(Offset(centerX, centerY + size.height * 0.15));

    // Palm points (4)
    for (int i = 0; i < 4; i++) {
      landmarks.add(Offset(
        centerX + (i - 1.5) * size.width * 0.08,
        centerY + size.height * 0.05,
      ));
    }

    // Fingers (4 joints each, 4 fingers + thumb = 16 points)
    for (int finger = 0; finger < 4; finger++) {
      for (int joint = 0; joint < 4; joint++) {
        landmarks.add(Offset(
          centerX + (finger - 1.5) * size.width * 0.09 +
              _random.nextDouble() * 4 - 2,
          centerY - joint * size.height * 0.08 -
              size.height * 0.02 +
              _random.nextDouble() * 4 - 2,
        ));
      }
    }

    // Draw connections
    for (int i = 0; i < landmarks.length - 1; i++) {
      if (i < landmarks.length - 1) {
        canvas.drawLine(landmarks[i], landmarks[i + 1], linePaint);
      }
    }

    // Draw finger connections to palm
    for (int i = 1; i < 5 && i < landmarks.length; i++) {
      final fingerStart = 5 + (i - 1) * 4;
      if (fingerStart < landmarks.length) {
        canvas.drawLine(landmarks[i], landmarks[fingerStart], linePaint);
      }
    }

    // Draw landmarks as dots
    for (final point in landmarks) {
      // Outer glow
      canvas.drawCircle(
        point,
        6,
        Paint()..color = AppColors.success.withOpacity(0.3),
      );
      // Inner dot
      canvas.drawCircle(point, 4, paint);
      // Center highlight
      canvas.drawCircle(
        point,
        2,
        Paint()..color = Colors.white.withOpacity(0.8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
