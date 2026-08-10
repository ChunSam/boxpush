# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

A new test is not trusted until it has been watched to fail. Break what it
guards, confirm it goes red with a message you could act on, then restore. Every
guard in this repo was added because a green suite turned out to be hiding
something, so a guard that has only ever been green proves nothing.

`.\tools\smoke.ps1` is the other check: it drives the whole screen flow through a
live scene tree — menu, every level cleared, the overlay, a relaunch. It is
deliberately *not* in the gate (tech-design §11), so run it yourself after
touching a screen, a signal between screens, or the save.

The other entry points are `.\tools\run.ps1` (launch the game),
`.\tools\editor.ps1` (open the editor), `.\tools\shots.ps1` (render every screen
to `shots/`, for the look), `.\tools\export.ps1` (build a Windows release into
`build/`) and `.\tools\make_assets.ps1` (regenerate the art and audio — the
results are committed, so run it only after editing the palette or the cues).
All of them resolve the engine through
`tools/find-godot.ps1`, which checks `$env:GODOT_BIN`, then `PATH`, then the
winget package folder. On a fresh clone the first run also does a one-time
`--import`: without the `.godot` cache no `class_name` resolves and every script
fails to compile.

Do not assume `godot` is on `PATH` — on a stock machine it is not, and the binary
is version-stamped
(`%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot_v4.7.1-stable_win64_console.exe`).
Go through `tools/`. When invoking the engine directly, use the `_console.exe`
build — the plain binary detaches from the console on Windows and its stdout
never reaches the caller, so a failing run looks silent and passes.

### Running a single test

There is no filter. `run_tests.gd` reads no command-line arguments and
`test.ps1` forwards none. The whole suite is about a second, so just run it all.
To iterate on one suite, temporarily trim the `SUITES` const — and put it back
before committing.

## The one architectural rule

`scripts/core/` must not reference `Node`, the scene tree, `Input`, rendering or
`get_tree()`. That is what lets the whole rule set be tested headlessly in under
a second. `LevelData`'s use of `FileAccess` is the only engine contact permitted
there.

Dependencies point downward: `scenes/` → `autoload/` → `core/`. Never upward.

- `core/` — `LevelData` (parses `.xsb`, immutable once loaded), `SokobanState`
  (the live board plus undo history), `LevelIndex` (the ship manifest). All
  plain `RefCounted`.
- `autoload/` — `LevelLibrary` parses every indexed level once at boot, so a
  malformed board fails loudly at startup instead of mid-session.
  `SaveManager` keys progress by level *id* (the `.xsb` basename) and never by
  index, so reordering levels cannot corrupt a save.

## Two hand-maintained manifests

Both exist for the same reason — `DirAccess` over `res://` cannot see
non-imported files in an exported build, so a directory scan would work in the
editor and return nothing in a shipped build:

- `LEVEL_PATHS` in `scripts/core/level_index.gd` — append a level here or it
  will not ship. Nothing catches an `.xsb` that is on disk but unlisted, because
  an unshipped work-in-progress level is a legitimate state. A new or edited
  level also needs its recorded solution regenerating: `.\tools\solve.ps1`.
- `SUITES` in `tests/run_tests.gd` — append a new test file here or it never
  runs. `test_every_suite_is_registered` catches the omission; before it existed
  a forgotten suite read as green, since the gate reports the tests it did run
  passing and exits 0. Within a listed suite, `test_*` methods are discovered
  automatically.

## Writing tests

Subclass `TestCase` (`tests/test_case.gd`) and name methods `test_*`. The runner
builds a fresh instance per test, so state cannot leak between them.

Assertions **record a failure and carry on** rather than aborting, so one method
reports every problem it finds instead of only the first. Do not write an
assertion whose failure leaves the lines after it to crash on a null.

`SokobanState.to_ascii()` renders the live board as XSB — print it first when a
movement test fails.

## Current state of the code

**The roadmap is finished.** v0.1 through v0.5 are all closed, both checks are
green (75 tests, 81 smoke checks), and the Windows build runs from a folder with
no checkout in it. The two hands-on sign-offs — how the key repeat feels, and the
exported build's save — were done on 2026-08-10; the roadmap records exactly what
was watched and what was inferred for the second one.

Further work is new scope, not remaining scope. The out-of-scope list at the foot
of the roadmap is deliberate omissions, not a backlog.

## Conventions

- Static types everywhere (`var x := 0`, explicit `-> void`). Tabs. Line length 100.
- `##` doc comments on classes and non-obvious functions. Comments say **why**.
- Signals in the past tense. `_leading_underscore` for private members.

## Gotchas already paid for

- `project.godot`'s `[input]` block is hand-written. `test_project_config.gd`
  guards it, because a broken input map yields a game that runs perfectly and
  ignores the keyboard.
- `export_presets.cfg` is **committed**, against the usual advice, because its
  `*.xsb` non-resource filter is the difference between a build with levels and
  one without. `test_project_config.gd` asserts the filter. Revisit if signing
  credentials ever have to live there.
- `SokobanState.DIRECTIONS` order is the undo history's encoding — entries pack
  as `direction_index | (was_a_push << 2)`. Reordering it silently invalidates
  stored histories.
- `LevelLibrary.levels` is **compacted** — a rejected level is skipped, not
  held as a gap — while `SaveManager.is_unlocked()` indexes the full
  `LEVEL_PATHS`. The two agree only because every shipped level parses. Known
  and unfixed; see "Known, and left alone" in the roadmap before relying on an
  index across both.
- Autoloads are **live during the headless gate** — `SaveManager` is on the root
  and has already read your real save. A test that calls the singleton overwrites
  your own progress and passes while doing it. Build the script yourself and set
  `save_path`; `tests/test_save_manager.gd` shows the shape.
- The save file is at `%APPDATA%\Godot\app_userdata\Boxpush\boxpush_save.cfg`.
  `SaveManager.reset_progress()` wipes it when a test needs a known-empty start.
- A newly added `class_name` stays invisible until the engine rescans, and the
  gate fails with `Could not find type "X" in the current scope` — which reads
  like a typo, not a stale cache. Run `godot --headless --path . --import` once.
  A fresh clone is unaffected; `Confirm-GodotImport` already does it.

## Language

Reports and questions to the user in Korean. Everything written to a file —
code, comments, docs, commit messages — in English.
