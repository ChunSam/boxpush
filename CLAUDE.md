# Boxpush — working notes for Claude

A Sokoban puzzle game in Godot 4.7.1, GDScript. Read `docs/tech-design.md`
before changing architecture and `docs/game-design.md` before changing rules or
content. `docs/roadmap.md` says what milestone we are on and what "done" means
for it.

## Verification gate

Nothing is done until this exits 0:

```powershell
.\tools\test.ps1
```

Read the real exit code. Never pipe it — a trailing `| tail` or `| Select-Object`
hides the failure.

Godot is **not on PATH**. It lives at
`%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot_v4.7.1-stable_win64_console.exe`.
Use the `tools/` scripts, which resolve it. When invoking the engine directly,
use the `_console.exe` build — the plain binary detaches from the console on
Windows and its stdout never reaches the caller, so a failing run looks silent
and passes.

## The one architectural rule

`scripts/core/` must not reference `Node`, the scene tree, `Input`, rendering or
`get_tree()`. That is what lets the whole rule set be tested headlessly in under
a second. `LevelData`'s use of `FileAccess` is the only engine contact permitted
there.

Dependencies point downward: `scenes/` → `autoload/` → `core/`. Never upward.

## Conventions

- Static types everywhere (`var x := 0`, explicit `-> void`). Tabs. Line length 100.
- `##` doc comments on classes and non-obvious functions. Comments say **why**.
- Signals in the past tense. `_leading_underscore` for private members.
- After adding a level: append it to `LEVEL_PATHS` in `scripts/core/level_index.gd`,
  or it will not ship. That manifest exists because `DirAccess` over `res://`
  cannot see non-imported files in an exported build.

## Gotchas already paid for

- `project.godot`'s `[input]` block is hand-written. `test_project_config.gd`
  guards it, because a broken input map yields a game that runs perfectly and
  ignores the keyboard.
- The export preset needs `*.xsb` in "Filters to export non-resource files", or
  the shipped build has no levels. `export_presets.cfg` is git-ignored, so this
  must be re-entered on every machine.
- `SokobanState.DIRECTIONS` order is the undo history's encoding. Reordering it
  silently invalidates stored histories.

## Language

Reports and questions to the user in Korean. Everything written to a file —
code, comments, docs, commit messages — in English.
