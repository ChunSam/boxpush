## One button per shipped level. A locked level shows its number and nothing
## else; a cleared one shows what the player's best run cost.
##
## Reports which level was chosen and leaves the rest to the router — see
## tech-design §8.
extends Control

signal level_chosen(index: int)
signal back_pressed

@onready var _list: VBoxContainer = $Layout/List


func _ready() -> void:
	_build_buttons()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back"):
		back_pressed.emit()
		accept_event()


## Built in code rather than authored as five nodes in the scene, because the
## level set is data: adding an `.xsb` to [constant LevelIndex.LEVEL_PATHS] has to
## be the only edit a new level needs.
func _build_buttons() -> void:
	var resume := SaveManager.resume_index()
	var focus_target: Button = null

	# LevelLibrary rather than LevelIndex: a level that failed to parse is not
	# playable, and it has already announced itself at boot.
	for index in LevelLibrary.count():
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 52)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 20)
		button.text = _label_for(index)
		button.disabled = not SaveManager.is_unlocked(index)

		if not button.disabled:
			button.pressed.connect(level_chosen.emit.bind(index))
			# The level Play would open, if it is reachable; otherwise the first
			# one that is. Either way the keyboard lands somewhere useful.
			if focus_target == null or index == resume:
				focus_target = button

		_list.add_child(button)

	if focus_target != null:
		focus_target.grab_focus()


func _label_for(index: int) -> String:
	if not SaveManager.is_unlocked(index):
		return "%d.   Locked" % [index + 1]

	var level := LevelLibrary.get_level(index)
	var title: String = level.title if level != null else "?"
	var level_id := LevelLibrary.id_at(index)

	if not SaveManager.is_cleared(level_id):
		return "%d.   %s" % [index + 1, title]

	# Not padded into columns: the default font is proportional, so space-padding
	# lines three rows up out of five and reads as a bug rather than as a list.
	# A real two-column row means labels nested in the button — v0.4's problem,
	# alongside the art.
	return (
		"%d.   %s      cleared - best %d moves, %d pushes"
		% [index + 1, title, SaveManager.best_moves(level_id), SaveManager.best_pushes(level_id)]
	)
