import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';
import '../../../shared/widgets/kawan_app_bar.dart';

class CommDirectionPickerScreen extends StatelessWidget {
  const CommDirectionPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: KawanAppBar(
        title: 'Komunikasi',
        showBackButton: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: AppSpacing.lg),
            Text(
              'Pilih arah komunikasi',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ).animate().fadeIn(duration: 400.ms),
            SizedBox(height: 6),
            Text(
              'Kedua mode bisa digunakan oleh siapa saja',
              style: GoogleFonts.beVietnamPro(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
            SizedBox(height: AppSpacing.xxxl),
            // Deaf to Hearing
            _DirectionCard(
              icon: Icons.sign_language_rounded,
              title: 'Isyarat ke Teks & Suara',
              description: 'Rekam isyarat BISINDO, AI menerjemahkan ke kalimat natural dan membacakannya',
              gradient: [AppColors.primaryDark, AppColors.primaryContainer],
              onTap: () => context.push('/comm-deaf'),
            ).animate().fadeIn(duration: 500.ms, delay: 200.ms).slideY(
                  begin: 0.05, end: 0, duration: 500.ms, delay: 200.ms,
                ),
            SizedBox(height: AppSpacing.lg),
            // Hearing to Deaf
            _DirectionCard(
              icon: Icons.mic_rounded,
              title: 'Suara ke Teks Ringkas',
              description: 'Rekam suara, AI menyederhanakan menjadi teks yang mudah dibaca',
              gradient: [AppColors.darkSurface, Color(0xFF2A3542)],
              onTap: () => context.push('/comm-hearing'),
            ).animate().fadeIn(duration: 500.ms, delay: 350.ms).slideY(
                  begin: 0.05, end: 0, duration: 500.ms, delay: 350.ms,
                ),
          ],
        ),
      ),
    );
  }
}

class _DirectionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _DirectionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradient,
    required this.onTap,
  });

  @override
  State<_DirectionCard> createState() => _DirectionCardState();
}

class _DirectionCardState extends State<_DirectionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: Duration(milliseconds: 150),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(AppSpacing.xxl),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.xxl),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(widget.icon, color: Colors.white, size: 28),
              ),
              SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      widget.description,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Icon(Icons.arrow_forward_rounded, color: Colors.white.withOpacity(0.6), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
