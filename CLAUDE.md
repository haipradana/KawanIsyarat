# KawanIsyarat — Project Context untuk AI

## Ringkasan Proyek
Aplikasi Flutter untuk komunikasi antara orang **Tuli (BISINDO)** dan orang dengar.
Peserta **Gemma 4 Good Hackathon (Kaggle)** — penggunaan Cactus SDK adalah bonus prize category.
Developer: Pradana, Pixel 6a (Android 16, arm64-v8a), package `com.kawanisyarat.kawan_isyarat`.

---

## Dua Flow Utama

### 1. Deaf → Hearing
Kamera → MediaPipe (tangan+pose) → LSTM → gloss BISINDO → **Gemma 4** → kalimat natural + saran empatik AI → TTS

### 2. Hearing → Deaf
Mikrofon → **Whisper STT** → unload Whisper → **Gemma 4** simplifikasi → teks sederhana untuk Tuli

---

## Stack Teknis

| Komponen | Detail |
|---|---|
| Framework | Flutter + Riverpod + GoRouter |
| LLM | Gemma 4 E2B via **flutter_gemma** (LiteRT LM / MediaPipe GenAI) — ~676MB RAM GPU |
| STT | Whisper Base INT8 via **Cactus SDK** (FFI) — tetap Cactus, tidak ada alternatif LiteRT |
| Gesture | MediaPipe (pose 33 landmarks + hand 21 landmarks) → LSTM TFLite |
| Alphabet | YOLO11n (`yolo_alphabet_sign_int8.tflite`) 26 huruf A-Z |
| State | Riverpod `StateNotifierProvider` |

### Migrasi Gemma: Cactus → flutter_gemma (LiteRT LM)
- **Kenapa migrasi:** Cactus Gemma 4 E2B INT4 (~2GB RAM) OOM di Pixel 6a bahkan setelah Whisper di-unload
- **Solusi:** flutter_gemma menggunakan MediaPipe GenAI backend (LiteRT) — terbukti jalan di Pixel 6a via AI Edge Gallery (~676MB RAM, ~3.2s response, GPU+CPU)
- **Model format:** `.litertlm` (LiteRT-LM native format, ~2.58GB) — ini yang dipakai AI Edge Gallery di Pixel 6a
- **Model URL baru:** `https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm`
- **Kenapa `.litertlm` bukan `.task`:** `.task` adalah format web/browser (MediaPipe WASM), `.litertlm` adalah LiteRT-LM native untuk Android — support GPU/NPU, dipakai oleh AI Edge Gallery
- **Kode Cactus Gemma:** dicomment di `gemma_service.dart`, bisa direstore untuk device RAM ≥ 8GB

---

## Model URLs & Paths

### URLs Saat Ini
```
Gemma (LiteRT-LM):    https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm
Whisper (Cactus zip):  https://huggingface.co/Cactus-Compute/whisper-base/resolve/main/weights/whisper-base-int8.zip
```
Path di HP: `/data/user/0/com.kawanisyarat.kawan_isyarat/app_flutter/cactus_models/`
- Gemma: `.../cactus_models/gemma-4-e2b-it.litertlm` (single file ~2.58GB)
- Whisper: `.../cactus_models/whisper-base-int8/` (directory, extracted dari zip)

### Gemma URL lama (Cactus, disabled):
```
https://huggingface.co/Cactus-Compute/gemma-4-E2B-it/resolve/main/weights/gemma-4-e2b-it-int4.zip
```

## Cactus SDK — Hal Penting (Whisper Only)

### Cactus masih dipakai untuk Whisper
Path di HP: `/data/user/0/com.kawanisyarat.kawan_isyarat/app_flutter/cactus_models/`

### Whisper Prompt (WAJIB persis ini)
```dart
'<|startoftranscript|><|id|><|transcribe|><|notimestamps|>'
```
- `<|notimestamps|>` **HARUS ADA** — tanpanya model generate timestamp tokens yang di-filter → response kosong
- `max_tokens: 2048` di options JSON
- `completion_mode: local` untuk disable cloud fallback

