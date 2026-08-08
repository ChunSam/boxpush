## The ordered list of levels that ship with the game.
##
## This is a hand-maintained manifest rather than a directory scan on purpose:
## [DirAccess] over [code]res://[/code] only sees *imported* resources in an
## exported build, and `.xsb` files are not imported — they are copied verbatim
## via the export preset's non-resource filter. A scan would therefore work in
## the editor and silently return nothing in a shipped build.
##
## To add a level: drop the `.xsb` in [code]levels/[/code] and append its path here.
class_name LevelIndex
extends RefCounted

const LEVEL_PATHS: Array[String] = [
	"res://levels/01_first_push.xsb",
	"res://levels/02_go_around.xsb",
	"res://levels/03_push_up.xsb",
	"res://levels/04_obstacle.xsb",
	"res://levels/05_the_corridor.xsb",
]


static func count() -> int:
	return LEVEL_PATHS.size()


## Stable identifier for a level, used as the key in the save file. Derived from
## the filename so that reordering [constant LEVEL_PATHS] never invalidates a
## player's progress.
static func id_for_path(path: String) -> String:
	return path.get_file().get_basename()


static func path_at(index: int) -> String:
	if index < 0 or index >= LEVEL_PATHS.size():
		return ""
	return LEVEL_PATHS[index]


static func index_of_id(level_id: String) -> int:
	for i in LEVEL_PATHS.size():
		if id_for_path(LEVEL_PATHS[i]) == level_id:
			return i
	return -1
