## Tests for the XSB parser and its validation rules
## (docs/game-design.md §5).
extends TestCase

const MINIMAL := """; Title: Minimal
#####
#@$.#
#####
"""


func test_parses_a_minimal_level() -> void:
	var level := LevelData.parse(MINIMAL)

	assert_true(level.is_valid(), "minimal level should parse: " + level.error_text())
	assert_eq(level.title, "Minimal", "title comes from the ; Title: comment")
	assert_eq(level.width, 5, "width")
	assert_eq(level.height, 3, "height")
	assert_eq(level.start_player, Vector2i(1, 1), "player position")
	assert_eq(level.start_boxes, [Vector2i(2, 1)], "crate positions")
	assert_eq(level.goals, [Vector2i(3, 1)], "goal positions")


func test_walls_and_bounds() -> void:
	var level := LevelData.parse(MINIMAL)

	assert_true(level.is_wall(Vector2i(0, 0)), "corner is a wall")
	assert_false(level.is_wall(Vector2i(1, 1)), "player cell is floor")
	assert_true(level.is_wall(Vector2i(-1, 1)), "out of bounds counts as wall")
	assert_true(level.is_wall(Vector2i(99, 99)), "far out of bounds counts as wall")
	assert_false(level.is_inside(Vector2i(5, 1)), "x == width is outside")


func test_round_trips_through_ascii() -> void:
	var source := "#####\n#+*.#\n#$$ #\n#####"
	var level := LevelData.parse(source)

	assert_true(level.is_valid(), "level should parse: " + level.error_text())
	assert_eq(level.to_ascii(), source, "to_ascii() reproduces the source board")


func test_player_and_crate_on_goal_glyphs() -> void:
	# '+' is a player standing on a goal, '*' a crate already home.
	var level := LevelData.parse("#####\n#+*.#\n#$$ #\n#####")

	assert_true(level.is_valid(), "level should parse: " + level.error_text())
	assert_eq(level.start_player, Vector2i(1, 1), "'+' places the player")
	assert_eq(level.goal_count(), 3, "'+', '*' and '.' are all goals")
	assert_eq(level.box_count(), 3, "'*' and '$' are both crates")
	assert_true(level.is_goal(Vector2i(1, 1)), "the player's own cell is a goal")


func test_dash_and_underscore_count_as_floor() -> void:
	var level := LevelData.parse("#####\n#@$.#\n#-_-#\n#####")

	assert_true(level.is_valid(), "dash/underscore floor should parse: " + level.error_text())
	assert_false(level.is_wall(Vector2i(1, 2)), "'-' is floor")
	assert_false(level.is_wall(Vector2i(2, 2)), "'_' is floor")


func test_rejects_missing_player() -> void:
	var level := LevelData.parse("#####\n# $.#\n#####")

	assert_false(level.is_valid(), "a level with no player must be rejected")
	assert_contains(level.error_text(), "no player", "reason names the missing player")


func test_rejects_two_players() -> void:
	var level := LevelData.parse("######\n#@$.@#\n######")

	assert_false(level.is_valid(), "two players must be rejected")
	assert_contains(level.error_text(), "2 players", "reason names the player count")


func test_rejects_crate_goal_mismatch() -> void:
	var level := LevelData.parse("#######\n#@$$. #\n#######")

	assert_false(level.is_valid(), "2 crates and 1 goal must be rejected")
	assert_contains(level.error_text(), "must match", "reason explains the mismatch")


func test_rejects_unenclosed_board() -> void:
	# The right-hand wall is missing, so the floor leaks to the grid edge.
	var level := LevelData.parse("#####\n#@$. \n#####")

	assert_false(level.is_valid(), "a board with a hole must be rejected")
	assert_contains(level.error_text(), "not enclosed", "reason names the leak")


func test_rejects_unknown_character() -> void:
	var level := LevelData.parse("#####\n#@$X#\n#..##\n#####")

	assert_false(level.is_valid(), "an unknown glyph must be rejected")
	assert_contains(level.error_text(), "unexpected character", "reason names the glyph")


func test_rejects_walled_off_goal() -> void:
	# The goal on the right sits in its own sealed chamber.
	var level := LevelData.parse("#######\n#@$#.##\n#######")

	assert_false(level.is_valid(), "an unreachable goal must be rejected")
	assert_contains(level.error_text(), "walled off", "reason explains the isolation")


func test_rejects_empty_text() -> void:
	var level := LevelData.parse("; Title: Nothing\n\n")

	assert_false(level.is_valid(), "text with no board must be rejected")
	assert_contains(level.error_text(), "no board", "reason says the board is missing")


func test_missing_file_is_reported_not_crashed() -> void:
	var level := LevelData.load_from_file("res://levels/does_not_exist.xsb")

	assert_false(level.is_valid(), "a missing file yields an invalid level")
	assert_contains(level.error_text(), "not found", "reason says the file is missing")


func test_comments_and_blank_lines_before_the_board_are_skipped() -> void:
	var level := LevelData.parse("; a note\n\n; another\n#####\n#@$.#\n#####\n")

	assert_true(level.is_valid(), "leading noise should be ignored: " + level.error_text())
	assert_eq(level.height, 3, "only the board rows are counted")


func test_a_blank_line_ends_the_board() -> void:
	# XSB files pack several levels into one file, separated by blank lines. Only
	# the first board is read.
	var level := LevelData.parse("#####\n#@$.#\n#####\n\n#####\n#@$.#\n#####\n")

	assert_true(level.is_valid(), "first board should parse: " + level.error_text())
	assert_eq(level.height, 3, "the second board is not appended")
