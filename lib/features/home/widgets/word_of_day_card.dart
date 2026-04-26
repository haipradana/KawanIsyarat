import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';
import '../../learning/widgets/bisindo_video_preview.dart';

/// "Video Hari Ini" — kartu di home screen yang menampilkan klip BISINDO
/// untuk satu kata dari label aktif. Tap untuk masuk ke flow Belajar Kata.
class WordOfDayCard extends StatelessWidget {
  /// Kata default yang ditampilkan di home. Harus salah satu dari label di
  /// `bisindo_wl_labels.json`. Default ke "terima_kasih".
  final String word;

  const WordOfDayCard({
    super.key,
    this.word = 'terima_kasih',
  });

  String _pretty(String raw) {
    return raw
        .split('_')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final label = _pretty(word);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Video Hari Ini',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: AppSpacing.md),
        GestureDetector(
          onTap: () => context.push('/learn/kata'),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.xxl),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Real BISINDO video preview (auto fallback ke placeholder).
                ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppRadius.xxl),
                  ),
                  child: Stack(
                    children: [
                      BisindoVideoPreview(
                        word: word,
                        aspectRatio: 16 / 10,
                      ),
                      // Sign language tag (top-left)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.sign_language_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'BISINDO',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Text content
                Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cara Mengisyaratkan "$label"',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Pelajari gerakan isyarat dasar untuk komunikasi sehari-hari',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
