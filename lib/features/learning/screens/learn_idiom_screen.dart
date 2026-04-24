import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';
import '../../../core/services/gemma_service.dart';
import '../../../core/providers/ai_providers.dart';

// ─── State ───────────────────────────────────────────────────────────────────

class IdiomState {
  final String? selectedIdiom;
  final String? meaning;
  final String? explanation;
  final bool isProcessing;
  final bool isCustom; // true = hasil dari Gemma free-text

  const IdiomState({
    this.selectedIdiom,
    this.meaning,
    this.explanation,
    this.isProcessing = false,
    this.isCustom = false,
  });

  IdiomState copyWith({
    String? selectedIdiom,
    String? meaning,
    String? explanation,
    bool? isProcessing,
    bool? isCustom,
  }) {
    return IdiomState(
      selectedIdiom: selectedIdiom ?? this.selectedIdiom,
      meaning: meaning ?? meaning,
      explanation: explanation ?? explanation,
      isProcessing: isProcessing ?? this.isProcessing,
      isCustom: isCustom ?? this.isCustom,
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────

final idiomProvider =
    StateNotifierProvider<IdiomNotifier, IdiomState>((ref) {
  return IdiomNotifier(ref);
});

class IdiomNotifier extends StateNotifier<IdiomState> {
  IdiomNotifier(this._ref) : super(const IdiomState());

  final Ref _ref;
  final GemmaService _gemma = GemmaService();

  /// Pilih idiom dari daftar (data langsung dari constants — instant, tidak butuh AI).
  void selectPreset(Map<String, String> idiomData) {
    state = IdiomState(
      selectedIdiom: idiomData['idiom'],
      meaning: idiomData['meaning'],
      explanation: idiomData['explanation'],
      isCustom: false,
    );
  }

  /// Cari idiom custom via Gemma (untuk kata yang tidak ada di daftar preset).
  Future<void> searchCustom(String query) async {
    if (query.trim().isEmpty) return;

    state = IdiomState(
      selectedIdiom: query.trim(),
      isProcessing: true,
      isCustom: true,
    );

    final gemmaReady =
        _ref.read(modelsDownloadedProvider).valueOrNull ?? false;
    if (!gemmaReady || !_gemma.isLoaded) {
      state = IdiomState(
        selectedIdiom: query.trim(),
        meaning: 'Model AI belum siap.',
        explanation:
            'Buka Pengaturan → Model AI Lokal untuk memuat Gemma terlebih dahulu.',
        isCustom: true,
      );
      return;
    }

    try {
      final result = await _gemma.explainIdiom(query.trim());
      state = IdiomState(
        selectedIdiom: query.trim(),
        meaning: result.arti.isNotEmpty ? result.arti : '–',
        explanation: result.contoh.isNotEmpty ? result.contoh : null,
        isCustom: true,
      );
    } catch (e) {
      state = IdiomState(
        selectedIdiom: query.trim(),
        meaning: 'Gagal menganalisis idiom.',
        explanation: e.toString(),
        isCustom: true,
      );
    }
  }

  void clear() {
    state = const IdiomState();
  }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class LearnIdiomScreen extends ConsumerStatefulWidget {
  const LearnIdiomScreen({super.key});

  @override
  ConsumerState<LearnIdiomScreen> createState() => _LearnIdiomScreenState();
}

class _LearnIdiomScreenState extends ConsumerState<LearnIdiomScreen> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    ref.read(idiomProvider.notifier).searchCustom(q);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(idiomProvider);

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
          'Penerjemah Idiom',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: AppSpacing.lg),
            Text(
              'Pahami arti di balik kata',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ).animate().fadeIn(duration: 400.ms),
            SizedBox(height: 6),
            Text(
              'Pilih idiom di bawah atau ketik ungkapan yang ingin dipahami',
              style: GoogleFonts.beVietnamPro(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms),

            SizedBox(height: AppSpacing.xxl),

            // ── Free-text search (Gemma-powered) ──────────────────────────
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(
                    color: AppColors.outlineVariant.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _submit(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Ketik idiom atau ungkapan…',
                        hintStyle: GoogleFonts.beVietnamPro(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg, vertical: 14),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: AppColors.textSecondary, size: 20),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: TextButton(
                      onPressed: _submit,
                      style: TextButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.lg)),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Cari',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 150.ms),

            SizedBox(height: AppSpacing.xl),

            // ── Preset chips ───────────────────────────────────────────────
            Text(
              'CONTOH IDIOM',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 1.3,
              ),
            ),
            SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: BisindoData.idiomList.map((idiom) {
                final isSelected =
                    state.selectedIdiom == idiom['idiom'] && !state.isCustom;
                return _IdiomChip(
                  label: idiom['idiom']!,
                  isSelected: isSelected,
                  onTap: () {
                    _ctrl.clear();
                    ref.read(idiomProvider.notifier).selectPreset(idiom);
                  },
                );
              }).toList(),
            ).animate().fadeIn(duration: 500.ms, delay: 200.ms),

            SizedBox(height: AppSpacing.xxl),

            // ── Result ─────────────────────────────────────────────────────
            if (state.isProcessing) _buildProcessingCard(),
            if (!state.isProcessing && state.explanation != null)
              _buildResultCard(state)
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: 0.05, end: 0, duration: 500.ms),

            SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          SizedBox(width: 12),
          Text(
            'Gemma menganalisis idiom…',
            style: GoogleFonts.beVietnamPro(
                fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildResultCard(IdiomState state) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: AppColors.primary.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '"${state.selectedIdiom}"',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (state.isCustom)
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          size: 11, color: AppColors.primary),
                      SizedBox(width: 3),
                      Text(
                        'Gemma 4',
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(
              'Arti: ${state.meaning}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          SizedBox(height: AppSpacing.lg),
          Container(height: 1, color: AppColors.outlineVariant.withOpacity(0.3)),
          SizedBox(height: AppSpacing.lg),
          Text(
            state.isCustom ? 'CONTOH KALIMAT' : 'PENJELASAN',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            state.explanation!,
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              color: AppColors.textPrimary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chip ─────────────────────────────────────────────────────────────────────

class _IdiomChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _IdiomChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color:
              isSelected ? AppColors.primary : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.outlineVariant.withOpacity(0.4),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
