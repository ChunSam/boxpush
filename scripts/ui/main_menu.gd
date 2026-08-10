## Title, and the three ways out of it.
##
## Knows nothing about what any of its buttons lead to — it reports, and the
## router decides (tech-design §8).
extends Control

signal play_pressed
signal level_select_pressed
signal quit_pressed

@onready var _subtitle: Label = $Layout/Subtitle
@onready var _play_button: Button = $Layout/PlayButton
@onready var _level_select_button: Button = $Layout/LevelSelectButton
@onready var _quit_button: Button = $Layout/QuitButton
@onready var _hint: Label = $Layout/Hint


func _ready() -> void:
	_play_button.pressed.connect(play_pressed.emit)
	_level_select_button.pressed.connect(level_select_pressed.emit)
	_quit_button.pressed.connect(quit_pressed.emit)

	# The router owns the mute key. This screen only reports where it now stands,
	# so that pressing M somewhere with no sound in it still shows an effect.
	SaveManager.mute_changed.connect(func(_muted: bool) -> void: _refresh_hint())
	_refresh_hint()
	_refresh_subtitle()
	# So the player can go from launch to cleared without reaching for a mouse —
	# GDD §8 makes this a requirement of every screen, not a nicety.
	_play_button.grab_focus()


func _refresh_hint() -> void:
	_hint.text = "[M] sound %s" % ["off" if SaveManager.is_muted() else "on"]


## Names the level Play will open, because "Play" alone gives a returning player
## no way to tell whether it resumes or starts over.
func _refresh_subtitle() -> void:
	if not LevelLibrary.has_any():
		_subtitle.text = "No levels loaded — see the console."
		_play_button.disabled = true
		_level_select_button.disabled = true
		return

	var index := SaveManager.resume_index()
	var level := LevelLibrary.get_level(index)
	if level == null:
		_subtitle.text = ""
		return

	# resume_index() only lands on a cleared level when every level is cleared,
	# so this is a finished game rather than a level the player is midway through.
	if SaveManager.is_cleared(LevelLibrary.id_at(index)):
		_subtitle.text = "All %d levels cleared — replay %d. %s" % [
			LevelLibrary.count(), index + 1, level.title
		]
	else:
		_subtitle.text = "Next up: %d. %s" % [index + 1, level.title]
