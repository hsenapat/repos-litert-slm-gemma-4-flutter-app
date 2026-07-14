# Features

## Current

- On-device streaming chat with Gemma 4 E2B int4 (~1.5 GB)
- Model download progress UI (first launch only)
- Thinking indicator while model generates
- User / model message bubbles
- Voice input (STT) via on-device Whisper (`whisper_kit`) — tap the mic, recording auto-stops on silence and transcribes, auto-sends on stop
- Spoken replies (TTS) via the platform's native voice — toggle with the speaker icon in the app bar

## Model Configuration

Default: **Gemma 4 E2B int4** from Hugging Face (`gemma4-e2b-it-int4.litertlm`).

To swap models, edit `_modelUrl` and `ModelType` in `lib/services/gemma_service.dart`.

Available `ModelType` values: `gemma4`, `gemma3`, `gemmaIt`, `deepSeek`, `qwen`, etc.
