## The mutable half of a Sokoban level: where the player and the crates are
## right now, plus the history needed to take moves back.
##
## Like [LevelData] this is a plain [RefCounted] with no engine dependency, so
## the entire rule set is exercisable from a headless test. It is also
## deliberately signal-free: callers learn what happened from the [enum MoveResult]
## that [method try_move] returns, which keeps the simulation a pure function of
## its inputs and keeps the view layer's redraw explicit rather than reactive.
##
## STATUS: v0.1 skeleton. The contract below is fixed, but [method try_move] and
## [method undo] are not implemented yet — that is milestone v0.2. Everything
## that is pure state bookkeeping is already live.
class_name SokobanState
extends RefCounted

## Outcome of a single [method try_move] call.
enum MoveResult {
	BLOCKED,  ## Nothing changed. Does not advance either counter.
	MOVED,    ## The player stepped onto empty floor.
	PUSHED,   ## The player stepped onto a crate's cell and the crate moved on.
}

## The four legal step vectors, in the order used by [member Directions] indices
## in the undo history. Do not reorder — saved histories depend on it.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,     # 0
	Vector2i.DOWN,   # 1
	Vector2i.LEFT,   # 2
	Vector2i.RIGHT,  # 3
]

var level: LevelData
var player: Vector2i
var move_count := 0
var push_count := 0

## Crate positions as a set: [code]Dictionary[/code] keyed by [Vector2i].
## Membership tests dominate the movement code, so a set beats an array here
## even at Sokoban's tiny crate counts.
var boxes := {}

## One entry per applied move, packed as
## [code]direction_index | (was_a_push << 2)[/code]. Storing the move rather than
## a board snapshot keeps undo O(1) in both time and memory, which matters
## because history is unbounded within an attempt.
var _history: PackedInt32Array = PackedInt32Array()


func _init(level_data: LevelData) -> void:
	level = level_data
	reset()


## Returns the board to the level's starting position and clears undo history.
func reset() -> void:
	player = level.start_player
	boxes.clear()
	for box in level.start_boxes:
		boxes[box] = true
	move_count = 0
	push_count = 0
	_history.clear()


## Attempts one step in [param dir], which must be one of [constant DIRECTIONS].
##
## Applies the rules in docs/game-design.md §4:
##   - target is a wall                    -> BLOCKED
##   - target is free floor                -> MOVED
##   - target has a crate, beyond is free  -> PUSHED
##   - target has a crate, beyond is not   -> BLOCKED
## On MOVED and PUSHED the move is appended to [member _history] and the
## counters advance.
func try_move(_dir: Vector2i) -> MoveResult:
	# TODO(v0.2): implement. See the truth table above; roughly 15 lines.
	push_error("SokobanState.try_move() is not implemented yet (v0.2)")
	return MoveResult.BLOCKED


## Takes back the most recent move, restoring the player, the crate and both
## counters. Returns false when there is nothing to undo.
##
## Undo is the inverse of the recorded move: step the player back by -dir, and
## if the move was a push, pull the crate from [code]player + dir[/code] back to
## [code]player[/code] as it was before the step.
func undo() -> bool:
	# TODO(v0.2): implement as the inverse of try_move using _history.
	push_error("SokobanState.undo() is not implemented yet (v0.2)")
	return false


func can_undo() -> bool:
	return not _history.is_empty()


func move_history_size() -> int:
	return _history.size()


func has_box(cell: Vector2i) -> bool:
	return boxes.has(cell)


## True once every crate stands on a goal. Since the parser guarantees the crate
## and goal counts match, checking that no crate is off-goal is sufficient.
func is_solved() -> bool:
	for box: Vector2i in boxes:
		if not level.is_goal(box):
			return false
	return true


## How many crates are already home. Drives the HUD's progress readout.
func boxes_on_goal() -> int:
	var count := 0
	for box: Vector2i in boxes:
		if level.is_goal(box):
			count += 1
	return count


func box_positions() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for box: Vector2i in boxes:
		result.append(box)
	return result


## Renders the *current* position as XSB. The single most useful thing to print
## when a movement test fails.
func to_ascii() -> String:
	var lines := PackedStringArray()
	for y in level.height:
		var line := ""
		for x in level.width:
			var cell := Vector2i(x, y)
			if level.is_wall(cell):
				line += LevelData.CH_WALL
			elif cell == player:
				line += LevelData.CH_PLAYER_ON_GOAL if level.is_goal(cell) else LevelData.CH_PLAYER
			elif boxes.has(cell):
				line += LevelData.CH_BOX_ON_GOAL if level.is_goal(cell) else LevelData.CH_BOX
			elif level.is_goal(cell):
				line += LevelData.CH_GOAL
			else:
				line += " "
		lines.append(line)
	return "\n".join(lines)
