# Boxpush — Game Design Document

Status: draft v1 (2026-08-09)
Genre: Sokoban (block-pushing logic puzzle)
Purpose: a deliberately small, fully-specified game used to exercise a complete
Godot 4 production pipeline — project setup, scene architecture, data-driven
content, save/load, UI flow, automated tests and export.

---

## 1. Concept

The player controls a single character on a rectangular grid inside a closed
warehouse. Crates must be pushed onto marked floor tiles. A level is cleared
when every crate rests on a goal tile. There is no timer, no enemy and no
randomness — every failure is the player's own reasoning error, and every level
is a fixed, solvable object.

**One-line pitch:** push every crate onto its mark, and think before you move.

### Why this genre for a test project

| Requirement of a test project | How Sokoban satisfies it |
| --- | --- |
| Deterministic, assertable behaviour | Pure integer grid state; identical inputs always produce identical states, so headless unit tests are trivial |
| Non-trivial but bounded rules | Roughly 30 lines of movement logic covers the entire game |
| Exercises data-driven content | Levels are plain text files parsed at load, so the content pipeline is real, not faked |
| Exercises persistence | Per-level best move/push counts and unlock progress |
| Exercises UI flow | Menu → level select → play → clear → next |
| Minimal art dependency | Six tile types; solid-colour placeholders are playable from day one |

---

## 2. Design pillars

1. **Total legibility.** At any instant the player can see the whole board and
   read the exact state. Nothing is hidden, animated away, or off-screen.
2. **Cheap mistakes.** Unlimited undo and instant restart. The cost of a wrong
   move is a keystroke, not a replay. This keeps the difficulty in the *thinking*
   rather than in the punishment.
3. **No noise.** No score multipliers, no stars, no currency. The only metrics
   are move count and push count, shown because optimisation is the natural
   second-order goal for players who want it — never gated on.

### Non-goals

- Procedural level generation (an unsolved-in-general problem; out of scope).
- A built-in solver or hint system.
- Multiplayer, story, or meta-progression.
- Mobile touch controls in v1 (the design leaves room; see §9).

---

## 3. Core loop

```
             ┌──────────────────────────────────────────┐
             │                                          │
   read board ──► plan a push ──► execute moves ──► did it work?
             ▲                                     │      │
             │                                  no │      │ yes
             └────────────── undo ◄────────────────┘      │
                                                          ▼
                                              all crates on goals → clear
                                                          │
                                                          ▼
                                                     next level
```

A single level takes 20 seconds (tutorial) to a few minutes (level 5). A full
v1 session is 10–15 minutes.

---

## 4. Rules (normative)

The board is a grid of cells addressed by `Vector2i(x, y)`, origin at the
top-left, `+x` right and `+y` down. Each cell is either **wall** or **floor**.
Any floor cell may additionally be marked as a **goal**. At most one **crate**
may occupy a floor cell, and exactly one **player** occupies a floor cell.

A *move* is an attempt to step in one of four orthogonal directions
`d ∈ {(0,-1), (0,1), (-1,0), (1,0)}`. Let `p` be the player position,
`a = p + d` the adjacent cell and `b = p + 2d` the cell beyond it.

| Condition | Result | Name |
| --- | --- | --- |
| `a` is a wall | nothing changes | `BLOCKED` |
| `a` is free floor | player moves to `a` | `MOVED` |
| `a` holds a crate, and `b` is free floor | crate moves to `b`, player moves to `a` | `PUSHED` |
| `a` holds a crate, and `b` is a wall or another crate | nothing changes | `BLOCKED` |

Consequences worth stating explicitly, because they define the entire skill of
the game:

- **Crates can only be pushed, never pulled.** The player must always stand on
  the side opposite the intended direction of travel.
- **Only one crate moves at a time.** A row of two crates cannot be pushed.
- **A crate pushed into a corner formed by two walls can never move again.** If
  that corner is not a goal, the level has become unsolvable. The game does not
  detect this; recovering is the player's job, via undo or restart. Teaching
  players to *see* corners before entering them is the core lesson of levels 1–3.

A level is **solved** at the instant the set of crate positions equals the set
of goal positions. Since the crate count always equals the goal count, that is
equivalent to "every crate stands on a goal".

### Counters

- **Moves** — incremented on every `MOVED` or `PUSHED`. Not on `BLOCKED`.
- **Pushes** — incremented on every `PUSHED` only.

Both are shown live and recorded as personal bests on clear. Optimising for
fewest moves and optimising for fewest pushes are genuinely different problems;
tracking both is free and gives replay value at zero content cost.

### Undo

Undo reverts exactly one move, restoring the player position, the crate
position, and both counters. Undo history is unbounded within a level attempt
and is cleared on restart or on leaving the level. Undo is never disabled —
including after the level is solved, so a player may undo out of a clear state
back into play.

---

## 5. Level format

Levels are authored as plain text in the **XSB** notation, the de-facto standard
in the Sokoban community. This buys interoperability with decades of existing
public-domain level sets, and levels remain diffable in git.

| Char | Meaning |
| --- | --- |
| `#` | wall |
| ` ` (space) | empty floor |
| `.` | goal |
| `$` | crate on floor |
| `*` | crate on goal |
| `@` | player on floor |
| `+` | player on goal |

Lines beginning with `;` are comments. A `; Title: ...` comment sets the level's
display name. Example — `levels/01_first_push.xsb`:

```
; Title: First Push
#######
#     #
# @$. #
#     #
#######
```

### Validation rules

The parser rejects a level, with a human-readable reason, unless all of these
hold. Invalid levels fail the automated test suite, so a broken level can never
reach a build.

