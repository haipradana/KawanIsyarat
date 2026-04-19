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
`GemmaService.getEmpathyTips(sentence)` -> `List<String>` (2-4 bullet tips):
- System prompt khusus bullet, parsing line-by-line (strip `-`, `*`, `•`, `1.`, `1)`)
- State: `DeafToHearingState.empathyTips` (List<String>)
- UI: `_AiSuggestionCard(tips: [...])` — render bullet dots di bawah kalimat terjemahan

Contoh: gloss `SAYA | PUSING | OBAT`
-> "Saya merasa pusing dan butuh obat."
-> Tips empati AI:
   • Tanyakan apakah dia butuh diantar ke ruang kesehatan.
   • Bicara perlahan dan hadap wajah saat merespon.
   • Tawarkan air putih atau tempat duduk yang nyaman.

### Hearing -> Deaf
`GemmaService.simplifyForDeaf(text)` -> teks bersih tanpa filler words

---

## Gemma 4 Vision Sign Coach

### Alur
1. User pilih huruf dari `learn_alfabet_screen.dart`
2. Masuk `alphabet_practice_screen.dart` dengan fase `ready → holding (2.2s stable) → capturing → coaching → reviewed`
3. `CameraController.takePicture()` saat stabil → save ke temp dir (.jpg)
4. CNN prediksi untuk validasi (benar/salah)
5. Gemma 4 Vision review foto (via Cactus SDK) dengan knowledge-injected prompt
6. Tampilkan card: hasil CNN + tips Gemma + tombol "Coba Lagi" / "Selesai"

### Knowledge Injection (WAJIB)
Gemma 4 TIDAK punya pengetahuan bawaan tentang bentuk huruf BISINDO/SIBI.
Solusi: inject referensi bentuk per huruf di user message setiap call.

- `GemmaService._bisindoAlphabetReference` (26 huruf A-Z BISINDO, 2 tangan)
- `GemmaService._sibiAlphabetReference` (24 huruf A-Y skip J&Z, 1 tangan)
- `GemmaService._bisindoWordReference` (6 kata: maaf, saya, terima_kasih, tuli, dengar, rumah)

Format user message yang dikirim:
```
Mode: BISINDO (alfabet, 2 tangan)
Target: A
Ini percobaan ke-3. Pengguna sudah mencoba berulang — beri dorongan positif.

Referensi bentuk "A" yang BENAR:
Dua tangan mengepal, ibu jari kedua tangan saling bertemu/menempel...

Hasil CNN: SALAH (terdeteksi "E", target seharusnya "A").

Bandingkan foto tangan pengguna dengan referensi di atas...
```

### Attempt Counter
- `_attemptCount` di screen state, increment tiap `_triggerCapture()`
- Dikirim ke Gemma supaya tone adaptif:
  - attempt 1 → netral
  - attempt 2 → "tetap rileks"
  - attempt ≥3 → "beri dorongan positif, jangan menghakimi"

### Cactus Vision API
Image path dipass via field `"images": [absolutePath]` di messages JSON (sibling dari `content`).
Cactus parse di `cactus_utils.h::parse_messages_json` → load via stb_image → patch embedding.
TIDAK butuh ubah FFI — cukup extend `ChatMessage` dengan `images: List<String>?`.

Method: `GemmaService.reviewSignImage({imagePath, targetLabel, detectedLabel, mode, attemptCount})`

---

## Deaf Vocabulary Helper

### Tujuan
Teman Tuli kadang sulit memahami kata/istilah baru (asuransi, polis, formulir).
Screen `/learn/kamus` memungkinkan input kata → Gemma jelaskan dengan bahasa sederhana.

### Flow
1. TextField + tombol send (atau tap chip saran cepat)
2. `GemmaService.explainVocabulary(word)` → `VocabularyExplanation(word, meaning, example)`
3. Hasil di-insert ke `_history` list → scrollable card di bawah input

### System Prompt Structure
Gemma diinstruksikan return format fixed:
```
Arti: [1 kalimat singkat]
Contoh: [1 kalimat contoh penggunaan]
```
Parser split by `\n`, cari prefix "Arti:" dan "Contoh:".

### Local-first, no RAG
Pakai knowledge internal Gemma 4 — untuk kata umum Indonesia ini cukup.
Kalau nanti butuh istilah super spesifik (hukum, medis lokal), bisa tambah RAG dengan `cactusRagQuery`, tapi tidak prioritas MVP.

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

## Status Saat Ini (20 Apr 2026)

