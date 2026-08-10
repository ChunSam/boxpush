## The two rules v0.4 is judged on that are arithmetic rather than taste: where
## the board lands in the window, and how a piece travels between cells.
##
## Both were on the milestone's list as things to check by eye at three window
## sizes. Neither needs an eye — [method BoardView.fit_into] is pure maths on a
## [Node2D], and [TileMotion] is a [RefCounted] with two [Vector2]s in it, so the
## gate can hold them to the rule exactly instead of approximately.
##
## What still needs looking at is everything these two do not decide: colour,
## legibility, and whether the movement reads well at 90 ms.
extends TestCase

## The same rectangle [code]game_screen.gd[/code] hands the board: the window
## less its margins and the HUD strip.
const BOARD_MARGIN := 32.0
const HUD_HEIGHT := 76.0

var _views: Array[Node] = []


func teardown() -> void:
	for view in _views:
		view.free()
	_views.clear()


func test_the_board_is_centred_and_integer_scaled_at_every_window_size() -> void:
	# The three sizes v0.4's acceptance names, and one deliberately awkward.
	for size: Vector2 in [
		Vector2(1280, 720), Vector2(1920, 1080), Vector2(800, 500), Vector2(640, 400)
	]:
		_assert_fits(_view(0), size, "%dx%d" % [size.x, size.y])


## The widest level in the set against the smallest window, which is the case
## where the fit has to give up. It must clamp to 1:1 and stay centred rather
## than scaling to nothing.
func test_a_board_too_big_for_the_window_clamps_to_one_to_one() -> void:
	var widest := 0
	var widest_index := 0
	for index in LevelIndex.count():
		var level := LevelData.load_from_file(LevelIndex.path_at(index))
		if level.is_valid() and level.width > widest:
			widest = level.width
			widest_index = index

	var view := _view(widest_index)
	_assert_fits(view, Vector2(320, 240), "a window smaller than the board")
	assert_eq(view.scale, Vector2.ONE, "the board clamps to 1:1 rather than shrinking")


func test_a_fresh_motion_is_already_where_it_started() -> void:
	var motion := TileMotion.new(Vector2(10, 20))

	assert_false(motion.is_moving(), "a piece that was placed is not travelling")
	assert_eq(motion.position(), Vector2(10, 20), "and is where it was placed")


func test_a_step_takes_exactly_the_specified_time() -> void:
	var motion := TileMotion.new(Vector2.ZERO)
	motion.retarget(Vector2(64, 0))

	motion.advance(TileMotion.DURATION * 0.5)
	assert_true(motion.is_moving(), "half way through, the piece is still moving")
	assert_eq(motion.position(), Vector2(32, 0), "and is half way there")

	motion.advance(TileMotion.DURATION * 0.5)
	assert_false(motion.is_moving(), "at the full duration it has arrived")
	assert_eq(motion.position(), Vector2(64, 0), "exactly on the target")


## The rule that makes a held-key burst resolve in full: a new move must start
## from where the piece is, not from where it was going.
func test_retargeting_mid_flight_starts_from_where_the_piece_is() -> void:
	var motion := TileMotion.new(Vector2.ZERO)
	motion.retarget(Vector2(64, 0))
	motion.advance(TileMotion.DURATION * 0.5)

	var before := motion.position()
	motion.retarget(Vector2(128, 0))

	assert_eq(motion.position(), before, "the piece does not jump when it is redirected")
	motion.advance(TileMotion.DURATION)
	assert_eq(motion.position(), Vector2(128, 0), "and arrives at the new target, not the old")


## v0.4's acceptance in one assertion: "no visual snapping during a held-key
## burst". Moves arrive faster than a step completes, which is exactly what
## holding a direction does at the 90 ms repeat rate.
func test_a_held_key_burst_never_makes_the_piece_jump() -> void:
	var motion := TileMotion.new(Vector2.ZERO)
	var frame := 1.0 / 60.0
	var travelled := 0.0
	var previous := motion.position()
	var cell := 0

	for step in 40:
		# A new move every third frame: sooner than DURATION, so every retarget
		# lands mid-flight.
		if step % 3 == 0:
			cell += 1
			motion.retarget(Vector2(cell * 64, 0))
			assert_eq(motion.position(), previous, "step %d: redirect moved nothing" % step)

		motion.advance(frame)
		var now := motion.position()
		var jump := previous.distance_to(now)
		travelled += jump
		# One frame can never carry a piece further than one whole cell: the
		# distance left is at most a cell and a frame is a fraction of a step.
		assert_true(jump <= 64.0, "step %d: moved %.1f px in one frame" % [step, jump])
		previous = now

	assert_true(travelled > 0.0, "the piece actually went somewhere")
	motion.advance(TileMotion.DURATION)
	assert_eq(motion.position(), Vector2(cell * 64, 0), "the burst ends on the cell it reached")


## Asserts the three things [method BoardView.fit_into] promises: a uniform
## integer scale of at least 1, the board centred in the area, and that scale
## being the largest one that fits.
func _assert_fits(view: BoardView, window: Vector2, label: String) -> void:
	var area := Rect2(
		BOARD_MARGIN,
		HUD_HEIGHT,
		window.x - BOARD_MARGIN * 2.0,
		window.y - HUD_HEIGHT - BOARD_MARGIN
	)
	view.fit_into(area)

	var factor := view.scale.x
	assert_eq(view.scale.y, factor, "%s: scaled uniformly" % label)
	assert_eq(factor, floorf(factor), "%s: scaled by a whole number, got %f" % [label, factor])
	assert_true(factor >= 1.0, "%s: never scaled below 1:1, got %f" % [label, factor])

	var board := Vector2(view.state.level.width, view.state.level.height) * BoardView.TILE
	var centre := view.position + board * factor * 0.5
	assert_true(
		centre.is_equal_approx(area.get_center()),
		"%s: centred — board centre %s, area centre %s" % [label, centre, area.get_center()],
	)

	# Largest *that fits* takes two assertions, not one. Checking only that the
	# next size up would overflow lets a fit that already overflows through.
	var scaled := board * factor
	assert_true(
		factor == 1.0 or (scaled.x <= area.size.x and scaled.y <= area.size.y),
		"%s: %dx does not fit in %s — %s" % [label, int(factor), area.size, scaled],
	)

	var bigger := board * (factor + 1.0)
	assert_true(
		bigger.x > area.size.x or bigger.y > area.size.y,
		"%s: %dx would have fitted too, so %dx was not the largest"
		% [label, int(factor) + 1, int(factor)],
	)


## A view over a real shipped level, never added to a tree — [method Node._ready]
## would build tiles and sprites, and none of that is what is under test here.
func _view(level_index: int) -> BoardView:
	var view := BoardView.new()
	_views.append(view)
	view.state = SokobanState.new(LevelData.load_from_file(LevelIndex.path_at(level_index)))
	return view
