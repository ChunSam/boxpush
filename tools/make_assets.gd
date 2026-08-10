## Writes the placeholder art and audio that v0.4 ships.
##
##     .\tools\make_assets.ps1
##
## Generated rather than drawn or downloaded, for three reasons: the palette is
## already specified in GDD §9 and a generator cannot drift from it, nothing here
## needs a paint program or a network, and a change of mind about the placeholder
## look is an edit to a constant rather than a redraw.
##
## Re-run it after editing the palette below, then commit the results — the game
## loads the `.png` and `.wav`, not this script.
extends SceneTree

const ATLAS_PATH := "res://assets/sprites/tiles.png"
const AUDIO_DIR := "res://assets/audio"

## One 64x64 cell per tile, in the order [enum BoardView.Tile] expects. The
## atlas is one row, so a tile's atlas coordinate is (index, 0).
const TILE := 64

## GDD §9: floor light grey, wall dark slate, goal a dim outlined square, crate
## warm brown, crate-on-goal warm brown with a bright outline. Carried over from
## v0.2's `_draw()` colours so the board does not change appearance when the
## renderer underneath it does.
const COLOR_FLOOR := Color("b8bcc4")
const COLOR_WALL := Color("2f3742")
const COLOR_GOAL_MARK := Color("6b7686")
const COLOR_CRATE := Color("a9713f")
const COLOR_CRATE_EDGE := Color("7c4f28")
const COLOR_CRATE_HOME := Color("d29b52")
const COLOR_CRATE_HOME_EDGE := Color("ffd98a")
const COLOR_PLAYER := Color("3d7fd6")
const COLOR_PLAYER_EDGE := Color("9cc4f5")

const SAMPLE_RATE := 22050


func _initialize() -> void:
	_ensure_dir("res://assets")
	_ensure_dir("res://assets/sprites")
	_ensure_dir(AUDIO_DIR)

	_write_atlas()
	_write_cues()

	print("")
	print("Assets written. Run `godot --headless --path . --import` before using them.")
	quit(0)


