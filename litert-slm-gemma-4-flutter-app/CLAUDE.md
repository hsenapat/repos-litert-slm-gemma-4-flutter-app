# CLAUDE.md

Flutter on-device AI chat app — Gemma 4 E2B int4 via LiteRT-LM, zero network calls during inference.

## Context

See [.claude/context.md](.claude/context.md) for prerequisites, common commands, and platform requirements.

## Docs

- [docs/Architecture.md](docs/Architecture.md) — file structure, state flow, streaming
- [docs/TechStack.md](docs/TechStack.md) — packages and native assets
- [docs/Features.md](docs/Features.md) — current features and model config

## Commands

| Slash command | Purpose |
|---------------|---------|
| `/feature` | Scaffold a new feature |
| `/test-unit` | Write unit tests |
| `/test-integration` | Write integration tests |
| `/deploy` | Build & release checklist |
| `/review` | Code review checklist |

See `.claude/commands/` for details.

## Agents

- [agents/engineer.md](agents/engineer.md) — feature dev & refactoring
- [agents/devops.md](agents/devops.md) — builds, releases, CI/CD

## Skills

- [skills/code-review/SKILL.md](skills/code-review/SKILL.md)
- [skills/testing/SKILL.md](skills/testing/SKILL.md)
- [skills/helper/SKILL.md](skills/helper/SKILL.md)

## Testing

See [tests/TESTING.md](tests/TESTING.md).
