import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../app/constants.dart';
import '../../../shared/widgets/kawan_app_bar.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../../core/providers/persona_provider.dart';
import '../../../core/providers/ai_providers.dart';
import '../../../shared/models/user_persona.dart';
import '../widgets/mode_card.dart';
import '../widgets/word_of_day_card.dart';

class HomeDashboardScreen extends ConsumerWidget {
  const HomeDashboardScreen({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 10) return 'Selamat Pagi';
    if (hour < 15) return 'Selamat Siang';
    if (hour < 18) return 'Selamat Sore';
    return 'Selamat Malam';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persona = ref.watch(personaProvider);
    final modelsAsync = ref.watch(modelsDownloadedProvider);
    final modelsReady = modelsAsync.valueOrNull ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: KawanAppBar(
        title: AppStrings.appName,
        actions: [
          Container(
            margin: EdgeInsets.only(right: 16),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              persona == null
                  ? Icons.person_outline_rounded
                  : (persona == UserPersona.tuli
                      ? Icons.sign_language_rounded
                      : Icons.hearing_rounded),
              color: AppColors.primary,
              size: 18,
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
            Text(
              'Halo, ${_getGreeting()}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ).animate().fadeIn(duration: 400.ms),
            SizedBox(height: 4),
            Text(
              'Apa yang ingin kamu lakukan hari ini?',
              style: GoogleFonts.beVietnamPro(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
            SizedBox(height: AppSpacing.xl),

            // AI Status Banner
            if (!modelsReady)
              _buildAIBanner(context)
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 150.ms),

            if (!modelsReady)
              SizedBox(height: AppSpacing.lg),

            // Communication Mode Card
            ModeCard(
              title: 'Komunikasi',
              subtitle: 'Terjemahkan isyarat atau suara secara instan',
              ctaText: 'MULAI BICARA',
              icon: Icons.forum_rounded,
              gradientColors: [AppColors.primaryDark, AppColors.primaryContainer],
              onTap: () => context.push('/comm-picker'),
            ).animate().fadeIn(duration: 500.ms, delay: 200.ms).slideY(
                  begin: 0.05, end: 0, duration: 500.ms, delay: 200.ms,
                  curve: Curves.easeOut,
                ),
            SizedBox(height: AppSpacing.lg),
            // Learning Mode Card
            ModeCard(
              title: 'Belajar BISINDO',
              subtitle: 'Modul interaktif untuk mengasah kemampuan',
              ctaText: 'BUKA MODUL',
              icon: Icons.school_rounded,
              gradientColors: [AppColors.darkSurface, Color(0xFF2A3542)],
              onTap: () => context.push('/learn'),
            ).animate().fadeIn(duration: 500.ms, delay: 350.ms).slideY(
                  begin: 0.05, end: 0, duration: 500.ms, delay: 350.ms,
                  curve: Curves.easeOut,
                ),
            SizedBox(height: AppSpacing.xxl),
            // Video of the Day
            WordOfDayCard()
                .animate()
                .fadeIn(duration: 500.ms, delay: 500.ms),
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

  Widget _buildAIBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/ai-init'),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFF0F9F7),
              Color(0xFFE0F2F1),
            ],
          ),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.primary.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.download_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Belum Tersedia',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    'Tap untuk download model AI (~5.2 GB)',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: AppColors.primary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _handleNavTap(BuildContext context, int index) {
    switch (index) {
      case 0:
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
