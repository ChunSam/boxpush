## Draws a board straight from a [SokobanState] — one filled rect per cell, plus
## the crates and the player on top.
##
## v0.2 uses [method CanvasItem._draw] rather than a [TileMapLayer] on purpose
## (tech-design §7): no art, no import step, no hand-authored [TileSet], and the
## shape of the code — a redraw driven by board state — is the same one the
## tile-based version in v0.4 will use.
##
## This node knows nothing about input, the HUD, or where it sits on screen. The
## owner hands it a rectangle via [method fit_into] and a state via
## [method show_state]; everything else is drawing.
class_name BoardView
extends Node2D

## Logical size of one cell before scaling. The whole board is scaled by an
## integer factor, so this is the unit every offset below is expressed in.
const TILE := 64.0

const COLOR_FLOOR := Color("b8bcc4")
const COLOR_WALL := Color("2f3742")
const COLOR_GOAL := Color("6b7686")
const COLOR_CRATE := Color("a9713f")
## Crate on a goal: a warmer, brighter body *and* an outline. Two independent
## signals, because GDD §9 forbids colour-only information and this is the single
## most important read on the board.
const COLOR_CRATE_HOME := Color("d29b52")
const COLOR_CRATE_HOME_EDGE := Color("ffd98a")
const COLOR_PLAYER := Color("3d7fd6")

const GOAL_INSET := 18.0
const GOAL_WIDTH := 5.0
const CRATE_INSET := 7.0
const CRATE_EDGE_WIDTH := 5.0
const PLAYER_RADIUS := 20.0

var state: SokobanState


## Points the view at a state and redraws. Passing null blanks the board, which
## is what happens before a level is loaded.
func show_state(new_state: SokobanState) -> void:
	state = new_state
	queue_redraw()


## Redraws from the state already set. Called after every move; the state object
## is mutated in place, so there is nothing to re-hand over.
func refresh() -> void:
	queue_redraw()


## Centres the board inside [param area] at the largest integer scale that fits.
##
## Integer-only so that cells never land on half-pixels — the reason the v0.4
## sprite version will look right without a camera. Never drops below 1: a board
## too big for the window is better clipped than invisible.
func fit_into(area: Rect2) -> void:
	if state == null or state.level == null:
		return

	var board := Vector2(state.level.width, state.level.height) * TILE
	if board.x <= 0.0 or board.y <= 0.0:
		return

	var factor := maxi(1, floori(minf(area.size.x / board.x, area.size.y / board.y)))
	scale = Vector2(factor, factor)
	position = area.position + (area.size - board * factor) * 0.5
	queue_redraw()


func _draw() -> void:
	if state == null or state.level == null:
		return

	var level := state.level

	for y in level.height:
		for x in level.width:
			var cell := Vector2i(x, y)
			if level.is_wall(cell):
				draw_rect(_cell_rect(cell), COLOR_WALL)
				continue

			draw_rect(_cell_rect(cell), COLOR_FLOOR)
			if level.is_goal(cell):
				# Outlined rather than filled, so a crate sitting on it stays the
				# thing that reads loudest.
				draw_rect(_cell_rect(cell).grow(-GOAL_INSET), COLOR_GOAL, false, GOAL_WIDTH)

	for box: Vector2i in state.box_positions():
		var body := _cell_rect(box).grow(-CRATE_INSET)
		if level.is_goal(box):
			draw_rect(body, COLOR_CRATE_HOME)
			draw_rect(body, COLOR_CRATE_HOME_EDGE, false, CRATE_EDGE_WIDTH)
		else:
			draw_rect(body, COLOR_CRATE)

	# A circle among squares: the player is distinguishable by shape as well as
	# by colour.
	draw_circle(_cell_rect(state.player).get_center(), PLAYER_RADIUS, COLOR_PLAYER)


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * TILE, Vector2(TILE, TILE))
