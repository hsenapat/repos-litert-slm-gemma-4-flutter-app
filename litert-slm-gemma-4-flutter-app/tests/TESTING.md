# Testing

## Run Tests

```bash
flutter test              # all unit tests
flutter test --coverage   # with coverage report
flutter analyze           # static analysis
```

## Test Structure

```
test/
  widget_test.dart        # widget smoke tests
```

## Guidelines

- Unit-test `GemmaService` state transitions with a mock downloader.
- Widget-test `ChatScreen` by stubbing `GemmaService.onStateChanged`.
- Integration tests go in `integration_test/` and require a connected device.
