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
  bool get hasError => status == AIInitStatus.error;
  bool get isWorking =>
      status != AIInitStatus.notStarted &&
      status != AIInitStatus.ready &&
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

  /// Initialize all AI models.
  /// Downloads if needed, then loads into memory.
  Future<void> initializeAll() async {
    if (state.isComplete || state.isWorking) return;

    try {
      // Phase 1: Download LLM (Gemma 4 E2B)
      state = state.copyWith(
        status: AIInitStatus.downloadingLLM,
        progress: 0.0,
        message: 'Memeriksa model AI Bahasa...',
      );

      final llmReady = await _modelManager.isModelReady(ModelType.gemmaLLM);
      if (!llmReady) {
        await _modelManager.downloadModel(
          ModelType.gemmaLLM,
          onProgress: (progress, statusMsg) {
            if (mounted) {
              state = state.copyWith(
                progress: progress * 0.4, // 0-40% for LLM download
                message: statusMsg,
              );
            }
          },
        );
      } else {
        state = state.copyWith(progress: 0.4, message: 'Model AI Bahasa sudah tersedia');
      }

      // Phase 2: Download STT (Whisper Tiny ID)
      state = state.copyWith(
        status: AIInitStatus.downloadingSTT,
        message: 'Memeriksa model Speech-to-Text...',
      );

      final sttReady = await _modelManager.isModelReady(ModelType.whisperSTT);
      if (!sttReady) {
        await _modelManager.downloadModel(
          ModelType.whisperSTT,
          onProgress: (progress, statusMsg) {
            if (mounted) {
              state = state.copyWith(
                progress: 0.4 + progress * 0.2, // 40-60% for STT download
                message: statusMsg,
              );
            }
          },
        );
      } else {
        state = state.copyWith(
          progress: 0.6,
          message: 'Model Speech-to-Text sudah tersedia',
        );
      }

      // Phase 3: Load LLM into memory
      state = state.copyWith(
        status: AIInitStatus.loadingLLM,
        progress: 0.6,
        message: 'Memuat AI Bahasa ke memori...',
      );

      await _gemmaService.initialize(
        onProgress: (p) {
          if (mounted) {
            state = state.copyWith(
              progress: 0.6 + p * 0.2, // 60-80%
            );
          }
        },
      );

      // Phase 4: Load STT into memory
      state = state.copyWith(
        status: AIInitStatus.loadingSTT,
        progress: 0.8,
        message: 'Memuat Speech-to-Text ke memori...',
      );

      await _sttService.initialize(
        onProgress: (p) {
          if (mounted) {
            state = state.copyWith(
              progress: 0.8 + p * 0.2, // 80-100%
            );
          }
        },
      );

      // Done!
      state = state.copyWith(
        status: AIInitStatus.ready,
        progress: 1.0,
        message: 'AI siap digunakan!',
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
      status: AIInitStatus.ready,
      progress: 1.0,
      message: 'Mode offline tanpa AI',
    );
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
