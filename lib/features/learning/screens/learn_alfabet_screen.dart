import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';
import '../../../core/services/sibi_alphabet_service.dart';
import '../../../core/services/bisindo_alphabet_service.dart';
import 'alphabet_practice_screen.dart';


class LearnAlfabetScreen extends StatefulWidget {
  /// Optional fixed mode. If provided, the mode toggle is hidden and
  /// the screen starts directly in that mode.
  final AlphabetMode? initialMode;

  const LearnAlfabetScreen({super.key, this.initialMode});

  @override
  State<LearnAlfabetScreen> createState() => _LearnAlfabetScreenState();
}

class _LearnAlfabetScreenState extends State<LearnAlfabetScreen> {
  String? _selectedLetter;
  late AlphabetMode _mode;

  List<String> get _letters => _mode == AlphabetMode.sibi
      ? SibiAlphabetService.supportedLetters
      : BisindoAlphabetService.supportedLetters;

  String get _modeName => _mode == AlphabetMode.sibi ? 'SIBI' : 'BISINDO';

  String get _modeDescription => _mode == AlphabetMode.sibi
      ? 'Sistem Isyarat Bahasa Indonesia (SIBI) — alfabet dengan 1 tangan. '
          'Mendukung 24 huruf statis (J & Z butuh gerakan, belum tersedia).'
      : 'Bahasa Isyarat Indonesia (BISINDO) — alfabet dengan 2 tangan. '
          'Lebih natural dan banyak digunakan komunitas Tuli Indonesia. '
          'Saat ini mendukung A-V.';

  String get _modeHandsBadge =>
      _mode == AlphabetMode.sibi ? '1 tangan' : '2 tangan';

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ?? AlphabetMode.sibi;
  }

  bool get _fixedMode => widget.initialMode != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _fixedMode
              ? 'Alfabet $_modeName'
              : 'Alfabet Isyarat',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Mode toggle SIBI / BISINDO (only when not fixed) ──────────
            if (!_fixedMode) ...[
              _buildModeToggle()
                  .animate()
                  .fadeIn(duration: 350.ms),
              SizedBox(height: AppSpacing.lg),
            ],

            // ── Mode info card ──────────────────────────────────────────
            _buildModeInfoCard()
                .animate()
                .fadeIn(duration: 350.ms, delay: 60.ms),

            SizedBox(height: AppSpacing.xxl),

            // ── Letter grid ─────────────────────────────────────────────
            Text(
              'Pilih huruf untuk dipelajari',
              style: GoogleFonts.beVietnamPro(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: AppSpacing.md),

            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.0,
              ),
              itemCount: _letters.length,
              itemBuilder: (context, index) {
                final letter = _letters[index];
                final isSelected = _selectedLetter == letter;
                return _LetterTile(
                  // Force rebuild on mode change so animation re-runs
                  key: ValueKey('${_mode.name}-$letter'),
                  letter: letter,
                  isSelected: isSelected,
                  delay: index * 20,
                  onTap: () {
                    setState(() => _selectedLetter = letter);
                  },
                );
              },
            ),

            SizedBox(height: AppSpacing.xxxl),

            // ── Detail section ─────────────────────────────────────────
            if (_selectedLetter != null) ...[
              _buildLetterDetail(_selectedLetter!)
                  .animate(key: ValueKey('${_mode.name}-${_selectedLetter!}'))
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.05, end: 0, duration: 400.ms),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Mode Toggle ───────────────────────────────────────────────────────────

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _modeTab(
            label: 'SIBI',
            sublabel: '1 tangan',
            icon: Icons.front_hand_rounded,
            isActive: _mode == AlphabetMode.sibi,
            onTap: () => _switchMode(AlphabetMode.sibi),
          ),
          _modeTab(
            label: 'BISINDO',
            sublabel: '2 tangan',
            icon: Icons.sign_language_rounded,
            isActive: _mode == AlphabetMode.bisindo,
            onTap: () => _switchMode(AlphabetMode.bisindo),
          ),
        ],
      ),
    );
  }

  void _switchMode(AlphabetMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _selectedLetter = null; // reset selection when switching mode
    });
  }

  Widget _modeTab({
    required String label,
    required String sublabel,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isActive ? Colors.white : AppColors.textPrimary,
                      letterSpacing: 0.6,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: isActive
                          ? Colors.white.withOpacity(0.85)
                          : AppColors.textSecondary,
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

  // ─── Mode info card ────────────────────────────────────────────────────────

  Widget _buildModeInfoCard() {
    return Container(
      key: ValueKey(_mode),
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.10),
            AppColors.primary.withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.18),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _mode == AlphabetMode.sibi
                ? Icons.info_outline_rounded
                : Icons.lightbulb_outline_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _modeName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _modeHandsBadge,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _modeDescription,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Letter Detail ─────────────────────────────────────────────────────────

  Widget _buildLetterDetail(String letter) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.12),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Mode tag + huruf besar
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$_modeName • $_modeHandsBadge',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          Text(
            letter,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 72,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
              height: 1.0,
            ),
          ),
          SizedBox(height: AppSpacing.lg),

          // Reference placeholder
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _mode == AlphabetMode.sibi
                      ? Icons.front_hand_rounded
                      : Icons.sign_language_rounded,
                  size: 56,
                  color: AppColors.outlineVariant,
                ),
                SizedBox(height: AppSpacing.sm),
                Text(
                  'Isyarat huruf "$letter"',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _mode == AlphabetMode.sibi
                      ? 'Gunakan 1 tangan'
                      : 'Gunakan 2 tangan',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    color: AppColors.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.xl),

          // Practice button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AlphabetPracticeScreen(
                      targetLetter: letter,
                      mode: _mode,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.videocam_rounded, size: 20),
              label: Text(
                'Praktik dengan Kamera',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LetterTile extends StatelessWidget {
  final String letter;
  final bool isSelected;
  final int delay;
  final VoidCallback onTap;

  const _LetterTile({
    super.key,
    required this.letter,
    required this.isSelected,
    required this.delay,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.outlineVariant.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            letter,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    ).animate().fadeIn(
          duration: 280.ms,
          delay: Duration(milliseconds: delay),
        );
  }
}
