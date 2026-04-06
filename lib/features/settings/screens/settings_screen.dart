import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';
import '../../../shared/widgets/kawan_app_bar.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../../core/services/tts_service.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/persona_provider.dart';
import '../../../shared/models/user_persona.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _ttsEnabled = true;
  String _selectedLanguage = 'Bahasa Indonesia';

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final persona = ref.watch(personaProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: KawanAppBar(
        title: 'Pengaturan',
        showBackButton: true,
      ),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile section
            _buildProfileCard(authState, persona)
                .animate()
                .fadeIn(duration: 300.ms),
            SizedBox(height: AppSpacing.xxl),
            // TTS Section
            _buildSectionTitle('Suara & Ucapan')
                .animate()
                .fadeIn(duration: 300.ms, delay: 100.ms),
            SizedBox(height: AppSpacing.md),
            _buildToggleTile(
              icon: Icons.volume_up_rounded,
              title: 'Text-to-Speech',
              subtitle: 'Aktifkan pembacaan teks otomatis',
              value: _ttsEnabled,
              onChanged: (value) {
                setState(() => _ttsEnabled = value);
                TtsService().setEnabled(value);
              },
            ).animate().fadeIn(duration: 300.ms, delay: 200.ms),
            SizedBox(height: AppSpacing.xxl),
            // Language Section
            _buildSectionTitle('Bahasa')
                .animate()
                .fadeIn(duration: 300.ms, delay: 300.ms),
            SizedBox(height: AppSpacing.md),
            _buildOptionTile(
              icon: Icons.language_rounded,
              title: 'Bahasa Aplikasi',
              subtitle: _selectedLanguage,
              onTap: () => _showLanguageDialog(context),
            ).animate().fadeIn(duration: 300.ms, delay: 400.ms),
            SizedBox(height: AppSpacing.xxl),
            // Account actions
            _buildSectionTitle('Akun')
                .animate()
                .fadeIn(duration: 300.ms, delay: 500.ms),
            SizedBox(height: AppSpacing.md),
            _buildActionTile(
              icon: Icons.psychology_rounded,
              title: 'Model AI Lokal',
              subtitle: 'Download dan kelola model AI on-device',
              iconColor: AppColors.primary,
              onTap: () => context.push('/ai-init'),
            ).animate().fadeIn(duration: 300.ms, delay: 600.ms),
            SizedBox(height: AppSpacing.sm),
            _buildActionTile(
              icon: Icons.swap_horiz_rounded,
              title: 'Ganti Persona',
              subtitle: 'Kembali ke pilihan Tuli atau Mendengar',
              iconColor: AppColors.accent,
              onTap: () => _switchPersona(context),
            ).animate().fadeIn(duration: 300.ms, delay: 650.ms),
            SizedBox(height: AppSpacing.sm),
            if (authState.isSignedIn)
              _buildActionTile(
                icon: Icons.logout_rounded,
                title: 'Keluar',
                subtitle: 'Keluar dari akun Google',
                iconColor: AppColors.error,
                onTap: () => _signOut(context),
              ).animate().fadeIn(duration: 300.ms, delay: 700.ms),
            SizedBox(height: AppSpacing.xxl),
            // About Section
            _buildSectionTitle('Tentang')
                .animate()
                .fadeIn(duration: 300.ms, delay: 800.ms),
            SizedBox(height: AppSpacing.md),
            _buildAboutCard()
                .animate()
                .fadeIn(duration: 300.ms, delay: 900.ms),
            SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 3,
        onTap: (index) => _handleNavTap(context, index),
      ),
    );
  }

  Widget _buildProfileCard(AuthState authState, UserPersona? persona) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: authState.photoUrl != null
                ? ClipOval(
                    child: Image.network(
                      authState.photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  )
                : Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
          ),
          SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authState.isSignedIn
                      ? authState.displayName
                      : 'Pengguna Tamu',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  authState.isSignedIn
                      ? authState.email ?? ''
                      : 'Belum masuk',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
                if (persona != null) ...[
                  SizedBox(height: 6),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      persona == UserPersona.tuli
                          ? 'Persona: Tuli'
                          : 'Persona: Mendengar',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!authState.isSignedIn)
            TextButton(
              onPressed: () => ref.read(authProvider.notifier).signIn(),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              ),
              child: Text(
                'Masuk',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 210,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/images/logo_full_kawanisyarat.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          // SizedBox(height: 16),
          // Text(
          //   'KawanIsyarat',
          //   style: GoogleFonts.plusJakartaSans(
          //     fontSize: 20,
          //     fontWeight: FontWeight.w700,
          //     color: AppColors.textPrimary,
          //   ),
          // ),
          SizedBox(height: 2),
          Text(
            'Versi 1.0.0',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Jembatan Komunikasi Inklusif antara pengguna Tuli dan Mendengar di Indonesia. Menggunakan BISINDO dengan pengenalan gestur real-time.',
            textAlign: TextAlign.center,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Dibuat untuk Inklusivitas',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  void _switchPersona(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
        title: Text(
          'Ganti Persona?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Kamu akan kembali ke halaman pemilihan persona.',
          style: GoogleFonts.beVietnamPro(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Batal',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(personaProvider.notifier).resetPersona();
              context.go('/persona');
            },
            child: Text(
              'Ganti',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _signOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
        title: Text(
          'Keluar?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Kamu akan keluar dari akun Google dan kembali ke halaman awal.',
          style: GoogleFonts.beVietnamPro(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Batal',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authProvider.notifier).signOut();
              ref.read(personaProvider.notifier).resetPersona();
              if (context.mounted) {
                context.go('/');
              }
            },
            child: Text(
              'Keluar',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
        title: Text(
          'Pilih Bahasa',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLanguageOption('Bahasa Indonesia', true),
            _buildLanguageOption('English', false),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption(String language, bool isAvailable) {
    return ListTile(
      title: Text(
        language,
        style: GoogleFonts.beVietnamPro(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: isAvailable
              ? AppColors.textPrimary
              : AppColors.textSecondary,
        ),
      ),
      trailing: _selectedLanguage == language
          ? Icon(Icons.check_circle_rounded,
              color: AppColors.primary, size: 22)
          : (isAvailable
              ? null
              : Text(
                  'Segera',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                )),
      onTap: isAvailable
          ? () {
              setState(() => _selectedLanguage = language);
              Navigator.pop(context);
            }
          : null,
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
        context.push('/learn');
        break;
      case 3:
        break; // Already on settings
    }
  }
}
