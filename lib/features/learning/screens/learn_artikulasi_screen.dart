import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import '../../../app/constants.dart';
import '../../../core/services/gemma_service.dart';
import '../../../core/providers/ai_providers.dart';

// ─── State ───────────────────────────────────────────────────────────────────

class ArtikulasiState {
  final int currentIndex;
  final bool isRecording;
  final bool isProcessing;
  final String? detectedWord;
  final String? feedback;
  final bool showResult;
  final bool isCorrect;
  final String? errorMessage;

  String get targetWord => BisindoData.artikulasiWords[currentIndex];

  const ArtikulasiState({
    this.currentIndex = 0,
    this.isRecording = false,
    this.isProcessing = false,
    this.detectedWord,
    this.feedback,
    this.showResult = false,
    this.isCorrect = false,
    this.errorMessage,
  });

  ArtikulasiState copyWith({
    int? currentIndex,
    bool? isRecording,
    bool? isProcessing,
    String? detectedWord,
    String? feedback,
    bool? showResult,
    bool? isCorrect,
    String? errorMessage,
  }) {
    return ArtikulasiState(
      currentIndex: currentIndex ?? this.currentIndex,
      isRecording: isRecording ?? this.isRecording,
      isProcessing: isProcessing ?? this.isProcessing,
      detectedWord: detectedWord ?? this.detectedWord,
      feedback: feedback ?? this.feedback,
      showResult: showResult ?? this.showResult,
      isCorrect: isCorrect ?? this.isCorrect,
      errorMessage: errorMessage,
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────

final artikulasiProvider =
    StateNotifierProvider<ArtikulasiNotifier, ArtikulasiState>((ref) {
  return ArtikulasiNotifier(ref);
});

class ArtikulasiNotifier extends StateNotifier<ArtikulasiState> {
  ArtikulasiNotifier(this._ref) : super(const ArtikulasiState());

  final Ref _ref;
  final AudioRecorder _recorder = AudioRecorder();
  final GemmaService _gemma = GemmaService();
  String? _recordingPath;

  Future<void> startRecording() async {
    state = state.copyWith(
      isRecording: true,
      showResult: false,
      detectedWord: null,
      feedback: null,
      errorMessage: null,
    );
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        state = state.copyWith(
          isRecording: false,
          errorMessage: 'Izin mikrofon ditolak.',
        );
        return;
      }
      final tempDir = await getTemporaryDirectory();
      _recordingPath = '${tempDir.path}/artikulasi_rec.wav';
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
        ),
        path: _recordingPath!,
      );
    } catch (e) {
      state = state.copyWith(
        isRecording: false,
        errorMessage: 'Gagal mulai rekam: $e',
      );
    }
  }

  Future<void> stopRecording() async {
    if (!state.isRecording) return;
    state = state.copyWith(isRecording: false, isProcessing: true);

    try {
      final path = await _recorder.stop();
      final audioPath = path ?? _recordingPath;
      if (audioPath == null) {
        state = state.copyWith(
            isProcessing: false, errorMessage: 'Rekaman tidak tersimpan.');
        return;
      }

      final file = File(audioPath);
      if (!await file.exists()) {
        state = state.copyWith(
            isProcessing: false, errorMessage: 'File rekaman tidak ditemukan.');
        return;
      }

      // Cek Gemma loaded
      final gemmaReady = _ref.read(modelsDownloadedProvider).valueOrNull ?? false;
      if (!gemmaReady || !_gemma.isLoaded) {
        state = state.copyWith(
            isProcessing: false,
            errorMessage: 'Model AI belum siap. Buka Pengaturan → Model AI Lokal.');
        return;
      }

      // Baca audio → strip WAV header → Gemma transcribe
      final rawBytes = await file.readAsBytes();
      Uint8List pcmData =
          rawBytes.length > 44 ? rawBytes.sublist(44) : rawBytes;

      // OOM guard (sama seperti Hearing→Deaf pipeline)
      const pcmSafeLimit = 256 * 1024;
      if (pcmData.length > pcmSafeLimit) {
        pcmData = _downsample(pcmData);
      }

      final transcription = await _gemma.transcribeAudio(pcmData);
      final detected = transcription.trim();

      if (detected.isEmpty) {
        state = state.copyWith(
          isProcessing: false,
          showResult: true,
          detectedWord: '(tidak terdeteksi)',
          isCorrect: false,
          feedback:
              'Suara tidak terdeteksi. Pastikan berbicara cukup keras dan dekat mikrofon.',
        );
        return;
      }

      final target = state.targetWord;
      final correct =
          detected.toLowerCase().contains(target.toLowerCase()) ||
          target.toLowerCase().contains(detected.toLowerCase());

      // Gemma beri feedback
      final feedback = await _gemma.feedbackArtikulasi(target, detected);

      state = state.copyWith(
        isProcessing: false,
        detectedWord: detected,
        feedback: feedback,
        showResult: true,
        isCorrect: correct,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Error saat memproses: $e',
      );
    }
  }

  void nextWord() {
    final next =
        (state.currentIndex + 1) % BisindoData.artikulasiWords.length;
    state = ArtikulasiState(currentIndex: next);
  }

  void retry() {
    state = state.copyWith(
      showResult: false,
      detectedWord: null,
      feedback: null,
      errorMessage: null,
    );
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Uint8List _downsample(Uint8List pcm) {
    final bd = ByteData.sublistView(pcm);
    final inSamples = pcm.length ~/ 2;
    final outSamples = inSamples ~/ 2;
    final out = ByteData(outSamples * 2);
    for (int i = 0; i < outSamples; i++) {
      final s1 = bd.getInt16(i * 4, Endian.little);
      final s2 = bd.getInt16(i * 4 + 2, Endian.little);
      out.setInt16(i * 2, ((s1 + s2) >> 1).clamp(-32768, 32767), Endian.little);
    }
    return out.buffer.asUint8List();
  }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

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
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.accent),
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
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (state.isRecording) ...[
                    SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: AppColors.error, shape: BoxShape.circle),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Sedang merekam…',
                          style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              color: AppColors.error,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms),

            Spacer(),

            // Error
            if (state.errorMessage != null)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(AppSpacing.md),
                margin: EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.error.withOpacity(0.25)),
                ),
                child: Text(
                  state.errorMessage!,
                  style: GoogleFonts.beVietnamPro(
                      fontSize: 13, color: AppColors.error),
                ),
              ).animate().fadeIn(duration: 300.ms),

            // Processing
            if (state.isProcessing)
              Center(
                child: Column(
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.accent),
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'AI menganalisis pengucapan…',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),

            // Result card
            if (state.showResult && state.feedback != null)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: state.isCorrect
                      ? AppColors.success.withOpacity(0.08)
                      : AppColors.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppRadius.xxl),
                  border: Border.all(
                    color: state.isCorrect
                        ? AppColors.success.withOpacity(0.25)
                        : AppColors.accent.withOpacity(0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          state.isCorrect
                              ? Icons.check_circle_rounded
                              : Icons.record_voice_over_rounded,
                          size: 20,
                          color: state.isCorrect
                              ? AppColors.success
                              : AppColors.accent,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.isCorrect
                                ? 'Pengucapan tepat!'
                                : 'Terdengar: "${state.detectedWord}"',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: state.isCorrect
                                  ? AppColors.success
                                  : AppColors.accent,
                            ),
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
                    begin: 0.05, end: 0, duration: 400.ms),

            SizedBox(height: AppSpacing.xxl),

            // Buttons
            if (state.showResult)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(artikulasiProvider.notifier).retry(),
                      icon: Icon(Icons.refresh_rounded, size: 18),
                      label: Text('Coba Lagi',
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                            color: AppColors.primary.withOpacity(0.4)),
                        padding: EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.full)),
                      ),
                    ),
                  ),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          ref.read(artikulasiProvider.notifier).nextWord(),
                      icon: Icon(Icons.arrow_forward_rounded, size: 18),
                      label: Text('Kata Berikutnya',
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.full)),
                      ),
                    ),
                  ),
                ],
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

// ─── Mic Button ──────────────────────────────────────────────────────────────

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
      child: Column(
        children: [
          GestureDetector(
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
                        .withOpacity(0.35),
                    blurRadius: isRecording ? 24 : 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(Icons.mic_rounded, color: Colors.white, size: 32),
            ),
          ),
          SizedBox(height: 10),
          Text(
            isRecording ? 'Lepas untuk berhenti' : 'Tahan untuk bicara',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 200.ms);
  }
}
