## Autoload. Parses every level in [LevelIndex] once at startup and hands them
## out by index or id.
##
## Parsing five tiny text files costs well under a millisecond, so doing it
## eagerly buys a guarantee worth far more than the time: if a level file is
## malformed, the game says so at boot with a file name and a reason, instead of
## failing halfway through a session when the player reaches that level.
extends Node

## Emitted once per level that failed to parse, after loading finishes.
signal level_rejected(level_id: String, reason: String)

## Levels that parsed cleanly, in [LevelIndex] order.
var levels: Array[LevelData] = []

## Parse failures, keyed by level id, with the human-readable reason as value.
var rejected := {}


func _ready() -> void:
	reload()


## Re-reads every level from disk. Called at startup; also useful from the editor
## while authoring, so a level can be tweaked without restarting the game.
func reload() -> void:
	levels.clear()
	rejected.clear()

	for path in LevelIndex.LEVEL_PATHS:
		var level := LevelData.load_from_file(path)
		var level_id := LevelIndex.id_for_path(path)

		if level.is_valid():
			levels.append(level)
			continue

		var reason := ", ".join(level.errors)
		rejected[level_id] = reason
		push_error("Level '%s' rejected: %s" % [level_id, reason])
		level_rejected.emit(level_id, reason)


func count() -> int:
	return levels.size()


func has_any() -> bool:
	return not levels.is_empty()


## Returns null for an out-of-range index. Callers are expected to have got the
## index from [method count] or from a level-select button, so a null here is a
## programming error rather than something to handle gracefully.
func get_level(index: int) -> LevelData:
	if index < 0 or index >= levels.size():
		return null
	return levels[index]


func get_level_by_id(level_id: String) -> LevelData:
	for level in levels:
		if LevelIndex.id_for_path(level.source_path) == level_id:
			return level
	return null


func id_at(index: int) -> String:
	var level := get_level(index)
	if level == null:
		return ""
	return LevelIndex.id_for_path(level.source_path)


## Index of the level after [param index], or -1 when that was the last one.
func next_index(index: int) -> int:
	var candidate := index + 1
	return candidate if candidate < levels.size() else -1
