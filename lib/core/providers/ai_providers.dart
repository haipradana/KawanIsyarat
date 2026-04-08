import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/model_manager.dart';
import '../services/gemma_service.dart';
import '../services/stt_service.dart';

/// The current state of AI model initialization.
enum AIInitStatus {
  notStarted,
  downloadingLLM,
  downloadingSTT,
  loadingLLM,
  loadingSTT,
  ready,
  skipped,
  error,
}

/// State for AI model initialization progress.
class AIInitState {
  final AIInitStatus status;
  final double progress; // 0.0 - 1.0 overall progress
  final String message;
  final String? error;

  const AIInitState({
    this.status = AIInitStatus.notStarted,
    this.progress = 0.0,
    this.message = '',
    this.error,
  });

  AIInitState copyWith({
    AIInitStatus? status,
    double? progress,
    String? message,
    String? error,
  }) {
    return AIInitState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      error: error,
    );
  }

  bool get isComplete => status == AIInitStatus.ready;
  bool get isSkipped => status == AIInitStatus.skipped;
  bool get hasError => status == AIInitStatus.error;
  bool get isWorking =>
      status != AIInitStatus.notStarted &&
      status != AIInitStatus.ready &&
      status != AIInitStatus.skipped &&
      status != AIInitStatus.error;
}

/// Provider for the AI initialization state.
final aiInitProvider =
    StateNotifierProvider<AIInitNotifier, AIInitState>((ref) {
  return AIInitNotifier();
});

class AIInitNotifier extends StateNotifier<AIInitState> {
  AIInitNotifier() : super(const AIInitState());

  final _modelManager = ModelManager();
  final _gemmaService = GemmaService();
  final _sttService = SttService();

  /// Initialize AI models.
  /// Downloads Gemma 4 (required), then loads into memory.
  /// Whisper is OPTIONAL (fallback only) — Gemma 4 audio encoder is primary STT.
  Future<void> initializeAll() async {
    if (state.isComplete || state.isWorking) return;

    try {
      // Phase 1: Download Gemma 4 E2B (multimodal: text + audio + vision)
      state = state.copyWith(
        status: AIInitStatus.downloadingLLM,
        progress: 0.0,
        message: 'Memeriksa model Gemma 4...',
      );

      final llmReady = await _modelManager.isModelReady(ModelType.gemmaLLM);
      if (!llmReady) {
        await _modelManager.downloadModel(
          ModelType.gemmaLLM,
          onProgress: (progress, statusMsg) {
            if (mounted) {
              state = state.copyWith(
                progress: progress * 0.7, // 0-70% for Gemma download
                message: statusMsg,
              );
            }
          },
        );
      } else {
        state = state.copyWith(progress: 0.7, message: 'Model Gemma 4 sudah tersedia');
      }

      // Phase 2: Load Gemma 4 into memory
      state = state.copyWith(
        status: AIInitStatus.loadingLLM,
        progress: 0.7,
        message: 'Memuat Gemma 4 ke memori...',
      );

      await _gemmaService.initialize(
        onProgress: (p) {
          if (mounted) {
            state = state.copyWith(
              progress: 0.7 + p * 0.3, // 70-100%
            );
          }
        },
      );

      // Whisper TIDAK di-download/load di sini.
      // Gemma 4 audio encoder adalah primary STT.
      // Whisper hanya di-load on-demand sebagai fallback jika Gemma audio gagal.

      // Done!
      state = state.copyWith(
        status: AIInitStatus.ready,
        progress: 1.0,
        message: 'Gemma 4 siap digunakan!',
      );
    } catch (e) {
      state = state.copyWith(
        status: AIInitStatus.error,
        error: e.toString(),
        message: 'Gagal mempersiapkan AI',
      );
    }
  }

  /// Skip AI initialization (use fallback mode).
  void skip() {
    state = state.copyWith(
      status: AIInitStatus.skipped,
      progress: 0.0,
      message: 'AI dilewati — Download kapan saja dari Settings',
    );
  }

  /// Reset state so the user can re-enter the download page.
  void resetForReentry() {
    if (state.isSkipped || state.status == AIInitStatus.notStarted) {
      state = const AIInitState();
    }
  }

  /// Retry after an error.
  Future<void> retry() async {
    state = const AIInitState();
    await initializeAll();
  }
}

/// Provider that exposes whether at least the LLM is loaded.
final isGemmaReadyProvider = Provider<bool>((ref) {
  return GemmaService().isLoaded;
});

/// Provider that exposes whether the STT is loaded.
final isSttReadyProvider = Provider<bool>((ref) {
  return SttService().isLoaded;
});

/// Provider that checks if model files exist on disk (regardless of in-memory state).
final modelsDownloadedProvider = FutureProvider<bool>((ref) async {
  final mm = ModelManager();
  final llm = await mm.isModelReady(ModelType.gemmaLLM);
  final stt = await mm.isModelReady(ModelType.whisperSTT);
  return llm && stt;
});
