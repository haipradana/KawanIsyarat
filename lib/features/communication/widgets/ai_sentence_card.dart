import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import '../../../app/constants.dart';

class AiSentenceCard extends StatelessWidget {
  final String sentence;
  final bool isProcessing;
  final VoidCallback onSpeak;

  const AiSentenceCard({
    super.key,
    required this.sentence,
    required this.isProcessing,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
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
          // Label
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 8),
              Text(
                'TRANSKRIPSI AI',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          // Sentence or shimmer
          if (isProcessing)
            Shimmer.fromColors(
              baseColor: AppColors.surfaceContainerHigh,
              highlightColor: AppColors.surface,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    width: 180,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            )
          else if (sentence.isNotEmpty)
            Text(
              sentence,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ).animate().fadeIn(duration: 400.ms)
          else
            Text(
              'Mulai isyarat untuk melihat terjemahan...',
              style: GoogleFonts.beVietnamPro(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          SizedBox(height: AppSpacing.md),
          // Speaker button
          if (sentence.isNotEmpty && !isProcessing)
            GestureDetector(
              onTap: onSpeak,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.volume_up_rounded,
                        size: 18, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text(
                      'Dengarkan',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 200.ms),
        ],
      ),
    );
  }
}
