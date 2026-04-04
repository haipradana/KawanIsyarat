import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../../core/providers/learning_provider.dart';
import '../widgets/reference_image_card.dart';
import '../widgets/live_camera_pip.dart';
import '../widgets/feedback_banner.dart';
import '../widgets/star_rating.dart';

class LearningModeScreen extends ConsumerWidget {
  const LearningModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(learningProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primaryContainer],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text('🤟', style: TextStyle(fontSize: 12)),
              ),
            ),
            SizedBox(width: 8),
            Text(
              AppStrings.appName,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          // Learning mode badge
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(
              'LEARNING MODE',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 1,
              ),
            ),
          ),
          SizedBox(width: 8),
          // XP counter
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(
              '⚡ ${state.xp} XP',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
          SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: AppSpacing.lg),
            // Progress bar
            _buildProgressSection(state)
                .animate()
                .fadeIn(duration: 400.ms),
            SizedBox(height: AppSpacing.xxl),
            // Word display
            _buildWordDisplay(state)
                .animate()
                .fadeIn(duration: 400.ms, delay: 100.ms),
            SizedBox(height: AppSpacing.xxl),
            // Reference image
            ReferenceImageCard(word: state.currentWord)
                .animate()
                .fadeIn(duration: 400.ms, delay: 200.ms),
            SizedBox(height: AppSpacing.lg),
            // Live camera PiP
            LiveCameraPip(
              isRecording: state.isRecording,
              onRecord: () {
                if (state.isRecording) {
                  ref.read(learningProvider.notifier).stopRecording();
                } else {
                  ref.read(learningProvider.notifier).startRecording();
                }
              },
            ).animate().fadeIn(duration: 400.ms, delay: 300.ms),
            SizedBox(height: AppSpacing.lg),
            // Feedback banner
            if (state.showFeedback && state.feedbackMessage != null)
              FeedbackBanner(
                message: state.feedbackMessage!,
                isVisible: state.showFeedback,
              ),
            SizedBox(height: AppSpacing.lg),
            // Star rating
            if (state.showFeedback)
              Center(
                child: StarRating(
                  rating: state.starRating,
                  maxStars: state.maxStars,
                ),
              ),
            SizedBox(height: AppSpacing.xxl),
            // Next word button
            if (state.showFeedback)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      ref.read(learningProvider.notifier).nextWord(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                  child: Text(
                    'Kata Berikutnya →',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
                  .animate()
                  .fadeIn(duration: 300.ms)
                  .slideY(begin: 0.2, end: 0, duration: 300.ms),
            SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 2,
        onTap: (index) => _handleNavTap(context, index),
      ),
    );
  }

  Widget _buildProgressSection(LearningState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'UNIT ${state.currentUnit}: ${state.unitTitle}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 1,
              ),
            ),
            Text(
              '${(state.progress * 100).toInt()}% LULUS',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: LinearProgressIndicator(
            value: state.progress,
            backgroundColor: AppColors.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildWordDisplay(LearningState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.currentWord,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.2,
          ),
        ),
        SizedBox(height: 8),
        Text(
          state.instruction,
          style: GoogleFonts.beVietnamPro(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
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
        break; // Already on learning
      case 3:
        context.push('/settings');
        break;
    }
  }
}
