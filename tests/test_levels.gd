## Content tests: every level that ships must parse and must be structurally
## sane. This is the gate that stops a mistyped `.xsb` from reaching a build.
##
## Solvability is not asserted — see docs/game-design.md §5 for why. Levels are
## verified by hand; once [SokobanState] lands in v0.2 this suite gains a
## recorded solution per level, replayed as a regression test.
extends TestCase


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

	# Poke the state directly; try_move() is not implemented until v0.2.
	state.player = Vector2i(0, 0)
	state.boxes.clear()
	state.move_count = 7

	state.reset()

	assert_eq(state.player, level.start_player, "reset restores the player")
	assert_eq(state.boxes.size(), level.box_count(), "reset restores the crates")
	assert_eq(state.move_count, 0, "reset zeroes the move counter")
