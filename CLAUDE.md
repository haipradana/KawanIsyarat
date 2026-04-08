# KawanIsyarat — Project Context untuk AI

## Ringkasan Proyek
Aplikasi Flutter untuk komunikasi antara orang **Tuli (BISINDO)** dan orang dengar.
Peserta **Gemma 4 Good Hackathon (Kaggle)** — penggunaan Cactus SDK adalah bonus prize category.
Developer: Pradana, Pixel 6a (Android 16, arm64-v8a), package `com.kawanisyarat.kawan_isyarat`.

---

## Dua Flow Utama

### 1. Deaf -> Hearing
Kamera -> MediaPipe (tangan+pose) -> LSTM -> gloss BISINDO -> **Gemma 4** -> kalimat natural + saran empatik AI -> TTS

### 2. Hearing -> Deaf
Mikrofon -> **Gemma 4 Audio Encoder** transkripsi -> **Gemma 4** simplifikasi -> teks sederhana untuk Tuli
*(Whisper STT sebagai fallback opsional — tidak wajib download)*

---

## Stack Teknis

| Komponen | Detail |
|---|---|
| Framework | Flutter + Riverpod + GoRouter |
| LLM + Audio | Gemma 4 E2B via **Cactus SDK** (FFI, INT4, ~4GB) — multimodal: text + audio + vision |
| STT (primary) | **Gemma 4 Audio Encoder** — built-in, tidak perlu model terpisah |
| STT (fallback) | Whisper Base INT8 via Cactus SDK — opsional, hanya jika Gemma audio gagal |
| Gesture | MediaPipe (pose 33 landmarks + hand 21 landmarks) -> LSTM TFLite |
| Alphabet | YOLO11n (`yolo_alphabet_sign_int8.tflite`) 26 huruf A-Z |
| State | Riverpod `StateNotifierProvider` |

### Gemma via Cactus SDK (Konfigurasi Saat Ini)
- **Model:** `gemma-4-e2b-it-int4.zip` (~4GB) dari Cactus-Compute HuggingFace
- **Optimasi RAM:** `n_ctx: 512`, `memory_f32: false`, `batch_size: 1`, `n_threads: 4`
- **Thinking disabled:** `enable_thinking_if_supported: false` di options JSON cactusComplete()
  - Tanpa ini, Cactus inject `<|think|>` ke system prompt -> model thinking 60-153 detik
  - Dengan `false`: konsisten 4-9 detik, 3.5-4.5 tok/s
- **RAM usage:** ~1.7-1.9 GB saat inference (Pixel 6a aman)

### flutter_gemma (LiteRT LM) — STABLE FALLBACK
- Kode dicomment di `gemma_service.dart` bagian bawah
- Jika Cactus OOM di device tertentu, uncomment kode flutter_gemma
- flutter_gemma: ~676MB RAM GPU, ~3.2s response via MediaPipe GenAI
- Model format: `.litertlm` (~2.58GB)
- URL: `https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm`
- Butuh `FlutterGemma.initialize()` di `main.dart` (saat ini dicomment)

---

## Model URLs & Paths

### URLs Saat Ini
```
Gemma (Cactus INT4): https://huggingface.co/Cactus-Compute/gemma-4-E2B-it/resolve/main/weights/gemma-4-e2b-it-int4.zip
Whisper (Cactus):    https://huggingface.co/Cactus-Compute/whisper-base/resolve/main/weights/whisper-base-int8.zip
```

### Path di HP
```
/data/user/0/com.kawanisyarat.kawan_isyarat/app_flutter/cactus_models/
  gemma-4-e2b-it-int4/    (directory, extracted dari zip ~4GB)
  whisper-base-int8/       (directory, extracted dari zip ~200MB)
```

---

## Cactus SDK — Hal Penting

### Cactus Engine (BUKAN llama.cpp)
Cactus punya inference engine sendiri (custom C++ + ARM SIMD kernels).
- Repo: https://github.com/cactus-compute/cactus
- Engine: custom computation graph + model implementations
- Gemma 4 model: `cactus/models/gemma4/model_gemma4.cpp`

