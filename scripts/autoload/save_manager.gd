## Autoload. Persists which levels are cleared and the player's best move and
## push counts for each.
##
## Progress is keyed by level *id* (the `.xsb` basename), never by index, so
## inserting or reordering levels cannot corrupt an existing save.
##
## The file is [ConfigFile] rather than JSON because it stays readable and
## hand-editable, which is worth more during development than compactness. It is
## written to [code]user://[/code], i.e.
## [code]%APPDATA%\Godot\app_userdata\Boxpush\[/code] on Windows.
extends Node

const SAVE_PATH := "user://boxpush_save.cfg"
const SECTION_META := "meta"
const SECTION_PROGRESS := "progress"

## Bump when the on-disk shape changes. A save written by a different version is
## discarded rather than migrated — acceptable for a test project, and the one
## decision here that a real game would revisit.
const SAVE_FORMAT_VERSION := 1

const NO_RECORD := -1

## Audio setting, kept in [constant SECTION_META] beside the format stamp rather
## than in [constant SECTION_PROGRESS]. It is not progress: wiping a save should
## not turn the sound back on.
const KEY_MUTED := "muted"

signal progress_changed(level_id: String)

## Not [signal progress_changed], because muting is not progress and the level
## select has no reason to redraw for it.
signal mute_changed(muted: bool)

## Where this instance reads and writes. A variable rather than a constant for
## exactly one reason: the test suite points its own instances at a scratch file.
##
## Autoloads are alive during a headless [code]--script[/code] run, so a test
## that used the [code]SaveManager[/code] singleton would overwrite the
## developer's real progress — and pass while doing it. Nothing in the game
## assigns this.
var save_path := SAVE_PATH

var _entries := {}
var _muted := false


func _ready() -> void:
	load_progress()


## Reads the save file. Returns false when nothing usable was loaded — a fresh
## install, an unreadable file, or a save from an incompatible version. In every
## one of those cases the in-memory progress is left empty, which is the correct
## starting state, so callers rarely need the return value.
func load_progress() -> bool:
	_entries.clear()

	var config := ConfigFile.new()
	var err := config.load(save_path)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			push_warning("Could not read %s (error %d); starting fresh." % [save_path, err])
		return false

	var version: int = config.get_value(SECTION_META, "format_version", 0)
	if version != SAVE_FORMAT_VERSION:
		push_warning(
			"Save format %d is not %d; discarding progress." % [version, SAVE_FORMAT_VERSION]
		)
		return false

	_muted = bool(config.get_value(SECTION_META, KEY_MUTED, false))

	# Guarded rather than assumed: a save written by reset_progress() has a [meta]
	# section and no [progress] one, and asking ConfigFile for the keys of a
	# section it does not have is an engine error, not an empty list.
	if not config.has_section(SECTION_PROGRESS):
		return true

	for level_id in config.get_section_keys(SECTION_PROGRESS):
		var entry: Dictionary = config.get_value(SECTION_PROGRESS, level_id, {})
		_entries[level_id] = {
			"cleared": bool(entry.get("cleared", false)),
			"best_moves": int(entry.get("best_moves", NO_RECORD)),
			"best_pushes": int(entry.get("best_pushes", NO_RECORD)),
		}

	return true


func save_progress() -> bool:
	var config := ConfigFile.new()
	config.set_value(SECTION_META, "format_version", SAVE_FORMAT_VERSION)
	config.set_value(SECTION_META, KEY_MUTED, _muted)
	for level_id: String in _entries:
		config.set_value(SECTION_PROGRESS, level_id, _entries[level_id])

	var err := config.save(save_path)
	if err != OK:
		push_error("Could not write %s (error %d)." % [save_path, err])
		return false
	return true


func is_cleared(level_id: String) -> bool:
	return _entries.has(level_id) and _entries[level_id]["cleared"]


## Fewest moves the player has ever cleared this level in, or [constant NO_RECORD].
func best_moves(level_id: String) -> int:
	if not _entries.has(level_id):
		return NO_RECORD
	return _entries[level_id]["best_moves"]


func best_pushes(level_id: String) -> int:
	if not _entries.has(level_id):
		return NO_RECORD
	return _entries[level_id]["best_pushes"]


## Records a clear and writes the file immediately — a level clear is rare and
## the file is a few hundred bytes, so there is nothing to gain from batching,
## and losing progress to a crash would be worse than a stutter.
##
## Move and push records are tracked independently: a run may set a new move
## record without touching the push record, and vice versa.
##
## Returns [code]{ first_clear, beat_moves, beat_pushes }[/code] so the clear
## overlay can say which record, if any, was just broken.
func record_clear(level_id: String, moves: int, pushes: int) -> Dictionary:
	var previous: Dictionary = _entries.get(
		level_id, {"cleared": false, "best_moves": NO_RECORD, "best_pushes": NO_RECORD}
	)

	var first_clear: bool = not previous["cleared"]
	var beat_moves: bool = previous["best_moves"] == NO_RECORD or moves < previous["best_moves"]
	var beat_pushes: bool = previous["best_pushes"] == NO_RECORD or pushes < previous["best_pushes"]

	_entries[level_id] = {
		"cleared": true,
		"best_moves": moves if beat_moves else previous["best_moves"],
		"best_pushes": pushes if beat_pushes else previous["best_pushes"],
	}

	save_progress()
	progress_changed.emit(level_id)

	return {
		"first_clear": first_clear,
		"beat_moves": beat_moves and not first_clear,
		"beat_pushes": beat_pushes and not first_clear,
	}


## Levels unlock in order: level 0 is always open, and level n opens once n-1 is
## cleared. Any level already cleared stays open even if the chain ahead of it
## is not.
##
## An index outside the set is locked, negatives included. That is not defensive
## padding: [method LevelLibrary.next_index] returns -1 past the end of the set,
## so "is the next level unlocked?" hands this a negative index as a matter of
## course, and answering yes would send the router at a level that is not there.
func is_unlocked(index: int) -> bool:
	if index < 0 or index >= LevelIndex.count():
		return false
	if index == 0:
		return true
	var previous_id := LevelIndex.id_for_path(LevelIndex.path_at(index - 1))
	return is_cleared(previous_id) or is_cleared(LevelIndex.id_for_path(LevelIndex.path_at(index)))


## Index the "Play" button should resume at: the first level not yet cleared, or
## the last level once everything is done.
func resume_index() -> int:
	for i in LevelIndex.count():
		if not is_cleared(LevelIndex.id_for_path(LevelIndex.path_at(i))):
			return i
	return maxi(0, LevelIndex.count() - 1)


func is_muted() -> bool:
	return _muted


## Writes immediately, like a clear does. Muting is a decision the player made
## once and should not have to make again next launch.
func set_muted(value: bool) -> void:
	if _muted == value:
		return
	_muted = value
	save_progress()
	mute_changed.emit(_muted)


## Wipes progress in memory and on disk. Exposed for the settings screen and for
## tests that need a known-empty starting state.
##
## Leaves [method is_muted] alone on purpose: someone clearing their progress is
## starting the levels again, not asking for the sound back.
func reset_progress() -> void:
	_entries.clear()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	save_progress()
	progress_changed.emit("")