| Fitur | Status |
|---|---|
| Download model Gemma 4 | ✅ Bekerja (~4GB, sekali download) |
| Gemma 4 Audio Transcription (PRIMARY STT) | ✅ Bekerja — ~28s untuk 7s audio, 2.2 tok/s, fully offline |
| Gemma simplifyForDeaf (Hearing->Deaf) | ✅ Bekerja — 4-9s, 3.5-4.5 tok/s |
| Gemma gloss -> kalimat (Deaf->Hearing) | ✅ Implemented, belum ditest end-to-end |
| Contextual Empathy — bullet tips | ✅ Implemented (getEmpathyTips → List&lt;String&gt;, rendered as bullet card), belum ditest |
| Gemma 4 Vision Sign Coach (alfabet) | ✅ Implemented — single-shot capture + knowledge-injected prompt per huruf, belum ditest |
| Deaf Vocabulary Helper | ✅ Implemented — /learn/kamus, Gemma explain (Arti + Contoh), belum ditest |
| BISINDO Kata Picker (dropdown preview) | ✅ Implemented — /learn/kata picker, video preview masih placeholder |
| Thinking mode disabled | ✅ enable_thinking_if_supported: false |
| OOM guard panjang audio | ✅ Downsample 2-tap hanya jika PCM > 256KB |
| Whisper fallback | ✅ Opsional — hanya jika Gemma audio gagal |
| MediaPipe real detection | Implemented, belum ditest end-to-end |
| YOLO alphabet | ✅ Bekerja (legacy, sudah diganti Dense classifier) |
| SIBI + BISINDO Alphabet (Dense classifier) | ✅ Bekerja — SIBI 24 kelas (1 tangan), BISINDO 26 kelas A-Z + NOTHING (2 tangan) |
| TTS | Belum diverifikasi |

### TODO Lanjutan (prioritas urut)
1. **Test end-to-end Vision Sign Coach di Pixel 6a** — ukur latensi image encode + inference (~10-15s warm-up, 4-8s steady?)
2. **Test Contextual Empathy bullet tips end-to-end** — cek format parsing (bullet "-" vs numbered)
3. **Video preview BISINDO kata** — ganti placeholder di `learn_kata_picker_screen.dart` dengan video demo per kata (6 kata saja untuk fase 1)
4. **Retake session reset** — sekarang `_attemptCount` direset saat screen re-open; tambah tombol "Ganti Huruf" di review panel untuk pindah target tanpa keluar screen
5. **Gemma Vision Sign Coach untuk kata BISINDO** — ekstensi ke mode `bisindo_kata` (LSTM detection + capture frame representatif)
6. **Vocabulary Helper — streaming generation** — sekarang blocking 4-9s, enak kalau streaming token-per-token
7. **TTS verifikasi + wire ke bullet tips** — opsi "dengarkan tips" untuk orang dengar buta huruf
8. **Emergency Quick-Sign feature** (dari strategi hackathon) — 1 tombol → "Saya tuli. Saya butuh bantuan." → TTS
9. **Video demo kata BISINDO** — rekam library video manusia asli per kata (bukan animasi)
10. **Dataset BISINDO alphabet merger** — re-train dengan dataset faizalfarizi + idhamozi (script `ml/prepare_bisindo_alphabet.py` sudah siap, tinggal run di Kaggle)

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

---

## Hackathon Winning Strategy (April 2026)

### Personal Story — KEKUATAN UTAMA
Developer (Pradana) punya **adik yang Tuli**. App ini bukan project iseng — ini kebutuhan nyata.
Di video, adik yang Tuli harus PAKAI app-nya di depan kamera. Bukan Pradana demo sendiri.
Referensi pemenang sebelumnya: developer bikin device untuk saudara buta → personal, emosional.

### Target Track (bisa menang BEBERAPA sekaligus)
| Track | Prize | Strategi |
|---|---|---|
| **Digital Equity & Inclusivity** | $10K | BISINDO, 2 juta deaf Indonesia tanpa AI tools |
| **Cactus** | $10K | On-device Gemma 4 via Cactus SDK |
| **Future of Education** | $10K | Sign learning + AI coach + vocab helper |
| **Main Track** | $50K-$10K | Tergantung "wow" factor video |

### SignGemma Positioning
Google sedang develop **SignGemma** (sign language AI) tapi belum rilis dan fokus ASL saja.
KawanIsyarat = "We're building what SignGemma promises — for BISINDO, TODAY, fully offline."
Framing di writeup: open model ecosystem (Gemma 4) empowers local devs to solve problems
yang bahkan Google sendiri belum sempat address.

### 3 Pilar Fitur

