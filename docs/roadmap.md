# Boxpush — Roadmap

Each milestone has an acceptance criterion that is *checkable*, not a feeling.
No milestone is complete while `tools\test.ps1` exits non-zero.

---

## v0.1 — Skeleton ✅ complete (2026-08-09)

Prove the pipeline before writing any gameplay.

- [x] Godot 4.7.1 installed; `tools/` scripts resolve it without PATH changes
- [x] `project.godot`: autoloads, input map, renderer, viewport
- [x] Directory layout and the core/autoload/scene layering rule
- [x] `LevelData` — XSB parser and validator, fully implemented
- [x] `LevelIndex`, `LevelLibrary`, `SaveManager`
- [x] `SokobanState` — contract fixed; `try_move`/`undo` stubbed for v0.2
- [x] Five levels authored and hand-verified as solvable
- [x] Headless test harness; 30 tests green
- [x] Boot scene reports the pipeline state on screen and on stdout
- [x] Design and technical documents

**Acceptance:** `tools\test.ps1` exits 0, and `tools\run.ps1` prints all five
levels with their geometry. Both verified.

---

## v0.2 — Playable ✅ complete (2026-08-09)

One level, fully playable. No menus, no progression, no art.

- [x] `SokobanState.try_move()` — the four-case truth table from GDD §4
- [x] `SokobanState.undo()` — inverse of the recorded move, counters included
- [x] `scenes/game/board_view.tscn` — `_draw()`-based board, integer-scaled and
      centred, redrawn from state
- [x] `scenes/game/game_screen.tscn` — owns the state, routes input, holds the HUD
- [x] Key repeat: 250 ms delay, 90 ms interval
- [x] `R` restarts, `Z` undoes
- [x] Clear detection: `is_solved()` freezes movement and prints to stdout;
      undo and restart keep working, per GDD §4
- [x] Tests: movement truth table; undo round-trip property; one recorded
      solution per level replayed to `is_solved()`

**Acceptance:** launch, clear `01_first_push` with the keyboard, undo back to the
start, and have `to_ascii()` match the level's start exactly. Solution-replay
tests green for all five levels.

Verified. The replay tests cover all five levels in the gate. The keyboard path
was driven through the real input layer — direction actions polled from
`Input`, undo pushed as an event into the viewport — confirming that one
keypress makes exactly one push, that a cleared board ignores further movement,
that undo restores the start exactly, and that holding a direction steps once
immediately and then repeats.

The parts no test can see — board placement and scaling, HUD legibility, whether
crate-on-goal reads at a glance, and how the repeat rate feels in the hand —
were checked in the running game and signed off on 2026-08-09.

**This was the milestone that mattered most** — it is where "the levels parse"
became "the levels are winnable", proven by replay rather than by hand.

---

## v0.3 — Game — verified; one hands-on check left

Everything around the board.

- [x] `scenes/main.tscn` — the screen router; one screen alive at a time
- [x] `scenes/ui/main_menu.tscn` — Play / Level select / Quit
- [x] `scenes/ui/level_select.tscn` — five buttons, locked ones dimmed, bests shown
- [x] Progression: `SaveManager.is_unlocked()` gates level select; `resume_index()`
      drives Play
- [x] HUD: level name, moves, pushes, crates-home, key hints
- [x] Clear overlay: final counts, records beaten, Next / Retry / Level list
- [x] `Esc` navigation between all screens
- [x] Tests: `SaveManager` against a redirected save path; unlock-chain logic

**Acceptance:** launch from a wiped save, clear all five levels in sequence
without touching the console, restart the game, and find progress and personal
bests intact.

`tools\smoke.ps1` performs exactly that, headlessly, in 81 checks — including the
relaunch. `tools\test.ps1` is green at 65 tests.

Every screen was then rendered to a PNG and looked at, which caught two things no
assertion would have: the clear overlay had no panel behind it and read as text
floating over the board, and space-padding the level list into columns lined up
three rows out of five, because the default font is proportional. The first is
fixed; the second is reverted and left to v0.4, where the labels get nested
properly alongside the art.

**Left over: how the key repeat feels in the hand.** The smoke run replays moves
straight into the state rather than through the repeat clock — deliberately, so
that it measures the flow and not the timing — so 250 ms / 90 ms is still
unconfirmed for v0.3's screens. That needs a human at `tools\run.ps1`.

`SaveManager` is the whole reason this milestone exists — shipped and untested
since v0.1, with every screen above built on top of it — so it was tested
*before* anything was built on it rather than after. Writing those tests turned
up two defects it had been carrying all along: `is_unlocked(-1)` answered *true*,
which is exactly what `LevelLibrary.next_index()` hands it at the end of the set,
and loading a save with no `[progress]` section raised an engine error.

---

## v0.4 — Polish

- [ ] `TileMapLayer` + atlas for the static layer; `Sprite2D` for player and crates
- [ ] 64×64 placeholder art, nearest filtering; crate-on-goal readable at a glance
- [ ] 90 ms move tweens that retarget rather than queue
- [ ] 120 ms scale pop when a crate lands on a goal
- [ ] Three audio cues: step, push, clear; mute toggle
- [ ] Window resize handling; verify at 1280×720, 1920×1080 and a small window

**Acceptance:** no visual snapping during a held-key burst, and the board is
correctly centred and integer-scaled at all three window sizes.

---

## v0.5 — Shippable

- [ ] Windows export preset, **with `*.xsb` in the non-resource filter** — see
      tech-design §5; this is the most likely way to ship a broken build
- [ ] Export templates installed; exported build smoke-tested from a clean folder
- [ ] README build instructions
- [ ] A cleared level in the exported build writes a save that survives a relaunch

**Acceptance:** copy the exported folder to a path with no project checkout, run
it, clear a level, relaunch, and see the progress.

---

## Out of scope for v1

Level editor · community `.xsb` import · move-replay export · deadlock hints ·
undo-tree branching · procedural generation · touch input · localisation.

Each is a deliberate omission, not an oversight. Touch input and localisation in
particular are cheap to retrofit because of decisions already made — abstract
direction actions, and a small UI string count.
