## Movement rules: the truth table in docs/game-design.md §4, the two counters,
## and undo as the exact inverse of a move.
##
## Boards are declared inline rather than loaded from levels/, so editing the
## shipped content cannot quietly change what these assert. They must start at
## column 0 — the parser treats a leading tab as an unknown character.
extends TestCase

## Player, then a crate with clear floor beyond it and a goal further on, so a
## push can be made without immediately solving the board.
const ROOM := """
########
#      #
# @$ . #
#      #
########
"""

## The goal sits against the right wall, so the push that solves this board is
## also the last one the crate can make.
const TIGHT := """
#####
#   #
#@$.#
#   #
#####
"""

## Two crates in a row. Only one crate moves at a time, so pushing right is
## blocked by the second.
const TWO_CRATES := """
#######
#     #
#@$$..#
#     #
#######
"""


func test_stepping_onto_free_floor_is_a_move() -> void:
	var state := _state(ROOM)
	var start := state.player

	var result := state.try_move(Vector2i.UP)

	assert_eq(result, SokobanState.MoveResult.MOVED, "floor ahead yields MOVED")
	assert_eq(state.player, start + Vector2i.UP, "player advanced one cell")
	assert_eq(state.move_count, 1, "the move counter advanced")
	assert_eq(state.push_count, 0, "the push counter did not")


func test_walking_into_a_wall_is_blocked() -> void:
	var state := _state(TIGHT)
	var before := state.to_ascii()

	var result := state.try_move(Vector2i.LEFT)

	assert_eq(result, SokobanState.MoveResult.BLOCKED, "a wall ahead yields BLOCKED")
	assert_eq(state.to_ascii(), before, "a blocked move changes nothing")
	assert_false(state.can_undo(), "a blocked move records no history")


func test_pushing_a_crate_onto_free_floor() -> void:
	var state := _state(ROOM)
	var crate := state.player + Vector2i.RIGHT

	var result := state.try_move(Vector2i.RIGHT)

	assert_eq(result, SokobanState.MoveResult.PUSHED, "a crate with room ahead yields PUSHED")
	assert_eq(state.player, crate, "the player took the crate's cell")
	assert_true(state.has_box(crate + Vector2i.RIGHT), "the crate moved one cell on")
	assert_false(state.has_box(crate), "the crate left its old cell")
	assert_eq(state.move_count, 1, "a push counts as a move")
	assert_eq(state.push_count, 1, "and as a push")


func test_pushing_a_crate_into_a_wall_is_blocked() -> void:
	var state := _state(TIGHT)
	state.try_move(Vector2i.RIGHT)  # crate lands on the goal, hard against the wall
	var before := state.to_ascii()

	var result := state.try_move(Vector2i.RIGHT)

	assert_eq(result, SokobanState.MoveResult.BLOCKED, "no room beyond the crate")
	assert_eq(state.to_ascii(), before, "nothing moved")
	assert_eq(state.move_count, 1, "only the first push counted")


func test_pushing_a_crate_into_another_crate_is_blocked() -> void:
	var state := _state(TWO_CRATES)
	var before := state.to_ascii()

	var result := state.try_move(Vector2i.RIGHT)

	assert_eq(result, SokobanState.MoveResult.BLOCKED, "a crate behind a crate blocks")
	assert_eq(state.to_ascii(), before, "neither crate moved")
	assert_eq(state.move_count, 0, "a blocked push does not count as a move")
	assert_eq(state.push_count, 0, "nor as a push")


func test_solving_is_detected() -> void:
	var state := _state(TIGHT)

	assert_false(state.is_solved(), "not solved before the push")
	assert_eq(state.boxes_on_goal(), 0, "no crate home yet")

	state.try_move(Vector2i.RIGHT)

	assert_true(state.is_solved(), "solved once the crate reaches the goal")
	assert_eq(state.boxes_on_goal(), 1, "the crate is counted as home")


