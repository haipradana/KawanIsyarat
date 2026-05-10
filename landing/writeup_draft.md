# KawanIsyarat — Hackathon Writeup Draft
## Gemma 4 Good Hackathon · Kaggle 2026

---

## Motivation

My younger brother is deaf. He uses BISINDO — Bahasa Isyarat Indonesia, the sign language of Indonesia's deaf community. According to Kemenko PMK (2023), around 22.97 million Indonesians are deaf or hard of hearing. Every time he needed to visit a doctor, attend a meeting, or handle anything at a government office, I had to come along as a human interpreter. Not because he couldn't communicate — he communicates beautifully in BISINDO. But because no tool existed to bridge the gap.

I spent weeks researching existing solutions. Google's interpreter tools focus on ASL. Hear Me, the most prominent Indonesian sign language app, offers a passive vocabulary library — but no live recognition, no two-way communication, no AI understanding. Zero AI apps existed for BISINDO.

So I built KawanIsyarat.

This is not a research demo or a proof-of-concept notebook. It is a real Android application that my brother can install today and use to communicate with anyone — without needing me present.

---

## The Problem

The communication barrier between deaf and hearing people in Indonesia is a daily reality for millions. Indonesia has an estimated 22.97 million people with hearing disabilities (Kemenko PMK, 2023) — around 8.5% of the population:

- **At hospitals**: Deaf patients must bring a hearing companion to interpret — losing privacy and independence in the most personal of situations.
- **At schools and offices**: Critical information gets lost. Misunderstandings happen constantly.
- **In emergencies**: When seconds matter, there is no fast way for a deaf person to communicate "I am deaf, I need medical help."
- **With complex language**: Indonesian bureaucratic and medical vocabulary ("asuransi", "polis", "formulir", "resep") frequently goes unexplained to deaf users who grew up with a different primary language.

The hearing world has not moved to meet the deaf halfway. KawanIsyarat is built to change that — from both sides.

---

## Solution Approach

I want to especially thank my brother for participating in testing and in the demo video. Working directly with someone who uses BISINDO daily provided invaluable insights into what an accessibility app must get right — not just what is technically impressive, but what is genuinely useful when you depend on it.

My design philosophy was the same as the Gemma Vision winner from the Gemma 3n hackathon: **one singular focus, done deeply.** But BISINDO communication has two sides, so KawanIsyarat focuses deeply on one thing: **making two-way communication between deaf and hearing people effortless and dignified.**

Gemma 4 was the obvious choice — specifically because of its multimodal capabilities. One model handles audio transcription, text generation, vision feedback, and reasoning. No model swapping. No multiple downloads. One 4 GB model, downloaded once, runs forever offline.

I chose Cactus SDK over flutter_gemma (LiteRT) after benchmarking both on a Pixel 6a. Cactus uses custom C++ with ARM SIMD kernels optimized for on-device inference — giving 3.5–4.5 tok/s with only 1.7–1.9 GB RAM usage. This matters for Android mid-range devices that are the primary phones of the communities KawanIsyarat is built for.

---

## What I Built

KawanIsyarat has three interconnected modules:

### 1. Two-Way Communication

**Deaf → Hearing:**
A live camera feed runs MediaPipe (33 pose landmarks + 21×2 hand landmarks = 258 floats per frame). These feed into a 1D Causal Depthwise CNN — architecture inspired by the 1st place Kaggle ASL Signs solution — which recognizes BISINDO words from a 30-frame (2-second) sliding window. Recognized gloss sequences are passed to Gemma 4, which generates a natural Indonesian sentence and then produces contextual empathy tips: short, actionable suggestions helping hearing users respond with appropriate empathy and communication style.

*Example: Gloss `SAYA | PUSING | OBAT` → "Saya merasa pusing dan butuh obat." → Empathy tips: "Tanyakan apakah dia butuh diantar ke ruang kesehatan. Bicara perlahan dan hadap wajah saat merespon."*

**Hearing → Deaf:**
Voice is recorded as WAV 16kHz 16-bit mono. I strip the 44-byte WAV header and pass raw PCM directly to `cactusComplete(pcmData:)` with the user message `<|audio|>` — Gemma 4's built-in audio encoder handles transcription. The transcript is then passed back to Gemma 4 to simplify: removing filler words, shortening sentences, replacing complex vocabulary with plain Indonesian. The result is displayed as clean text for the deaf user to read.

### 2. Learning Module

