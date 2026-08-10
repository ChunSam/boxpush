# Boxpush

A small Sokoban puzzle game, built as a test project for the full Godot 4
pipeline: data-driven content, headless tests, save/load, and export.

Status: **v0.5 — shippable**. Menus, progression and personal bests sit on a rule
set where every shipped level is proven winnable by a recorded solution the test
suite replays; the board is tiles and sprites with 90 ms motion, a
crate-lands-home pop and three audio cues; and `tools\export.ps1` produces a
Windows build that runs from a folder with no project checkout in it. See
[`docs/roadmap.md`](docs/roadmap.md).

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
.\tools\smoke.ps1     # drive the whole screen flow once, headlessly
.\tools\shots.ps1     # render every screen to shots/, for the parts you must see
.\tools\solve.ps1     # regenerate the recorded level solutions
.\tools\make_assets.ps1   # regenerate the placeholder art and audio cues
.\tools\export.ps1    # build a Windows release into build/
```

## Building a Windows release

```powershell
.\tools\export.ps1
```

The build lands in `build/`, which is git-ignored. Copy the **whole folder** to
run it elsewhere — the `.exe` needs its `.pck` beside it.

This needs the Godot **export templates** for 4.7.1, which are a separate
download from the engine itself (~1 GB). Install them once from the editor —
*Editor → Manage Export Templates → Download and Install* — or extract
`Godot_v4.7.1-stable_export_templates.tpz` into
`%APPDATA%\Godot\export_templates\4.7.1.stable\`.

`export_presets.cfg` is committed rather than ignored, so its `*.xsb`
non-resource filter travels with the repository, and `tools\test.ps1` asserts
that the filter is there. Without it the build launches, runs, and contains no
levels at all — see tech-design §5.

## Documentation

| Document | Contents |
| --- | --- |
| [`docs/game-design.md`](docs/game-design.md) | Rules, level format, content plan, controls, UX |
| [`docs/tech-design.md`](docs/tech-design.md) | Architecture, core types, save format, testing, conventions |
| [`docs/roadmap.md`](docs/roadmap.md) | Milestones with checkable acceptance criteria |

## Controls

`WASD` or the arrow keys move, `Z` undoes, `R` restarts, `Esc` goes back one
screen. Undo is unlimited and never disabled — including after a clear, so you
can undo back into play, and the clear overlay gets out of the way when you do.

## Adding a level

1. Write the board in [XSB notation](docs/game-design.md#5-level-format) as
   `levels/NN_name.xsb`, with a `; Title: ...` comment.
2. Append its path to `LEVEL_PATHS` in `scripts/core/level_index.gd`. This is a
   manifest rather than a directory scan on purpose — see tech-design §5.
3. Run `.\tools\solve.ps1` and paste the block it prints over `SOLUTIONS` in
   `tests/test_levels.gd`. A level without a recorded solution fails the suite:
   every shipped level has to be proven winnable, not assumed to be.
4. Run `.\tools\test.ps1`. The suite parses and validates every indexed level and
   replays every solution, so a malformed or broken board fails the build rather
   than the player.
