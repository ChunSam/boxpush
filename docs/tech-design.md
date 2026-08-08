# Boxpush — Technical Design

Status: v0.1 (2026-08-09)
Engine: Godot **4.7.1.stable.official** — `winget install GodotEngine.GodotEngine`
Language: **GDScript**

---

## 1. Stack decisions

**GDScript, not C#.** There is no .NET SDK on the development machine, and the
Mono build would add a compile step, a second toolchain and larger exports in
exchange for nothing this project needs. The entire simulation is integer
arithmetic on a board smaller than 10×10.

**GL Compatibility renderer.** The game is 2D, unlit, and untextured until v0.4.
The Compatibility backend runs on the widest range of drivers and starts fastest,
which matters when the test suite and the game are launched dozens of times a
day. Set in `project.godot` for both desktop and mobile.

**1280×720 base viewport**, `canvas_items` stretch, `keep` aspect. Board scaling
is handled by the board view rather than by the window stretch (see §7), so the
HUD stays crisp at any window size.

**Nearest-neighbour texture filtering** project-wide
(`textures/canvas_textures/default_texture_filter=0`), because the art plan is
pixel art and bilinear filtering on a 64 px tile is visibly wrong.

---

## 2. Architecture

```
              ┌───────────────────────────────────────────────┐
   scenes/    │  main.tscn → menus → game screen → overlays    │
   scripts/   │  Nodes. Input, drawing, tweens, UI.            │
              └──────────────────────┬────────────────────────┘
                                     │ calls, reads
              ┌──────────────────────▼────────────────────────┐
   autoload/  │  LevelLibrary          SaveManager            │
              │  Process-wide services. Extend Node.          │
              └──────────────────────┬────────────────────────┘
                                     │ calls, reads
              ┌──────────────────────▼────────────────────────┐
   core/      │  LevelIndex   LevelData   SokobanState        │
              │  Pure RefCounted. No engine dependency.       │
              └───────────────────────────────────────────────┘
```

**The one architectural rule:** dependencies point downward only. Nothing in
`scripts/core/` may reference `Node`, the scene tree, `Input`, rendering, or
`get_tree()`. `LevelData` uses `FileAccess` and that is the whole extent of its
engine contact.

This is not architecture for its own sake — it is what makes
`tools/test.ps1` possible. The entire rule set is exercisable in a headless
process with no window, no main scene and no frame loop, which is why the suite
runs in well under a second and can gate every commit.

The corollary: **the core is signal-free.** `SokobanState.try_move()` returns a
`MoveResult` instead of emitting. Callers learn what happened from the return
value, the simulation stays a pure function of its inputs, and the view layer's
redraw is an explicit call rather than an implicit reaction.

---

## 3. Directory layout

```
boxpush/
├─ project.godot            Engine config: autoloads, input map, renderer
├─ icon.svg                 Window/app icon
├─ docs/
│  ├─ game-design.md        Rules, content plan, UX  ← the "what"
│  ├─ tech-design.md        This file               ← the "how"
│  └─ roadmap.md            Milestones and acceptance criteria
├─ levels/                  Level content as XSB text (*.xsb)
├─ scenes/
│  └─ main.tscn             Boot scene (v0.1: pipeline report)
├─ scripts/
│  ├─ main.gd               Boot scene script
│  ├─ core/                 Engine-independent logic — see the rule above
│  │  ├─ level_data.gd      Parses and validates one XSB level
│  │  ├─ level_index.gd     The ordered manifest of shipped levels
│  │  └─ sokoban_state.gd   Mutable board state, movement, undo
│  └─ autoload/
│     ├─ level_library.gd   Loads every level once at boot
│     └─ save_manager.gd    Progress and personal bests
├─ tests/
│  ├─ run_tests.gd          Headless runner (SceneTree MainLoop)
│  ├─ test_case.gd          Assertion base class
│  └─ test_*.gd             Suites
└─ tools/
   ├─ find-godot.ps1        Resolves the engine binary
   ├─ test.ps1              The verification gate
   ├─ run.ps1               Launches the game
   └─ editor.ps1            Opens the editor
```

Folders added later: `scenes/game/`, `scenes/ui/`, `assets/sprites/`,
`assets/audio/`.

---

## 4. Core types

| Type | File | Responsibility |
| --- | --- | --- |
| `LevelData` | `core/level_data.gd` | Everything about a level that never changes: walls, goals, start positions. Parses XSB and validates it. |
| `SokobanState` | `core/sokoban_state.gd` | Everything that changes while playing: player cell, crate cells, counters, undo history. |
| `LevelIndex` | `core/level_index.gd` | The static, ordered list of shipped level paths, and id↔index lookups. |
| `LevelLibrary` | `autoload/level_library.gd` | Parses every indexed level once at boot; hands out `LevelData` by index or id. |
| `SaveManager` | `autoload/save_manager.gd` | Cleared flags and best move/push counts, persisted to `user://`. |

