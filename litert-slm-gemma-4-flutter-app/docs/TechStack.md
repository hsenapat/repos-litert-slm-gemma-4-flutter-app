# Tech Stack

## Core Packages

| Package | Role |
|---------|------|
| `flutter_gemma` | Core LLM integration |
| `flutter_gemma_litertlm` | LiteRT-LM engine via `dart:ffi` |
| `background_downloader` | One-time model download + on-device caching |
| `whisper_kit` | On-device STT — wraps whisper.cpp via `dart:ffi` |
| `record` | Microphone capture; records 16 kHz mono WAV for Whisper to transcribe |
| `flutter_tts` | On-device TTS via the platform's native speech engine |

## Key Details

- Model format: `.litertlm` (quantized)
- Native LiteRT-LM library is fetched automatically at build time via **Native Assets** — no manual `.so`/`.dylib` setup needed.
- Model is downloaded once and cached on-device; subsequent launches load from cache.
- STT: `whisper_kit`'s `base` ggml model (~142 MB) is downloaded once on first launch and cached under the app support directory. `whisper_kit` only exposes file-based transcription (no live/streaming API), so mic audio is recorded to a WAV file and transcribed in one pass once silence is detected — there are no real-time partial transcripts. Fully offline after the initial download — no server, no API keys. See [stt_service.dart](../lib/services/stt_service.dart).
- TTS: `flutter_tts` speaks through the OS-native synthesizer (AVSpeechSynthesizer on iOS/macOS, Android `TextToSpeech`), so there's no model download and no network call at all.
