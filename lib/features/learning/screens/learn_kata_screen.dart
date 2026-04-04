import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';

import '../../../core/providers/learning_provider.dart';
import '../widgets/reference_image_card.dart';
import '../widgets/live_camera_pip.dart';
import '../widgets/feedback_banner.dart';
import '../widgets/star_rating.dart';

class LearnKataScreen extends ConsumerWidget {
  const LearnKataScreen({super.key});

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
          Container(
            margin: EdgeInsets.only(right: 16),
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(
              '${state.xp} XP',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
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
            // Progress
            _buildProgressSection(state).animate().fadeIn(duration: 400.ms),
            SizedBox(height: AppSpacing.xxl),
            // Current word
            Text(
              state.currentWord,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
            SizedBox(height: 6),
            Text(
              state.instruction,
              style: GoogleFonts.beVietnamPro(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 150.ms),
            SizedBox(height: AppSpacing.xxl),
            // Reference
            ReferenceImageCard(word: state.currentWord)
                .animate()
                .fadeIn(duration: 400.ms, delay: 200.ms),
            SizedBox(height: AppSpacing.lg),
            // Camera
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
            // Feedback
            if (state.showFeedback && state.feedbackMessage != null)
              FeedbackBanner(
                message: state.feedbackMessage!,
                isVisible: state.showFeedback,
              ),
            SizedBox(height: AppSpacing.lg),
            if (state.showFeedback)
              Center(
                child: StarRating(
                  rating: state.starRating,
                  maxStars: state.maxStars,
                ),
              ),
            SizedBox(height: AppSpacing.xxl),
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
                    'Kata Berikutnya',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 300.ms),
            SizedBox(height: AppSpacing.xxxl),
          ],
        ),
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
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 1,
              ),
            ),
            Text(
              '${(state.progress * 100).toInt()}%',
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
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}
