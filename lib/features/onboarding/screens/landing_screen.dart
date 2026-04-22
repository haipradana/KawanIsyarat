import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';
import '../../../core/providers/auth_provider.dart';

class LandingScreen extends ConsumerWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    // Auto-navigate when signed in
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.isSignedIn && !(prev?.isSignedIn ?? false)) {
        context.go('/persona');
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Column(
            children: [
              Spacer(flex: 2),

              // ── Hero Section ──
              _buildHeroSection(),

              Spacer(flex: 1),

              // ── Feature highlights ──
              _buildFeatureRow(
                Icons.wifi_off_rounded,
                'Offline',
                'AI berjalan di perangkat',
              ).animate().fadeIn(duration: 400.ms, delay: 500.ms),
              SizedBox(height: AppSpacing.md),
              _buildFeatureRow(
                Icons.sign_language_rounded,
                'BISINDO',
                'Bahasa isyarat Indonesia',
              ).animate().fadeIn(duration: 400.ms, delay: 600.ms),
              SizedBox(height: AppSpacing.md),
              _buildFeatureRow(
                Icons.lock_outline_rounded,
                'Privasi',
                'Data tidak keluar perangkat',
              ).animate().fadeIn(duration: 400.ms, delay: 700.ms),

              Spacer(flex: 1),

              // ── Error message ──
              if (authState.error != null)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(AppSpacing.md),
                  margin: EdgeInsets.only(bottom: AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text(
                    authState.error!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: AppColors.error,
                    ),
                  ),
                ),

              // ── Google Sign In button ──
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: authState.isLoading
                      ? null
                      : () => ref.read(authProvider.notifier).signIn(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      side: BorderSide(
                        color: AppColors.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                  ),
                  child: authState.isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation(AppColors.primary),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildGoogleLogo(),
                            SizedBox(width: 12),
                            Text(
                              'Masuk dengan Google',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 800.ms)
                  .slideY(begin: 0.15, end: 0, duration: 500.ms, delay: 800.ms),

              SizedBox(height: AppSpacing.lg),

              // ── Skip login ──
              TextButton(
                onPressed: () => context.go('/persona'),
                child: Text(
                  'Lewati untuk sekarang',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.textSecondary.withOpacity(0.5),
                  ),
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 900.ms),

              SizedBox(height: AppSpacing.xxxl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    return Column(
      children: [
        // App logo
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.28),
                blurRadius: 40,
                offset: Offset(0, 16),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            'assets/images/logo_kawanisyarat.png',
            fit: BoxFit.cover,
          ),
        )
            .animate()
            .fadeIn(duration: 600.ms)
            .scale(
              begin: Offset(0.7, 0.7),
              end: Offset(1, 1),
              duration: 600.ms,
              curve: Curves.easeOut,
            ),
        SizedBox(height: AppSpacing.xxl),

        // App name
        Text(
          AppStrings.appName,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ).animate().fadeIn(duration: 500.ms, delay: 200.ms),
        SizedBox(height: 8),

        // Tagline
        Text(
          AppStrings.tagline,
          style: GoogleFonts.beVietnamPro(
            fontSize: 16,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ).animate().fadeIn(duration: 500.ms, delay: 300.ms),
        SizedBox(height: 6),

        // Subtitle
        Text(
          'Komunikasi tanpa batas antara\nTeman Tuli & Teman Dengar',
          style: GoogleFonts.beVietnamPro(
            fontSize: 14,
            color: AppColors.textSecondary.withOpacity(0.7),
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ).animate().fadeIn(duration: 500.ms, delay: 400.ms),
      ],
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, String desc) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          SizedBox(width: AppSpacing.lg),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                desc,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleLogo() {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          'G',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4285F4),
          ),
        ),
      ),
    );
  }
}