### Grid convention

`Vector2i(x, y)`, origin top-left, `+x` right, `+y` down — the same as Godot's
2D space, so a board cell converts to a pixel position by multiplying by the
tile size, with no axis flip anywhere.

Out-of-bounds cells report as **walls** (`LevelData.is_wall`). Movement code
therefore never needs a bounds check before asking whether a step is legal, and
an unenclosed board cannot produce an out-of-range crash — it produces a
rejected level at parse time instead.

### `SokobanState` contract

```gdscript
enum MoveResult { BLOCKED, MOVED, PUSHED }

const DIRECTIONS: Array[Vector2i] = [UP, DOWN, LEFT, RIGHT]  # index order is load-bearing

func try_move(dir: Vector2i) -> MoveResult   # v0.2
func undo() -> bool                          # v0.2
func reset() -> void
func is_solved() -> bool
func boxes_on_goal() -> int
func to_ascii() -> String
```

`try_move` and `undo` are **stubs as of v0.1** — they `push_error` and are
implemented in v0.2. Everything else on the class is live and under test.

---

## 5. Level pipeline

```
levels/*.xsb ──► LevelData.parse() ──► validation ──► LevelLibrary.levels[]
   (text)          (RefCounted)         (§5 of GDD)      (parsed once, at boot)
```

Levels are **parsed eagerly at boot**, all five of them, costing well under a
millisecond. The guarantee that buys is worth far more than the time: a
malformed level file is reported at startup with a filename and a reason,
instead of failing halfway through a session when the player reaches it.

### Two non-obvious constraints

**1. `LevelIndex` is a hand-maintained manifest, not a directory scan.**
`DirAccess` over `res://` only sees *imported* resources in an exported build.
`.xsb` files are not imported — they are copied verbatim. A scan would work
perfectly in the editor and silently return an empty list in a shipped build,
which is the worst possible failure shape. Adding a level therefore means
dropping the file in `levels/` **and** appending its path to
`LevelIndex.LEVEL_PATHS`; `test_levels.gd` covers everything in that list.

**2. The export preset must include `*.xsb`.**
In *Project → Export → Resources*, "Filters to export non-resource files" must
contain `*.xsb`, or the levels will not exist in the exported build. This is a
v0.5 milestone item and the single most likely way to ship a broken build.
`export_presets.cfg` is git-ignored because it embeds absolute local paths, so
this setting is not carried by the repository and has to be re-entered on a new
machine — hence writing it down here.

---

## 6. Movement and undo

Undo stores **moves, not snapshots**. Each applied move is packed into one
`int` in a `PackedInt32Array`:

```
bits 0-1 : direction index into SokobanState.DIRECTIONS
bit  2   : 1 if the move pushed a crate
```

Undo is the inverse operation: step the player back by `-dir`, and if the move
was a push, pull the crate from `player + dir` back to `player`. This is O(1) in
time and 4 bytes per move, which is what makes "unlimited undo" a non-decision
rather than a memory budget. A snapshot-per-move design would be simpler to
write and roughly 100× the memory for no behavioural gain.

The direction *order* in `DIRECTIONS` is load-bearing: it is the encoding, so
reordering it would silently invalidate any stored history. Noted in the source.

Move and push counters are restored by undo as well, so a player cannot farm a
better score by moving and undoing.

---

## 7. Rendering plan (v0.2 →)

**v0.2 uses `_draw()`, not tiles.** The board view is a single `Node2D` whose
`_draw()` fills a rect per cell and per crate. No art assets, no import step, no
`TileSet` resource to hand-author — the fastest possible route to a playable
level, and the shape of the code (a redraw driven by board state) is the same
one the tile-based version will use.

**v0.4 swaps in a `TileMapLayer`** for the static layer (floor, wall, goal) plus
`Sprite2D` nodes for the player and each crate. The static/dynamic split matters:
tiles cannot be tweened, and the moving pieces are exactly the things that need
tweening.

**Board fitting.** With `TILE = 64`, the board container is positioned and scaled
each time the viewport resizes:

```gdscript
var scale_factor := floori(min(
    (viewport.x - MARGIN * 2) / float(level.width * TILE),
    (viewport.y - MARGIN * 2 - HUD_HEIGHT) / float(level.height * TILE)
))
scale_factor = maxi(scale_factor, 1)
```

Integer scaling only, so pixel art never lands on half-pixels. A 7×5 tutorial and
a 9×9 level both fill the screen sensibly, and no camera is needed.

**Tween policy.** Tweens are cosmetic and never gate input. The logical state
updates instantly; a new move *retargets* the running tween rather than queuing
behind it. A burst of held-key moves therefore always resolves in full, and the
board is never in a state the player did not ask for. 90 ms linear per step.

