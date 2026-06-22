# /test-integration

Write integration tests that run on a real device or emulator.

## Steps

1. Place tests in `integration_test/`.
2. Use `flutter_test` + `integration_test` packages.
3. Run: `flutter test integration_test/ -d <device-id>`

## Notes

- Integration tests require a connected device or running emulator.
- Model inference tests require the `.litertlm` model to be pre-cached.
