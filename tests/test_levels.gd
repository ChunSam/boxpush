## Content tests: every level that ships must parse, must be structurally sane,
## and must still be winnable. This is the gate that stops a mistyped `.xsb` from
## reaching a build.
##
## Solvability in general is not decidable cheaply — see docs/game-design.md §5 —
## so it is not computed here. Instead each level carries a recorded solution
## that this suite replays. That turns "the level parses" into "the level is
## winnable", which is the whole point of the v0.2 milestone.
extends TestCase

## A shortest solution for each shipped level, in LURD notation, where an
## uppercase letter marks a push.
##
## Found once by breadth-first search driven through the real
## [method SokobanState.try_move], then committed. The gate replays; it does not
## solve. Searching here would be slow, and would also happily pass a level that
## had silently become a different — but still solvable — level.
##
## Editing a `.xsb` almost certainly invalidates its entry. Re-run the search
## rather than patching the string by hand.
const SOLUTIONS := {
	"01_first_push": "R",
	"02_go_around": "luRRRdllldRRR",
	"03_push_up": "UUddrUU",
	"04_obstacle": "lluRRRlluluRRR",
	"05_the_corridor": "uuulDDldRRRRurDDullldddlUUluRRRRdrUU",
}


func test_every_indexed_level_parses() -> void:
	for path in LevelIndex.LEVEL_PATHS:
		var level := LevelData.load_from_file(path)
		assert_true(level.is_valid(), "level must parse — " + level.error_text())


func test_every_level_has_content() -> void:
	for path in LevelIndex.LEVEL_PATHS:
		var level := LevelData.load_from_file(path)
		if not level.is_valid():
			continue  # already reported by test_every_indexed_level_parses

		assert_true(level.box_count() > 0, "%s has at least one crate" % path)
		assert_eq(level.box_count(), level.goal_count(), "%s crates match goals" % path)
		assert_true(level.width >= 3, "%s is at least 3 wide" % path)
		assert_true(level.height >= 3, "%s is at least 3 tall" % path)


func test_every_level_has_a_title() -> void:
	for path in LevelIndex.LEVEL_PATHS:
		var level := LevelData.load_from_file(path)
		assert_ne(level.title, "Untitled", "%s declares a ; Title: comment" % path)


func test_level_ids_are_unique() -> void:
	var seen := {}
	for path in LevelIndex.LEVEL_PATHS:
		var level_id := LevelIndex.id_for_path(path)
		assert_false(seen.has(level_id), "duplicate level id '%s'" % level_id)
		seen[level_id] = true

	assert_eq(seen.size(), LevelIndex.count(), "every path yields a distinct id")


func test_index_lookups_round_trip() -> void:
	for i in LevelIndex.count():
		var path := LevelIndex.path_at(i)
		assert_eq(LevelIndex.index_of_id(LevelIndex.id_for_path(path)), i, "id -> index")

	assert_eq(LevelIndex.path_at(-1), "", "negative index yields no path")
	assert_eq(LevelIndex.path_at(LevelIndex.count()), "", "past-the-end index yields no path")
	assert_eq(LevelIndex.index_of_id("nope"), -1, "unknown id yields -1")


func test_parsing_is_deterministic() -> void:
	for path in LevelIndex.LEVEL_PATHS:
		var first := LevelData.load_from_file(path)
		var second := LevelData.load_from_file(path)
		assert_eq(second.to_ascii(), first.to_ascii(), "%s parses identically twice" % path)


func test_no_level_starts_solved() -> void:
	for path in LevelIndex.LEVEL_PATHS:
		var level := LevelData.load_from_file(path)
		if not level.is_valid():
			continue

		var state := SokobanState.new(level)
		assert_false(state.is_solved(), "%s does not start already solved" % path)


func test_fresh_state_matches_the_level_start() -> void:
	var level := LevelData.load_from_file(LevelIndex.path_at(0))
	var state := SokobanState.new(level)

	assert_eq(state.player, level.start_player, "state starts at the level's player cell")
	assert_eq(state.boxes.size(), level.box_count(), "state starts with every crate")
	assert_eq(state.move_count, 0, "move counter starts at zero")
	assert_eq(state.push_count, 0, "push counter starts at zero")
	assert_false(state.can_undo(), "nothing to undo on a fresh state")
	assert_eq(state.to_ascii(), level.to_ascii(), "fresh state renders as the level start")