---

## 8. Save data

`user://boxpush_save.cfg` — on Windows,
`%APPDATA%\Godot\app_userdata\Boxpush\boxpush_save.cfg`.

`ConfigFile`, not JSON: it stays readable and hand-editable, which is worth more
during development than compactness.

```ini
[meta]
format_version=1

[progress]
01_first_push={"cleared": true, "best_moves": 3, "best_pushes": 1}
```

**Keyed by level id (the `.xsb` basename), never by index.** Inserting a level in
the middle of `LEVEL_PATHS` therefore cannot corrupt an existing save.

Written immediately on each clear. A clear is rare and the file is a few hundred
bytes, so batching would buy nothing and losing progress to a crash would cost
more than the stutter.

A save whose `format_version` does not match is **discarded, not migrated**. That
is the right trade for a test project and the one decision here a shipping game
would revisit.

---

## 9. Input

Actions are defined in `project.godot` and asserted by `test_project_config.gd`,
because a broken input map produces a game that runs perfectly and ignores the
keyboard — a failure no other test would catch.

| Action | Bindings |
| --- | --- |
| `move_up` / `move_down` / `move_left` / `move_right` | `W`/`S`/`A`/`D` and the arrow keys |
| `undo_move` | `Z`, `Backspace` |
| `restart_level` | `R` |
| `back` | `Esc` |

All bindings use **physical** keycodes, so `WASD` stays in the same physical
position on AZERTY and Dvorak.

Key repeat is handled in the game screen, not by the OS: 250 ms initial delay,
then one move every 90 ms. OS repeat rates vary per machine and would make the
game feel different on every desk.

Because the input layer maps device events onto four abstract direction actions,
adding swipe or an on-screen D-pad later touches one file and no game logic.

---

## 10. Testing

```powershell
.\tools\test.ps1        # exits 0 on success, 1 on any failure
```

Under the hood:

```
godot --headless --path . --script res://tests/run_tests.gd
```

`run_tests.gd` extends `SceneTree`, so it *is* the main loop: no window, no main
scene, no frame loop. Suites are listed explicitly in `run_tests.SUITES`; each
`test_*` method gets a fresh suite instance so state cannot leak between tests,
and assertions record failures rather than aborting, so one method reports every
problem it found instead of only the first.

**No test addon.** GUT and friends are good, but the entire harness here is two
small files, has no version to keep in step with the engine, and runs anywhere
Godot runs. If the suite outgrows it, swapping in GUT is a contained change.

Covered as of v0.1 (30 tests):

- **`test_level_data.gd`** — parsing, every glyph, ASCII round-trip, and each
  validation rule, asserted through its rejection message.
- **`test_levels.gd`** — every shipped level parses, has matching crate/goal
  counts, has a title; ids are unique; parsing is deterministic; no level starts
  already solved.
- **`test_project_config.gd`** — every input action exists and is bound to a
  physical key; the main scene is set and loadable; autoloads are registered.

Not covered yet, in the order it will be:

1. **Movement rules** — the `MoveResult` truth table, arriving with v0.2.
2. **Solution replay** — one recorded solution per level, replayed through
   `try_move` and asserted to end in `is_solved()`. This is what turns "the
   levels parse" into "the levels are winnable", and it is the highest-value
   test in the plan.
3. **Undo** — property test: any sequence of moves followed by the same number
   of undos restores `to_ascii()`, `move_count` and `push_count` exactly.
4. **`SaveManager`** — needs `user://` redirected to a temp dir to stay
   hermetic; use `--userdir` or inject the path.

---

## 11. Conventions

Godot's official GDScript style guide, with these specifics:

- **Tabs** for indentation (Godot's editor default; `.gitattributes` pins LF).
- **Static types everywhere** — `var x := 0`, explicit `-> void` returns. The
  parser catches the mistakes the tests would otherwise have to.
- `snake_case` for files, variables and functions; `PascalCase` for classes and
  nodes; `_leading_underscore` for private members.
- `##` doc comments on every class and on any function whose contract is not
  obvious from its name. Comments explain **why**, not what.
- Line length 100.
- Signals are named in the past tense (`level_rejected`, `progress_changed`).
- `class_name` only on types worth referencing globally.

---

## 12. Open decisions

- **Level select for more than ~12 levels** — the current design is a flat grid
  of buttons. Chapters/pages are deferred until there is content to justify them.
- **Save file migration** — currently discard-on-mismatch. Revisit if the format
  changes while anyone has real progress.
- **Audio bus layout** — trivial for three cues; deferred to v0.4.
- **Localisation** — the UI string count is small enough that a CSV can be
  retrofitted at any point. Not planned for v1.
