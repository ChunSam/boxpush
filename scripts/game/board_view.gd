## Draws a board from a [SokobanState]: a [TileMapLayer] for the parts that never
## move, and a [Sprite2D] for each part that does.
##
## The split is the point (tech-design §7). Tiles cannot be tweened and do not
## need to be; the player and the crates are exactly the things that do, so they
## are the things that are not tiles.
##
## Every child is built in code rather than authored in `board_view.tscn`. The
## crate count is a property of the level, the tile set is derived from the atlas
## image, and a scene file would only be a second place for both to be wrong.
##
## This node knows nothing about input, the HUD, or where it sits on screen. The
## owner hands it a rectangle via [method fit_into] and a state via
## [method show_state]; everything else is drawing.
class_name BoardView
extends Node2D

## Logical size of one cell before scaling, and the atlas's cell size. The whole
## board is scaled by an integer factor, so this is the unit every offset below
## is expressed in.
const TILE := 64.0

const ATLAS := preload("res://assets/sprites/tiles.png")

## Column of each tile in the one-row atlas. The first three are the static
## layer; the rest are cut out as [AtlasTexture]s for the sprites.
enum Tile { FLOOR, WALL, GOAL, CRATE, CRATE_HOME, PLAYER }

## One-shot celebration when a crate arrives on a goal. GDD §9: 120 ms.
const POP_DURATION := 0.12
const POP_STRENGTH := 0.22

var state: SokobanState

var _tiles: TileMapLayer
var _player: Sprite2D
var _player_motion: TileMotion

## Crate sprites by the cell they logically occupy. Rekeyed as crates move, so
## the dictionary is always the current truth about which sprite is which crate.
var _boxes := {}
## Per-sprite motion and appearance, keyed by the sprite itself.
var _motions := {}
var _tile_of := {}
var _pops := {}

var _textures := {}


func _ready() -> void:
	for tile: int in Tile.values():
		_textures[tile] = _atlas_texture(tile)

	_tiles = TileMapLayer.new()
	_tiles.tile_set = _build_tile_set()
	add_child(_tiles)

	_player = Sprite2D.new()
	_player.texture = _textures[Tile.PLAYER]
	add_child(_player)
	_player_motion = TileMotion.new(Vector2.ZERO)


## Advances every piece toward where the rules already put it.
##
## Appearance changes wait for arrival: a crate turns "home" and pops when it
## lands on the goal, not while it is still sliding onto it.
func _process(delta: float) -> void:
	if state == null:
		return

	_player_motion.advance(delta)
	_player.position = _player_motion.position()

	for cell: Vector2i in _boxes:
		var sprite: Sprite2D = _boxes[cell]
		var motion: TileMotion = _motions[sprite]
		motion.advance(delta)
		sprite.position = motion.position()

		if not motion.is_moving():
			_settle(sprite, cell)

		_advance_pop(sprite, delta)


## Points the view at a state and rebuilds from it. Passing null blanks the
## board, which is what happens before a level is loaded.
func show_state(new_state: SokobanState) -> void:
	state = new_state
	_rebuild()


## Re-reads the state after a move, a restart or an undo. The state object is
## mutated in place, so there is nothing to hand over again.
##
## Exactly one crate can change cells per move, and undo moves exactly one back,
## so a one-in-one-out difference is a crate that travelled and gets to slide.
## Anything else is a restart or a fresh level, and snaps.
func refresh() -> void:
	if state == null:
		return

	_player_motion.retarget(_centre_of(state.player))

	var gone: Array[Vector2i] = []
	for cell: Vector2i in _boxes:
		if not state.boxes.has(cell):
			gone.append(cell)

	var arrived: Array[Vector2i] = []
	for cell: Vector2i in state.boxes:
		if not _boxes.has(cell):
			arrived.append(cell)

	if gone.is_empty() and arrived.is_empty():
		return

	if gone.size() != 1 or arrived.size() != 1:
		_rebuild_boxes()
		return

	var sprite: Sprite2D = _boxes[gone[0]]
	_boxes.erase(gone[0])
	_boxes[arrived[0]] = sprite
	(_motions[sprite] as TileMotion).retarget(_centre_of(arrived[0]))


