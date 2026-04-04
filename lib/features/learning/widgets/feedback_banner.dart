import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../app/constants.dart';

class FeedbackBanner extends StatelessWidget {
  final String message;
  final bool isVisible;

  const FeedbackBanner({
    super.key,
    required this.message,
    required this.isVisible,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.warning.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.lightbulb_outline_rounded,
              color: AppColors.warning,
              size: 16,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .slideY(begin: 0.3, end: 0, duration: 400.ms, curve: Curves.easeOut)
        .fadeIn(duration: 400.ms);
  }
}
