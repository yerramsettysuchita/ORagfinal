// Represents a single chat message in the conversation.

enum MessageRole { user, assistant, system }

class ChatMessage {
  final MessageRole role;
  String text;
  final DateTime timestamp;
  bool isStreaming;

  ChatMessage({
    required this.role,
    required this.text,
    DateTime? timestamp,
    this.isStreaming = false,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;

  /// Whether this message has any visible content yet.
  bool get isEmpty => text.trim().isEmpty;
}
