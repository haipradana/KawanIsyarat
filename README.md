# KawanIsyarat — Jembatan Komunikasi Inklusif 🤟

An offline-first, inclusive communication bridge between Deaf (Tuli) and Hearing (Mendengar) users in Indonesia. It uses sign language (BISINDO) with real-time gesture recognition + AI-powered sentence refinement. **ALL features run 100% offline — no internet required.**

## 📱 Screenshots

The app includes 5 main screens:
1. **Persona Selection** – Choose between Deaf or Hearing user mode
2. **Home Dashboard** – Quick access to Communication and Learning modes
3. **Deaf → Hearing** – Sign language to text/speech translation
4. **Hearing → Deaf** – Speech to text summarization for deaf users
5. **Learning Mode** – Interactive BISINDO learning with AI feedback

## 🏗️ Project Structure

```
lib/
├── main.dart                          # App entry point
├── app/
│   ├── router.dart                    # GoRouter configuration
│   ├── theme.dart                     # Material theme with design tokens
│   └── constants.dart                 # Colors, spacing, mock data
├── features/
│   ├── onboarding/
│   │   ├── screens/persona_selection_screen.dart
│   │   └── widgets/persona_card.dart
│   ├── home/
│   │   ├── screens/home_dashboard_screen.dart
│   │   └── widgets/
│   │       ├── mode_card.dart
│   │       └── word_of_day_card.dart
│   ├── communication/
│   │   ├── screens/
│   │   │   ├── comm_deaf_to_hearing_screen.dart
│   │   │   └── comm_hearing_to_deaf_screen.dart
│   │   └── widgets/
│   │       ├── gloss_chip_row.dart
│   │       ├── ai_sentence_card.dart
│   │       ├── push_to_start_button.dart
│   │       └── waveform_visualizer.dart
│   ├── learning/
│   │   ├── screens/learning_mode_screen.dart
│   │   └── widgets/
│   │       ├── reference_image_card.dart
│   │       ├── live_camera_pip.dart
│   │       ├── feedback_banner.dart
│   │       └── star_rating.dart
│   ├── history/
│   │   └── screens/history_screen.dart
│   └── settings/
│       └── screens/settings_screen.dart
├── shared/
│   ├── widgets/
│   │   ├── bottom_nav_bar.dart
│   │   ├── offline_badge.dart
│   │   └── kawan_app_bar.dart
│   └── models/
│       ├── user_persona.dart
│       ├── gloss_result.dart
│       └── conversation_entry.dart
└── core/
    ├── services/
    │   ├── gesture_service.dart         ← STUB: emits mock gloss words
    │   ├── gemma_service.dart           ← STUB: returns mock refined sentences
    │   ├── stt_service.dart             ← STUB: returns mock transcriptions
    │   └── tts_service.dart             ← Wraps flutter_tts
    └── providers/
        ├── persona_provider.dart
        ├── communication_provider.dart
        └── learning_provider.dart
```

## 🛠️ Tech Stack

| Component          | Technology            |
|--------------------|-----------------------|
| Framework          | Flutter (latest)      |
| State Management   | Riverpod              |
| Navigation         | GoRouter              |
| Local Storage      | Hive                  |
| Text-to-Speech     | flutter_tts           |
| Animations         | flutter_animate       |
| Typography         | Google Fonts          |

## 🎨 Design System

- **Primary**: Deep Teal `#006D6D`
- **Accent**: Warm Amber `#F5A623`
- **Background**: Near White `#F9F9F7`
- **Headlines**: Plus Jakarta Sans (bold)
- **Body Text**: Be Vietnam Pro (regular)
- **Border Radius**: 24px cards, 12px chips, 999px buttons
- **Design Philosophy**: "Tactical Humanism" — warm, inclusive, no borders

## 🚀 Getting Started

### Prerequisites
- Flutter SDK >= 3.2.0
- Android Studio / VS Code
- Android device or emulator (SDK 21+)

### Running the App

```bash
# Get dependencies
flutter pub get

# Run the app
flutter run

# Build APK
flutter build apk
```

## 📝 Stub Services

The following services return mock data and serve as placeholders for future ML integration:

- **GestureService**: Simulates MediaPipe gesture recognition, emits gloss words via stream
- **GemmaService**: Simulates Gemma LLM inference for gloss→sentence refinement
- **SttService**: Simulates Whisper STT transcription
- **TtsService**: Real implementation using `flutter_tts` for Indonesian TTS

## 🔮 Future Integration Points

1. Replace `gesture_service.dart` with MediaPipe hand tracking
2. Replace `gemma_service.dart` with Gemma 4 LiteRT on-device inference
3. Replace `stt_service.dart` with Whisper on-device STT
4. Replace TTS stub with Piper TTS for more natural Indonesian speech
5. Add camera plugin integration for real-time video feed

## 📄 License

This project is licensed under the MIT License.
