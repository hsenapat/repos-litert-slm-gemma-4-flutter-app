# Skill: Testing

Generate and review tests for this Flutter on-device AI app.

## Test Types

| Type | Location | Command |
|------|----------|---------|
| Unit | `test/` | `flutter test` |
| Widget | `test/` | `flutter test` |
| Integration | `integration_test/` | `flutter test integration_test/ -d <device>` |

## Patterns

- Mock `FlutterGemma` and `background_downloader` for unit tests.
- Use `StreamController` fakes to simulate token streaming.
- Widget tests: pump `ChatScreen` with a stubbed `GemmaService`.
- Never assert on model output content — only assert on state transitions and UI reactions.

## Coverage

Run `flutter test --coverage` and check `coverage/lcov.info`.
