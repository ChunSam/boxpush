## Drives the real scene tree through the whole v0.3 path in one headless run:
## main menu -> level select -> every level cleared in sequence -> clear overlay
## -> undo back out of a clear -> relaunch with the progress intact.
##
## This is not part of [code]tools\test.ps1[/code] and is not meant to be. The
## gate runs as a [SceneTree] that never builds a tree, which is what keeps it
## under a second; everything here needs a live tree, a [Window] that is actually
## inside it, and one real frame. Keeping the two apart is what stops the fast
## check from turning into the slow one.
##
## Two deliberate liberties:
##
## - It reaches into [code]GameScreen[/code]'s private state to replay a recorded
##   solution. Driving 71 moves through the real key-repeat clock would need a
##   frame per move and would end up measuring the repeat timing rather than the
##   flow. Navigation and undo *are* driven as real input events, because those
##   are the parts where the binding is the thing under test.
## - It redirects [code]SaveManager.save_path[/code] at a scratch file, so a smoke
##   run never touches the player's own progress.
extends SceneTree

const TestLevels := preload("res://tests/test_levels.gd")
const SaveManagerScript := preload("res://scripts/autoload/save_manager.gd")

const SMOKE_SAVE := "user://smoke_flow.cfg"

var _problems := PackedStringArray()
var _checks := 0
var _main: Control
var _started := false

## Frames to idle after the run, for the deletion queue.
const SETTLE_FRAMES := 5
var _settling := 0

# Fetched by node path rather than named directly: a script started with
# `--script` is compiled before the autoload names become global identifiers.
var _save: Node
var _library: Node


## Everything runs on the first frame rather than in [method _initialize]. At
## initialize time the root [Window] is not yet inside the tree, so [method
## Node._ready] never fires on anything added and [method Viewport.push_input]
## refuses outright — which reads as "the menu did not open".
func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
		_report()
		return false

	# Idle frames before quitting, so the deletion queue drains. The run walks
	# through six screens and every one of them is removed and queue_free()d;
	# quitting in the same frame reports all of their nodes as leaked, which is
	# an artefact of the harness rather than anything the game does.
	_settling += 1
	if _settling < SETTLE_FRAMES:
		return false

	quit(0 if _problems.is_empty() else 1)
	return false


func _run() -> void:
	_save = root.get_node("SaveManager")
	_library = root.get_node("LevelLibrary")
	_save.save_path = SMOKE_SAVE
	_save.reset_progress()

	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)

	_check_fresh_menu()
	_check_fresh_level_select()

	_press("MainMenu/Layout/PlayButton")
	for index in LevelIndex.count():
		_play_level(index)

	_check_finished_level_select()
	_check_finished_menu()
	_check_survives_a_relaunch()

	_cleanup()


func _check_fresh_menu() -> void:
	_check(_screen_name() == "MainMenu", "boots to the main menu, got '%s'" % _screen_name())

	var subtitle := _main.get_node_or_null("MainMenu/Layout/Subtitle") as Label
	if subtitle == null:
		_check(false, "the main menu Subtitle is not at the wired path")
		return

	_check(
		subtitle.text.begins_with("Next up: 1."),
		"a fresh save points Play at level 1, got '%s'" % subtitle.text,
	)


func _check_fresh_level_select() -> void:
	_press("MainMenu/Layout/LevelSelectButton")
	_check(_screen_name() == "LevelSelect", "Level select opens, got '%s'" % _screen_name())

	var buttons := _level_buttons()
	_check(buttons.size() == LevelIndex.count(), "one button per level, got %d" % buttons.size())
	if buttons.size() == LevelIndex.count():
		_check(not buttons[0].disabled, "level 1 is open on a fresh save")
		_check(buttons[1].disabled, "level 2 is locked on a fresh save")
		_check(
			buttons[1].text.contains("Locked"),
			"a locked level shows only its number, got '%s'" % buttons[1].text,
		)

	_key(KEY_ESCAPE)
	_check(
		_screen_name() == "MainMenu",
		"Esc from the level list goes back to the menu, got '%s'" % _screen_name(),
	)


