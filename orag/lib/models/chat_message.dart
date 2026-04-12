// Represents a single chat message in the conversation.

enum MessageRole { user, assistant, system }

/// Source attribution for RAG responses.
class SourceAttribution {
  final String docName;
  final String chunkText;
  final double score;

  const SourceAttribution({
    required this.docName,
    required this.chunkText,
    required this.score,
  });

  factory SourceAttribution.fromJson(Map<String, dynamic> json) {
    return SourceAttribution(
      docName: json['doc_name'] as String? ?? '',
      chunkText: json['chunk_text'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ChatMessage {
  final MessageRole role;
  String text;
  final DateTime timestamp;
  bool isStreaming;
  List<SourceAttribution> sources;

  ChatMessage({
    required this.role,
    required this.text,
    DateTime? timestamp,
    this.isStreaming = false,
    List<SourceAttribution>? sources,
  })  : timestamp = timestamp ?? DateTime.now(),
        sources = sources ?? [];

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;

  /// Whether this message has any visible content yet.
  bool get isEmpty => text.trim().isEmpty;

  /// Whether this message has source attribution data.
  bool get hasSources => sources.isNotEmpty;
}
