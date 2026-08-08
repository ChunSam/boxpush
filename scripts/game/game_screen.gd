## The playable screen: owns a [SokobanState], routes the keyboard onto it, and
## keeps the board and the HUD in step with it.
##
## v0.2 plays one level and has no menus. The level is an exported index rather
## than a constant so that v0.3's level select has something to pass in without
## this script changing shape.
extends Control

## Seconds a direction must be held before it starts repeating, then seconds
## between repeats. GDD §7.
const REPEAT_DELAY := 0.25
const REPEAT_INTERVAL := 0.09

const BOARD_MARGIN := 32.0
const HUD_HEIGHT := 76.0

## Input actions mapped onto step vectors. Iteration order settles which
## direction wins when two are held, so it is insertion order, not chance.
const DIRECTION_ACTIONS := {
	"move_up": Vector2i.UP,
	"move_down": Vector2i.DOWN,
	"move_left": Vector2i.LEFT,
	"move_right": Vector2i.RIGHT,
}

@export var level_index := 0

@onready var _board: BoardView = $BoardView
@onready var _hud: Label = $Hud

var _state: SokobanState
var _held_action := ""
var _repeat_countdown := 0.0
var _clear_reported := false


func _ready() -> void:
	resized.connect(_fit_board)
	_load_level(level_index)


func _process(delta: float) -> void:
	if _state == null:
		return

	var action := _current_direction_action()
	if action.is_empty():
		_held_action = ""
		return

	if action != _held_action:
		# A newly pressed direction takes effect at once and restarts the delay,
		# so rolling from one key to another never feels sticky.
		_held_action = action
		_repeat_countdown = REPEAT_DELAY
		_step(DIRECTION_ACTIONS[action])
		return

	_repeat_countdown -= delta
	if _repeat_countdown <= 0.0:
		_repeat_countdown = REPEAT_INTERVAL
		_step(DIRECTION_ACTIONS[action])


## Undo and restart are single-shot rather than repeating: GDD §7 gives a repeat
## rate for directions only.
##
## Neither is disabled by a clear. The GDD is explicit that undo always works,
## including out of a solved board and back into play.
func _unhandled_input(event: InputEvent) -> void:
	if _state == null:
		return

	if event.is_action_pressed("undo_move"):
		if _state.undo():
			_after_change()
		accept_event()
	elif event.is_action_pressed("restart_level"):
		_state.reset()
		_after_change()
		accept_event()


func _load_level(index: int) -> void:
	var level := LevelLibrary.get_level(index)
	if level == null:
		_hud.text = (
			"No level at index %d — %d of %d loaded.\nSee the console for parse errors."
			% [index, LevelLibrary.count(), LevelIndex.count()]
		)
		return

	_state = SokobanState.new(level)
	_clear_reported = false
	_board.show_state(_state)
	_fit_board()
	_refresh_hud()


## The direction to act on this frame: whatever was just pressed, otherwise
## whatever is still held. Checking "just pressed" first is what lets a new key
## interrupt a running repeat instead of waiting for the old key to come up.
func _current_direction_action() -> String:
	for action: String in DIRECTION_ACTIONS:
		if Input.is_action_just_pressed(action):
			return action
	for action: String in DIRECTION_ACTIONS:
		if Input.is_action_pressed(action):
			return action
	return ""


func _step(dir: Vector2i) -> void:
	# A cleared board freezes: only undo and restart still reach the state.
	if _state.is_solved():
		return
	if _state.try_move(dir) == SokobanState.MoveResult.BLOCKED:
		return
	_after_change()


func _after_change() -> void:
	_board.refresh()
	_refresh_hud()
	_report_clear()


## Prints the clear line once per entry into the solved state. Undoing back out
## re-arms it, so a player who undoes and re-solves is told again.
func _report_clear() -> void:
	if not _state.is_solved():
		_clear_reported = false
		return
	if _clear_reported:
		return

	_clear_reported = true
	print(
		"Cleared '%s' in %d moves, %d pushes."
		% [_state.level.title, _state.move_count, _state.push_count]
	)


func _refresh_hud() -> void:
	if _state == null:
		return

	var status := "  —  CLEARED" if _state.is_solved() else ""
	_hud.text = (
		"%s%s\nmoves %d    pushes %d    crates home %d/%d        [WASD] move   [Z] undo   [R] restart"
		% [
			_state.level.title,
			status,
			_state.move_count,
			_state.push_count,
			_state.boxes_on_goal(),
			_state.level.goal_count(),
		]
	)


func _fit_board() -> void:
	if _state == null:
		return

	var area := Rect2(
		BOARD_MARGIN,
		HUD_HEIGHT,
		size.x - BOARD_MARGIN * 2.0,
		size.y - HUD_HEIGHT - BOARD_MARGIN
	)
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return

	_board.fit_into(area)
