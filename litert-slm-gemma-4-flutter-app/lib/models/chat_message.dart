enum MessageRole { user, model }

class ChatMessage {
  final String text;
  final MessageRole role;
  final bool isThinking;

  const ChatMessage({
    required this.text,
    required this.role,
    this.isThinking = false,
  });

  ChatMessage copyWith({String? text, bool? isThinking}) => ChatMessage(
    text: text ?? this.text,
    role: role,
    isThinking: isThinking ?? this.isThinking,
  );
}
