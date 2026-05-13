# KawanIsyarat: Offline Gemma 4 for BISINDO Communication
## A local-first Android app that helps Deaf BISINDO users and hearing Indonesians meet halfway.

## Motivation

My younger brother is Deaf and uses BISINDO, the sign language of Indonesia's Deaf community. In hospitals, meetings, schools, or government offices, I often had to come with him as the interpreter. Not because he cannot communicate, but because the hearing world around him usually cannot understand BISINDO.

Indonesia has millions of Deaf and hard-of-hearing people, yet practical AI tools for BISINDO are almost nonexistent. Most sign-language AI demos target ASL. The most visible Indonesian alternatives are vocabulary libraries, not live two-way communication tools. KawanIsyarat was built from that gap: a real Android app my brother can install and use without waiting for a server, a subscription, or me standing beside him.

KawanIsyarat is not built to make Deaf people adapt alone; it is built so hearing people finally carry part of the communication effort too.

The core requirement was simple: communication must still work when the internet is weak, when the conversation is private, and when the user only has a mid-range Android phone.

## What KawanIsyarat Does

KawanIsyarat is a two-way communication and learning app for BISINDO:

- **Deaf → Hearing:** camera -> MediaPipe landmarks -> 1D CNN -> BISINDO gloss -> Gemma 4 -> natural Indonesian sentence + empathy tips -> TTS.
- **Hearing → Deaf:** microphone -> 16 kHz WAV -> raw PCM -> Gemma 4 Audio -> transcript -> Gemma 4 simplification -> short, clear Indonesian text.
- **Learning:** alphabet and word practice with local classifiers plus Gemma 4 Vision feedback.
- **Vocabulary help:** Gemma 4 explains difficult Indonesian words in simple language for Deaf readers.
- **Emergency SOS:** one-tap spoken phrases such as "I am Deaf", "I need medical help", and "Please call my family".

This is not a chatbot wrapped in an accessibility theme. It is an accessibility workflow where Gemma 4 is the language, audio, vision, and reasoning layer behind daily communication.

## Why Gemma 4 Offline Matters

Gemma 4 E2B INT4 is downloaded once, then runs fully offline through Cactus SDK. This matters for three reasons.

First, accessibility cannot depend on connectivity. A Deaf user may need help in a clinic, a market, a school office, or on the road. The app should not fail because mobile data is unstable.

Second, privacy matters. Medical questions, family details, and identity information should not leave the phone just to become understandable.

Third, Gemma 4's multimodality lets one local model power the whole experience: text refinement, audio transcription, text simplification, vision coaching, and contextual empathy tips. I did not want a fragile chain of cloud APIs. I wanted one local intelligence layer that could be trusted in the field.

## Cactus SDK and Local Model Routing

KawanIsyarat targets the Cactus special technology track because the app is a local-first mobile application that routes tasks between on-device models.

The default route is Gemma 4 E2B through Cactus:

- Text: gloss-to-Indonesian, vocabulary explanation, empathy tips.
- Audio: raw PCM is passed directly to Gemma 4 with `<|audio|>`.
- Vision: captured sign photos are passed as local image paths in the Cactus messages JSON.

The fallback route is Whisper Base INT8, also through Cactus. If Gemma 4 audio transcription is empty, fails, or becomes too slow on a mid-low device, the app loads Whisper on demand and uses it only for STT. After transcription, Whisper is unloaded so Gemma 4 can reclaim memory for simplification. This is not a fallback for convenience; it is a memory-aware local model routing strategy for real Android devices.

The primary path remains Gemma-native: Gemma 4 handles audio, text simplification, empathy, vocabulary, and vision feedback. Whisper only steps in when the device needs a lighter STT route. That balance is why KawanIsyarat fits the Cactus track: Cactus is not just an inference backend here, but the layer that makes local multimodal routing practical on mobile.

On a Pixel 6a, Gemma 4 via Cactus uses about 1.7-1.9 GB RAM at runtime and produces about 3.5-4.5 tokens/second in my app settings. I tuned Cactus with `n_ctx: 512`, `memory_f32: false`, `batch_size: 1`, and `n_threads: 4` to keep enough headroom for camera, audio, and Flutter UI.

## Architecture

