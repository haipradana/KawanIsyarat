import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';
import '../../../shared/widgets/kawan_app_bar.dart';

import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../../core/providers/communication_provider.dart';
import '../widgets/waveform_visualizer.dart';
import '../widgets/push_to_start_button.dart';

class CommHearingToDeafScreen extends ConsumerStatefulWidget {
  const CommHearingToDeafScreen({super.key});

  @override
  ConsumerState<CommHearingToDeafScreen> createState() =>
      _CommHearingToDeafScreenState();
}

class _CommHearingToDeafScreenState
    extends ConsumerState<CommHearingToDeafScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hearingToDeafProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: KawanAppBar(
        title: 'Suara ke Teks',
        showBackButton: true,
      ),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: AppSpacing.xxl),
            WaveformVisualizer(isRecording: state.isRecording)
                .animate()
                .fadeIn(duration: 400.ms, delay: 100.ms),
            SizedBox(height: AppSpacing.xxl),
            // Raw Transcription
            _buildTranscriptionSection(
              label: 'TRANSKRIPSI MENTAH',
              labelColor: AppColors.textSecondary,
              text: state.rawTranscription.isNotEmpty
                  ? state.rawTranscription
                  : 'Tekan dan tahan tombol untuk mulai bicara...',
              textStyle: GoogleFonts.beVietnamPro(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: state.rawTranscription.isNotEmpty
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                height: 1.6,
              ),
              isPlaceholder: state.rawTranscription.isEmpty,
            ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
            SizedBox(height: AppSpacing.xxl),
            // Smart Summary
            _buildSmartSummarySection(state)
                .animate()
                .fadeIn(duration: 500.ms, delay: 300.ms),
            SizedBox(height: AppSpacing.huge),
            // Mic button
            Center(
              child: PushToStartButton(
                isActive: state.isRecording,
                icon: Icons.mic_rounded,
                label: 'TAHAN UNTUK BICARA',
                onStart: () =>
                    ref.read(hearingToDeafProvider.notifier).startRecording(),
                onStop: () =>
                    ref.read(hearingToDeafProvider.notifier).stopRecording(),
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 400.ms),
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

  Widget _buildTranscriptionSection({
    required String label,
    required Color labelColor,
    required String text,
    required TextStyle textStyle,
    bool isPlaceholder = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: labelColor,
              letterSpacing: 1.5,
            ),
          ),
          SizedBox(height: AppSpacing.md),
          Text(
            text,
            style: textStyle,
          ),
        ],
      ),
    );
  }

  Widget _buildSmartSummarySection(HearingToDeafState state) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: AppColors.accent.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: AppColors.accent,
              ),
              SizedBox(width: 6),
              Text(
                'INTISARI CERDAS',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          if (state.isProcessing)
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.accent),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Memproses...',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            )
          else
            Text(
              state.smartSummary.isNotEmpty
                  ? state.smartSummary
                  : 'Ringkasan cerdas akan muncul di sini...',
              style: GoogleFonts.plusJakartaSans(
                fontSize: state.smartSummary.isNotEmpty ? 22 : 15,
                fontWeight: state.smartSummary.isNotEmpty
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: state.smartSummary.isNotEmpty
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                height: 1.4,
              ),
            ),
        ],
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