### Gemma 4 Thinking Mode
- Flag: `enable_thinking_if_supported` (default: `true` di `engine.h`)
- Lokasi di source: `cactus/engine/engine_tokenizer.cpp` -> `format_gemma4_style()`
- Jika `true`: Cactus inject `<|think|>` di system prompt -> model thinking dulu -> lambat
- Solusi: pass `'enable_thinking_if_supported': false` di options JSON `cactusComplete()`
- Diparsing di `cactus/ffi/cactus_complete.cpp` -> `parse_inference_options_json()`

### Whisper Prompt (WAJIB persis ini)
```dart
'<|startoftranscript|><|id|><|transcribe|><|notimestamps|>'
```
- `<|notimestamps|>` **HARUS ADA** — tanpanya model generate timestamp tokens yang di-filter -> response kosong

### Whisper Optimasi (options JSON)
```dart
{'max_tokens': 2048, 'completion_mode': 'local', 'n_ctx': 512, 'memory_f32': false, 'batch_size': 1, 'n_threads': 4}
```

### Model Swap (RAM Management)
Pixel 6a tidak kuat load Whisper + Gemma bersamaan (OOM).
Solusi: setelah transkripsi, `_sttService.dispose()` -> panggil Gemma -> reload Whisper saat rekam berikutnya.

### NPU via Pro Key
API: `CactusConfig.setProKey("your-pro-key")` (satu kali di app startup).
Pro key didapat dari `founders@cactuscompute.com` — email sudah dikirim, belum ada balasan.
Tanpa key -> CPU-only. Dengan key -> NPU/GPU otomatis aktif.

---

## File-File Kunci

```
lib/core/ffi/
  cactus.dart              — FFI bindings (JANGAN EDIT)
  cactus_wrapper.dart      — CactusModel (+ enable_thinking_if_supported: false), CactusTranscriber

lib/core/services/
  model_manager.dart       — Download & path management (zip-based untuk Gemma + Whisper)
  gemma_service.dart       — GemmaService: refineGloss, refineGlossWithEmpathy, simplifyForDeaf
                              (Cactus aktif, flutter_gemma dicomment sebagai fallback)
  stt_service.dart         — SttService: initialize, transcribeFile, dispose
  mediapipe_service.dart   — Real MediaPipe pose+hand detection (258 floats/frame)
  gesture_service.dart     — LSTM sliding window (30 frames x 258 floats)
  yolo_alphabet_service.dart — YOLO11n A-Z detection

lib/core/providers/
  communication_provider.dart — DeafToHearingNotifier, HearingToDeafNotifier

lib/features/communication/screens/
  comm_deaf_to_hearing_screen.dart   — Kamera + capture isyarat -> kalimat + AI suggestion card
  comm_hearing_to_deaf_screen.dart   — Rekam suara -> transkripsi -> Gemma simplify

lib/features/learning/screens/
  alphabet_practice_screen.dart      — YOLO alphabet detection

lib/main.dart              — Entry point (flutter_gemma dicomment)
```

---

## Fitur Contextual Empathy (Gemma 4)

### Deaf -> Hearing
`GemmaService.refineGlossWithEmpathy(glossList)` -> `EmpathyResult`:
- `sentence`: terjemahan kalimat lengkap
- `aiSuggestion`: saran proaktif untuk orang dengar

Contoh: gloss `SAYA | PUSING | OBAT`
-> "Saya merasa pusing dan butuh obat."
-> (Saran AI): "Tanyakan apakah dia butuh diantar ke ruang kesehatan atau air putih."

### Hearing -> Deaf
`GemmaService.simplifyForDeaf(text)` -> teks bersih tanpa filler words

---

## MediaPipe Feature Vector (258 floats/frame)

```
Pose:  33 landmarks x 4 (x,y,z,visibility) = 132 floats  -> index 0-131
Hand L: 21 landmarks x 3 (x,y,z) = 63 floats             -> index 132-194
Hand R: 21 landmarks x 3 (x,y,z) = 63 floats             -> index 195-257
```
LSTM model: `assets/models/bisindo_gesture.tflite`, 30-frame window, 32+ kelas BISINDO.

---

## YOLO11n Alphabet