#### Pilar 1: Two-Way Communication (Hear Me TIDAK bisa)
```
Deaf → Hearing: Camera → MediaPipe → 1D CNN → Gloss → Gemma 4 → Kalimat + Empathy + TTS
Hearing → Deaf: Mic → Gemma 4 Audio → Transkripsi → Gemma 4 Simplify + Vocab Helper
```

#### Pilar 2: Learning — Dua Arah (upgrade dari Hear Me)
```
UNTUK DEAF:
  LIHAT  → Video manusia asli cara sign (bukan animasi robot)
  COBA   → User praktek di kamera langsung
  REVIEW → CNN detect + Gemma 4 Vision feedback ("jarimu kurang tepat, coba lagi!")
  PAHAM  → Vocab helper jelaskan kata sulit untuk Tuli

UNTUK HEARING:
  Belajar alfabet isyarat (SIBI) → ejaan jari nama, singkatan
  Belajar kata dasar BISINDO → bisa berkomunikasi dasar dengan orang Tuli
  → Breaking the wall: hearing juga explore & PD berkomunikasi dengan Tuli
```

#### Pilar 3: Single Model Offline
```
Gemma 4 E2B = 1 model, 4 peran (text + audio + vision + reasoning), 0 internet
→ Cocok untuk Indonesia rural yang internet tidak stabil
```

### Vs Kompetitor

| | Google Interpreter | Hear Me | KawanIsyarat |
|---|---|---|---|
| Bahasa isyarat | ASL | BISINDO (pasif) | **BISINDO (aktif + pasif)** |
| Live recognition | ❌ | ❌ | **✅ CNN real-time** |
| Two-way comm | ❌ | ❌ | **✅ Deaf↔Hearing** |
| AI learning coach | ❌ | ❌ | **✅ Gemma 4 Vision** |
| Vocab helper | ❌ | ❌ | **✅ Kata sulit dijelaskan** |
| Empathy suggestion | ❌ | ❌ | **✅ Saran untuk hearing** |
| Offline | ❌ | ❌ | **✅ Fully offline** |
| Library kosakata | ❌ | ✅ Animasi | **Video manusia asli** |

### Killer Features (yang TIDAK ADA di app lain)
1. **Gemma 4 Vision Sign Coach** — camera capture → Gemma review → "Hampir benar! Telunjuk harus lebih ke telinga."
2. **Contextual Empathy** — bukan cuma translate, tapi saran cara berkomunikasi dengan Tuli
3. **Deaf Vocabulary Helper** — detect kata sulit (asuransi, polis, formulir) → jelaskan sederhana
4. **Emergency Quick-Sign** — 1 tombol → "Saya tuli. Saya butuh bantuan." → TTS
5. **Fully offline BISINDO** — satu-satunya AI app untuk BISINDO yang kerja tanpa internet
6. **Breaking the Wall** — bukan cuma alat bantu Tuli, tapi juga mendorong hearing untuk belajar BISINDO → komunikasi jadi seamless dari kedua sisi

### Visi Jangka Panjang: Platform & Plugin Ecosystem

#### Misi Utama
KawanIsyarat bukan sekadar app — ini adalah **jembatan** yang memecah tembok komunikasi.
Tujuannya: Tuli lebih PD dan eksplor dunia, hearing lebih PD dan mau belajar komunikasi dengan Tuli.
Ketika kedua sisi bergerak mendekat → komunikasi jadi **seamless**.

#### Plugin / SDK Vision (Setelah Hackathon)
- **Video Call Plugin** — embed KawanIsyarat sebagai overlay di WhatsApp VC, Zoom, Google Meet
  - Real-time sign → text subtitle di video call
  - Audio → simplified text untuk participant Tuli
  - Accessibility layer yang bisa ditambahkan ke platform manapun
- **Android Accessibility Service** — system-wide overlay, aktif di app apapun
- **Web SDK** — JavaScript SDK untuk embed di website (customer service, e-learning, telehealth)
- **API / On-Device SDK** — developer lain bisa integrasi BISINDO recognition ke app mereka

#### Kenapa Ini Penting untuk Writeup
- Menunjukkan app ini bukan one-time hackathon project tapi punya **scalable vision**
- Plugin approach = **multiplier effect** — 1 teknologi, jutaan touchpoint
- Framing: "Today it's an app. Tomorrow it's an accessibility layer for the entire Indonesian digital ecosystem."

