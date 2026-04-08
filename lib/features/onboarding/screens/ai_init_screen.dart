import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/constants.dart';
import '../../../core/providers/ai_providers.dart';
import '../../../core/services/model_manager.dart';

class AIInitScreen extends ConsumerStatefulWidget {
  const AIInitScreen({super.key});

  @override
  ConsumerState<AIInitScreen> createState() => _AIInitScreenState();
}

class _AIInitScreenState extends ConsumerState<AIInitScreen> {
  bool _llmReady = false;
  bool _sttReady = false;
  bool _checkingStatus = true;

  @override
  void initState() {
    super.initState();
    // Reset state so users can re-enter this page after skipping
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(aiInitProvider.notifier).resetForReentry();
    });
    _checkModelStatus();
  }

  Future<void> _checkModelStatus() async {
    final mm = ModelManager();
    final llm = await mm.isModelReady(ModelType.gemmaLLM);
    final stt = await mm.isModelReady(ModelType.whisperSTT);
    if (mounted) {
      setState(() {
        _llmReady = llm;
        _sttReady = stt;
        _checkingStatus = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(aiInitProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () {
            if (Navigator.canPop(context)) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: Text(
          'Model AI Lokal',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: _checkingStatus
          ? Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SingleChildScrollView(
              physics: BouncingScrollPhysics(),
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  _buildHeader().animate().fadeIn(duration: 400.ms),
                  SizedBox(height: AppSpacing.xxl),

                  // Model cards
                  _buildModelCard(
                    model: ModelType.gemmaLLM,
                    icon: Icons.psychology_rounded,
                    name: 'Gemma 4 E2B (Cactus INT4)',
                    desc: 'Model AI bahasa via Cactus SDK. Terjemahkan gloss isyarat & hasilkan saran empatik.',
                    size: '~4 GB',
                    isReady: _llmReady,
                    aiState: aiState,
                    phaseMatch: [
                      AIInitStatus.downloadingLLM,
                      AIInitStatus.loadingLLM,
                    ],
                  ).animate().fadeIn(duration: 400.ms, delay: 100.ms),

                  SizedBox(height: AppSpacing.lg),

                  _buildModelCard(
                    model: ModelType.whisperSTT,
                    icon: Icons.mic_rounded,
                    name: 'Whisper Tiny ID',
                    desc: 'Model speech-to-text untuk transkripsi bahasa Indonesia secara offline.',
                    size: '~200 MB',
                    isReady: _sttReady,
                    aiState: aiState,
                    phaseMatch: [
                      AIInitStatus.downloadingSTT,
                      AIInitStatus.loadingSTT,
                    ],
                  ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

                  SizedBox(height: AppSpacing.xxxl),

                  // Overall progress (during download)
                  if (aiState.isWorking) ...[
                    _buildProgressSection(aiState)
                        .animate()
                        .fadeIn(duration: 300.ms),
                    SizedBox(height: AppSpacing.xxl),
                  ],

                  // Error display
                  if (aiState.hasError) ...[
                    _buildErrorCard(aiState)
                        .animate()
                        .fadeIn(duration: 300.ms)
                        .shake(duration: 400.ms, hz: 3, offset: Offset(2, 0)),
                    SizedBox(height: AppSpacing.lg),
                  ],

                  // Action buttons
                  if (!aiState.isWorking && !aiState.isComplete)
                    _buildActionButtons(aiState)
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 300.ms),

                  if (aiState.isComplete)
                    _buildCompleteSection()
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .scale(begin: Offset(0.95, 0.95), duration: 400.ms),

                  SizedBox(height: AppSpacing.xxxl),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI On-Device',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Download model AI agar semua fitur bekerja offline di perangkatmu. Proses ini hanya dilakukan sekali.',
          style: GoogleFonts.beVietnamPro(
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        SizedBox(height: AppSpacing.md),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.warning.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.wifi_rounded, color: AppColors.warning, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pastikan terhubung ke WiFi. Total download ~4.2 GB.',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: AppColors.warning,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModelCard({
    required ModelType model,
    required IconData icon,
    required String name,
    required String desc,
    required String size,
    required bool isReady,
    required AIInitState aiState,
    required List<AIInitStatus> phaseMatch,
  }) {
    final isThisPhase = phaseMatch.contains(aiState.status);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: isReady
              ? AppColors.success.withOpacity(0.3)
              : isThisPhase
                  ? AppColors.primary.withOpacity(0.3)
                  : AppColors.outlineVariant.withOpacity(0.2),
          width: isReady || isThisPhase ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isReady
                      ? AppColors.success.withOpacity(0.1)
                      : AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: isReady ? AppColors.success : AppColors.primary,
                  size: 24,
                ),
              ),
              SizedBox(width: AppSpacing.lg),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      size,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isReady
                      ? AppColors.success.withOpacity(0.1)
                      : isThisPhase
                          ? AppColors.primary.withOpacity(0.1)
                          : AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isThisPhase)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                    if (isThisPhase) SizedBox(width: 6),
                    if (isReady)
                      Icon(Icons.check_circle_rounded,
                          color: AppColors.success, size: 14),
                    if (isReady) SizedBox(width: 4),
                    Text(
                      isReady
                          ? 'Siap'
                          : isThisPhase
                              ? 'Memproses...'
                              : 'Belum diunduh',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isReady
                            ? AppColors.success
                            : isThisPhase
                                ? AppColors.primary
                                : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          Text(
            desc,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          // Phase progress bar
          if (isThisPhase) ...[
            SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: aiState.progress,
                minHeight: 4,
                backgroundColor: AppColors.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            SizedBox(height: 6),
            Text(
              aiState.message,
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                color: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressSection(AIInitState state) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progress Keseluruhan',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${(state.progress * 100).toInt()}%',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: 10,
              backgroundColor: AppColors.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          SizedBox(height: AppSpacing.md),
          Text(
            state.message,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(AIInitState state) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 32),
          SizedBox(height: AppSpacing.md),
          Text(
            state.message,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            ),
            textAlign: TextAlign.center,
          ),
          if (state.error != null) ...[
            SizedBox(height: 6),
            Text(
              state.error!,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: AppColors.error.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => ref.read(aiInitProvider.notifier).retry(),
              icon: Icon(Icons.refresh_rounded, size: 20),
              label: Text(
                'Coba Lagi',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(AIInitState state) {
    final allReady = _llmReady && _sttReady;

    return Column(
      children: [
        // Download button
        if (!allReady)
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () {
                ref.read(aiInitProvider.notifier).initializeAll();
              },
              icon: Icon(Icons.download_rounded, size: 22),
              label: Text(
                'Download & Muat Semua Model',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                elevation: 0,
              ),
            ),
          ),

        if (allReady)
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () {
                ref.read(aiInitProvider.notifier).initializeAll();
              },
              icon: Icon(Icons.memory_rounded, size: 22),
              label: Text(
                'Muat Model ke Memori',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                elevation: 0,
              ),
            ),
          ),

        SizedBox(height: AppSpacing.lg),

        // Skip button
        TextButton(
          onPressed: () {
            ref.read(aiInitProvider.notifier).skip();
            context.go('/home');
          },
          child: Text(
            'Lewati — Gunakan Mode Dasar',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: AppColors.textSecondary,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.textSecondary.withOpacity(0.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompleteSection() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 48),
          SizedBox(height: AppSpacing.lg),
          Text(
            'AI Siap Digunakan! 🎉',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Semua model sudah dimuat. Fitur AI bekerja sepenuhnya offline.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => context.go('/home'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                elevation: 0,
              ),
              child: Text(
                'Mulai Gunakan KawanIsyarat',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