- Model: `assets/models/yolo_alphabet_sign_int8.tflite`
- Input: `[1][320][320][3]` float32 (letterbox RGBA->RGB)
- Output: `[1][30][2100]` -> 26 class scores (index 4-29), 2100 anchors

---

## Status Saat Ini (8 Apr 2026)

| Fitur | Status |
|---|---|
| Download model Gemma 4 | ✅ Bekerja (~4GB, sekali download) |
| Gemma 4 Audio Transcription (PRIMARY STT) | ✅ Bekerja — ~28s untuk 7s audio, 2.2 tok/s, fully offline |
| Gemma simplifyForDeaf (Hearing->Deaf) | ✅ Bekerja — 4-9s, 3.5-4.5 tok/s |
| Gemma gloss -> kalimat (Deaf->Hearing) | ✅ Implemented, belum ditest end-to-end |
| Contextual Empathy (AI suggestion) | ✅ Implemented, belum ditest end-to-end |
| Thinking mode disabled | ✅ enable_thinking_if_supported: false |
| OOM guard panjang audio | ✅ Downsample 2-tap hanya jika PCM > 256KB |
| Whisper fallback | ✅ Opsional — hanya jika Gemma audio gagal |
| MediaPipe real detection | Implemented, belum ditest end-to-end |
| YOLO alphabet | ✅ Bekerja |
| Gemma 4 Vision (sign detection) | Belum diimplementasi |
| TTS | Belum diverifikasi |

---

## Gemma 4 Multimodal (Audio + Vision)

### Gemma 4 E2B = Fully Multimodal! (CONFIRMED WORKING)
Model `gemma-4-e2b-it-int4.zip` sudah termasuk audio + vision encoder weights.
- Audio encoder: ~300M params (conformer blocks + SSCP) — **TESTED, WORKING**
- Vision encoder: ~150M params (ViT + patch embedding) — belum ditest
- Hanya E2B dan E4B yang punya audio — model besar (31B, 26B MoE) hanya vision.

### Gemma 4 Audio Transcription (PRIMARY STT)
- **Status:** WORKING di Pixel 6a! Tested 8 Apr 2026
- **Cara:** PCM audio dikirim via `cactusComplete(pcmData:)`, user message `<|audio|>`
- **Performa:** ~28s untuk 7s audio (229KB PCM), 2.2 tok/s, ~1.9GB RAM
- **Kelebihan:** 1 model untuk semua (tanpa Whisper), arsitektur simpel, no model swap
- **WAV handling:** Strip 44-byte WAV header sebelum kirim raw PCM
- **OOM guard:** Jika PCM > 256KB (~8s), apply 2-tap averaging downsample (rata-rata 2 sample int16 berurutan → setengah ukuran). Gemma baca audio as-is tapi "sped up 2×" — cukup untuk mencegah OOM. Audio ≤ 8s → dikirim penuh 16kHz tanpa modifikasi (kualitas terbaik). Downsampling ini BUKAN resampling proper — tidak pakai low-pass filter, bukan 8kHz output, hanya decimation 2-tap.

### Cactus SDK Multimodal Support
- `cactusComplete()` punya param `Uint8List? pcmData` untuk audio
- Image handling via file paths di messages JSON
- Source: `cactus/models/gemma4/model_gemma4_audio.cpp`, `_vision.cpp`, `_mm.cpp`

### Whisper = Opsional Fallback
- Whisper TIDAK wajib download
- Hanya di-load on-demand jika Gemma audio gagal dan model Whisper tersedia
- Untuk install: user bisa download manual di settings (TODO)

### Rencana Vision (Selanjutnya)
- Ganti MediaPipe+LSTM dengan Gemma 4 vision untuk deteksi isyarat
- 1 model untuk SEMUA AI tasks (text + audio + vision)
- Perlu prompt engineering untuk sign language recognition dari frame kamera

---

## Roadmap: Dua Varian Aplikasi

### Latar Belakang
Tidak semua device masyarakat Indonesia mampu menjalankan Gemma 4 (~4GB, ~2GB RAM inference). Solusi: dua varian aplikasi yang share codebase yang sama, dibedakan di layer AI service.