### Video Script (3 menit)
```
0:00-0:20  HOOK
  "Di Indonesia, 2 juta orang Tuli pakai BISINDO. Tidak ada satu pun
   AI app yang mendukung mereka. Adik saya salah satunya."

0:20-0:40  PERSONAL STORY
  Tunjukkan adik Tuli dalam keseharian. Kesulitan di RS/bank/sekolah.
  "Setiap kali dia perlu ke dokter, saya harus ikut sebagai juru bahasa."

0:40-1:30  DEMO: TWO-WAY COMMUNICATION
  Adik sign BISINDO → app translate → orang dengar paham + saran empatik
  Orang dengar bicara → app transkripsi → simplify untuk adik baca + vocab helper

1:30-2:00  DEMO: LEARNING MODE
  Adik belajar kata baru → lihat video manusia → coba di kamera → AI feedback
  "Hampir benar! Coba lagi." → berhasil → senyum

2:00-2:30  TECHNICAL WOW
  "Semua ini berjalan dari SATU model Gemma 4, fully offline, di HP biasa.
   Audio, text, vision — satu model, zero internet."
  Tunjukkan: matikan WiFi → app tetap jalan

2:30-2:50  VISION: BREAKING THE WALL
  "KawanIsyarat bukan cuma untuk orang Tuli. Orang dengar juga bisa belajar
   isyarat di sini. Ketika kedua sisi bergerak mendekat — tembok itu runtuh."
  Tunjukkan: hearing user belajar alfabet isyarat di app
  "Bayangkan ini sebagai plugin di WhatsApp video call, Zoom, Google Meet —
   real-time sign language subtitle, di mana saja."

2:50-3:00  CLOSING
  "Google sedang membangun SignGemma untuk ASL. Tapi 2 juta orang Tuli Indonesia
   tidak bisa menunggu. KawanIsyarat hadir sekarang — dibangun dengan Gemma 4,
   untuk adik saya, dan untuk semua Tuli di Indonesia."
  Shot terakhir: adik tersenyum menggunakan app
```

### Writeup Key Sentences (English)
- "KawanIsyarat is the first AI-powered BISINDO communication app — built for my deaf sibling and 2 million deaf Indonesians."
- "One Gemma 4 model powers ALL AI tasks: audio transcription, text generation, vision feedback, and contextual empathy — fully offline on a $300 phone."
- "While Google develops SignGemma for ASL, KawanIsyarat brings that vision to BISINDO TODAY — proving that the Gemma open model ecosystem empowers local developers to solve accessibility challenges in their own communities."
- "KawanIsyarat doesn't just help the deaf communicate — it empowers hearing people to learn sign language too, breaking the wall from BOTH sides. Today it's an app; tomorrow it's an accessibility layer for video calls, websites, and the entire Indonesian digital ecosystem."

### Gesture Recognition — Dual Model Architecture

#### Model 1: SIBI Alfabet (Statis)
- Dataset: Kaggle SIBI 5280 gambar (A-Z, ~220/huruf)
- Feature: 42 floats (21 hand landmarks × xy, Boháček bbox-normalized)
- Model: Dense classifier (bukan LSTM — huruf statis)
- Skip: J, Z (dinamis)
- Script: `ml/prepare_sibi_alphabet.py`

#### Model 2: BISINDO Kata Umum (Dinamis)
- Dataset: Rekam sendiri via webcam
- Vocabulary fase 1 (16 kelas):
  TULI, SAYA, KAMU, NAMA, TOLONG, APA, TERIMA_KASIH,
  BAIK, SAKIT, LAPAR, HAUS, MINTA, PAGI, MALAM, SEKOLAH, NOISE
- Feature: 94 floats/frame (nose-centered, shoulder-normalized)
  + temporal derivatives saat training (94 × 3 = 282 floats/frame)
- Sequence: 30 frame @ 15fps = 2 detik
- Model: 1D CNN (Causal Depthwise Conv, kernel=11) — mengikuti arsitektur 1st place Kaggle ASL Signs
- Tanpa Transformer (data terlalu kecil, prone overfit)
- Script: `ml/data_collector.py`

#### Normalisasi (kedua model)
- Nose-centered: semua koordinat dikurangi posisi hidung
- Shoulder-width scaling: dibagi lebar bahu → scale-invariant
- Temporal derivatives (Model 2 only): velocity + acceleration
- Mengikuti approach 1st place Kaggle ASL Signs (Hoyeol Sohn)

### ML Pipeline Files
```
ml/
  data_collector.py          — Rekam data BISINDO kata dari webcam (94 floats)
  prepare_sibi_alphabet.py   — Ekstrak SIBI alfabet → landmarks (42 floats)
  prepare_asl_dataset.py     — Opsional: import Google ASL Signs dataset
  requirements.txt           — mediapipe, opencv, numpy, pandas, pyarrow
  dataset/                   — Output BISINDO kata (per label folder)
  dataset_alphabet/          — Output SIBI alfabet (per huruf folder)
```
