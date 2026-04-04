import 'user_persona.dart';

class ConversationEntry {
  final String id;
  final UserPersona sourcePersona;
  final String originalText;
  final String translatedText;
  final DateTime timestamp;
  final ConversationType type;

  ConversationEntry({
    required this.id,
    required this.sourcePersona,
    required this.originalText,
    required this.translatedText,
    required this.timestamp,
    required this.type,
  });
}

enum ConversationType {
  signToText,
  speechToSign,
}

extension ConversationTypeExtension on ConversationType {
  String get label {
    switch (this) {
      case ConversationType.signToText:
        return 'Isyarat → Teks';
      case ConversationType.speechToSign:
        return 'Suara → Isyarat';
    }
  }

  String get icon {
    switch (this) {
      case ConversationType.signToText:
        return '🤟';
      case ConversationType.speechToSign:
        return '🎙️';
    }
  }
}
