## Boot scene for the v0.1 skeleton.
##
## There is no gameplay yet. What this screen does is prove, in the real engine
## rather than in a test harness, that the content pipeline is wired end to end:
## autoloads come up, every `.xsb` in [LevelIndex] parses, and the save file
## round-trips. Each level is printed with its parsed geometry, so an authoring
## mistake is visible the moment you press F5.
##
## Milestone v0.2 replaces this with the real board view; see docs/roadmap.md.
extends Control

const MARGIN := 32.0


func _ready() -> void:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = MARGIN
	label.offset_top = MARGIN
	label.offset_right = -MARGIN
	label.offset_bottom = -MARGIN
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.text = _build_report()
	add_child(label)

	print(_build_report())


func _build_report() -> String:
	var lines := PackedStringArray()
	lines.append("Boxpush — v0.1 skeleton")
	lines.append("Godot %s" % Engine.get_version_info()["string"])
	lines.append("")
	lines.append(
		"Levels: %d of %d loaded" % [LevelLibrary.count(), LevelIndex.count()]
	)
	lines.append("")

	for i in LevelLibrary.count():
		var level := LevelLibrary.get_level(i)
		lines.append(
			"  %d. %-14s  %dx%d  %d crates  [%s]"
			% [
				i + 1,
				level.title,
				level.width,
				level.height,
				level.box_count(),
				_progress_note(LevelIndex.id_for_path(level.source_path)),
			]
		)

	for level_id: String in LevelLibrary.rejected:
		lines.append("  !! %s rejected: %s" % [level_id, LevelLibrary.rejected[level_id]])

	lines.append("")
	lines.append("Save file: %s" % ProjectSettings.globalize_path(SaveManager.SAVE_PATH))
	lines.append("Resume at level %d" % (SaveManager.resume_index() + 1))

	return "\n".join(lines)


func _progress_note(level_id: String) -> String:
	if not SaveManager.is_cleared(level_id):
		return "not cleared"
	return "best %d moves / %d pushes" % [
		SaveManager.best_moves(level_id),
		SaveManager.best_pushes(level_id),
	]
