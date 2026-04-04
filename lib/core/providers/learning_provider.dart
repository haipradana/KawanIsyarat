import 'package:flutter_riverpod/flutter_riverpod.dart';

class LearningState {
  final String currentWord;
  final String instruction;
  final int currentUnit;
  final String unitTitle;
  final double progress;
  final int xp;
  final int starRating;
  final int maxStars;
  final String? feedbackMessage;
  final bool isRecording;
  final bool showFeedback;

  const LearningState({
    this.currentWord = 'TERIMA KASIH 🙏',
    this.instruction = 'Lakukan gerakan dari dagu ke arah depan',
    this.currentUnit = 3,
    this.unitTitle = 'DASAR PERCAKAPAN',
    this.progress = 0.65,
    this.xp = 450,
    this.starRating = 2,
    this.maxStars = 3,
    this.feedbackMessage,
    this.isRecording = false,
    this.showFeedback = false,
  });

  LearningState copyWith({
    String? currentWord,
    String? instruction,
    int? currentUnit,
    String? unitTitle,
    double? progress,
    int? xp,
    int? starRating,
    int? maxStars,
    String? feedbackMessage,
    bool? isRecording,
    bool? showFeedback,
  }) {
    return LearningState(
      currentWord: currentWord ?? this.currentWord,
      instruction: instruction ?? this.instruction,
      currentUnit: currentUnit ?? this.currentUnit,
      unitTitle: unitTitle ?? this.unitTitle,
      progress: progress ?? this.progress,
      xp: xp ?? this.xp,
      starRating: starRating ?? this.starRating,
      maxStars: maxStars ?? this.maxStars,
      feedbackMessage: feedbackMessage ?? this.feedbackMessage,
      isRecording: isRecording ?? this.isRecording,
      showFeedback: showFeedback ?? this.showFeedback,
    );
  }
}

final learningProvider =
    StateNotifierProvider<LearningNotifier, LearningState>((ref) {
  return LearningNotifier();
});

class LearningNotifier extends StateNotifier<LearningState> {
  LearningNotifier() : super(const LearningState());

  void startRecording() {
    state = state.copyWith(isRecording: true, showFeedback: false);
  }

  Future<void> stopRecording() async {
    state = state.copyWith(isRecording: false);
    // Simulate processing delay
    await Future.delayed(Duration(milliseconds: 1000));
    if (mounted) {
      state = state.copyWith(
        showFeedback: true,
        feedbackMessage:
            'Hampir benar! Posisi jari telunjuk kurang lurus. Coba angkat sedikit lebih tinggi.',
        starRating: 2,
        xp: state.xp + 15,
      );
    }
  }

  void nextWord() {
    const words = [
      ('TERIMA KASIH 🙏', 'Lakukan gerakan dari dagu ke arah depan'),
      ('HALO 👋', 'Lambaikan tangan dengan telapak terbuka'),
      ('MAAF 🙏', 'Letakkan telapak tangan di dada dan gerakkan melingkar'),
      ('TOLONG ✋', 'Angkat kedua tangan dengan telapak menghadap ke atas'),
      ('NAMA 👆', 'Tunjuk diri sendiri lalu buat huruf N dengan jari'),
    ];
    final currentIndex = words.indexWhere((w) => w.$1 == state.currentWord);
    final nextIndex = (currentIndex + 1) % words.length;
    state = state.copyWith(
      currentWord: words[nextIndex].$1,
      instruction: words[nextIndex].$2,
      showFeedback: false,
      feedbackMessage: null,
    );
  }
}
