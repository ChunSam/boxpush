## Immutable description of a single Sokoban level, parsed from XSB text.
##
## This class has no scene, node or rendering dependency, so it can be built and
## asserted inside a headless test run. Everything that changes while playing
## lives in [SokobanState] instead; everything here is fixed for the level's
## lifetime.
##
## Grid convention: [code]Vector2i(x, y)[/code], origin at the top-left,
## [code]+x[/code] right and [code]+y[/code] down — matching Godot's 2D space.
##
## See [code]docs/game-design.md[/code] §5 for the format and its validation rules.
class_name LevelData
extends RefCounted

const CH_WALL := "#"
const CH_GOAL := "."
const CH_BOX := "$"
const CH_BOX_ON_GOAL := "*"
const CH_PLAYER := "@"
const CH_PLAYER_ON_GOAL := "+"
const CH_COMMENT := ";"

## Characters treated as plain floor. Space is the standard; `-` and `_` appear
## in level sets from the wild, where trailing spaces get stripped by editors.
const FLOOR_CHARS := [" ", "-", "_"]

const TITLE_TAG := "title:"

var title := "Untitled"
var source_path := "<memory>"
var width := 0
var height := 0
var start_player := Vector2i.ZERO
var goals: Array[Vector2i] = []
var start_boxes: Array[Vector2i] = []

## Human-readable reasons the level was rejected. Empty means the level is
## structurally sound — note that this says nothing about whether it is
## *solvable*, which is deliberately not checked (see the design doc).
var errors := PackedStringArray()

var _walls := PackedByteArray()
var _goal_set := {}
var _has_player := false


## Parses XSB text into a level. Never returns null: on failure the returned
## instance has a non-empty [member errors] and [method is_valid] returns false.
static func parse(text: String, source := "<memory>") -> LevelData:
	var level := LevelData.new()
	level.source_path = source

	var rows := PackedStringArray()
	var board_started := false

	for raw_line in text.split("\n"):
		var line := (raw_line as String).rstrip("\r\n\t ")
		var stripped := line.strip_edges()

		if stripped.begins_with(CH_COMMENT):
			var body := stripped.substr(1).strip_edges()
			if body.to_lower().begins_with(TITLE_TAG):
				level.title = body.substr(TITLE_TAG.length()).strip_edges()
			continue

		if stripped.is_empty():
			# Blank lines lead in to the board; the first one after it ends the
			# board, which is how XSB files pack several levels into one file.
			if board_started:
				break
			continue

		board_started = true
		rows.append(line)

	if rows.is_empty():
		level.errors.append("no board rows found")
		return level

	level._build_grid(rows)
	level._validate()
	return level


## Reads and parses a level file. A missing or unreadable file yields an invalid
## level rather than an engine error, so a bad path fails the tests loudly but
## does not crash a running build.
static func load_from_file(path: String) -> LevelData:
	if not FileAccess.file_exists(path):
		var missing := LevelData.new()
		missing.source_path = path
		missing.errors.append("file not found")
		return missing

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var unreadable := LevelData.new()
		unreadable.source_path = path
		unreadable.errors.append(
			"could not open file (error %d)" % FileAccess.get_open_error()
		)
		return unreadable

	var text := file.get_as_text()
	file.close()

	var level := LevelData.parse(text, path)
	if level.title == "Untitled":
		level.title = path.get_file().get_basename()
	return level


func is_valid() -> bool:
	return errors.is_empty()


## All rejection reasons on one line, prefixed with the source path — the form
## used in test failures and in the editor's error output.
func error_text() -> String:
	if errors.is_empty():
		return ""
	return "%s: %s" % [source_path, ", ".join(errors)]


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


## Out-of-bounds cells count as walls, so movement code never needs a separate
## bounds check before asking whether a step is legal.
func is_wall(cell: Vector2i) -> bool:
	if not is_inside(cell):
		return true
	return _walls[cell.y * width + cell.x] == 1


func is_goal(cell: Vector2i) -> bool:
	return _goal_set.has(cell)