**Gemma 4 Vision Sign Coach:** The user selects a letter or word to practice. After holding their hand sign steady for 2.2 seconds, the camera captures a photo. A Dense classifier (SIBI/BISINDO alphabet) validates the prediction. The photo path is then passed to Gemma 4 Vision via the Cactus SDK messages JSON format (`"images": [absolutePath]`), alongside a knowledge-injected prompt containing the exact BISINDO reference description for that letter. Gemma reviews the photo and provides specific feedback: *"Hampir benar! Telunjukmu perlu lebih ditekuk ke dalam."*

Because Gemma 4 has no innate knowledge of BISINDO letter shapes, I built a full reference library (26 BISINDO letters + 24 SIBI letters + 6 common words) injected into every vision call. Attempt count is tracked and passed to the prompt — so tone adapts from neutral (attempt 1) to encouraging and non-judgmental (attempt 3+).

**Deaf Vocabulary Helper:** A simple but powerful feature. The deaf user types any word they don't understand. Gemma 4 explains it in simple Indonesian with a practical example sentence. Designed for the vocabulary gap deaf users often experience with bureaucratic and technical terms.

**Idiom Translator:** Preset idioms from a curated BISINDO list are explained instantly (no AI call). Unknown expressions typed by the user are explained via Gemma 4.

**Articulation Practice:** Hearing users can practice pronouncing BISINDO-related words. They record their voice, Gemma 4 Audio transcribes it, and `feedbackArtikulasi()` provides pronunciation guidance.

### 3. Emergency SOS

One-tap access to six critical emergency phrases — "I am deaf", "I need medical help", "Please call my family", "I am lost", "Please call the police", "I need an interpreter" — each immediately spoken aloud via TTS. No navigation, no typing, one button.

---

## Technical Challenges I Actually Faced

This section is the most honest part of this writeup. These are not hypothetical problems — they are problems I hit, debugged, and solved.

### Gemma Thinking Mode: 153 seconds → 4 seconds

The biggest surprise in integrating Cactus SDK was discovering that by default, it injects `<|think|>` into the system prompt, causing Gemma 4 to enter thinking mode before responding. On a Pixel 6a, this produced response times of 60–153 seconds for simple queries — completely unusable for communication.

After reading through the Cactus source code (`engine_tokenizer.cpp` → `format_gemma4_style()`), I found the flag: `enable_thinking_if_supported`. Setting this to `false` in the options JSON passed to `cactusComplete()` brought response times down to a consistent **4–9 seconds**, with 3.5–4.5 tok/s throughput. This single discovery was the difference between an unusable and usable app.

### Out-of-Memory on Long Audio

Gemma 4's audio encoder is memory-hungry. Testing showed that PCM data above ~256 KB causes OOM crashes on the Pixel 6a. A 7-second audio clip at 16kHz is about 229 KB — safely within limits. But users speaking longer explanations would crash the app.

I implemented a 2-tap decimation guard: if raw PCM exceeds 256 KB, I average each pair of consecutive int16 samples, halving the data size. This is not a proper low-pass resample — it's a pragmatic OOM guard. The audio is effectively "sped up 2×" from Gemma's perspective, but for typical short speech this remains accurate enough for transcription. Audio under 8 seconds is sent at full 16kHz quality with no modification.

### Camera Lifecycle and the Notification Shade

A subtle but critical bug: the camera would permanently freeze if the user pulled down Android's notification shade or quick settings panel while recording. The root cause was using `AppLifecycleState.inactive` as the trigger to dispose the camera controller. On Android, `inactive` fires for notification shade interactions — not just app switching. Changing to `AppLifecycleState.paused` (which only fires when the app is truly backgrounded) fixed this completely.

### Whisper Fallback Prompt Format

When integrating Whisper via Cactus SDK as a fallback STT option, I discovered that the prompt must end with `<|notimestamps|>` — without it, the model generates timestamp tokens that get filtered from the output, resulting in empty responses. The correct prompt format is: `<|startoftranscript|><|id|><|transcribe|><|notimestamps|>`. This took considerable debugging to identify.

### flutter_gemma vs Cactus SDK Decision

I originally started with flutter_gemma (LiteRT, MediaPipe GenAI) — it uses ~676 MB GPU RAM and achieves ~3.2 second responses via GPU acceleration. However, it requires the proprietary `.litertlm` format and provides less control over inference parameters. Cactus SDK, while requiring more setup (FFI bindings, zip extraction, path management), gave me full control: `n_ctx`, `memory_f32`, `batch_size`, `n_threads`, and the ability to pass PCM audio and image paths directly. The tradeoff of higher RAM usage (~1.9 GB) was worth the flexibility. I kept the flutter_gemma implementation commented in the codebase as a fallback for lower-end devices.

