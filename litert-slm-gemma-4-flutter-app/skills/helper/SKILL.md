# Skill: Helper

General-purpose helper skill for quick lookups and guidance in this project.

## Common Questions

**How do I change the model?**
Edit `_modelUrl` and `ModelType` in `lib/services/gemma_service.dart`.
Available values: `gemma4`, `gemma3`, `gemmaIt`, `deepSeek`, `qwen`.

**Why does Flutter fail to build?**
Ensure Flutter ≥3.44.0: run `flutter upgrade`.

**Where is app state managed?**
`GemmaService` (service layer) → `onStateChanged` callback → `ChatScreen` (UI).

**How do I add a new screen?**
Create `lib/screens/<name>_screen.dart`, add route in `main.dart`, follow `/feature` command.

**iOS build fails on device — model too large?**
Add `com.apple.developer.kernel.increased-memory-limit: true` to `ios/Runner/Runner.entitlements`.
