# Boxpush — Technical Design

Status: v0.3 (2026-08-09)
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
│  ├─ main.tscn             Main scene: holds one screen at a time — see §8
│  ├─ ui/
│  │  ├─ main_menu.tscn     Title, Play, Level select, Quit
│  │  └─ level_select.tscn  One button per level, locked ones dimmed
│  └─ game/
│     ├─ game_screen.tscn   Owns the state, the input, the HUD and the overlay
│     └─ board_view.tscn    The board, drawn from state
├─ scripts/
│  ├─ ui/                   Menus and navigation
│  │  ├─ screen_router.gd   Swaps screens; the only script that knows the flow
│  │  ├─ main_menu.gd       ─┐ Report by signal, decide nothing
│  │  └─ level_select.gd    ─┘
│  ├─ game/                 Scene scripts
│  │  ├─ game_screen.gd     Input routing, key repeat, clear detection
│  │  └─ board_view.gd      _draw() renderer, integer-scaled and centred
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
   ├─ editor.ps1            Opens the editor
   ├─ solve.ps1             Regenerates the recorded level solutions
   ├─ solve_levels.gd       The search behind it (headless, BFS)
   ├─ smoke.ps1             Drives the whole screen flow once — see §11
   └─ smoke_flow.gd         The run behind it (headless, but with a live tree)
```

Folders added later: `assets/sprites/`, `assets/audio/`.

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

func try_move(dir: Vector2i) -> MoveResult
func undo() -> bool
func reset() -> void
func is_solved() -> bool
func boxes_on_goal() -> int
func to_ascii() -> String

static func direction_from_letter(letter: String) -> Vector2i  # LURD notation
```

All of it is implemented and under test as of v0.2. Undo stores the move, not a
board snapshot — one packed int per move, `direction_index | (was_a_push << 2)` —
so it stays O(1) in time and memory with unbounded history.

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

## 8. Screen flow (v0.3 →)

GDD §8 owns the flow itself — which screens exist and what the player can reach
from where. This section is only how it is assembled.

**One root scene owns exactly one screen at a time.** From v0.3, `scenes/main.tscn`
is the main scene. Its script instantiates the next screen, sets whatever that
screen needs, adds it, and frees the outgoing one.

```
main.tscn  (Control, screen_router.gd)
└─ one of:  main_menu.tscn  │  level_select.tscn  │  game_screen.tscn
```

`get_tree().change_scene_to_file()` was the obvious alternative and is worse
here: it replaces the whole tree, so the only way left to tell the incoming
screen *which level* to open is a global, and the autoloads are services, not a
message bus. Instantiating explicitly means the level index is an ordinary
argument set before `add_child` — which is the shape `game_screen.gd` was
already written for, its `@export var level_index` being exported for exactly
this.

**Screens report; the router decides.** A screen emits a past-tense signal and
does nothing else about navigation, so no screen has to know what any other
screen is called.

| Screen | Emits |
| --- | --- |
| `MainMenu` | `play_pressed`, `level_select_pressed`, `quit_pressed` |
| `LevelSelect` | `level_chosen(index)`, `back_pressed` |
| `GameScreen` | `next_level_requested`, `level_list_requested` |

So the game screen never learns whether a next level exists: the router asks
`LevelLibrary.next_index()` and falls back to the level list at the end of the
set. Retry and restart never leave the screen, so neither is a signal.

**`Esc` (the `back` action) means one step outward, and never quits:**

| From | Goes to |
| --- | --- |
| Main menu | nowhere — deliberately inert |
| Level select | main menu |
| Game, and the clear overlay | level list |

Quitting is the explicit button on the main menu. A `back` key that exits the
game from the root is a key that loses a session to a mis-hit.

**The clear overlay belongs to the game screen, not to the router.** It is drawn
over the frozen board when `is_solved()` first goes true and hidden again the
moment the player undoes back into play. GDD §4 makes undo unconditional —
including out of a solved board — so the overlay must not consume `Z`: its
buttons are focusable, and undo, restart and movement keep reaching the state
underneath it.

**A clear is recorded once per entry into the solved state**, at the same latch
v0.2 used to print the clear line. Undoing out and re-solving records again, and
that is correct rather than an exploit: undo restores both counters, so the
second clear's numbers were genuinely paid for.

---

## 9. Save data

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

### The path is a `var`, not a `const`

