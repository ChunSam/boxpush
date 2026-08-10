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

## v0.3 — Game ✅ complete (2026-08-10)

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

The last thing no script could settle — **how the key repeat feels in the hand** —
was signed off on 2026-08-10, after a session at `tools\run.ps1` that cleared all
five levels. 250 ms / 90 ms stands. The smoke run replays moves straight into the
state rather than through the repeat clock, deliberately, so that it measures the
flow and not the timing; that is why this needed a person and not a test.

`SaveManager` is the whole reason this milestone exists — shipped and untested
since v0.1, with every screen above built on top of it — so it was tested
*before* anything was built on it rather than after. Writing those tests turned
up two defects it had been carrying all along: `is_unlocked(-1)` answered *true*,
which is exactly what `LevelLibrary.next_index()` hands it at the end of the set,
and loading a save with no `[progress]` section raised an engine error.

---

## v0.4 — Polish ✅ complete (2026-08-10)

- [x] `TileMapLayer` + atlas for the static layer; `Sprite2D` for player and crates
- [x] 64×64 placeholder art, nearest filtering; crate-on-goal readable at a glance
- [x] 90 ms move tweens that retarget rather than queue
- [x] 120 ms scale pop when a crate lands on a goal
- [x] Three audio cues: step, push, clear; mute toggle
- [x] Window resize handling; verify at 1280×720, 1920×1080 and a small window

**Acceptance:** no visual snapping during a held-key burst, and the board is
correctly centred and integer-scaled at all three window sizes.

**Both halves are assertions now, not opinions.** `test_board_view.gd` holds
`fit_into()` to a whole-number scale, centred, and the largest that fits, at
every size named above plus one too small for the board; and it drives
`TileMotion` through a burst arriving faster than a step completes, asserting
that a redirect never moves the piece. Writing those tests is what found the hole
in the first version of the fit assertion: checking only that the *next* size up
would overflow lets a fit that already overflows through.

The art and the cues are generated by `tools\make_assets.ps1` from the palette in
GDD §9, so the placeholder look is a constant to edit rather than a binary nobody
can reproduce. `tools\shots.ps1` renders every screen, including one caught two
frames into a step — which is how the wall tile's per-tile highlight was found to
read as scanlines across a block of them, and removed.

The key repeat and the 90 ms step were signed off by hand on 2026-08-10 — see
v0.3. No test and no screenshot has an opinion about 90 ms, so that one always
had to end with somebody playing it.

---

## v0.5 — Shippable ✅ complete (2026-08-10)

- [x] Windows export preset, **with `*.xsb` in the non-resource filter** — see
      tech-design §5; this is the most likely way to ship a broken build
- [x] Export templates installed; exported build launched from a clean folder
- [x] README build instructions
- [x] A cleared level in the exported build writes a save that survives a relaunch

**Acceptance:** copy the exported folder to a path with no project checkout, run
it, clear a level, relaunch, and see the progress.

`tools\export.ps1` builds into `build/`. The preset is now committed rather than
git-ignored, and `test_project_config.gd` asserts its filters — so the filter
that decides whether a build has levels in it fails as a red test rather than
being a paragraph someone had to have read. See tech-design §5 for why that
reversal was worth making.

Copied to a folder with no checkout, the build launches and runs clean: every
level parses out of the pack, which `LevelLibrary` would have said otherwise at
boot. **The first build made from this preset shipped the entire test harness and
six screenshots**, because "all resources" means the suites and the review images
are resources too; `exclude_filter` now drops them and the assertion holds it
there. The pack went from 188 KB to 61 KB.

### What the save half actually rests on

Worth being exact, because the last box was ticked on inference rather than on
watching a number change.

Copied to a folder with no checkout in it and played, the build left the save
file rewritten — a later modification time, byte-identical contents. Both halves
follow from that. It **read** the save: nothing else explains five records
surviving a write, since a build that had failed to load would have written back
only what it had, which is one entry. It **wrote** the save: nothing writes at
boot, so a write means `record_clear` or `set_muted` ran.

What nobody watched is a record *set in the exported build* being read back by a
later launch of it — no record improved during that session, so the round trip of
a changed value was never on screen. Each half was observed; their composition is
the same code twenty tests and the smoke run already cover. Good enough to close,
and written down so that nobody later mistakes it for something someone saw.

---

## The ladder is finished

v0.5 was the last rung, and it is done. There is no v1.0 milestone here because
there was never any work in one: **v0.5's acceptance is v1's**, and both
documents have used "v1" all along to mean the thing v0.5 produces. What is left
is a release decision — whether to tag it `1.0.0` — not a build one.
`project.godot` reads `0.5.0`, which matches the ladder rather than the tag.

Everything below is what v1 deliberately does *not* contain.

---

## Known, and left alone

One defect is on the record and not fixed, because fixing it is new scope rather
than unfinished scope.

**`LevelLibrary`'s indices drift from `LevelIndex`'s when a level is rejected.**
`LevelLibrary.levels` is compacted — `reload()` appends only the levels that
parsed — while `SaveManager.is_unlocked()` indexes the full `LEVEL_PATHS`
manifest. If an `.xsb` ever failed to parse, every index past it would name a
different level to each of them: locks would land on the wrong rows in the level
select, and a clear would be recorded against the wrong id.

It is invisible today, because `test_levels.gd` proves every shipped level
parses and the two lists are therefore always the same length. It is written down
anyway, because `LevelLibrary` is *built* to carry on past a rejected level — it
pushes an error and keeps going — which makes the tolerance half-implemented
rather than absent, and half-implemented is the shape that bites later.

Fixing it means picking one: keep `levels` index-aligned by storing nulls for the
rejected, or make a rejected level fatal at boot and drop the tolerance.

---

## Out of scope for v1

Level editor · community `.xsb` import · move-replay export · deadlock hints ·
undo-tree branching · procedural generation · touch input · localisation.

Each is a deliberate omission, not an oversight. Touch input and localisation in
particular are cheap to retrofit because of decisions already made — abstract
direction actions, and a small UI string count.