## The six tiles, side by side in one row.
##
## Floor, wall and goal are the static layer the TileMapLayer draws. Crate,
## crate-on-goal and player are the moving pieces, and they are cut from the same
## image with an AtlasTexture so there is one asset to keep consistent instead of
## four.
func _write_atlas() -> void:
	var image := Image.create(TILE * 6, TILE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	_fill(image, 0, COLOR_FLOOR)

	# Flat, with no top-edge highlight. A per-tile highlight looked like a bevel
	# on one wall and like scanlines on a block of them, and a wall reads as solid
	# perfectly well from its colour alone.
	_fill(image, 1, COLOR_WALL)

	_fill(image, 2, COLOR_FLOOR)
	_outline(image, 2, 18, 5, COLOR_GOAL_MARK)

	_fill(image, 3, Color(0, 0, 0, 0))
	_rounded_body(image, 3, COLOR_CRATE, COLOR_CRATE_EDGE)

	_fill(image, 4, Color(0, 0, 0, 0))
	_rounded_body(image, 4, COLOR_CRATE_HOME, COLOR_CRATE_HOME_EDGE)

	_fill(image, 5, Color(0, 0, 0, 0))
	_disc(image, 5, 20, COLOR_PLAYER, COLOR_PLAYER_EDGE)

	var path := ProjectSettings.globalize_path(ATLAS_PATH)
	var err := image.save_png(path)
	if err != OK:
		push_error("Could not write %s (error %d)" % [ATLAS_PATH, err])
		return
	print("wrote %s (%dx%d)" % [ATLAS_PATH, image.get_width(), image.get_height()])


## The three cues from GDD §9. Short, dry and deliberately plain: they mark an
## event, they are not music, and the game has to stay pleasant with them looping
## at the 90 ms key-repeat rate.
func _write_cues() -> void:
	_write_wav("step", _tone([440.0], 0.045, 0.18))
	_write_wav("push", _tone([220.0, 330.0], 0.075, 0.28))
	_write_wav("clear", _arpeggio([523.25, 659.25, 783.99], 0.11, 0.3))


## Samples in [-1, 1] for a mix of sine partials under a short linear decay, so
## every cue ends at exactly zero and cannot click when it stops.
func _tone(partials: Array, seconds: float, gain: float) -> PackedFloat32Array:
	var count := int(SAMPLE_RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)

	for i in count:
		var t := float(i) / SAMPLE_RATE
		var envelope := 1.0 - float(i) / float(count)
		var value := 0.0
		for frequency: float in partials:
			value += sin(TAU * frequency * t)
		samples[i] = value / partials.size() * envelope * gain

	return samples


func _arpeggio(frequencies: Array, note_seconds: float, gain: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	for frequency: float in frequencies:
		samples.append_array(_tone([frequency], note_seconds, gain))
	return samples


## 16-bit mono PCM. Written by hand rather than through an AudioStream because
## there is no engine-side WAV *writer*, and the header is 44 bytes.
func _write_wav(name: String, samples: PackedFloat32Array) -> void:
	var data := PackedByteArray()
	for sample in samples:
		var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.append(value & 0xFF)
		data.append((value >> 8) & 0xFF)

	var out := PackedByteArray()
	_append_string(out, "RIFF")
	_append_u32(out, 36 + data.size())
	_append_string(out, "WAVE")
	_append_string(out, "fmt ")
	_append_u32(out, 16)  # PCM chunk size
	_append_u16(out, 1)  # format: PCM
	_append_u16(out, 1)  # channels: mono
	_append_u32(out, SAMPLE_RATE)
	_append_u32(out, SAMPLE_RATE * 2)  # byte rate
	_append_u16(out, 2)  # block align
	_append_u16(out, 16)  # bits per sample
	_append_string(out, "data")
	_append_u32(out, data.size())
	out.append_array(data)

	var path := "%s/%s.wav" % [AUDIO_DIR, name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % path)
		return
	file.store_buffer(out)
	file.close()
	print("wrote %s (%d samples)" % [path, samples.size()])


func _fill(image: Image, tile: int, color: Color) -> void:
	_rect(image, tile, Rect2i(0, 0, TILE, TILE), color)


func _rect(image: Image, tile: int, area: Rect2i, color: Color) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			image.set_pixel(tile * TILE + x, y, color)


func _outline(image: Image, tile: int, inset: int, width: int, color: Color) -> void:
	for y in range(inset, TILE - inset):
		for x in range(inset, TILE - inset):
			var on_edge := (
				x < inset + width
				or x >= TILE - inset - width
				or y < inset + width
				or y >= TILE - inset - width
			)
			if on_edge:
				image.set_pixel(tile * TILE + x, y, color)


## A crate: an inset square with a border. Squares among squares, so the player
## stays the only round thing on the board — GDD §9 forbids colour-only reads.
func _rounded_body(image: Image, tile: int, body: Color, edge: Color) -> void:
	var inset := 7
	var border := 5
	for y in range(inset, TILE - inset):
		for x in range(inset, TILE - inset):
			var on_edge := (
				x < inset + border
				or x >= TILE - inset - border
				or y < inset + border
				or y >= TILE - inset - border
			)
			image.set_pixel(tile * TILE + x, y, edge if on_edge else body)


func _disc(image: Image, tile: int, radius: int, body: Color, edge: Color) -> void:
	var centre := Vector2(TILE, TILE) * 0.5
	for y in TILE:
		for x in TILE:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(centre)
			if distance > radius:
				continue
			image.set_pixel(tile * TILE + x, y, edge if distance > radius - 5.0 else body)


func _ensure_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _append_string(buffer: PackedByteArray, text: String) -> void:
	buffer.append_array(text.to_ascii_buffer())


func _append_u16(buffer: PackedByteArray, value: int) -> void:
	buffer.append(value & 0xFF)
	buffer.append((value >> 8) & 0xFF)


func _append_u32(buffer: PackedByteArray, value: int) -> void:
	buffer.append(value & 0xFF)
	buffer.append((value >> 8) & 0xFF)
	buffer.append((value >> 16) & 0xFF)
	buffer.append((value >> 24) & 0xFF)
