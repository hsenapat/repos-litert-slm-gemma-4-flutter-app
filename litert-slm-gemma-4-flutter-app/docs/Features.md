# Features

## Current

- On-device streaming chat with Gemma 4 E2B int4 (~1.5 GB)
- Model download progress UI (first launch only)
- Thinking indicator while model generates
- User / model message bubbles

## Model Configuration

Default: **Gemma 4 E2B int4** from Hugging Face (`gemma4-e2b-it-int4.litertlm`).

To swap models, edit `_modelUrl` and `ModelType` in `lib/services/gemma_service.dart`.

Available `ModelType` values: `gemma4`, `gemma3`, `gemmaIt`, `deepSeek`, `qwen`, etc.