1. Exactly one player (`@` or `+`).
2. At least one goal, and `crate count == goal count`.
3. The board is fully enclosed: a flood fill of floor cells starting from the
   player never reaches the outer boundary of the grid. This catches the most
   common authoring mistake — a hole in the wall.
4. Every crate and every goal lies in the region reachable from the player.
   A crate the player can never touch, or a goal no crate can ever reach, is
   always an authoring error.

Note that solvability is deliberately *not* validated: deciding Sokoban
solvability is PSPACE-complete, so levels are verified by hand and by a recorded
solution in the level's test fixture.

---

## 6. Content plan (v1)

Five levels, each introducing exactly one idea, in order. This is a teaching
sequence, not a difficulty curve for its own sake.

| # | File | Teaches | Crates |
| --- | --- | --- | --- |
| 1 | `01_first_push.xsb` | You push by walking into a crate | 1 |
| 2 | `02_go_around.xsb` | You must walk around to get behind a crate | 2 |
| 3 | `03_push_up.xsb` | Pushes work in all four directions; order matters | 2 |
| 4 | `04_obstacle.xsb` | Interior walls constrain the routes, not just the pushes | 2 |
| 5 | `05_the_corridor.xsb` | Sequencing: solve in the wrong order and you block yourself | 2 |

Level 5 is the first level where a plausible-looking move order leaves the board
unsolvable — the point at which undo stops being a convenience and becomes part
of the toolkit. Its middle wall has a single gap, which is the only route through
for the player *and* for both crates; a crate parked in that gap ends the attempt.

Beyond v1, the content axis is "add more `.xsb` files"; no code change is
required to ship additional levels.

---

## 7. Controls

| Action | Primary | Secondary |
| --- | --- | --- |
| Move up | `W` | `↑` |
| Move down | `S` | `↓` |
| Move left | `A` | `←` |
| Move right | `D` | `→` |
| Undo | `Z` | `Backspace` |
| Restart level | `R` | — |
| Back / pause | `Esc` | — |

Bindings use *physical* key codes, so `WASD` stays in the same physical position
on AZERTY and Dvorak layouts.

Holding a direction repeats the move after a short delay (250 ms, then one move
every 90 ms). Moving is instantaneous in the simulation; the animation is purely
cosmetic and never blocks the next input, so a queued burst of moves always
resolves in full.

---

## 8. Screens and flow

```
        ┌───────────┐
        │ Main Menu │──── Quit
        └─────┬─────┘
              │ Play
              ▼
      ┌───────────────┐
      │ Level Select  │◄──────────────┐
      └───────┬───────┘               │
              │ pick                  │ Esc / "Level list"
              ▼                       │
        ┌───────────┐                 │
        │   Game    │─────────────────┤
        └─────┬─────┘                 │
              │ solved                │
              ▼                       │
      ┌───────────────┐               │
      │ Clear overlay │───────────────┘
      └───────┬───────┘
              │ Next level
              └──────────► Game (n+1)
```

- **Main menu** — title, Play (resumes at the furthest unlocked level), Level
  select, Quit.
- **Level select** — a grid of five buttons. Locked levels are dimmed; a cleared
  level shows its best move/push counts.
- **Game HUD** — level name, move count, push count, and a hint line for the
  undo/restart keys. Deliberately a single unobtrusive top bar.
- **Clear overlay** — semi-transparent panel over the frozen board showing final
  counts, whether a personal best was beaten, and Next / Retry / Level list.

---

## 9. Presentation

**Art.** 64×64 pixel tiles, nearest-neighbour filtering, no camera zoom in v1.
The board is centred in the viewport and uniformly scaled to fit with a margin,
so a 7×5 tutorial and a 10×7 level both fill the screen sensibly. Placeholder
art is flat colour: floor light grey, wall dark slate, goal a dim outlined
square, crate warm brown, crate-on-goal warm brown with a bright outline. The
crate-on-goal state must be readable *at a glance* — it is the single most
important piece of visual feedback in the game.

**Motion.** Player and crates tween to their new cell over 90 ms with a linear
curve. Tweens are cosmetic only: the logical state updates instantly, and a new
move retargets a running tween rather than waiting for it. A crate landing on a
goal gets a one-shot 120 ms scale pop.

**Audio.** Three cues in v1 — step, push, level clear. All are optional; the
game is fully playable muted, and audio is a v0.4 milestone, not a v0.1 one.

**Accessibility.** No colour-only information: crate-on-goal differs by outline
as well as hue. No time pressure anywhere. No flashing. Full keyboard control
with no mouse requirement during play.

**Deferred for touch.** The input layer maps device events onto four abstract
direction actions, so adding swipe or on-screen D-pad input later touches one
file and no game logic.

---

## 10. Scope ladder

**v0.1 — Skeleton (this milestone).** Project boots, design and tech docs exist,
directory layout and core class contracts are fixed, levels are authored and
parse cleanly, headless test harness runs green.

**v0.2 — Playable.** One level renders and is fully playable with keyboard,
undo, restart and a clear condition. No menus.

**v0.3 — Game.** All five levels, level select, progression unlock, save file,
clear overlay, HUD counters, personal bests.

**v0.4 — Polish.** Tweens, crate-on-goal pop, three audio cues, key-repeat
tuning, window/scaling behaviour.

**v0.5 — Shippable.** Windows export preset with the `*.xsb` filter configured,
smoke-tested exported build, README with build instructions.

**Stretch, explicitly out of v1.** Level editor, community `.xsb` import, move
replay export, deadlock detection hints, undo-tree branching.
