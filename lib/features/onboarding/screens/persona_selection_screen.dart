import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';
import '../../../shared/models/user_persona.dart';
import '../../../core/providers/persona_provider.dart';
import '../widgets/persona_card.dart';

class PersonaSelectionScreen extends ConsumerWidget {
  const PersonaSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              child: Column(
                children: [
                  SizedBox(height: AppSpacing.huge),
                  _buildHeader(context),
                  SizedBox(height: AppSpacing.huge),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: PersonaCard(
                            persona: UserPersona.tuli,
                            backgroundColor: AppColors.primary,
                            onTap: () =>
                                _selectPersona(context, ref, UserPersona.tuli),
                          ).animate().fadeIn(duration: 500.ms).slideY(
                                begin: 0.1,
                                end: 0,
                                duration: 500.ms,
                                curve: Curves.easeOut,
                              ),
                        ),
                        SizedBox(height: AppSpacing.lg),
                        Expanded(
                          child: PersonaCard(
                            persona: UserPersona.mendengar,
                            backgroundColor: AppColors.darkSurface,
                            onTap: () =>
                                _selectPersona(context, ref, UserPersona.mendengar),
                          ).animate().fadeIn(duration: 500.ms, delay: 200.ms).slideY(
                                begin: 0.1,
                                end: 0,
                                duration: 500.ms,
                                delay: 200.ms,
                                curve: Curves.easeOut,
                              ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: AppSpacing.xxl),
                  Text(
                    'Pilih persona sesuai kebutuhanmu',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ).animate().fadeIn(duration: 600.ms, delay: 400.ms),
                  SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.25),
                blurRadius: 24,
                offset: Offset(0, 8),
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
            .fadeIn(duration: 400.ms)
            .scale(begin: Offset(0.8, 0.8), duration: 400.ms),
        SizedBox(height: AppSpacing.lg),
        Text(
          AppStrings.appName,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
        SizedBox(height: 4),
        Text(
          AppStrings.tagline,
          style: GoogleFonts.beVietnamPro(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
        ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
      ],
    );
  }

  void _selectPersona(
      BuildContext context, WidgetRef ref, UserPersona persona) {
    ref.read(personaProvider.notifier).setPersona(persona);
    context.go('/ai-init');
  }
}
