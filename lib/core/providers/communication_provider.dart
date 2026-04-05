import 'dart:async';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/gesture_service.dart';
import '../services/mediapipe_service.dart';
import '../services/gemma_service.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';
import '../../shared/models/conversation_entry.dart';
import '../../shared/models/user_persona.dart';

// ---- Deaf to Hearing State ----

class DeafToHearingState {
  final List<String> currentGloss;
  final String refinedSentence;
  final bool isCapturing;
  final bool isProcessing;
  final List<Offset> skeletonPoints;
  final String? errorMessage;

  const DeafToHearingState({
    this.currentGloss = const [],
    this.refinedSentence = '',
    this.isCapturing = false,
    this.isProcessing = false,
    this.skeletonPoints = const [],
    this.errorMessage,
  });

  DeafToHearingState copyWith({
    List<String>? currentGloss,
    String? refinedSentence,
    bool? isCapturing,
    bool? isProcessing,
    List<Offset>? skeletonPoints,
    String? errorMessage,
  }) {
    return DeafToHearingState(
      currentGloss: currentGloss ?? this.currentGloss,
      refinedSentence: refinedSentence ?? this.refinedSentence,
      isCapturing: isCapturing ?? this.isCapturing,
      isProcessing: isProcessing ?? this.isProcessing,
      skeletonPoints: skeletonPoints ?? this.skeletonPoints,
      errorMessage: errorMessage,
    );
  }
}

final deafToHearingProvider =
    StateNotifierProvider<DeafToHearingNotifier, DeafToHearingState>((ref) {
  return DeafToHearingNotifier();
});

class DeafToHearingNotifier extends StateNotifier<DeafToHearingState> {
  DeafToHearingNotifier() : super(const DeafToHearingState());

  final _gestureService = GestureService();
  final _mediaPipe = MediaPipeService();
  final _gemmaService = GemmaService();
  final _ttsService = TtsService();
  StreamSubscription<List<String>>? _glossSubscription;

  /// Called every camera frame while capturing.
  /// Extracts keypoints via MediaPipe, feeds to LSTM buffer,
  /// and updates skeleton overlay.
  void onCameraFrame(dynamic cameraImage, double previewW, double previewH) {
    if (!state.isCapturing) return;

    final keypoints = _mediaPipe.extractKeypoints(cameraImage);
    _gestureService.addFrame(keypoints);

    // Update skeleton overlay for UI
    final skeleton = _mediaPipe.getHandLandmarkPositions(
      keypoints,
      Size(previewW, previewH),
    );
    if (mounted) {
      state = state.copyWith(skeletonPoints: skeleton);
    }
  }

  void startCapture() {
    state = state.copyWith(
      isCapturing: true,
      currentGloss: [],
      refinedSentence: '',
      errorMessage: null,
    );

    _gestureService.startGestureCapture();

    // Listen to mock gloss stream (fallback when LSTM not loaded)
    _glossSubscription = _gestureService.glossStream.listen((gloss) {
      state = state.copyWith(currentGloss: gloss);
      _refineCurrentGloss(gloss);
    });
  }

  /// Stop capture and run LSTM prediction if model is loaded.
  Future<void> stopCapture() async {
    _gestureService.stopGestureCapture();
    _glossSubscription?.cancel();

    if (_gestureService.isModelLoaded) {
      // Real LSTM path
      state = state.copyWith(isCapturing: false, isProcessing: true);

      final result = _gestureService.predict();
      if (result != null) {
        final glossList = [result.word];
        state = state.copyWith(currentGloss: glossList);
        await _refineCurrentGloss(glossList);
      } else {
        state = state.copyWith(
          isProcessing: false,
          errorMessage: 'Isyarat kurang jelas. Coba lagi.',
        );
      }
    } else {
      // Mock mode — just stop
      state = state.copyWith(isCapturing: false);
    }
  }

  Future<void> _refineCurrentGloss(List<String> gloss) async {
    state = state.copyWith(isProcessing: true);
    final sentence = await _gemmaService.refineGloss(gloss);
    if (mounted) {
      state = state.copyWith(
        refinedSentence: sentence,
        isProcessing: false,
      );
    }
  }