### Whisper FFI Call
```dart
cactusTranscribe(handle, audioPath, prompt, optionsJson, null, null)
// prompt BUKAN null — harus string di atas
```

### Model Swap (RAM Management)
Pixel 6a tidak kuat load Whisper + Gemma bersamaan (OOM ~1.7GB+).
Solusi: setelah transkripsi, `_sttService.dispose()` → panggil Gemma → reload Whisper saat rekam berikutnya.

---

## File-File Kunci

```
lib/core/ffi/
  cactus.dart              — FFI bindings (JANGAN EDIT)
  cactus_wrapper.dart      — High-level wrapper: CactusModel, CactusTranscriber

lib/core/services/
  model_manager.dart       — Download & path management model
  gemma_service.dart       — GemmaService (singleton): refineGloss, refineGlossWithEmpathy, simplifyForDeaf
  stt_service.dart         — SttService (singleton): initialize, transcribeFile, dispose
  mediapipe_service.dart   — Real MediaPipe pose+hand detection (258 floats/frame)
  gesture_service.dart     — LSTM sliding window (30 frames × 258 floats)
  yolo_alphabet_service.dart — YOLO11n A-Z detection

lib/core/providers/
  communication_provider.dart — DeafToHearingNotifier, HearingToDeafNotifier

lib/features/communication/screens/
  comm_deaf_to_hearing_screen.dart   — Kamera + capture isyarat → kalimat + AI suggestion card
  comm_hearing_to_deaf_screen.dart   — Rekam suara → transkripsi → Gemma simplify

lib/features/learning/screens/
  alphabet_practice_screen.dart      — YOLO alphabet detection
```

---

## Fitur Contextual Empathy (Gemma 4)

### Deaf → Hearing
`GemmaService.refineGlossWithEmpathy(glossList)` → `EmpathyResult`:
- `sentence`: terjemahan kalimat lengkap
- `aiSuggestion`: saran proaktif untuk orang dengar

Contoh: gloss `SAYA | PUSING | OBAT`
→ "Saya merasa pusing dan butuh obat."
→ (Saran AI): "Tanyakan apakah dia butuh diantar ke ruang kesehatan atau air putih."

### Hearing → Deaf
`GemmaService.simplifyForDeaf(text)` → teks bersih tanpa filler words

---

## MediaPipe Feature Vector (258 floats/frame)

```
Pose:  33 landmarks × 4 (x,y,z,visibility) = 132 floats  → index 0–131
Hand L: 21 landmarks × 3 (x,y,z) = 63 floats             → index 132–194
Hand R: 21 landmarks × 3 (x,y,z) = 63 floats             → index 195–257
```
LSTM model: `assets/models/bisindo_gesture.tflite`, 30-frame window, 32+ kelas BISINDO.

---

## YOLO11n Alphabet

- Model: `assets/models/yolo_alphabet_sign_int8.tflite`
- Input: `[1][320][320][3]` float32 (letterbox RGBA→RGB)
- Output: `[1][30][2100]` → 26 class scores (index 4–29), 2100 anchors
- Selalu return hasil (fallback `_bestAnchor` kalau tidak ada yang lewat threshold 0.10)

---

## Status Saat Ini (terakhir ditest)

| Fitur | Status |
|---|---|
| Download model (Gemma + Whisper) | ✅ Bekerja |
| Whisper STT transkripsi | ✅ Bekerja (`cloud_handoff: true` — perlu internet) |
| Gemma gloss → kalimat | ✅ Bekerja (via flutter_gemma LiteRT) |
| Contextual Empathy (AI suggestion) | ✅ Implemented, belum ditest penuh dengan LiteRT |
| Gemma simplifyForDeaf | ⚠️ Diimplementasi via flutter_gemma, belum ditest (sebelumnya force close di Pixel 6a dengan Cactus) |
| MediaPipe real detection | ✅ Implemented, belum ditest end-to-end |
| YOLO alphabet | ✅ Bekerja |
| `cloud_handoff: true` Whisper | ⚠️ Masih terjadi — `completion_mode: local` belum terbukti fix |

---

## Optimasi Cactus (TODO — nanti setelah LiteRT LM jalan)