func test_reset_restores_the_start() -> void:
	var level := LevelData.load_from_file(LevelIndex.path_at(0))
	var state := SokobanState.new(level)

	state.try_move(Vector2i.RIGHT)  # this level's one push
	state.try_move(Vector2i.UP)

	state.reset()

	assert_eq(state.player, level.start_player, "reset restores the player")
	assert_eq(state.boxes.size(), level.box_count(), "reset restores the crates")
	assert_eq(state.move_count, 0, "reset zeroes the move counter")
	assert_eq(state.to_ascii(), level.to_ascii(), "reset restores the whole board")


func test_every_level_has_a_recorded_solution() -> void:
	for path in LevelIndex.LEVEL_PATHS:
		var level_id := LevelIndex.id_for_path(path)
		assert_true(
			SOLUTIONS.has(level_id),
			"%s has no entry in SOLUTIONS — a level ships unproven without one" % level_id,
		)

	assert_eq(SOLUTIONS.size(), LevelIndex.count(), "no solution outlives the level it solved")


## The v0.2 acceptance test. Every shipped level is cleared by replaying its
## recorded solution, so a content edit that breaks a level fails the build
## rather than the player.
func test_recorded_solutions_clear_their_levels() -> void:
	for path in LevelIndex.LEVEL_PATHS:
		var level_id := LevelIndex.id_for_path(path)
		if not SOLUTIONS.has(level_id):
			continue  # already reported by test_every_level_has_a_recorded_solution

		var level := LevelData.load_from_file(path)
		if not level.is_valid():
			continue  # already reported by test_every_indexed_level_parses

		var state := _replay(level_id, level, SOLUTIONS[level_id])
		if state == null:
			continue  # the replay reported where it stopped

		assert_true(
			state.is_solved(),
			"%s: the solution replays in full but leaves the level unsolved\n%s"
			% [level_id, state.to_ascii()],
		)


## The uppercase letters in a recorded solution claim which steps push. Replay
## ignores case on purpose, so nothing else would notice the claim going stale —
## and a stale one makes the committed fixture lie about how the level is solved.
func test_recorded_solutions_label_their_pushes() -> void:
	for path in LevelIndex.LEVEL_PATHS:
		var level_id := LevelIndex.id_for_path(path)
		if not SOLUTIONS.has(level_id):
			continue

		var level := LevelData.load_from_file(path)
		if not level.is_valid():
			continue

		var moves: String = SOLUTIONS[level_id]
		var state := SokobanState.new(level)

		for i in moves.length():
			var letter: String = moves[i]
			var result := state.try_move(SokobanState.direction_from_letter(letter))
			if result == SokobanState.MoveResult.BLOCKED:
				break  # already reported by test_recorded_solutions_clear_their_levels

			var claims_push := letter == letter.to_upper()
			assert_eq(
				result == SokobanState.MoveResult.PUSHED,
				claims_push,
				"%s: move %d ('%s') disagrees with the recorded notation" % [level_id, i + 1, letter],
			)


## Applies a LURD string, reporting the first move that does not happen and
## returning null so the caller can stop. The board is printed on failure — it is
## the one thing that makes a broken solution diagnosable.
func _replay(level_id: String, level: LevelData, moves: String) -> SokobanState:
	var state := SokobanState.new(level)

	for i in moves.length():
		var letter: String = moves[i]
		var dir := SokobanState.direction_from_letter(letter)

		if dir == Vector2i.ZERO:
			fail("%s: '%s' at position %d is not a LURD letter" % [level_id, letter, i + 1])
			return null

		if state.try_move(dir) == SokobanState.MoveResult.BLOCKED:
			fail(
				"%s: move %d ('%s') is blocked; the level stops here\n%s"
				% [level_id, i + 1, letter, state.to_ascii()],
			)
			return null

	return state
