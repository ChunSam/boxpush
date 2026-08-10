## Renders every screen to a PNG so the parts no assertion can reach — layout,
## legibility, colour, a move caught in flight — can actually be looked at.
##
##     .\tools\shots.ps1
##
## Needs a real window, so this is the one tool that does not run headless. It
## drives a scratch save, never the player's own.
extends SceneTree

const TestLevels := preload("res://tests/test_levels.gd")

const SHOT_SAVE := "user://shots.cfg"
const DEFAULT_DIR := "res://shots"
const BUTTONS := "GameScreen/ClearOverlay/Panel/Margin/Layout/Buttons/"

var _frame := 0
var _dir := ""
var _main: Control
var _save: Node
var _library: Node


func _process(_delta: float) -> bool:
	_frame += 1

	# Frame numbers rather than awaits: each shot needs the *previous* frame to
	# have been drawn, and the gaps are what let a tween be caught part-way.
	match _frame:
		1:
			_start()
		6:
			_shot("1_main_menu")
			_press("MainMenu/Layout/LevelSelectButton")
		10:
			_shot("2_level_select_locked")
			_key(KEY_ESCAPE)
		12:
			_press("MainMenu/Layout/PlayButton")
		17:
			_shot("3_game_screen")
			_solve_current()
		22:
			_shot("4_clear_overlay")
			_press_node(_main.get_node(BUTTONS + "NextButton"))
		26:
			# Level 2, walked up to the move before its first push. Level 1 is
			# solved by a single push, so there is no such thing as a mid-move
			# there — the board is already cleared and the overlay is up.
			_play(0, 2)
		36:
			_play(2, 3)
		38:
			# Two frames into a 90 ms step: the player and the crate it is pushing
			# should both be between cells rather than snapped onto them.
			_shot("5_mid_move")
		44:
			_solve_current()
			_clear_the_rest()
		50:
			_shot("6_level_select_cleared")
		52:
			_finish()

	return false


func _start() -> void:
	_dir = OS.get_environment("BOXPUSH_SHOT_DIR")
	if _dir.is_empty():
		_dir = ProjectSettings.globalize_path(DEFAULT_DIR)
	DirAccess.make_dir_recursive_absolute(_dir)
	_mark_ignored(_dir)

	_save = root.get_node("SaveManager")
	_library = root.get_node("LevelLibrary")
	_save.save_path = SHOT_SAVE
	_save.reset_progress()

	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _finish() -> void:
	if FileAccess.file_exists(SHOT_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SHOT_SAVE))
	print("")
	print("Shots written to %s" % _dir)
	quit(0)


## Plays the recorded solution's moves in [param from, to), so a shot can be
## taken with the board part-way through a level rather than at either end.
func _play(from: int, to: int) -> void:
	var screen: Control = _main.get_node_or_null("GameScreen")
	if screen == null:
		return

	var solution: String = TestLevels.SOLUTIONS[_library.id_at(screen.level_index)]
	for i in range(from, mini(to, solution.length())):
		screen._state.try_move(SokobanState.direction_from_letter(solution[i]))
	screen._after_change()


func _solve_current() -> void:
	var screen: Control = _main.get_node_or_null("GameScreen")
	if screen == null:
		return
	var state: SokobanState = screen._state
	state.reset()
	for letter in TestLevels.SOLUTIONS[_library.id_at(screen.level_index)]:
		state.try_move(SokobanState.direction_from_letter(letter))
	screen._after_change()


## Clears everything still outstanding, so the last shot shows a finished list
## with real records in it rather than a row of locks.
func _clear_the_rest() -> void:
	while true:
		var next: Button = _main.get_node_or_null(BUTTONS + "NextButton")
		if next == null:
			return
		if not next.visible:
			_press_node(_main.get_node(BUTTONS + "ListButton"))
			return
		_press_node(next)
		_solve_current()


## Drops a `.gdignore` beside the shots, so the engine never imports them.
##
## Without it the screenshots become imported resources and get packed into the
## exported build — which is how a review aid ends up shipping to players. The
## export preset excludes `shots/*` as well; this stops them existing as
## resources in the first place.
func _mark_ignored(dir: String) -> void:
	var marker := "%s/.gdignore" % dir
	if FileAccess.file_exists(marker):
		return
	var file := FileAccess.open(marker, FileAccess.WRITE)
	if file != null:
		file.close()


func _shot(name: String) -> void:
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [_dir, name]
	var err := image.save_png(path)
	if err != OK:
		push_error("Could not write %s (error %d)" % [path, err])
		return
	print("wrote %s" % path)


func _press(path: String) -> void:
	var button := _main.get_node_or_null(path) as Button
	if button != null:
		_press_node(button)


func _press_node(button: Button) -> void:
	button.pressed.emit()


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	root.push_input(event)
