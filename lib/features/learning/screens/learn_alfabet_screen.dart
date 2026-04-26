import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';
import '../../../core/services/sibi_alphabet_service.dart';
import '../../../core/services/bisindo_alphabet_service.dart';
import '../../../core/providers/learning_progress_provider.dart';
import 'alphabet_practice_screen.dart';
import '../widgets/alphabet_reference_image.dart';


class LearnAlfabetScreen extends ConsumerStatefulWidget {
  /// Optional fixed mode. If provided, the mode toggle is hidden and
  /// the screen starts directly in that mode.
  final AlphabetMode? initialMode;

  const LearnAlfabetScreen({super.key, this.initialMode});

  @override
  ConsumerState<LearnAlfabetScreen> createState() => _LearnAlfabetScreenState();
}

class _LearnAlfabetScreenState extends ConsumerState<LearnAlfabetScreen> {
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

  String get _currentModuleKey => _mode == AlphabetMode.sibi
      ? LearningModule.alfabetSibi
      : LearningModule.alfabetBisindo;

  Widget _buildProgressSummary() {
    final progress = ref.watch(learningProgressProvider);
    final done = progress.countFor(_currentModuleKey);
    final total = LearningModule.totalFor(_currentModuleKey);
    final ratio = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Container(
      padding: EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_rounded,
                  color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Progres $_modeName',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Spacer(),
              Text(
                '$done / $total selesai',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              if (done > 0) ...[
                SizedBox(width: 8),
                InkWell(
                  onTap: () => _confirmResetModule(),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  child: Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Icon(Icons.restart_alt_rounded,
                        size: 16, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmResetModule() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xxl)),
        title: Text('Reset Progres $_modeName?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text(
          'Semua huruf yang sudah selesai akan dihapus dari daftar.',
          style: GoogleFonts.beVietnamPro(
              fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref
                  .read(learningProgressProvider.notifier)
                  .resetModule(_currentModuleKey);
            },
            child: Text('Reset',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700, color: AppColors.error)),
          ),
        ],
      ),
    );
  }

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

            // ── Progress bar ────────────────────────────────────────────
            _buildProgressSummary(),

            SizedBox(height: AppSpacing.lg),

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
                final progress = ref.watch(learningProgressProvider);
                final isDone =
                    progress.isDone(_currentModuleKey, letter.toUpperCase());
                return _LetterTile(
                  // Force rebuild on mode change so animation re-runs
                  key: ValueKey('${_mode.name}-$letter'),
                  letter: letter,
                  isSelected: isSelected,
                  isDone: isDone,
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

  String get _fullChartAsset => _mode == AlphabetMode.sibi
      ? 'assets/images/alfabet/alfabet_sibi_full.jpg'
      : 'assets/images/alfabet/alfabet_bisindo_full.jpg';

  void _showFullChart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FullChartSheet(
        assetPath: _fullChartAsset,
        title: 'Abjad $_modeName Lengkap',
      ),
    );
  }

  Widget _buildModeInfoCard() {
    return GestureDetector(
      onTap: _showFullChart,
      child: Container(
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
            const SizedBox(width: 8),
            // Hint: tap to see full chart
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.grid_view_rounded,
                    size: 16, color: AppColors.primary.withOpacity(0.7)),
                const SizedBox(height: 2),
                Text(
                  'Lihat\nsemua',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 9,
                    color: AppColors.primary.withOpacity(0.7),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ],
        ),
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

          // Reference image (auto fallback ke placeholder kalau asset belum ada)
          AlphabetReferenceImage(
            letter: letter,
            mode: _mode,
            height: 200,
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
  final bool isDone;
  final int delay;
  final VoidCallback onTap;

  const _LetterTile({
    super.key,
    required this.letter,
    required this.isSelected,
    required this.isDone,
    required this.delay,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? AppColors.primary
        : (isDone
            ? AppColors.success.withOpacity(0.5)
            : AppColors.outlineVariant.withOpacity(0.3));
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (isDone
                  ? AppColors.success.withOpacity(0.08)
                  : AppColors.surfaceContainerLow),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: borderColor, width: 1),
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
        child: Stack(
          children: [
            Center(
              child: Text(
                letter,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? Colors.white
                      : (isDone
                          ? AppColors.success
                          : AppColors.textPrimary),
                ),
              ),
            ),
            if (isDone)
              Positioned(
                top: 3,
                right: 3,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 13,
                  color: isSelected ? Colors.white : AppColors.success,
                ),
              ),
          ],
        ),
      ),
    ).animate().fadeIn(
          duration: 280.ms,
          delay: Duration(milliseconds: delay),
        );
  }
}

// ─── Full Alphabet Chart Bottom Sheet ─────────────────────────────────────────

class _FullChartSheet extends StatelessWidget {
  final String assetPath;
  final String title;

  const _FullChartSheet({
    required this.assetPath,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title + close
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded,
                      color: AppColors.textSecondary),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surfaceContainerHigh,
                    shape: const CircleBorder(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Zoomable image
          Expanded(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5.0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Image.asset(
                  assetPath,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image_rounded,
                            size: 64, color: AppColors.outlineVariant),
                        const SizedBox(height: 12),
                        Text(
                          'Gambar tidak tersedia',
                          style: GoogleFonts.beVietnamPro(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Hint text
          Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 16),
            child: Text(
              'Cubit untuk zoom • Geser untuk tutup',
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                color: AppColors.outlineVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
