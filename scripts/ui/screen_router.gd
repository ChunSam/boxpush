## The main scene. Holds exactly one screen at a time, and is the only script in
## the project that knows what follows what — tech-design §8.
##
## Screens report by signal and decide nothing. That is what lets the level
## select stay ignorant of the game screen, and the game screen stay ignorant of
## whether a next level even exists.
extends Control

const MAIN_MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const LEVEL_SELECT_SCENE := preload("res://scenes/ui/level_select.tscn")
const GAME_SCREEN_SCENE := preload("res://scenes/game/game_screen.tscn")

var _screen: Control
## Which level the game screen is showing, so "Next" has something to count from.
var _level_index := 0


func _ready() -> void:
	show_main_menu()


func show_main_menu() -> void:
	var screen := MAIN_MENU_SCENE.instantiate()
	screen.play_pressed.connect(_on_play_pressed)
	screen.level_select_pressed.connect(show_level_select)
	screen.quit_pressed.connect(_on_quit_pressed)
	_swap_to(screen)


func show_level_select() -> void:
	var screen := LEVEL_SELECT_SCENE.instantiate()
	screen.level_chosen.connect(show_level)
	screen.back_pressed.connect(show_main_menu)
	_swap_to(screen)


func show_level(index: int) -> void:
	_level_index = index

	var screen := GAME_SCREEN_SCENE.instantiate()
	# Set before add_child, because _ready() is what loads the level. This is the
	# whole reason level_index is an exported property rather than a constant.
	screen.level_index = index
	screen.next_level_requested.connect(_on_next_level_requested)
	screen.level_list_requested.connect(show_level_select)
	_swap_to(screen)


func _on_play_pressed() -> void:
	show_level(SaveManager.resume_index())


func _on_quit_pressed() -> void:
	get_tree().quit()


## Falls back to the level list at the end of the set. [method
## LevelLibrary.next_index] answers -1 there, and [method SaveManager.is_unlocked]
## is what turns that into "no" — asking about the lock rather than about the
## bound keeps the two rules in one place.
func _on_next_level_requested() -> void:
	var next := LevelLibrary.next_index(_level_index)
	if not SaveManager.is_unlocked(next):
		show_level_select()
		return
	show_level(next)


## [method Node.remove_child] before [method Node.queue_free] because this is
## almost always running inside a signal handler of the screen being replaced:
## the outgoing screen has to stop receiving input and stop holding focus now,
## not at the end of the frame when it is finally deleted.
func _swap_to(screen: Control) -> void:
	if _screen != null:
		remove_child(_screen)
		_screen.queue_free()

	_screen = screen
	add_child(_screen)