Cactus Gemma & Whisper sebelumnya **tidak mengaktifkan NPU/GPU** sama sekali — jalan CPU murni.
Yang perlu dicoba kalau mau balik/optimize Cactus:

1. **`enable_pro: true`** di options JSON → aktifkan NPU/GPU Cactus
   ```dart
   // Di CactusModel.complete() dan CactusTranscriber.transcribeFile():
   final options = {'max_tokens': ..., 'enable_pro': true, ...};
   ```
2. **Kuantisasi sudah benar**: Gemma INT4 ✅, Whisper INT8 ✅ — tidak perlu diubah
3. **NPU Cactus** sudah **LANDING** di `cactus-compute/cactus-flutter` commit "Adding NPU support (#29)" ~4 bulan lalu — bukan "Coming" lagi. Cek API-nya di README terbaru sebelum implementasi.
4. **Memory management** sudah benar (dispose, singleton, model swap) ✅

→ Prioritas: LiteRT LM dulu, Cactus optimization belakangan.

---

## Yang Belum Selesai / Perlu Ditest

1. **Whisper local inference** — `cloud_handoff: true` masih terjadi. Kemungkinan Whisper base INT8 butuh pendekatan lain untuk force local. Investigasi key lain di options JSON Cactus.
2. **End-to-end Deaf→Hearing** — MediaPipe + LSTM + Gemma empathy belum ditest full dengan tangan nyata.
3. **Gemma untuk Hearing→Deaf tidak jalan di Pixel 6a** — Gemma 4 E2B INT4 butuh ~2GB RAM, melebihi limit Pixel 6a bahkan setelah Whisper di-unload (OOM/force close). Solusi:
   - Opsi A: Skip Gemma untuk Hearing→Deaf, tampilkan raw Whisper transcription langsung (sudah cukup baik)
   - Opsi B: Test di HP dengan RAM ≥ 8GB (e.g. Pixel 8 Pro, Samsung S23+)
   - Opsi C: Pakai model Gemma yang lebih kecil (belum ada di Cactus-Compute HuggingFace)
4. **Reload Whisper latency** — model swap (~2-3s reload) belum diukur UX-nya.
5. **TTS** — `TtsService` belum diverifikasi bekerja setelah kalimat dari Gemma.

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
- **Gemma 4 adalah WAJIB** — semua fitur AI/LLM HARUS menggunakan Gemma 4 via Cactus SDK
- **JANGAN pernah skip/nonaktifkan Gemma** meski device tidak kuat — kode harus tetap memanggil Gemma, device yang perlu diupgrade
- **Cactus SDK** adalah bonus prize category — pastikan tetap dipakai dan prominently disebutkan
- BISINDO = Bahasa Isyarat Indonesia (berbeda dari SIBI)

### Kenapa Gemma 4 Dipilih untuk Fitur Ini
1. **Deaf→Hearing**: Gemma menerjemahkan gloss + menambahkan saran empatik ("world knowledge" Gemma untuk fasilitasi komunikasi berempati) — ini nilai utama submission
2. **Hearing→Deaf**: Gemma membersihkan/menyederhanakan transkripsi Whisper (filler words, inakurasi) supaya lebih mudah dipahami orang Tuli

### Keterbatasan Hardware Saat Ini
- Dev device: **Pixel 6a** (6GB RAM) — tidak cukup untuk Gemma 4 E2B INT4 (~2GB) + Whisper bersamaan
- Gemma untuk Hearing→Deaf flow OOM/force close di Pixel 6a
- **Solusi untuk demo/judging**: pakai HP dengan RAM ≥ 8GB (Pixel 8 Pro, Samsung S23+, dll)
- Kode sudah benar — model swap strategy sudah diimplementasi, tinggal butuh device lebih baik

### Untuk Demo Submission
- Target demo: kedua flow berjalan end-to-end **offline** di device RAM ≥ 8GB
- Download model hanya sekali (butuh internet), setelah itu fully offline
- Fitur unggulan untuk submission: **Contextual Empathy** (Gemma generates empathic suggestion for hearing person)
