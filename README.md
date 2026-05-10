# KawanIsyarat

Two-way communication app between Deaf BISINDO users and hearing Indonesians. Runs fully offline after the initial model download — no internet, no server, no data leaving the device.

Built for the [Gemma 4 Good Hackathon (Kaggle, 2026)](https://www.kaggle.com/competitions/google-gemma-4-good-hackathon).

---

## How it works

**Deaf → Hearing**
Camera → MediaPipe (pose + hand landmarks) → 1D CNN → BISINDO gloss → Gemma 4 → natural Indonesian sentence + contextual empathy tips → TTS

**Hearing → Deaf**
Mic → WAV → raw PCM → Gemma 4 audio encoder → transcript → Gemma 4 simplify → clean short text

---

## Features

- **Sign-to-text** — real-time 1D CNN recognizes 16 BISINDO words from 30-frame sequences
- **Speech-to-simplified-text** — Gemma 4 audio transcription + simplification for deaf readers
- **Alphabet practice** — SIBI (24 letters, 1 hand) and BISINDO (26 letters, 2 hands) with Gemma 4 Vision feedback
- **Vocabulary helper** — type any unfamiliar word, Gemma explains it in plain Indonesian
- **Articulation practice** — hearing users practice pronunciation, Gemma evaluates via audio
- **Emergency SOS** — one-tap TTS for six critical phrases ("I am deaf", "I need help", etc.)
- **History** — session log with timestamps

---

## Tech Stack

| Component | Detail |
|---|---|
| Framework | Flutter + Riverpod + GoRouter |
| On-device LLM | Gemma 4 E2B INT4 via **Cactus SDK** (FFI, ~4 GB, ~1.9 GB RAM) |
| Primary STT | Gemma 4 Audio Encoder — built into E2B, no separate model |
| Fallback STT | Whisper Base INT8 via Cactus SDK (optional, ~200 MB) |
| Gesture recognition | MediaPipe (33 pose + 21×2 hand landmarks) → 1D Causal Depthwise CNN |
| Alphabet recognition | Dense classifier: SIBI 24 classes + BISINDO 26 classes (A–Z + NOTHING) |
| Local storage | Hive |
| TTS | flutter_tts |

---

## Running the App

```bash
flutter pub get

# Run on device (replace with your device ID)
flutter run -d YOUR_DEVICE_ID
```

First launch downloads the Gemma 4 model (~4 GB). After that, everything runs offline.

**Do not use `flutter install`** — it will wipe app data including the downloaded model.

---

## Model Paths (on device)

```
/data/user/0/com.kawanisyarat.kawan_isyarat/app_flutter/cactus_models/
  gemma-4-e2b-it-int4/     ← Gemma 4 E2B (primary, ~4 GB)
  whisper-base-int8/        ← Whisper fallback (optional, ~200 MB)
```

---

## Key Implementation Notes

**Thinking mode must be disabled.** Cactus SDK defaults `enable_thinking_if_supported` to `true`, which causes 60–153 second responses. Passing `'enable_thinking_if_supported': false` in the options JSON brings this to 4–9 seconds.

**Whisper prompt format.** Must end with `<|notimestamps|>` — without it, the model generates timestamp tokens that get filtered, producing empty output.

**OOM guard for long audio.** PCM > 256 KB (~8s at 16kHz) triggers 2-tap decimation before sending to Gemma. Audio ≤ 8s is sent at full quality.

**Gemma 4 Vision knowledge injection.** Gemma has no knowledge of BISINDO/SIBI hand shapes. Every vision coaching call injects a textual reference of the correct hand form for that letter/word.

---

## Project Structure

```
lib/
├── app/
│   ├── router.dart              GoRouter — all routes
│   ├── theme.dart               Material theme + design tokens
│   └── constants.dart           Colors, spacing, static data
├── core/
│   ├── ffi/
│   │   ├── cactus.dart          Cactus FFI bindings (do not edit)
│   │   └── cactus_wrapper.dart  CactusModel + CactusTranscriber
│   ├── services/
│   │   ├── gemma_service.dart         Gemma 4: text, audio, vision, empathy
│   │   ├── gesture_service.dart       1D CNN: BISINDO word recognition
│   │   ├── mediapipe_service.dart     MediaPipe: pose + hand landmarks
│   │   ├── sibi_alphabet_service.dart SIBI alphabet (24 classes, 1 hand)
│   │   ├── bisindo_alphabet_service.dart BISINDO alphabet (26 classes, 2 hands)
│   │   ├── model_manager.dart         Model download + path management
│   │   ├── stt_service.dart           Whisper STT (fallback)
│   │   ├── tts_service.dart           flutter_tts wrapper
│   │   └── persistence_service.dart   Hive local storage
│   └── providers/
│       ├── ai_providers.dart          Gemma init + download state
│       ├── communication_provider.dart DeafToHearingNotifier + HearingToDeafNotifier
│       ├── learning_provider.dart     Learning hub state
│       ├── learning_progress_provider.dart Per-module completion tracking
│       ├── persona_provider.dart      User persona (Deaf / Hearing)
│       └── auth_provider.dart         Simple onboarding auth state
└── features/
    ├── onboarding/     Landing, persona selection, AI init screen
    ├── home/           Dashboard + word-of-day card
    ├── communication/  Deaf↔Hearing screens + widgets
    ├── learning/       Hub, kata, alfabet, idiom, artikulasi, kamus
    ├── history/        Session history
    ├── settings/       Model management, app settings
    └── emergency/      SOS quick-sign screen
```

---

## ML Models

### BISINDO Gesture (1D CNN)
- Input: 30 frames × 100 floats (nose-centered, shoulder-normalized, w/ temporal derivatives)
- 16 classes: TULI, SAYA, KAMU, NAMA, TOLONG, APA, TERIMA_KASIH, BAIK, SAKIT, LAPAR, HAUS, MINTA, PAGI, MALAM, SEKOLAH, NOISE
- Evaluated with LOSO (Leave-One-Signer-Out): **86.2% test accuracy**
- Training scripts: `ml/data_collector.py`

### BISINDO Alphabet (Dense classifier)
- Input: 42 floats (21 hand landmarks × xy, bbox-normalized)
- 26 classes A–Z + NOTHING
- Training dataset: recorded with MediaPipe hand landmarker

### SIBI Alphabet (Dense classifier)
- Input: 42 floats (1 hand, same format)
- 24 classes (A–Z, skip J and Z — dynamic)
- Training dataset: Kaggle SIBI 5280 images

---

## License

MIT
