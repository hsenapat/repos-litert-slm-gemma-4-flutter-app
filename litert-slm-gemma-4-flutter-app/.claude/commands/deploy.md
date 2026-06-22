# /deploy

Build and release steps.

## Android

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

## iOS

```bash
flutter build ipa --release
# Requires Xcode + valid provisioning profile
# Output: build/ios/ipa/
```

## Checklist

- [ ] `flutter analyze` passes with no issues
- [ ] `flutter test` passes
- [ ] Version bumped in `pubspec.yaml`
- [ ] iOS memory entitlement present in `Runner.entitlements` (models >512 MB)
- [ ] Android `minSdk` is API 24 in `build.gradle.kts`
