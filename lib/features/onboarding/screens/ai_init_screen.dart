import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/providers/ai_providers.dart';

class AIInitScreen extends ConsumerStatefulWidget {
  const AIInitScreen({super.key});

  @override
  ConsumerState<AIInitScreen> createState() => _AIInitScreenState();
}

class _AIInitScreenState extends ConsumerState<AIInitScreen> {
  @override
  void initState() {
    super.initState();
    // Start initialization after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(aiInitProvider.notifier).initializeAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(aiInitProvider);

    // Auto-navigate when ready
    ref.listen<AIInitState>(aiInitProvider, (prev, next) {
      if (next.isComplete && !(prev?.isComplete ?? false)) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) context.go('/home');
        });
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Animated AI icon
              _buildAIIcon(aiState),
              const SizedBox(height: 40),

              // Title
              Text(
                'Mempersiapkan AI Lokal',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1),
              const SizedBox(height: 12),

              Text(
                'Ini hanya dilakukan sekali.\nSetelah ini, semua AI bekerja offline di perangkatmu.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  color: const Color(0xFF6B6B6B),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(duration: 500.ms, delay: 200.ms),
              const SizedBox(height: 48),

              // Progress section
              _buildProgressSection(aiState),
              const SizedBox(height: 24),

              // Status message
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  aiState.message,
                  key: ValueKey(aiState.message),
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: aiState.hasError
                        ? const Color(0xFFD32F2F)
                        : const Color(0xFF2A9D8F),
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const Spacer(flex: 1),

              // Error retry or skip button
              if (aiState.hasError) ...[
                _buildRetryButton(),
                const SizedBox(height: 12),
              ],
              _buildSkipButton(aiState),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAIIcon(AIInitState state) {
    final isWorking = state.isWorking;
    final isComplete = state.isComplete;
    final hasError = state.hasError;

    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: hasError
              ? [const Color(0xFFFFCDD2), const Color(0xFFEF9A9A)]
              : isComplete
                  ? [const Color(0xFFB2DFDB), const Color(0xFF80CBC4)]
                  : [const Color(0xFFE0F2F1), const Color(0xFFB2DFDB)],
        ),
        boxShadow: [
          BoxShadow(
            color: (hasError
                    ? const Color(0xFFEF9A9A)
                    : const Color(0xFF80CBC4))
                .withOpacity(0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(
        hasError
            ? Icons.error_outline_rounded
            : isComplete
                ? Icons.check_circle_outline_rounded
                : Icons.psychology_rounded,
        size: 56,
        color: hasError
            ? const Color(0xFFD32F2F)
            : const Color(0xFF2A9D8F),
      ),
    )
        .animate(
          onPlay: (controller) {
            if (isWorking) controller.repeat();
          },
        )
        .shimmer(
          duration: 2000.ms,
          color: Colors.white.withOpacity(0.3),
        )
        .animate()
        .scale(
          duration: 600.ms,
          curve: Curves.elasticOut,
        );
  }

  Widget _buildProgressSection(AIInitState state) {
    return Column(
      children: [
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: state.progress,
            minHeight: 8,
            backgroundColor: const Color(0xFFE0E0E0),
            valueColor: AlwaysStoppedAnimation<Color>(
              state.hasError
                  ? const Color(0xFFD32F2F)
                  : const Color(0xFF2A9D8F),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Progress percentage
        Text(
          '${(state.progress * 100).toInt()}%',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF2A9D8F),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 500.ms, delay: 400.ms);
  }

  Widget _buildRetryButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () => ref.read(aiInitProvider.notifier).retry(),
        icon: const Icon(Icons.refresh_rounded),
        label: Text(
          'Coba Lagi',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2A9D8F),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildSkipButton(AIInitState state) {
    if (state.isComplete) return const SizedBox.shrink();

    return TextButton(
      onPressed: () {
        ref.read(aiInitProvider.notifier).skip();
        context.go('/home');
      },
      child: Text(
        'Lewati (Mode Offline Dasar)',
        style: GoogleFonts.beVietnamPro(
          fontSize: 13,
          color: const Color(0xFF9E9E9E),
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
