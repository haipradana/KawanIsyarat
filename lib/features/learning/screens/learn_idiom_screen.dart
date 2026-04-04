import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';

// Provider
final idiomProvider = StateNotifierProvider<IdiomNotifier, IdiomState>((ref) {
  return IdiomNotifier();
});

class IdiomState {
  final String query;
  final String? selectedIdiom;
  final String? meaning;
  final String? explanation;
  final bool isProcessing;

  IdiomState({
    this.query = '',
    this.selectedIdiom,
    this.meaning,
    this.explanation,
    this.isProcessing = false,
  });

  IdiomState copyWith({
    String? query,
    String? selectedIdiom,
    String? meaning,
    String? explanation,
    bool? isProcessing,
  }) {
    return IdiomState(
      query: query ?? this.query,
      selectedIdiom: selectedIdiom ?? this.selectedIdiom,
      meaning: meaning ?? this.meaning,
      explanation: explanation ?? this.explanation,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }
}

class IdiomNotifier extends StateNotifier<IdiomState> {
  IdiomNotifier() : super(IdiomState());

  void selectIdiom(Map<String, String> idiomData) {
    state = IdiomState(
      isProcessing: true,
      selectedIdiom: idiomData['idiom'],
    );
    // Simulate AI processing
    Future.delayed(Duration(milliseconds: 800), () {
      if (mounted) {
        state = state.copyWith(
          isProcessing: false,
          meaning: idiomData['meaning'],
          explanation: idiomData['explanation'],
        );
      }
    });
  }

  void searchIdiom(String query) {
    state = state.copyWith(query: query);
  }

  void clear() {
    state = IdiomState();
  }
}

class LearnIdiomScreen extends ConsumerWidget {
  const LearnIdiomScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              'Pilih idiom di bawah atau ketik kalimat yang ingin kamu pahami',
              style: GoogleFonts.beVietnamPro(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
            SizedBox(height: AppSpacing.xxl),
            // Idiom chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: BisindoData.idiomList.asMap().entries.map((entry) {
                final idiom = entry.value;
                final isSelected = state.selectedIdiom == idiom['idiom'];
                return _IdiomChip(
                  label: idiom['idiom']!,
                  isSelected: isSelected,
                  onTap: () =>
                      ref.read(idiomProvider.notifier).selectIdiom(idiom),
                );
              }).toList(),
            ).animate().fadeIn(duration: 500.ms, delay: 200.ms),
            SizedBox(height: AppSpacing.xxl),
            // Result card
            if (state.isProcessing)
              _buildProcessingCard()
                  .animate()
                  .fadeIn(duration: 300.ms),
            if (!state.isProcessing && state.explanation != null)
              _buildResultCard(state)
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: 0.05, end: 0, duration: 500.ms),
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
            'Menganalisis idiom...',
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(IdiomState state) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Idiom title
          Text(
            '"${state.selectedIdiom}"',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: AppSpacing.md),
          // Meaning badge
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
          // Divider
          Container(
            height: 1,
            color: AppColors.outlineVariant.withOpacity(0.3),
          ),
          SizedBox(height: AppSpacing.lg),
          // Explanation
          Text(
            'PENJELASAN',
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
          color: isSelected ? AppColors.primary : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.outlineVariant.withOpacity(0.4),
            width: 1,
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