### KawanIsyarat Lite (Edge-First)
- **Target device:** Mid-range ke bawah, ~3GB RAM
- **STT:** Whisper tiny/base via Cactus SDK (~80–200MB)
- **Gesture:** MediaPipe + LSTM (tetap sama)
- **"Otak akhir":** Gemma 4 (atau Gemma 2 2B / Gemma 3 1B) untuk:
  - Simplifikasi teks (Hearing→Deaf)
  - Gloss → kalimat natural (Deaf→Hearing)
  - Contextual empathy suggestion
- **Download total:** ~500MB–1GB
- **Keunggulan:** Inference STT lebih cepat (Whisper tiny ~3-5s), bisa jalan di HP lama

### KawanIsyarat (Full / Flagship)
- **Target device:** Flagship, ≥6GB RAM (Pixel 6a ke atas)
- **STT:** Gemma 4 Audio Encoder (PRIMARY) — 1 model untuk semua
- **Gesture:** MediaPipe + LSTM (atau Gemma 4 Vision di masa depan)
- **LLM:** Gemma 4 E2B multimodal (~4GB) untuk semua AI tasks
- **Download total:** ~4GB (sekali download, fully offline)
- **Keunggulan:** Single model architecture, audio+text+vision dari 1 model, showcase Gemma 4 multimodal

### Strategi Implementasi
- Sama: Flutter UI, Riverpod state, semua non-AI logic, MediaPipe, LSTM, YOLO
- Beda: `GemmaService` (satu bisa pakai model lebih kecil), `SttService` (Whisper jadi primary di Lite)
- Bisa pakai `flavor` Flutter atau cukup `BuildConfig` flag untuk switch service implementation
- Gemma tetap wajib ada di kedua varian (hackathon requirement) — hanya sebagai "otak akhir" di Lite

---

## Perintah Penting

```bash
# Run ke Pixel 6a (JANGAN flutter install — model hilang)
flutter run -d 24191JEAR09003

# Delete model lama via ADB
~/Library/Android/sdk/platform-tools/adb shell run-as com.kawanisyarat.kawan_isyarat rm -rf /data/user/0/com.kawanisyarat.kawan_isyarat/app_flutter/cactus_models/NAMA_FOLDER

# Analyze
flutter analyze --no-fatal-infos
```

---

## Konteks Hackathon — BACA INI DULU

### Lomba: Gemma 4 Good Hackathon (Kaggle)
- URL: https://www.kaggle.com/competitions/google-gemma-4-good-hackathon
- **Gemma 4 adalah WAJIB** — semua fitur AI/LLM HARUS menggunakan Gemma 4
- **Cactus SDK** adalah bonus prize category — pastikan tetap dipakai
- BISINDO = Bahasa Isyarat Indonesia (berbeda dari SIBI)

### Kenapa Gemma 4 Dipilih — Unique Features Showcase
1. **Gemma 4 Audio Encoder** (PRIMARY STT): transkripsi suara tanpa Whisper — 1 model multimodal
2. **Gemma 4 Text** (Deaf->Hearing): gloss -> kalimat + saran empatik (contextual empathy)
3. **Gemma 4 Text** (Hearing->Deaf): simplifikasi kalimat untuk orang Tuli
4. **(Next)** Gemma 4 Vision: deteksi isyarat langsung dari kamera
5. **Single model architecture**: 1 model (~4GB) untuk semua AI tasks — no model swap needed

### Hardware
- Dev device: **Pixel 6a** (6GB RAM, Tensor G1)
- Gemma Cactus INT4: ~2 GB RAM saat inference (text+audio) — aman di Pixel 6a
- **Tidak perlu model swap** — 1 model Gemma 4 untuk semua

### Untuk Demo Submission
- Target demo: kedua flow end-to-end **offline**
- Download 1 model sekali (~4GB, butuh internet), setelah itu fully offline
- Fitur unggulan:
  - **Gemma 4 Multimodal** (audio+text+vision dari 1 model)
  - **Contextual Empathy** (AI saran empatik)
  - **Cactus SDK** (bonus prize category)
  - **Digital Equity & Inclusivity** (BISINDO, orang Tuli)