  Future<void> speakSentence() async {
    if (state.refinedSentence.isNotEmpty) {
      await _ttsService.speak(state.refinedSentence);
    }
  }

  @override
  void dispose() {
    _glossSubscription?.cancel();
    _gestureService.stopGestureCapture();
    super.dispose();
  }
}

// ---- Hearing to Deaf State ----

class HearingToDeafState {
  final String rawTranscription;
  final String smartSummary;
  final bool isRecording;
  final bool isProcessing;

  const HearingToDeafState({
    this.rawTranscription = '',
    this.smartSummary = '',
    this.isRecording = false,
    this.isProcessing = false,
  });

  HearingToDeafState copyWith({
    String? rawTranscription,
    String? smartSummary,
    bool? isRecording,
    bool? isProcessing,
  }) {
    return HearingToDeafState(
      rawTranscription: rawTranscription ?? this.rawTranscription,
      smartSummary: smartSummary ?? this.smartSummary,
      isRecording: isRecording ?? this.isRecording,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }
}

final hearingToDeafProvider =
    StateNotifierProvider<HearingToDeafNotifier, HearingToDeafState>((ref) {
  return HearingToDeafNotifier();
});

class HearingToDeafNotifier extends StateNotifier<HearingToDeafState> {
  HearingToDeafNotifier() : super(const HearingToDeafState());

  final _sttService = SttService();
  final _gemmaService = GemmaService();

  void startRecording() {
    state = state.copyWith(
      isRecording: true,
      rawTranscription: '',
      smartSummary: '',
    );
  }

  Future<void> stopRecording() async {
    state = state.copyWith(isRecording: false, isProcessing: true);

    final transcription = await _sttService.transcribe(null);
    state = state.copyWith(rawTranscription: transcription);

    final summary = await _gemmaService.summarizeSpeech(transcription);
    if (mounted) {
      state = state.copyWith(
        smartSummary: summary,
        isProcessing: false,
      );
    }
  }
}

// ---- Conversation History ----

final conversationHistoryProvider =
    StateNotifierProvider<ConversationHistoryNotifier, List<ConversationEntry>>(
        (ref) {
  return ConversationHistoryNotifier();
});

class ConversationHistoryNotifier extends StateNotifier<List<ConversationEntry>> {
  ConversationHistoryNotifier() : super(_mockHistory);

  static final List<ConversationEntry> _mockHistory = [
    ConversationEntry(
      id: '1',
      sourcePersona: UserPersona.tuli,
      originalText: 'NAMA SAYA APA',
      translatedText: 'Siapa nama kamu?',
      timestamp: DateTime.now().subtract(Duration(minutes: 5)),
      type: ConversationType.signToText,
    ),
    ConversationEntry(
      id: '2',
      sourcePersona: UserPersona.mendengar,
      originalText: 'Saya sedang mencari jalan menuju stasiun terdekat',
      translatedText: 'Budi ingin tahu jalan ke stasiun.',
      timestamp: DateTime.now().subtract(Duration(minutes: 15)),
      type: ConversationType.speechToSign,
    ),
    ConversationEntry(
      id: '3',
      sourcePersona: UserPersona.tuli,
      originalText: 'TERIMA KASIH',
      translatedText: 'Terima kasih banyak!',
      timestamp: DateTime.now().subtract(Duration(hours: 1)),
      type: ConversationType.signToText,
    ),
    ConversationEntry(
      id: '4',
      sourcePersona: UserPersona.mendengar,
      originalText: 'Permisi, apakah toko buku ini masih buka?',
      translatedText: 'Dia bertanya apakah toko buku buka.',
      timestamp: DateTime.now().subtract(Duration(hours: 3)),
      type: ConversationType.speechToSign,
    ),
    ConversationEntry(
      id: '5',
      sourcePersona: UserPersona.tuli,
      originalText: 'TOLONG BANTU',
      translatedText: 'Tolong bantu saya.',
      timestamp: DateTime.now().subtract(Duration(hours: 5)),
      type: ConversationType.signToText,
    ),
  ];

  void addEntry(ConversationEntry entry) {
    state = [entry, ...state];
  }
}
