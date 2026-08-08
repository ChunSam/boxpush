## Finds a shortest solution for every indexed level and prints the result as a
## ready-to-paste [code]SOLUTIONS[/code] block for tests/test_levels.gd.
##
##     tools\solve.ps1
##
## Run this after editing a `.xsb`, because editing a board almost always
## invalidates its recorded solution. The test suite replays those strings; it
## does not search, so this is the only thing that produces them.
##
## Breadth-first, so the result is shortest in *moves* — not necessarily in
## pushes, which is a different optimisation and not what the fixture claims.
##
## Every transition goes through the real [method SokobanState.try_move]. A
## second copy of the rules written for the search could drift from the shipped
## ones and would then happily emit a "solution" the game rejects.
extends SceneTree

## Must match the order of [constant SokobanState.DIRECTIONS].
const LETTERS := ["u", "d", "l", "r"]


func _initialize() -> void:
	var failed := false

	print("")
	print("const SOLUTIONS := {")

	for path in LevelIndex.LEVEL_PATHS:
		var level := LevelData.load_from_file(path)
		if not level.is_valid():
			printerr("%s does not parse: %s" % [path, level.error_text()])
			failed = true
			continue

		var found := _solve(level)
		var solution: String = found["solution"]

		if solution.is_empty():
			printerr(
				"%s has no solution — searched %d positions" % [path, found["searched"]]
			)
			failed = true
			continue

		print(
			'\t"%s": "%s",  # %d moves, %d pushes'
			% [LevelIndex.id_for_path(path), solution, solution.length(), _count_pushes(solution)]
		)

	print("}")
	print("")

	quit(1 if failed else 0)


## Breadth-first over (player, crates) positions. Returns
## [code]{ solution, searched }[/code]; an empty solution means none exists.
func _solve(level: LevelData) -> Dictionary:
	var probe := SokobanState.new(level)
	if probe.is_solved():
		return {"solution": "", "searched": 0}

	var seen := {_key(probe.player, probe.boxes): true}
	var queue: Array = [[probe.player, probe.boxes.duplicate(), ""]]
	var head := 0

	while head < queue.size():
		var node: Array = queue[head]
		head += 1

		var from_player: Vector2i = node[0]
		var from_boxes: Dictionary = node[1]
		var path: String = node[2]

		for i in SokobanState.DIRECTIONS.size():
			# Rewind the probe onto this node, then let the shipped rules decide.
			probe.player = from_player
			probe.boxes = from_boxes.duplicate()

			var outcome := probe.try_move(SokobanState.DIRECTIONS[i])
			if outcome == SokobanState.MoveResult.BLOCKED:
				continue

			var key := _key(probe.player, probe.boxes)
			if seen.has(key):
				continue
			seen[key] = true

			var letter: String = LETTERS[i]
			if outcome == SokobanState.MoveResult.PUSHED:
				letter = letter.to_upper()
			var next_path := path + letter

			if probe.is_solved():
				return {"solution": next_path, "searched": seen.size()}

			queue.append([probe.player, probe.boxes.duplicate(), next_path])

	return {"solution": "", "searched": seen.size()}


## Identifies a position. Crate cells are sorted so that two orderings of the
## same crates collapse to one entry — without that the search revisits
## positions it has already proved nothing about.
func _key(player: Vector2i, boxes: Dictionary) -> String:
	var cells: Array[Vector2i] = []
	for box: Vector2i in boxes:
		cells.append(box)
	cells.sort()

	var parts := PackedStringArray()
	for cell in cells:
		parts.append("%d.%d" % [cell.x, cell.y])

	return "%d.%d|%s" % [player.x, player.y, "|".join(parts)]


func _count_pushes(solution: String) -> int:
	var pushes := 0
	for i in solution.length():
		if solution[i] == solution[i].to_upper():
			pushes += 1
	return pushes
