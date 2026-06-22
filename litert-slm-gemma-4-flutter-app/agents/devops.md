# DevOps Agent

Handles builds, releases, and CI/CD for this Flutter project.

## Scope

- Release builds (APK / IPA)
- Platform configuration (Android `build.gradle.kts`, iOS `project.pbxproj`)
- Entitlements and signing
- Flutter version management

## Key Config Files

| File | Purpose |
|------|---------|
| `pubspec.yaml` | App version, dependencies |
| `android/app/build.gradle.kts` | Android SDK versions, build config |
| `ios/Runner.xcodeproj/project.pbxproj` | iOS deployment target |
| `ios/Runner/Runner.entitlements` | iOS capabilities (memory entitlement) |

## Release Checklist

1. `flutter upgrade` — ensure Flutter ≥3.44.0
2. `flutter pub get`
3. `flutter analyze && flutter test`
4. Bump version in `pubspec.yaml`
5. `flutter build apk --release` or `flutter build ipa --release`
