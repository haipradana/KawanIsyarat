import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';
import '../../../shared/widgets/kawan_app_bar.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../../core/providers/persona_provider.dart';
import '../../../shared/models/user_persona.dart';


class LearningHubScreen extends ConsumerWidget {
  const LearningHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persona = ref.watch(personaProvider);
    final isTuli = persona == UserPersona.tuli;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: KawanAppBar(title: 'Belajar'),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: AppSpacing.lg),
            Text(
              'Modul Belajar',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ).animate().fadeIn(duration: 400.ms),
            SizedBox(height: 6),
            Text(
              isTuli
                  ? 'Perkuat pemahaman bahasa dan latih artikulasi'
                  : 'Pelajari bahasa isyarat BISINDO secara interaktif',
              style: GoogleFonts.beVietnamPro(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
            SizedBox(height: AppSpacing.xxxl),

            if (!isTuli) ...[
              // Mendengar modules
              _ModuleCard(
                icon: Icons.front_hand_rounded,
                title: 'Belajar Kata BISINDO',
                description: 'Praktikkan isyarat kata-kata sehari-hari dengan panduan AI',
                progress: 0.3,
                progressLabel: '3/10 kata',
                color: AppColors.primary,
                onTap: () => context.push('/learn/kata'),
              ).animate().fadeIn(duration: 500.ms, delay: 200.ms).slideY(
                    begin: 0.05, end: 0, duration: 500.ms, delay: 200.ms,
                  ),
              SizedBox(height: AppSpacing.lg),
              _ModuleCard(
                icon: Icons.front_hand_rounded,
                title: 'Belajar Alfabet SIBI',
                description: 'Isyarat huruf A-Z dengan 1 tangan (Sistem Isyarat Bahasa Indonesia)',
                progress: 0.0,
                progressLabel: '0/24 huruf',
                color: AppColors.accent,
                onTap: () => context.push('/learn/alfabet/sibi'),
              ).animate().fadeIn(duration: 500.ms, delay: 350.ms).slideY(
                    begin: 0.05, end: 0, duration: 500.ms, delay: 350.ms,
                  ),
              SizedBox(height: AppSpacing.lg),
              _ModuleCard(
                icon: Icons.sign_language_rounded,
                title: 'Belajar Alfabet BISINDO',
                description: 'Isyarat huruf A-Z dengan 2 tangan (lebih natural, digunakan komunitas Tuli)',
                progress: 0.0,
                progressLabel: '0/26 huruf',
                color: const Color(0xFF7C3AED),
                onTap: () => context.push('/learn/alfabet/bisindo'),
              ).animate().fadeIn(duration: 500.ms, delay: 500.ms).slideY(
                    begin: 0.05, end: 0, duration: 500.ms, delay: 500.ms,
                  ),
            ] else ...[
              // Tuli modules
              _ModuleCard(
                icon: Icons.translate_rounded,
                title: 'Penerjemah Idiom',
                description: 'Pahami arti kiasan dan idiom dalam bahasa sehari-hari',
                progress: 0.0,
                progressLabel: '0/5 idiom',
                color: AppColors.primary,
                onTap: () => context.push('/learn/idiom'),
              ).animate().fadeIn(duration: 500.ms, delay: 200.ms).slideY(
                    begin: 0.05, end: 0, duration: 500.ms, delay: 200.ms,
                  ),
              SizedBox(height: AppSpacing.lg),
              _ModuleCard(
                icon: Icons.record_voice_over_rounded,
                title: 'Latihan Artikulasi',
                description: 'Latih pengucapan kata dengan umpan balik AI',
                progress: 0.0,
                progressLabel: '0/10 kata',
                color: AppColors.accent,
                onTap: () => context.push('/learn/artikulasi'),
              ).animate().fadeIn(duration: 500.ms, delay: 350.ms).slideY(
                    begin: 0.05, end: 0, duration: 500.ms, delay: 350.ms,
                  ),
              SizedBox(height: AppSpacing.lg),
              _ModuleCard(
                icon: Icons.menu_book_rounded,
                title: 'Kamus Pintar AI',
                description: 'Tanyakan arti kata atau istilah sulit — Gemma 4 menjelaskan dengan bahasa sederhana',
                progress: 0.0,
                progressLabel: 'Gemma 4 Vocabulary Helper',
                color: const Color(0xFF7C3AED),
                onTap: () => context.push('/learn/kamus'),
              ).animate().fadeIn(duration: 500.ms, delay: 500.ms).slideY(
                    begin: 0.05, end: 0, duration: 500.ms, delay: 500.ms,
                  ),
            ],
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

  void _handleNavTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.push('/history');
        break;
      case 2:
        break;
      case 3:
        context.push('/settings');
        break;
    }
  }
}

class _ModuleCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final double progress;
  final String progressLabel;
  final Color color;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.progress,
    required this.progressLabel,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<_ModuleCard> {
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
          padding: EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            border: Border.all(
              color: widget.color.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: widget.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 24),
                  ),
                  SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          widget.description,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppColors.outlineVariant),
                ],
              ),
              SizedBox(height: AppSpacing.lg),
              // Progress bar
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      child: LinearProgressIndicator(
                        value: widget.progress,
                        backgroundColor: AppColors.surfaceContainerHigh,
                        valueColor: AlwaysStoppedAnimation<Color>(widget.color),
                        minHeight: 6,
                      ),
                    ),
                  ),
                  SizedBox(width: AppSpacing.md),
                  Text(
                    widget.progressLabel,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
