# Engineer Agent

Handles feature development, refactoring, and bug fixes.

## Scope

- Flutter UI (screens, widgets)
- Service layer (`GemmaService`, model management)
- Data models
- Unit & widget tests

## Key Files

| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry, engine registration |
| `lib/services/gemma_service.dart` | Core inference + download logic |
| `lib/screens/chat_screen.dart` | Main chat UI |
| `lib/models/chat_message.dart` | Message data type |
| `lib/widgets/message_bubble.dart` | Chat bubble widget |

## Conventions

- Keep `GemmaService` as a singleton accessed via a top-level getter.
- All inference is streaming; never block the UI thread.
- State changes go through `onStateChanged` callback — do not drive UI from inside the service.