func goal_count() -> int:
	return goals.size()


func box_count() -> int:
	return start_boxes.size()


## Renders the level's starting position back to XSB. Round-tripping through
## this is how the parser tests assert on a whole board at once instead of
## poking at individual cells.
func to_ascii() -> String:
	var box_set := {}
	for box in start_boxes:
		box_set[box] = true

	var lines := PackedStringArray()
	for y in height:
		var line := ""
		for x in width:
			var cell := Vector2i(x, y)
			if is_wall(cell):
				line += CH_WALL
			elif cell == start_player:
				line += CH_PLAYER_ON_GOAL if is_goal(cell) else CH_PLAYER
			elif box_set.has(cell):
				line += CH_BOX_ON_GOAL if is_goal(cell) else CH_BOX
			elif is_goal(cell):
				line += CH_GOAL
			else:
				line += " "
		lines.append(line)
	return "\n".join(lines)


func _build_grid(rows: PackedStringArray) -> void:
	height = rows.size()
	for row in rows:
		width = maxi(width, (row as String).length())

	_walls.resize(width * height)
	_walls.fill(0)

	var players_found := 0

	for y in height:
		var row: String = rows[y]
		for x in width:
			# Rows shorter than the widest one are padded with floor. That padding
			# sits outside the level's wall ring, so the enclosure check below is
			# what stops it from ever mattering.
			var ch := row.substr(x, 1) if x < row.length() else " "
			var cell := Vector2i(x, y)

			match ch:
				CH_WALL:
					_walls[y * width + x] = 1
				CH_GOAL:
					_add_goal(cell)
				CH_BOX:
					start_boxes.append(cell)
				CH_BOX_ON_GOAL:
					start_boxes.append(cell)
					_add_goal(cell)
				CH_PLAYER:
					players_found += 1
					start_player = cell
				CH_PLAYER_ON_GOAL:
					players_found += 1
					start_player = cell
					_add_goal(cell)
				_:
					if not FLOOR_CHARS.has(ch):
						errors.append(
							"unexpected character '%s' at (%d, %d)" % [ch, x, y]
						)

	_has_player = players_found == 1
	if players_found == 0:
		errors.append("no player ('@' or '+')")
	elif players_found > 1:
		errors.append("%d players, expected exactly 1" % players_found)


func _add_goal(cell: Vector2i) -> void:
	if _goal_set.has(cell):
		return
	_goal_set[cell] = true
	goals.append(cell)


func _validate() -> void:
	if goals.is_empty():
		errors.append("no goals ('.', '*' or '+')")

	if start_boxes.size() != goals.size():
		errors.append(
			"%d crates but %d goals — they must match"
			% [start_boxes.size(), goals.size()]
		)

	# Everything below reasons about the region the player can walk in, which is
	# meaningless without a player, so bail out if the board has no valid one.
	if not _has_player:
		return

	var reachable := _reachable_from(start_player)

	for cell: Vector2i in reachable:
		if cell.x == 0 or cell.y == 0 or cell.x == width - 1 or cell.y == height - 1:
			errors.append(
				"board is not enclosed — floor reaches the edge at (%d, %d)"
				% [cell.x, cell.y]
			)
			break

	for box in start_boxes:
		if not reachable.has(box):
			errors.append("crate at (%d, %d) is walled off from the player" % [box.x, box.y])
	for goal in goals:
		if not reachable.has(goal):
			errors.append("goal at (%d, %d) is walled off from the player" % [goal.x, goal.y])


## Flood fill over non-wall cells. Returns the reached cells as a set
## ([code]Dictionary[/code] keyed by [code]Vector2i[/code]).
##
## Crates are ignored on purpose: the question this answers is which cells are
## *structurally* part of the level, and crates move.
func _reachable_from(origin: Vector2i) -> Dictionary:
	var seen := {}
	if is_wall(origin):
		return seen

	var queue: Array[Vector2i] = [origin]
	seen[origin] = true

	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + step
			if seen.has(next) or is_wall(next):
				continue
			seen[next] = true
			queue.append(next)

	return seen