func test_undo_on_a_fresh_state_reports_nothing_to_undo() -> void:
	var state := _state(ROOM)

	assert_false(state.can_undo(), "a fresh state has no history")
	assert_false(state.undo(), "undo reports that it did nothing")
	assert_eq(state.move_count, 0, "and did not drive the counter negative")


func test_undo_reverses_a_plain_move() -> void:
	var state := _state(ROOM)
	var before := state.to_ascii()
	state.try_move(Vector2i.UP)

	assert_true(state.undo(), "undo reports that it acted")
	assert_eq(state.to_ascii(), before, "the board is back to where it was")
	assert_eq(state.move_count, 0, "the move counter rewound")
	assert_false(state.can_undo(), "the history is empty again")


func test_undo_reverses_a_push_including_the_crate() -> void:
	var state := _state(ROOM)
	var before := state.to_ascii()
	state.try_move(Vector2i.RIGHT)

	state.undo()

	assert_eq(state.to_ascii(), before, "the crate was pulled back with the player")
	assert_eq(state.move_count, 0, "the move counter rewound")
	assert_eq(state.push_count, 0, "the push counter rewound too")


## The GDD is explicit that undo is never disabled, including out of a clear
## state — a solved board is a position like any other, not an end.
func test_undo_works_after_the_level_is_solved() -> void:
	var state := _state(TIGHT)
	var before := state.to_ascii()
	state.try_move(Vector2i.RIGHT)

	assert_true(state.is_solved(), "solved first")
	assert_true(state.undo(), "undo still acts on a solved board")
	assert_false(state.is_solved(), "and takes the board back out of the clear state")
	assert_eq(state.to_ascii(), before, "all the way to where it started")


## The property that matters most: whatever route was taken, undoing every step
## must land exactly on the start. Blocked attempts are mixed in because they
## must not leave anything behind to undo.
func test_undoing_every_move_restores_the_start() -> void:
	var state := _state(ROOM)
	var before := state.to_ascii()

	var route := "rrlluuddrrlluldr"
	var applied := 0
	for i in route.length():
		if state.try_move(SokobanState.direction_from_letter(route[i])) != \
				SokobanState.MoveResult.BLOCKED:
			applied += 1

	assert_true(applied > 0, "the route actually moved the player")
	assert_eq(state.move_count, applied, "the counter agrees with what happened")

	while state.can_undo():
		state.undo()

	assert_eq(state.to_ascii(), before, "undoing everything restores the start exactly")
	assert_eq(state.move_count, 0, "the move counter is back to zero")
	assert_eq(state.push_count, 0, "the push counter is back to zero")
	assert_eq(state.player, state.level.start_player, "the player is home")


func test_reset_clears_the_undo_history() -> void:
	var state := _state(ROOM)
	state.try_move(Vector2i.RIGHT)

	state.reset()

	assert_false(state.can_undo(), "reset drops the history")
	assert_eq(state.move_history_size(), 0, "and reports it as empty")
	assert_eq(state.to_ascii(), state.level.to_ascii(), "the board is back to the start")


func test_letters_map_to_the_four_directions() -> void:
	assert_eq(SokobanState.direction_from_letter("u"), Vector2i.UP, "u is up")
	assert_eq(SokobanState.direction_from_letter("D"), Vector2i.DOWN, "case is ignored")
	assert_eq(SokobanState.direction_from_letter("l"), Vector2i.LEFT, "l is left")
	assert_eq(SokobanState.direction_from_letter("r"), Vector2i.RIGHT, "r is right")
	assert_eq(SokobanState.direction_from_letter("x"), Vector2i.ZERO, "anything else is no step")


## Builds a state from inline XSB. A broken fixture is reported here rather than
## crashing the test that used it: the parser fills in the geometry before it
## validates, so the returned state is still safe to poke at.
func _state(xsb: String) -> SokobanState:
	var level := LevelData.parse(xsb)
	assert_true(level.is_valid(), "fixture parses — " + level.error_text())
	return SokobanState.new(level)
