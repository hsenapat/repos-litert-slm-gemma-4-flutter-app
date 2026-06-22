# /review

Code review checklist for this project.

## General

- [ ] No network calls made during inference (on-device only)
- [ ] `GemmaService` state machine transitions are correct
- [ ] Streams are properly closed / cancelled on dispose
- [ ] No memory leaks from uncancelled subscriptions

## Flutter Specifics

- [ ] Widgets are stateless where possible
- [ ] `setState` is not called after `dispose`
- [ ] Heavy work is off the UI thread (use `Isolate` or service layer)

## Model / LiteRT

- [ ] `ModelType` matches the downloaded `.litertlm` file
- [ ] iOS entitlement present if model >512 MB
- [ ] Android `minSdk` ≥ API 24
