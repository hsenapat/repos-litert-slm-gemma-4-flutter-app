# /test-unit

Write unit tests for a given class or function.

## Steps

1. Place test file in `test/` mirroring `lib/` path (e.g. `test/services/gemma_service_test.dart`).
2. Mock external dependencies (`background_downloader`, `FlutterGemma`).
3. Cover: happy path, error states, edge cases.
4. Run: `flutter test test/<path>`