---

## Architecture

```
KawanIsyarat
├── Communication Layer
│   ├── Deaf → Hearing:  Camera → MediaPipe (258 floats/frame) → 1D CNN → Gloss → Gemma 4 Text → Sentence + Empathy Tips → TTS
│   └── Hearing → Deaf:  Mic → WAV → PCM → Gemma 4 Audio → Transcript → Gemma 4 Simplify → Clean Text
│
├── Learning Layer
│   ├── Sign Coach:       Camera capture → Dense Classifier → Gemma 4 Vision (knowledge-injected) → Feedback
│   ├── Vocab Helper:     Text input → Gemma 4 Text → Simple explanation + example
│   ├── Idiom Translator: Preset (instant) or Gemma 4 (custom query)
│   └── Articulation:     Voice → Gemma 4 Audio → Transcript → Gemma 4 feedback
│
└── Emergency Layer
    └── SOS:              One-tap → TTS phrase → Immediate audio output
```

**ML Stack:**
| Component | Detail |
|---|---|
| LLM | Gemma 4 E2B INT4 via Cactus SDK (~4 GB, ~1.9 GB RAM at runtime) |
| Audio STT | Gemma 4 Audio Encoder (primary) · Whisper Base INT8 via Cactus (fallback) |
| Gesture recognition | MediaPipe pose (33 lm) + hand (21×2 lm) → 1D CNN, 16 BISINDO classes |
| Alphabet recognition | Dense classifier: SIBI 24 classes + BISINDO 26 classes |
| Framework | Flutter + Riverpod + GoRouter |
| State management | `StateNotifierProvider` with cross-provider `Ref` injection |

---

## Impact

KawanIsyarat targets four hackathon prize tracks simultaneously because it genuinely addresses all four:

1. **Digital Equity & Inclusivity** — 22.97 million Indonesians with hearing disabilities (Kemenko PMK, 2023), zero dedicated AI tools for BISINDO before this.
2. **Future of Education** — Sign Coach with AI vision feedback, vocabulary helper, alphabet/word learning for both deaf and hearing.
3. **Cactus SDK Bonus Prize** — Gemma 4 E2B deployed on-device via Cactus custom inference engine.
4. **Main Track** — Gemma 4 multimodal showcase: one model handling audio, vision, and text reasoning.

**KawanIsyarat is not just a tool for deaf people.** It is also designed to help hearing people learn BISINDO — breaking the wall from both directions. When both sides move toward each other, the wall comes down.

Today it is an Android app. The vision is an accessibility layer: a plugin for WhatsApp video calls, Zoom, Google Meet — real-time sign language subtitles, deaf-friendly text simplification, anywhere. A Web SDK and Android Accessibility Service overlay are the natural next steps.

---

## Comparison to Existing Solutions

| | Google Interpreter | Hear Me | KawanIsyarat |
|---|---|---|---|
| Sign language | ASL | BISINDO (passive library) | **BISINDO (live, active)** |
| Live recognition | ❌ | ❌ | ✅ Real-time CNN |
| Two-way communication | ❌ | ❌ | ✅ Deaf ↔ Hearing |
| AI learning coach | ❌ | ❌ | ✅ Gemma 4 Vision |
| Vocabulary helper | ❌ | ❌ | ✅ Gemma 4 Text |
| Empathy suggestions | ❌ | ❌ | ✅ Contextual tips |
| Fully offline | ❌ | ❌ | ✅ |
| Personal story | — | — | ✅ Developer's deaf brother |

---

## Closing

Google is building SignGemma for ASL. But 22.97 million deaf and hard-of-hearing Indonesians cannot wait for a global product to localize.

KawanIsyarat is what that future looks like — for BISINDO, today, on a $300 Android phone, fully offline, built by someone who needs it in their own family.

The open Gemma ecosystem made this possible. I hope this demonstrates what local developers can build when given the right foundation.

— Pradana Yahya Abdillah, Universitas Gadjah Mada

---

*Built with Gemma 4 E2B · Cactus SDK · Flutter · MediaPipe · TFLite*
*Submitted to Gemma 4 Good Hackathon · Kaggle · May 2026*
