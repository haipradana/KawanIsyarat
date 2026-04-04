import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';

// Provider
final artikulasiProvider =
    StateNotifierProvider<ArtikulasiNotifier, ArtikulasiState>((ref) {
  return ArtikulasiNotifier();
});

class ArtikulasiState {
  final int currentIndex;
  final bool isRecording;
  final bool isProcessing;
  final String? detectedWord;
  final String? feedback;
  final bool showResult;

  String get targetWord => BisindoData.artikulasiWords[currentIndex];

  ArtikulasiState({
    this.currentIndex = 0,
    this.isRecording = false,
    this.isProcessing = false,
    this.detectedWord,
    this.feedback,
    this.showResult = false,
  });
}

class ArtikulasiNotifier extends StateNotifier<ArtikulasiState> {
  ArtikulasiNotifier() : super(ArtikulasiState());

  void startRecording() {
    state = ArtikulasiState(
      currentIndex: state.currentIndex,
      isRecording: true,
    );
  }

  void stopRecording() {
    state = ArtikulasiState(
      currentIndex: state.currentIndex,
      isRecording: false,
      isProcessing: true,
    );
    // Simulate STT processing
    Future.delayed(Duration(milliseconds: 1200), () {
      if (mounted) {
        final target = state.targetWord;
        // Simulate slightly wrong detection
        final detected = _simulateDetection(target);
        final isCorrect = detected.toLowerCase() == target.toLowerCase();
        state = ArtikulasiState(
          currentIndex: state.currentIndex,
          detectedWord: detected,
          feedback: isCorrect
              ? 'Pengucapanmu sudah tepat. Lanjutkan ke kata berikutnya.'
              : 'Kata yang terdengar adalah "$detected". Coba ucapkan lebih pelan dan jelas. Perhatikan penekanan pada suku kata pertama.',
          showResult: true,
        );
      }
    });
  }

  String _simulateDetection(String target) {
    // Simulate occasional misdetection
    final variants = {
      'Bapak': 'Papak',
      'Terima kasih': 'Trima kasih',
      'Selamat pagi': 'Slamat pagi',
    };
    return variants[target] ?? target;
  }

  void nextWord() {
    final next = (state.currentIndex + 1) % BisindoData.artikulasiWords.length;
    state = ArtikulasiState(currentIndex: next);
  }
}

class LearnArtikulasiScreen extends ConsumerWidget {
  const LearnArtikulasiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(artikulasiProvider);

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
          'Latihan Artikulasi',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: AppSpacing.lg),
            // Progress
            Text(
              'KATA ${state.currentIndex + 1}/${BisindoData.artikulasiWords.length}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 1.5,
              ),
            ).animate().fadeIn(duration: 300.ms),
            SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                value: (state.currentIndex + 1) /
                    BisindoData.artikulasiWords.length,
                backgroundColor: AppColors.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                minHeight: 6,
              ),
            ),
            SizedBox(height: AppSpacing.xxxl),
            // Target word
            Center(
              child: Column(
                children: [
                  Text(
                    'Ucapkan kata ini:',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: AppSpacing.md),
                  Text(
                    state.targetWord,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
            Spacer(),
            // Result
            if (state.isProcessing)
              Center(
                child: Column(
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.accent),
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Menganalisis pengucapan...',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),
            if (state.showResult && state.feedback != null)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: state.detectedWord?.toLowerCase() ==
                          state.targetWord.toLowerCase()
                      ? AppColors.success.withOpacity(0.08)
                      : AppColors.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppRadius.xxl),
                  border: Border.all(
                    color: state.detectedWord?.toLowerCase() ==
                            state.targetWord.toLowerCase()
                        ? AppColors.success.withOpacity(0.2)
                        : AppColors.accent.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          state.detectedWord?.toLowerCase() ==
                                  state.targetWord.toLowerCase()
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                          size: 20,
                          color: state.detectedWord?.toLowerCase() ==
                                  state.targetWord.toLowerCase()
                              ? AppColors.success
                              : AppColors.accent,
                        ),
                        SizedBox(width: 8),
                        Text(
                          state.detectedWord?.toLowerCase() ==
                                  state.targetWord.toLowerCase()
                              ? 'Tepat!'
                              : 'Hampir benar',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: state.detectedWord?.toLowerCase() ==
                                    state.targetWord.toLowerCase()
                                ? AppColors.success
                                : AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.md),
                    Text(
                      state.feedback!,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(
                    begin: 0.05, end: 0, duration: 400.ms,
                  ),
            SizedBox(height: AppSpacing.xxl),
            // Mic button / Next button
            if (state.showResult)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      ref.read(artikulasiProvider.notifier).nextWord(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                  child: Text(
                    'Kata Berikutnya',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 300.ms)
            else if (!state.isProcessing)
              _MicButton(
                isRecording: state.isRecording,
                onStart: () =>
                    ref.read(artikulasiProvider.notifier).startRecording(),
                onStop: () =>
                    ref.read(artikulasiProvider.notifier).stopRecording(),
              ),
            SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _MicButton({
    required this.isRecording,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTapDown: (_) => onStart(),
        onTapUp: (_) => onStop(),
        onTapCancel: onStop,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          width: isRecording ? 88 : 80,
          height: isRecording ? 88 : 80,
          decoration: BoxDecoration(
            color: isRecording ? AppColors.error : AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (isRecording ? AppColors.error : AppColors.primary)
                    .withOpacity(0.3),
                blurRadius: isRecording ? 24 : 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            Icons.mic_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 200.ms);
  }
}
