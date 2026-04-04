class GlossResult {
  final List<String> glossTokens;
  final String? refinedSentence;
  final DateTime timestamp;

  GlossResult({
    required this.glossTokens,
    this.refinedSentence,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get glossString => glossTokens.join(' ');

  GlossResult copyWith({
    List<String>? glossTokens,
    String? refinedSentence,
    DateTime? timestamp,
  }) {
    return GlossResult(
      glossTokens: glossTokens ?? this.glossTokens,
      refinedSentence: refinedSentence ?? this.refinedSentence,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
