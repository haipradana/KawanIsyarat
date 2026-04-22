import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../app/constants.dart';
import '../../../core/services/tts_service.dart';

/// Emergency Quick-Sign — 1-tap audio broadcast untuk teman Tuli.
///
/// Saat teman Tuli butuh bantuan darurat (kecelakaan, tersesat, butuh
/// perhatian orang sekitar), mereka tidak bisa teriak. App ini jadi suara
/// pengganti: tap tombol → TTS speaker HP mengumumkan kebutuhan dengan
/// jelas ke orang sekitar.
///
/// Fitur offline — TTS native OS, tidak butuh AI atau internet.
class EmergencyQuickSignScreen extends StatefulWidget {
  const EmergencyQuickSignScreen({super.key});

  @override
  State<EmergencyQuickSignScreen> createState() =>
      _EmergencyQuickSignScreenState();
}

class _EmergencyQuickSignScreenState extends State<EmergencyQuickSignScreen> {
  final TtsService _tts = TtsService();
  String? _speakingId;

  static const _phrases = <_EmergencyPhrase>[
    _EmergencyPhrase(
      id: 'help',
      icon: Icons.priority_high_rounded,
      label: 'Saya butuh bantuan',
      utterance:
          'Mohon perhatiannya. Saya tuli. Saya butuh bantuan. Tolong bantu saya.',
      color: Color(0xFFBA1A1A),
    ),
    _EmergencyPhrase(
      id: 'medical',
      icon: Icons.local_hospital_rounded,
      label: 'Butuh pertolongan medis',
      utterance:
          'Saya tuli. Saya butuh pertolongan medis. Tolong panggilkan dokter atau ambulans.',
      color: Color(0xFFD32F2F),
    ),
    _EmergencyPhrase(
      id: 'lost',
      icon: Icons.location_off_rounded,
      label: 'Saya tersesat',
      utterance:
          'Saya tuli. Saya tersesat. Mohon bantu saya menemukan jalan atau hubungi keluarga saya.',
      color: Color(0xFFF57C00),
    ),
    _EmergencyPhrase(
      id: 'deaf_intro',
      icon: Icons.sign_language_rounded,
      label: 'Saya tuli, mohon pengertian',
      utterance:
          'Mohon maaf, saya tuli. Saya tidak bisa mendengar. Tolong bicara pelan atau tuliskan pesan Anda.',
      color: AppColors.primary,
    ),
    _EmergencyPhrase(
      id: 'police',
      icon: Icons.local_police_rounded,
      label: 'Butuh polisi',
      utterance:
          'Saya tuli. Saya butuh polisi. Tolong panggilkan petugas kepolisian.',
      color: Color(0xFF1565C0),
    ),
    _EmergencyPhrase(
      id: 'family',
      icon: Icons.family_restroom_rounded,
      label: 'Hubungi keluarga saya',
      utterance:
          'Saya tuli. Mohon bantuan untuk menghubungi keluarga saya. Nomor ada di kontak darurat ponsel ini.',
      color: Color(0xFF6A1B9A),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tts.init();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(_EmergencyPhrase p) async {
    setState(() => _speakingId = p.id);
    await _tts.stop();
    await _tts.speak(p.utterance);
    // Heuristic: utterance durasi ~50ms/char; minimal 2 detik
    final estMs = (p.utterance.length * 55).clamp(2000, 12000);
    await Future.delayed(Duration(milliseconds: estMs));
    if (mounted && _speakingId == p.id) {
      setState(() => _speakingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Darurat / SOS',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          physics: BouncingScrollPhysics(),
          padding: EdgeInsets.all(AppSpacing.xxl),
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFBA1A1A).withOpacity(0.10),
                    Color(0xFFF57C00).withOpacity(0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(
                    color: Color(0xFFBA1A1A).withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.campaign_rounded,
                      color: Color(0xFFBA1A1A), size: 28),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Suara untuk Teman Tuli',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tap kartu untuk mengumumkan kebutuhan kamu lewat speaker HP. Angkat HP ke atas supaya orang sekitar mendengar.',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12.5,
                            color: AppColors.textPrimary.withOpacity(0.72),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 350.ms),
            SizedBox(height: AppSpacing.xl),
            Text(
              'PILIH PESAN',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: AppSpacing.sm),
            ..._phrases.asMap().entries.map((e) {
              final i = e.key;
              final p = e.value;
              final speaking = _speakingId == p.id;
              return Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: _phraseCard(p, speaking: speaking)
                    .animate()
                    .fadeIn(
                        duration: 400.ms,
                        delay: Duration(milliseconds: 80 * i))
                    .slideY(begin: 0.05, end: 0),
              );
            }),
            SizedBox(height: AppSpacing.xl),
            Text(
              'Semua pesan diucapkan melalui speaker HP (offline, tanpa internet).',
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(
                fontSize: 11.5,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phraseCard(_EmergencyPhrase p, {required bool speaking}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _speak(p),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 250),
          padding: EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: speaking
                ? p.color.withOpacity(0.08)
                : AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(
              color: speaking
                  ? p.color.withOpacity(0.6)
                  : AppColors.outlineVariant.withOpacity(0.4),
              width: speaking ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: p.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(p.icon, color: p.color, size: 24),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.label,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      p.utterance,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Icon(
                speaking
                    ? Icons.graphic_eq_rounded
                    : Icons.volume_up_rounded,
                color: speaking ? p.color : AppColors.textSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmergencyPhrase {
  final String id;
  final IconData icon;
  final String label;
  final String utterance;
  final Color color;

  const _EmergencyPhrase({
    required this.id,
    required this.icon,
    required this.label,
    required this.utterance,
    required this.color,
  });
}
