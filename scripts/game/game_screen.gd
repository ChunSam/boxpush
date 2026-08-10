## The playable screen: owns a [SokobanState], routes the keyboard onto it, and
## keeps the board, the HUD and the clear overlay in step with it.
##
## Navigation is reported, not performed: this screen does not know whether a
## next level exists or what the level list is called. The router decides —
## tech-design §8.
extends Control

## Emitted from the clear overlay. Which level comes next is the router's
## problem; this screen only knows the player asked to move on.
signal next_level_requested
signal level_list_requested

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
@onready var _overlay: Control = $ClearOverlay
@onready var _overlay_heading: Label = $ClearOverlay/Panel/Margin/Layout/Heading
@onready var _overlay_detail: Label = $ClearOverlay/Panel/Margin/Layout/Detail
@onready var _next_button: Button = $ClearOverlay/Panel/Margin/Layout/Buttons/NextButton
@onready var _retry_button: Button = $ClearOverlay/Panel/Margin/Layout/Buttons/RetryButton
@onready var _list_button: Button = $ClearOverlay/Panel/Margin/Layout/Buttons/ListButton
@onready var _step_sound: AudioStreamPlayer = $Sounds/Step
@onready var _push_sound: AudioStreamPlayer = $Sounds/Push
@onready var _clear_sound: AudioStreamPlayer = $Sounds/Clear

var _state: SokobanState
var _held_action := ""
var _repeat_countdown := 0.0
var _clear_reported := false


func _ready() -> void:
	resized.connect(_fit_board)
	_next_button.pressed.connect(next_level_requested.emit)
	_retry_button.pressed.connect(_on_retry_pressed)
	_list_button.pressed.connect(level_list_requested.emit)
	# The router owns the mute key; the HUD only has to notice it happened.
	SaveManager.mute_changed.connect(func(_muted: bool) -> void: _refresh_hud())
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
## Neither is disabled by a clear, and the overlay does not change that. The GDD
## is explicit that undo always works, including out of a solved board and back
## into play — the overlay's buttons take focus but none of these keys is a `ui_*`
## action, so all three still arrive here with the overlay up.
func _unhandled_input(event: InputEvent) -> void:
	# Ahead of the state check, so a level that failed to load is still a screen
	# the player can leave.
	if event.is_action_pressed("back"):
		level_list_requested.emit()
		accept_event()
		return

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
	_overlay.visible = false
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

	var result := _state.try_move(dir)
	if result == SokobanState.MoveResult.BLOCKED:
		return

	# No cue for a blocked move. Walking into a wall should feel like nothing
	# happened, because nothing did.
	if result == SokobanState.MoveResult.PUSHED:
		_push_sound.play()
	else:
		_step_sound.play()

	_after_change()


func _after_change() -> void:
	_board.refresh()
	_refresh_hud()
	_report_clear()


func _on_retry_pressed() -> void:
	_state.reset()
	_after_change()


## Records the clear once per entry into the solved state and raises the overlay.
## Undoing back out lowers it and re-arms the latch, so a player who undoes and
## re-solves is recorded again — correctly, since undo restores both counters and
## the second run's numbers were genuinely paid for.
func _report_clear() -> void:
	if not _state.is_solved():
		_clear_reported = false
		_overlay.visible = false
		return
	if _clear_reported:
		return

	_clear_reported = true
	_clear_sound.play()
	print(
		"Cleared '%s' in %d moves, %d pushes."
		% [_state.level.title, _state.move_count, _state.push_count]
	)

	var outcome := SaveManager.record_clear(
		LevelLibrary.id_at(level_index), _state.move_count, _state.push_count
	)
	_show_overlay(outcome)


func _show_overlay(outcome: Dictionary) -> void:
	_overlay_heading.text = "Cleared"
	_overlay_detail.text = "%d moves, %d pushes\n%s" % [
		_state.move_count, _state.push_count, _describe_records(outcome)
	]

	# Absent rather than disabled on the last level, per GDD §8: a button that
	# cannot do anything is a question the player has to answer twice.
	_next_button.visible = LevelLibrary.next_index(level_index) != -1
	_overlay.visible = true

	var focus_target := _next_button if _next_button.visible else _retry_button
	focus_target.grab_focus()


func _describe_records(outcome: Dictionary) -> String:
	if outcome["first_clear"]:
		return "First clear."
	if outcome["beat_moves"] and outcome["beat_pushes"]:
		return "New best: moves and pushes."
	if outcome["beat_moves"]:
		return "New best: moves."
	if outcome["beat_pushes"]:
		return "New best: pushes."

	var level_id := LevelLibrary.id_at(level_index)
	return (
		"Best so far: %d moves, %d pushes."
		% [SaveManager.best_moves(level_id), SaveManager.best_pushes(level_id)]
	)


func _refresh_hud() -> void:
	if _state == null:
		return

	var status := "  —  CLEARED" if _state.is_solved() else ""
	_hud.text = (
		"%d. %s%s\nmoves %d    pushes %d    crates home %d/%d"
		+ "     [WASD] move  [Z] undo  [R] restart  [M] sound %s  [Esc] level list"
	) % [
		level_index + 1,
		_state.level.title,
		status,
		_state.move_count,
		_state.push_count,
		_state.boxes_on_goal(),
		_state.level.goal_count(),
		"off" if SaveManager.is_muted() else "on",
	]


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
