## Where one moving piece is, between the cell it left and the cell it is going
## to. Cosmetic only — the logical position changed the instant the move did.
##
## A plain [RefCounted] with nothing but [Vector2] in it, so the gate can assert
## the motion policy without a scene tree, a viewport or a frame loop. That is
## the whole reason this is not simply a [Tween] inside [BoardView].
##
## **A new move retargets; it never queues.** [method retarget] takes the piece's
## *current* position as the new origin and restarts the clock, so a burst of
## held-key moves always resolves in full and always lands on the cell the player
## actually reached. Queueing would let the board show a position nobody asked
## for — tech-design §7.
class_name TileMotion
extends RefCounted

## Seconds per step. GDD §9 specifies 90 ms, linear.
const DURATION := 0.09

var _from: Vector2
var _to: Vector2
var _elapsed := DURATION


func _init(start: Vector2) -> void:
	snap_to(start)


## Aims at [param to] from wherever the piece is right now. Mid-flight this
## shortens the distance left to travel rather than adding to it.
func retarget(to: Vector2) -> void:
	if to == _to:
		return
	_from = position()
	_to = to
	_elapsed = 0.0


## Puts the piece at [param at] with no travel at all: a level load, or a restart.
func snap_to(at: Vector2) -> void:
	_from = at
	_to = at
	_elapsed = DURATION


func advance(delta: float) -> void:
	_elapsed = minf(_elapsed + delta, DURATION)


func position() -> Vector2:
	if _elapsed >= DURATION:
		return _to
	return _from.lerp(_to, _elapsed / DURATION)


func is_moving() -> bool:
	return _elapsed < DURATION


func target() -> Vector2:
	return _to
