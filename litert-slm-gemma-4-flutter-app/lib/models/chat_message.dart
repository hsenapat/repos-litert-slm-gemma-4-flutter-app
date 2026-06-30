import 'rag_chunk.dart';

enum MessageRole { user, model }

class ChatMessage {
  final String text;
  final MessageRole role;
  final bool isThinking;
  final List<RagChunk>? sources;

  const ChatMessage({
    required this.text,
    required this.role,
    this.isThinking = false,
    this.sources,
  });

  ChatMessage copyWith({
    String? text,
    bool? isThinking,
    List<RagChunk>? sources,
  }) => ChatMessage(
    text: text ?? this.text,
    role: role,
    isThinking: isThinking ?? this.isThinking,
    sources: sources ?? this.sources,
  );
}