## Clears one level the way a player reaches it, then checks everything the clear
## is supposed to move: the overlay, the record, and undo back out of it.
func _play_level(index: int) -> void:
	var screen: Control = _main.get_node_or_null("GameScreen")
	if screen == null:
		_check(false, "level %d does not open the game screen" % [index + 1])
		return

	_check(
		screen.level_index == index,
		"the router opened %d, the screen shows %d" % [index, screen.level_index],
	)

	var level_id: String = _library.id_at(index)
	var solution: String = TestLevels.SOLUTIONS[level_id]
	var state: SokobanState = screen._state
	for letter in solution:
		state.try_move(SokobanState.direction_from_letter(letter))
	screen._after_change()

	_check(state.is_solved(), "%s replays to a clear" % level_id)

	var overlay: Control = screen.get_node_or_null("ClearOverlay")
	var detail := screen.get_node_or_null("ClearOverlay/Panel/Margin/Layout/Detail") as Label
	var next_button := screen.get_node_or_null(
		"ClearOverlay/Panel/Margin/Layout/Buttons/NextButton"
	) as Button
	if overlay == null or detail == null or next_button == null:
		_check(false, "%s: the clear overlay is not at the wired paths" % level_id)
		return

	_check(overlay.visible, "%s raises the clear overlay" % level_id)
	_check(
		detail.text.contains("First clear."),
		"%s announces a first clear, got '%s'" % [level_id, detail.text],
	)
	_check(_save.is_cleared(level_id), "%s is recorded as cleared" % level_id)
	_check(
		_save.best_moves(level_id) == solution.length(),
		"%s records %d moves, expected %d"
		% [level_id, _save.best_moves(level_id), solution.length()],
	)

	var is_last: bool = index == LevelIndex.count() - 1
	_check(
		next_button.visible != is_last,
		"%s: Next is visible=%s with last level=%s" % [level_id, next_button.visible, is_last],
	)

	# GDD §4 makes undo unconditional, including out of a solved board, so the
	# overlay has to get out of the way rather than swallow the key.
	_key(KEY_Z)
	_check(not state.is_solved(), "%s: undo puts a cleared board back into play" % level_id)
	_check(not overlay.visible, "%s: undo lowers the clear overlay" % level_id)

	state.try_move(SokobanState.direction_from_letter(solution[solution.length() - 1]))
	screen._after_change()
	_check(overlay.visible, "%s: re-solving raises the overlay again" % level_id)

	if is_last:
		_press_node(screen.get_node("ClearOverlay/Panel/Margin/Layout/Buttons/ListButton"))
	else:
		_press_node(next_button)


func _check_finished_level_select() -> void:
	_check(
		_screen_name() == "LevelSelect",
		"the last level ends at the level list, got '%s'" % _screen_name(),
	)
	for button in _level_buttons():
		_check(not button.disabled, "every level is open once the set is finished")
		_check(
			button.text.contains("cleared - best"),
			"a finished level shows its bests, got '%s'" % button.text,
		)


func _check_finished_menu() -> void:
	_key(KEY_ESCAPE)
	var subtitle := _main.get_node_or_null("MainMenu/Layout/Subtitle") as Label
	if subtitle == null:
		_check(false, "Esc from a finished level list did not reach the main menu")
		return

	_check(
		subtitle.text.begins_with("All %d levels cleared" % LevelIndex.count()),
		"the menu reports a finished game, got '%s'" % subtitle.text,
	)


## The relaunch half of the v0.3 acceptance: a second manager over the same file
## must see everything the session wrote.
func _check_survives_a_relaunch() -> void:
	var reopened := SaveManagerScript.new()
	reopened.save_path = SMOKE_SAVE
	reopened.load_progress()

	for index in LevelIndex.count():
		var level_id: String = _library.id_at(index)
		_check(reopened.is_cleared(level_id), "%s is still cleared after a relaunch" % level_id)
		_check(
			reopened.best_moves(level_id) == TestLevels.SOLUTIONS[level_id].length(),
			"%s keeps its move record across a relaunch" % level_id,
		)

	_check(
		reopened.resume_index() == LevelIndex.count() - 1,
		"a finished save resumes at the last level",
	)
	reopened.free()


## The name of the screen the router currently has up. The router keeps exactly
## one child, so this is the whole of the navigation state.
func _screen_name() -> String:
	if _main.get_child_count() == 0:
		return "<none>"
	return _main.get_child(_main.get_child_count() - 1).name


func _level_buttons() -> Array[Button]:
	var found: Array[Button] = []
	var list := _main.get_node_or_null("LevelSelect/Layout/List")
	if list == null:
		return found
	for child in list.get_children():
		found.append(child as Button)
	return found


func _press(path: String) -> void:
	var button := _main.get_node_or_null(path) as Button
	if button == null:
		_check(false, "no button at '%s'" % path)
		return
	_press_node(button)


func _press_node(button: Button) -> void:
	button.pressed.emit()


## Through the real input layer, so the binding in [code]project.godot[/code] and
## the screen's [method Node._unhandled_input] are what get exercised rather than
## a method call standing in for them.
func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	root.push_input(event)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_problems.append(message)


func _cleanup() -> void:
	if FileAccess.file_exists(SMOKE_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SMOKE_SAVE))


func _report() -> void:
	print("")
	print("----------------")
	if _problems.is_empty():
		print("%d checks passed." % _checks)
		print("")
		return

	print("%d of %d checks failed:" % [_problems.size(), _checks])
	for problem in _problems:
		print("  - %s" % problem)
	print("")
