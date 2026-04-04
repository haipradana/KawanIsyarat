import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../app/constants.dart';

class StarRating extends StatelessWidget {
  final int rating;
  final int maxStars;
  final String label;

  const StarRating({
    super.key,
    required this.rating,
    this.maxStars = 3,
    this.label = 'SKOR USAHA',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
        SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(maxStars, (index) {
            final isFilled = index < rating;
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isFilled ? AppColors.accent : AppColors.outlineVariant,
                size: 32,
              )
                  .animate()
                  .scale(
                    begin: Offset(0, 0),
                    end: Offset(1, 1),
                    duration: 400.ms,
                    delay: Duration(milliseconds: index * 150),
                    curve: Curves.elasticOut,
                  )
                  .fadeIn(
                    duration: 300.ms,
                    delay: Duration(milliseconds: index * 150),
                  ),
            );
          }),
        ),
      ],
    );
  }
}