`save_manager.gd` holds `save_path`, defaulted to `SAVE_PATH`. Nothing in the
game ever assigns it; the test suite does, and that is the whole reason it is
not a constant.

The seam is not optional. Autoloads **do** exist in a headless `--script` run —
`SaveManager` and `LevelLibrary` are both children of the root while the suite
executes, and `_ready()` has already read the real save. A test that called
`SaveManager.record_clear()` would therefore overwrite the developer's own
progress and, worse, would pass. Tests instantiate the script themselves and
point it at a scratch file beside the real one.

Redirecting the whole directory was tried first and does not work: `--userdir`
leaves `OS.get_user_data_dir()` at `…/app_userdata/Boxpush` for this project, so
the suite would still have been writing to the live folder.

---

## 10. Input

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

## 11. Testing

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

There is a `teardown()` hook and no `setup()` hook, which is not an oversight: a
fresh instance per test means a member initialiser already *is* setup, while
releasing a `Node` or deleting a scratch file has no such equivalent. It runs
whether the test passed or failed — and the non-aborting assertions are what
make that reliable, since a failed expectation cannot skip the cleanup below it.

**The gate also fails a green run that leaked.** Godot reports leaked objects at
exit, long after the runner has printed `0 failed` and decided the run passed, so
`test.ps1` re-reads stderr and turns a leak into a non-zero exit. Watched to
fail: deleting the runner's `teardown()` call leaks 24 instances, and before this
check existed that run still reported 64 passed and exited 0.

**No test addon.** GUT and friends are good, but the entire harness here is two
small files, has no version to keep in step with the engine, and runs anywhere
Godot runs. If the suite outgrows it, swapping in GUT is a contained change.

Covered as of v0.3 (65 tests):

- **`test_level_data.gd`** — parsing, every glyph, ASCII round-trip, and each
  validation rule, asserted through its rejection message.
- **`test_sokoban_state.gd`** — the `MoveResult` truth table, both counters, and
  undo as the exact inverse of a move, including the property that undoing an
  arbitrary route restores `to_ascii()` and both counters exactly.
- **`test_levels.gd`** — every shipped level parses, is structurally sane, and
  **is cleared by replaying its recorded solution**. That last one is what turns
  "the levels parse" into "the levels are winnable".
- **`test_save_manager.gd`** — the records, the unlock chain, `resume_index`, and
  every way a save file can go wrong: missing, unparseable, unstamped, or written
  by another format version. The on-disk keys are asserted against the file
  itself, because "keyed by level id, never by index" is a promise about the file
  rather than about the API.
- **`test_project_config.gd`** — the input map, the autoloads, the `SUITES`
  manifest, and that the main scene and every screen instantiate with their
  scripts attached.

Solutions are recorded rather than searched at test time: `tools\solve.ps1`
finds them by breadth-first search driven through the real `try_move`, and the
suite only replays. Searching in the gate would be slow, and would also pass a
level that had silently become a different — but still solvable — level.

### The smoke run, and what is still hand-checked

`tools\smoke.ps1` drives the real scene tree once — menu, level select, all five
levels cleared in sequence, the clear overlay, undo back out of a clear, and a
relaunch with the progress intact. That is the v0.3 acceptance path, made
re-runnable.

It is **not** part of the gate, and that separation is the point. The gate runs
as a `SceneTree` that never builds a tree, which is what keeps it under a second
and lets it run on every save; the smoke run needs a live tree, a `Window`
actually inside it, and a real frame. Folding one into the other would turn the
fast check into the slow one. Run the smoke after touching a screen, a signal
between screens, or the save.

What neither can see, and what therefore still needs eyes:

- **How it looks.** Board placement and scaling, whether the overlay sits over
  the board legibly, whether crate-on-goal reads at a glance, font sizes.
- **How it feels.** The key-repeat rate in the hand. The smoke run replays moves
  straight into the state rather than through the repeat clock, precisely so that
  it tests the flow and not the timing.

---

## 12. Conventions

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

## 13. Open decisions

- **Level select for more than ~12 levels** — the current design is a flat grid
  of buttons. Chapters/pages are deferred until there is content to justify them.
- **Save file migration** — currently discard-on-mismatch. Revisit if the format
  changes while anyone has real progress.
- **Audio bus layout** — trivial for three cues; deferred to v0.4.
- **Localisation** — the UI string count is small enough that a CSV can be
  retrofitted at any point. Not planned for v1.