## Centres the board inside [param area] at the largest integer scale that fits.
##
## Integer-only so that a 64 px tile never lands on half-pixels, which is what
## lets pixel art look right without a camera. Never drops below 1: a board too
## big for the window is better clipped than invisible.
func fit_into(area: Rect2) -> void:
	if state == null or state.level == null:
		return

	var board := Vector2(state.level.width, state.level.height) * TILE
	if board.x <= 0.0 or board.y <= 0.0:
		return

	var factor := maxi(1, floori(minf(area.size.x / board.x, area.size.y / board.y)))
	scale = Vector2(factor, factor)
	position = area.position + (area.size - board * factor) * 0.5


func _rebuild() -> void:
	if _tiles == null:
		return  # _ready has not run yet; show_state will be replayed by the owner

	_tiles.clear()
	if state == null or state.level == null:
		_clear_boxes()
		_player.visible = false
		return

	var level := state.level
	for y in level.height:
		for x in level.width:
			var cell := Vector2i(x, y)
			var tile := Tile.WALL
			if not level.is_wall(cell):
				tile = Tile.GOAL if level.is_goal(cell) else Tile.FLOOR
			_tiles.set_cell(cell, 0, Vector2i(tile, 0))

	_player.visible = true
	_player.position = _centre_of(state.player)
	_player_motion.snap_to(_player.position)

	_rebuild_boxes()


## Throws away every crate sprite and lays them out again where they are now, all
## of them already arrived. Used for a level load and for a restart, where the
## board did not travel from anywhere.
func _rebuild_boxes() -> void:
	_clear_boxes()

	for cell: Vector2i in state.boxes:
		var sprite := Sprite2D.new()
		var tile := Tile.CRATE_HOME if state.level.is_goal(cell) else Tile.CRATE
		sprite.texture = _textures[tile]
		sprite.position = _centre_of(cell)
		add_child(sprite)

		_boxes[cell] = sprite
		_motions[sprite] = TileMotion.new(sprite.position)
		_tile_of[sprite] = tile


func _clear_boxes() -> void:
	for cell: Vector2i in _boxes:
		(_boxes[cell] as Node).queue_free()
	_boxes.clear()
	_motions.clear()
	_tile_of.clear()
	_pops.clear()


## Applies the appearance a crate has earned by arriving. Starting the pop here
## rather than at the moment of the push is what makes it read as *landing*.
func _settle(sprite: Sprite2D, cell: Vector2i) -> void:
	var wanted := Tile.CRATE_HOME if state.level.is_goal(cell) else Tile.CRATE
	if _tile_of[sprite] == wanted:
		return

	_tile_of[sprite] = wanted
	sprite.texture = _textures[wanted]
	if wanted == Tile.CRATE_HOME:
		_pops[sprite] = 0.0


func _advance_pop(sprite: Sprite2D, delta: float) -> void:
	if not _pops.has(sprite):
		return

	var elapsed: float = _pops[sprite] + delta
	if elapsed >= POP_DURATION:
		_pops.erase(sprite)
		sprite.scale = Vector2.ONE
		return

	_pops[sprite] = elapsed
	# One half-sine: out and back, ending exactly where it started.
	sprite.scale = Vector2.ONE * (1.0 + sin(elapsed / POP_DURATION * PI) * POP_STRENGTH)


## Sprites are centred, so a cell's sprite sits half a tile in from its corner.
## Tiles are not, which is why only this conversion exists.
func _centre_of(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE + Vector2(TILE, TILE) * 0.5


## Built from the atlas rather than authored as a `.tres`, so the tile set cannot
## disagree with the image it cuts up. Only the three static tiles are registered:
## the rest are sprites and never appear in the map.
func _build_tile_set() -> TileSet:
	var source := TileSetAtlasSource.new()
	source.texture = ATLAS
	source.texture_region_size = Vector2i(int(TILE), int(TILE))
	for tile: int in [Tile.FLOOR, Tile.WALL, Tile.GOAL]:
		source.create_tile(Vector2i(tile, 0))

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(int(TILE), int(TILE))
	tile_set.add_source(source, 0)
	return tile_set


func _atlas_texture(tile: int) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = ATLAS
	texture.region = Rect2(tile * TILE, 0.0, TILE, TILE)
	return texture
