# Tech Stack

## Core Packages

| Package | Role |
|---------|------|
| `flutter_gemma` | Core LLM integration |
| `flutter_gemma_litertlm` | LiteRT-LM engine via `dart:ffi` |
| `background_downloader` | One-time model download + on-device caching |

## Key Details

- Model format: `.litertlm` (quantized)
- Native LiteRT-LM library is fetched automatically at build time via **Native Assets** — no manual `.so`/`.dylib` setup needed.
- Model is downloaded once and cached on-device; subsequent launches load from cache.
