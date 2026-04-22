import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';
import '../../../core/providers/auth_provider.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    // Auto-navigate when signed in
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.isSignedIn) {
        context.go('/onboarding');
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Column(
            children: [
              Spacer(flex: 3),
              // Logo
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.25),
                      blurRadius: 32,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/images/logo_kawanisyarat.png',
                  fit: BoxFit.cover,
                ),
              ).animate().fadeIn(duration: 600.ms).scale(
                    begin: Offset(0.8, 0.8),
                    duration: 600.ms,
                    curve: Curves.easeOut,
                  ),
              SizedBox(height: AppSpacing.xxl),
              // App name
              Text(
                AppStrings.appName,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 200.ms),
              SizedBox(height: 6),
              Text(
                AppStrings.tagline,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 300.ms),
              Spacer(flex: 2),
              // Error message
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
              // Google Sign In button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: authState.isLoading
                      ? null
                      : () => ref.read(authProvider.notifier).signIn(),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    backgroundColor: Colors.white,
                  ),
                  child: authState.isLoading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(AppColors.primary),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Google "G" logo
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  'G',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF4285F4),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Masuk dengan Google',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 400.ms).slideY(
                    begin: 0.1,
                    end: 0,
                    duration: 500.ms,
                    delay: 400.ms,
                  ),
              SizedBox(height: AppSpacing.lg),
              // Skip login
              TextButton(
                onPressed: () => context.go('/onboarding'),
                child: Text(
                  'Lewati untuk sekarang',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 500.ms),
              SizedBox(height: AppSpacing.huge),
            ],
          ),
        ),
      ),
    );
  }
}
