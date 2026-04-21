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

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourcePersona': sourcePersona.name,
        'originalText': originalText,
        'translatedText': translatedText,
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
      };

  factory ConversationEntry.fromJson(Map<String, dynamic> json) {
    return ConversationEntry(
      id: json['id'] as String,
      sourcePersona: UserPersona.values.firstWhere(
        (e) => e.name == json['sourcePersona'],
        orElse: () => UserPersona.tuli,
      ),
      originalText: json['originalText'] as String? ?? '',
      translatedText: json['translatedText'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      type: ConversationType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ConversationType.signToText,
      ),
    );
  }
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
