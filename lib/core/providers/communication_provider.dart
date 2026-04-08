import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../services/gesture_service.dart';
import '../services/mediapipe_service.dart';
import '../services/gemma_service.dart';
import '../services/stt_service.dart';
import '../services/model_manager.dart';
import '../services/tts_service.dart';
import '../../shared/models/conversation_entry.dart';
import '../../shared/models/user_persona.dart';

// ---- Deaf to Hearing State ----

class DeafToHearingState {
  final List<String> currentGloss;
  final String refinedSentence;
  /// Saran empatik dari Gemma untuk lawan bicara (orang dengar).
  final String? aiSuggestion;
  final bool isCapturing;
  final bool isProcessing;
  final List<Offset> skeletonPoints;
  final String? errorMessage;

  const DeafToHearingState({
    this.currentGloss = const [],
    this.refinedSentence = '',
    this.aiSuggestion,
    this.isCapturing = false,
    this.isProcessing = false,
    this.skeletonPoints = const [],
    this.errorMessage,
  });

  DeafToHearingState copyWith({
    List<String>? currentGloss,
    String? refinedSentence,
    String? aiSuggestion,
    bool? isCapturing,
    bool? isProcessing,
    List<Offset>? skeletonPoints,
    String? errorMessage,
    bool clearAiSuggestion = false,
  }) {
    return DeafToHearingState(
      currentGloss: currentGloss ?? this.currentGloss,
      refinedSentence: refinedSentence ?? this.refinedSentence,
      aiSuggestion: clearAiSuggestion ? null : (aiSuggestion ?? this.aiSuggestion),
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

  bool _isProcessingFrame = false;

  /// Called every camera frame while capturing.
  /// Extracts keypoints via MediaPipe, feeds to LSTM buffer,
  /// and updates skeleton overlay.
  void onCameraFrame(dynamic cameraImage, double previewW, double previewH, {int sensorOrientation = 90}) {
    if (!state.isCapturing || _isProcessingFrame) return;
    _isProcessingFrame = true;

    _gestureService.addFrameFromCameraAsync(cameraImage, sensorOrientation).then((keypoints) {
      if (!mounted) return;
      _isProcessingFrame = false;

      // Update skeleton overlay for UI
      final skeleton = _mediaPipe.getHandLandmarkPositions(
        keypoints,
        Size(previewW, previewH),
      );
      state = state.copyWith(skeletonPoints: skeleton);
    }).catchError((e) {
      _isProcessingFrame = false;
      debugPrint('[DeafToHearing] Frame processing error: $e');
    });
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
    state = state.copyWith(isProcessing: true, clearAiSuggestion: true);
    final result = await _gemmaService.refineGlossWithEmpathy(gloss);
    if (mounted) {
      state = state.copyWith(
        refinedSentence: result.sentence,
        aiSuggestion: result.aiSuggestion,
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
  final String? errorMessage;
  final String? lastRecordingPath;
  final String? debugWavInfo;

  const HearingToDeafState({
    this.rawTranscription = '',
    this.smartSummary = '',
    this.isRecording = false,
    this.isProcessing = false,
    this.errorMessage,
    this.lastRecordingPath,
    this.debugWavInfo,
  });

  HearingToDeafState copyWith({
    String? rawTranscription,
    String? smartSummary,
    bool? isRecording,
    bool? isProcessing,
    String? errorMessage,
    String? lastRecordingPath,
    String? debugWavInfo,
  }) {
    return HearingToDeafState(
      rawTranscription: rawTranscription ?? this.rawTranscription,
      smartSummary: smartSummary ?? this.smartSummary,
      isRecording: isRecording ?? this.isRecording,
      isProcessing: isProcessing ?? this.isProcessing,
      errorMessage: errorMessage,
      lastRecordingPath: lastRecordingPath ?? this.lastRecordingPath,
      debugWavInfo: debugWavInfo ?? this.debugWavInfo,
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
  final _recorder = AudioRecorder();
  String? _recordingPath;

  /// Start recording real audio via microphone.
  Future<void> startRecording() async {
    state = state.copyWith(
      isRecording: true,
      rawTranscription: '',
      smartSummary: '',
      errorMessage: null,
    );

    try {
      // Whisper reload tidak perlu — Gemma 4 audio encoder adalah primary.
      // Whisper hanya di-load saat fallback (jika Gemma audio gagal).

      // Check permission
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        state = state.copyWith(
          isRecording: false,
          errorMessage: 'Izin mikrofon ditolak',
        );
        return;
      }

      // Record WAV: 16kHz, 16-bit, mono — Whisper expected format
      final tempDir = await getTemporaryDirectory();
      _recordingPath = '${tempDir.path}/stt_recording.wav';

      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
        ),
        path: _recordingPath!,
      );

      debugPrint('[STT] Recording started → $_recordingPath');
    } catch (e) {
      debugPrint('[STT] Recording start error: $e');
      state = state.copyWith(
        isRecording: false,
        errorMessage: 'Gagal merekam: $e',
      );
    }
  }

  /// Stop recording, transcribe, then summarize.
  Future<void> stopRecording() async {
    state = state.copyWith(isRecording: false, isProcessing: true);

    try {
      // Stop recorder — file is saved at _recordingPath
      final path = await _recorder.stop();
      debugPrint('[STT] Recording stopped → $path');

      final audioPath = path ?? _recordingPath;
      if (audioPath == null || audioPath.isEmpty) {
        state = state.copyWith(
          isProcessing: false,
          errorMessage: 'Rekaman gagal disimpan',
        );
        return;
      }

      // Check file exists
      final file = File(audioPath);
      if (!await file.exists()) {
        state = state.copyWith(
          isProcessing: false,
          errorMessage: 'File rekaman tidak ditemukan',
        );
        return;
      }

      final fileSize = await file.length();
      debugPrint('[STT] Audio file: $audioPath ($fileSize bytes)');

      // Inspect WAV header for debugging
      String wavInfo = 'File: $fileSize bytes';
      try {
        final headerBytes = await file.openRead(0, 44).fold<List<int>>(
          <int>[], (prev, chunk) => prev..addAll(chunk));
        if (headerBytes.length >= 44) {
          final bd = ByteData.sublistView(Uint8List.fromList(headerBytes));
          final sampleRate = bd.getUint32(24, Endian.little);
          final numChannels = bd.getUint16(22, Endian.little);
          final bitsPerSample = bd.getUint16(34, Endian.little);
          final dataSize = bd.getUint32(40, Endian.little);
          final durationSec = dataSize / (sampleRate * numChannels * (bitsPerSample / 8));
          wavInfo = '${sampleRate}Hz ${numChannels}ch ${bitsPerSample}bit | '
              '${durationSec.toStringAsFixed(1)}s | ${fileSize}B';
          debugPrint('[STT] WAV: $wavInfo');
        }
      } catch (e) {
        debugPrint('[STT] WAV header parse error: $e');
      }

      if (mounted) {
        state = state.copyWith(
          lastRecordingPath: audioPath,
          debugWavInfo: wavInfo,
        );
      }

      // [EKSPERIMEN] Gemma 4 audio transcription — dispose Whisper dulu biar Gemma punya full RAM.
      // Jika gagal/kosong, reload Whisper dan fallback ke pipeline biasa.
      String transcription = '';
      bool usedGemmaAudio = false;

      if (_gemmaService.isLoaded) {
        // Free Whisper RAM dulu sebelum Gemma audio
        debugPrint('[STT] [GEMMA-AUDIO] Disposing Whisper to free RAM for Gemma audio...');
        await _sttService.dispose();

        try {
          final audioFile = File(audioPath);
          final rawBytes = await audioFile.readAsBytes();
          // Strip WAV header (44 bytes) — kirim raw PCM saja ke Gemma audio encoder
          Uint8List pcmData = rawBytes.length > 44 ? rawBytes.sublist(44) : rawBytes;

          // Downsample hanya jika PCM terlalu besar — cegah OOM pada audio panjang di Pixel 6a.
          // 256KB ≈ 8s pada 16kHz 16-bit mono. Audio normal (<8s) dikirim penuh 16kHz.
          const pcmSafeLimit = 256 * 1024; // 256 KB
          if (pcmData.length > pcmSafeLimit) {
            final before = pcmData.length;
            pcmData = _downsamplePcm16Bit(pcmData);
            debugPrint('[STT] [GEMMA-AUDIO] Downsampled ${before}B → ${pcmData.length}B (OOM guard)');
          }
          if (pcmData.length > pcmSafeLimit) {
            final before = pcmData.length;
            pcmData = _downsamplePcm16Bit(pcmData);
            debugPrint('[STT] [GEMMA-AUDIO] 2nd downsample ${before}B → ${pcmData.length}B');
          }

          debugPrint('[STT] [GEMMA-AUDIO] Trying Gemma 4 audio (${pcmData.length} PCM bytes)...');

          final gemmaResult = await _gemmaService.transcribeAudio(pcmData);
          debugPrint('[STT] [GEMMA-AUDIO] Result: "$gemmaResult"');

          if (gemmaResult.isNotEmpty) {
            transcription = gemmaResult;
            usedGemmaAudio = true;
            debugPrint('[STT] [GEMMA-AUDIO] SUCCESS — using Gemma audio transcription');
          } else {
            debugPrint('[STT] [GEMMA-AUDIO] Empty result — falling back to Whisper');
          }
        } catch (e) {
          debugPrint('[STT] [GEMMA-AUDIO] Failed: $e — falling back to Whisper');
        }
      }

      // Fallback: Whisper STT (jika Gemma audio gagal/kosong)
      if (!usedGemmaAudio) {
        // Cek dulu apakah Whisper model tersedia (opsional, tidak wajib download)
        final whisperReady = await ModelManager().isModelReady(ModelType.whisperSTT);
        if (whisperReady) {
          if (!_sttService.isLoaded) {
            debugPrint('[STT] [FALLBACK] Loading Whisper...');
            await _sttService.initialize();
          }
          debugPrint('[STT] [FALLBACK] Transcribing via Whisper...');
          transcription = await _sttService.transcribeFile(audioPath);
          debugPrint('[STT] [FALLBACK] Whisper result: "$transcription"');
        } else {
          debugPrint('[STT] [FALLBACK] Whisper not downloaded — no fallback available');
        }
      }

      if (transcription.isEmpty) {
        state = state.copyWith(
          isProcessing: false,
          rawTranscription: '',
          errorMessage: 'Transkripsi kosong ($wavInfo)',
        );
        return;
      }

      if (mounted) {
        state = state.copyWith(rawTranscription: transcription);
      }

      // Unload Whisper jika masih loaded — model swap untuk hemat RAM sebelum Gemma simplify.
      if (_sttService.isLoaded) {
        debugPrint('[STT] Unloading Whisper to free RAM before Gemma...');
        await _sttService.dispose();
      }

      // Step 2: Simplify via Gemma 4 for Deaf user
      // Jika pakai Gemma audio, bisa skip simplify (sudah 1 model) — tapi tetap run untuk konsistensi.
      debugPrint('[STT] Simplifying via Gemma...');
      final summary = await _gemmaService.simplifyForDeaf(transcription);
      debugPrint('[STT] Simplified: "$summary"');

      if (mounted) {
        state = state.copyWith(
          smartSummary: summary,
          isProcessing: false,
        );
      }
    } catch (e) {
      debugPrint('[STT] Pipeline error: $e');
      if (mounted) {
        state = state.copyWith(
          isProcessing: false,
          errorMessage: 'Error: $e',
        );
      }
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }
}

/// Downsample 16-bit mono PCM dengan averaging 2 sample berurutan.
/// Input/output: raw PCM bytes (int16 little-endian, no WAV header).
/// Hasilnya setengah panjang — efektif 2× speed dari perspektif Gemma audio encoder.
/// Speech tetap intelligible karena formant utama (<4kHz) terjaga.
Uint8List _downsamplePcm16Bit(Uint8List pcm) {
  final bd = ByteData.sublistView(pcm);
  final inSamples = pcm.length ~/ 2;
  final outSamples = inSamples ~/ 2;
  final out = ByteData(outSamples * 2);
  for (int i = 0; i < outSamples; i++) {
    final s1 = bd.getInt16(i * 4, Endian.little);
    final s2 = bd.getInt16(i * 4 + 2, Endian.little);
    final avg = ((s1 + s2) >> 1).clamp(-32768, 32767);
    out.setInt16(i * 2, avg, Endian.little);
  }
  return out.buffer.asUint8List();
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
