# Skill: Code Review

Review Flutter/Dart code in this project for correctness, performance, and style.

## Focus Areas

1. **State management** — verify `GemmaService` state machine is consistent; no invalid transitions.
2. **Stream hygiene** — all `StreamSubscription`s cancelled in `dispose`; no leaks.
3. **Thread safety** — heavy work (model loading, inference) not blocking the UI isolate.
4. **Platform correctness** — entitlements, SDK versions, and `ModelType` alignment.
5. **Dart style** — prefer `const`, immutable models, `final` fields.

## Output Format

For each issue found:
- **File:line** — what the problem is
- **Severity**: critical / warning / suggestion
- **Fix**: one-line recommendation
