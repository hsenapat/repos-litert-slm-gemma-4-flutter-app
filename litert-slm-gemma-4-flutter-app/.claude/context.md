---
description: Project context, conventions, and prerequisites for Claude Code
---

# Project Context

On-device AI chat app running **Gemma 4 E2B int4** via the LiteRT-LM engine. Zero network calls during inference — model runs entirely on-device.

## Prerequisites

**Flutter ≥3.44.0 is required** (`flutter_gemma` v1.x constraint). The project was created with 3.41.6 — upgrade before running:

```bash
flutter upgrade
flutter pub get
```

## Common Commands

```bash
flutter run                        # Run on connected device/simulator
flutter run -d <device-id>         # Run on specific device
flutter devices                    # List available devices
flutter test                       # Run tests
flutter analyze                    # Static analysis
flutter build apk --release        # Android release APK
flutter build ipa --release        # iOS release IPA (requires Xcode)
```

## Platform Requirements

| Platform | Min Version | Notes |
|----------|-------------|-------|
| Android | API 24 (Android 7.0) | GPU via OpenCL; set in `android/app/build.gradle.kts` |
| iOS | 16.0 | Metal GPU on device; CPU-only on simulator; set in `ios/Runner.xcodeproj/project.pbxproj` |

## iOS: Large Model Memory Entitlement

For models >512 MB on iOS, `ios/Runner/Runner.entitlements` must include:

```xml
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```
