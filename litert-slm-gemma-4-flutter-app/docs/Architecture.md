# Architecture

## File Structure

```
lib/
  main.dart               # App entry point; registers LiteRtLmEngine with FlutterGemma
  models/
    chat_message.dart     # ChatMessage value type (text, role, isThinking)
  services/
    gemma_service.dart    # Singleton; handles model download, loading, and streaming inference
  screens/
    chat_screen.dart      # Main UI; drives state via GemmaService.onStateChanged callback
  widgets/
    message_bubble.dart   # Stateless bubble widget; user vs. model alignment
```

## State Flow

`GemmaService` owns a state machine:

```
idle → downloading → loading → ready | error
```

`ChatScreen` subscribes via `onStateChanged` callback and switches its body widget accordingly.

## Streaming Inference

`sendMessage()` returns a `Stream<String>` of tokens. The screen appends each token to the last message in the list while `isGenerating` is true.