```
KawanIsyarat
+-- Communication
|   +-- Deaf -> Hearing: Camera -> MediaPipe -> 1D CNN -> Gloss -> Gemma 4 -> Sentence + Empathy Tips -> TTS
|   +-- Hearing -> Deaf: Mic -> PCM -> Gemma 4 Audio -> Transcript -> Gemma 4 Simplify -> Text
+-- Learning
|   +-- Sign Coach: Camera capture -> classifier -> Gemma 4 Vision feedback
|   +-- Vocabulary Helper: difficult word -> Gemma 4 simple explanation
|   +-- Idiom Helper: curated list or Gemma 4 explanation
|   +-- Articulation: voice -> Gemma 4 transcription -> pronunciation feedback
+-- Emergency
    +-- One-tap TTS for critical phrases
```

The sign-recognition model uses MediaPipe pose and hand landmarks. For BISINDO words, each 30-frame window is converted into normalized landmark features and classified by a 1D causal depthwise CNN inspired by the 1st place Kaggle ASL Signs solution. The current prototype supports 16 BISINDO classes and reached 86.2% leave-one-signer-out test accuracy in my experiments.

For alphabet learning, local Dense classifiers validate SIBI and BISINDO letters first. Gemma 4 Vision then acts as a coach, not as the only judge. Because Gemma 4 does not inherently know the exact BISINDO/SIBI hand shapes, every vision prompt injects my reference library: 26 BISINDO letters, 24 SIBI letters, and common word signs. This makes feedback grounded and specific instead of generic.

## Engineering Challenges

The hardest bug was Gemma 4 thinking mode. Cactus enabled thinking by default through `enable_thinking_if_supported`, which made simple responses take 60-153 seconds on a Pixel 6a. After tracing the Cactus formatting path, I disabled that flag in the completion options. Response time dropped to about 4-9 seconds, which changed the app from impressive-but-unusable into something that could support real conversation.

Gemma 4 audio also required memory discipline. Audio above roughly 256 KB raw PCM could trigger OOM on the Pixel 6a. I added a guard that keeps short recordings at full 16 kHz quality, but decimates longer PCM buffers before sending them to Gemma 4. It is a pragmatic mobile safeguard, not a perfect resampler, but it prevents crashes during real use.

Whisper fallback had its own trap: the prompt must end with `<|notimestamps|>`. Without that token, Whisper generated timestamp tokens that were filtered out, producing empty results. The working Indonesian prompt is `<|startoftranscript|><|id|><|transcribe|><|notimestamps|>`.

I also fixed an Android camera lifecycle issue where pulling down the notification shade froze the camera. The cause was disposing the camera on `AppLifecycleState.inactive`; switching disposal to `paused` fixed it because notification shade interactions are not true backgrounding.

## Impact

KawanIsyarat is strongest for **Digital Equity & Inclusivity**, with a serious fit for **Future of Education** and the **Cactus** prize.

For Deaf users, the impact is independence: asking for help, explaining symptoms, handling forms, learning new words, or communicating in public without always needing a hearing family member beside them. In medical and government settings, this also means privacy. A Deaf person should not need a sibling or parent to interpret every personal detail just because the system around them cannot understand BISINDO.

For hearing users, KawanIsyarat changes the burden of communication. Instead of expecting Deaf Indonesians to adapt alone, the app helps hearing people understand, respond more clearly, and learn basic BISINDO. The empathy tips are intentionally simple because inclusion is not only translation; it is also how people respond after they understand.

For learners, the app goes beyond a passive dictionary. The Sign Coach, vocabulary helper, idiom helper, and articulation module make KawanIsyarat a practical learning companion for both Deaf and hearing users.

For low-connectivity communities, the offline design is essential. After the first model download, the core experience runs locally: no server, no subscription, and no private conversation leaving the phone.

My goal is not to replace human interpreters. The goal is to make everyday communication less fragile and less dependent on whether an interpreter, internet connection, or expensive device is available.

KawanIsyarat shows what local developers can build for a specific community today when Gemma 4 can run offline on a phone.

## Project Links

- Landing page / live demo: https://kawanisyarat.pradanayahya.com
- Public code repository: https://github.com/haipradana/KawanIsyarat
- Demo video: Soon

## Built With

Gemma 4 E2B INT4, Cactus SDK, Whisper Base INT8 fallback, Flutter, Riverpod, MediaPipe, TFLite, Hive, and Android.

Submitted to the Gemma 4 Good Hackathon, Kaggle 2026.
