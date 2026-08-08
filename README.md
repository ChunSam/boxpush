# Boxpush

A small Sokoban puzzle game, built as a test project for the full Godot 4
pipeline: data-driven content, headless tests, save/load, and export.

Status: **v0.1 — skeleton**. The content pipeline, save system and test harness
are live; gameplay lands in v0.2. See [`docs/roadmap.md`](docs/roadmap.md).

## Requirements

- [Godot 4.7.1](https://godotengine.org) — `winget install GodotEngine.GodotEngine`
- No .NET SDK needed; the project is pure GDScript.

The scripts in `tools/` locate the engine automatically, checking `$env:GODOT_BIN`,
then `PATH`, then the winget package folder. Nothing needs to be on `PATH`.

## Commands

```powershell
.\tools\test.ps1      # run the test suite — the verification gate, exits 0 or 1
.\tools\run.ps1       # launch the game
.\tools\editor.ps1    # open the Godot editor
```

## Documentation

| Document | Contents |
| --- | --- |
| [`docs/game-design.md`](docs/game-design.md) | Rules, level format, content plan, controls, UX |
| [`docs/tech-design.md`](docs/tech-design.md) | Architecture, core types, save format, testing, conventions |
| [`docs/roadmap.md`](docs/roadmap.md) | Milestones with checkable acceptance criteria |

## Adding a level

1. Write the board in [XSB notation](docs/game-design.md#5-level-format) as
   `levels/NN_name.xsb`, with a `; Title: ...` comment.
2. Append its path to `LEVEL_PATHS` in `scripts/core/level_index.gd`. This is a
   manifest rather than a directory scan on purpose — see tech-design §5.
3. Run `.\tools\test.ps1`. The suite parses and validates every indexed level, so
   a malformed board fails the build rather than the player.
