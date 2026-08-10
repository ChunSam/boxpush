## Guards the hand-maintained project files that nothing else would notice were
## broken.
##
## Input actions are stored in an engine-specific serialised form; a bad
## hand-edit there produces a game that runs perfectly and ignores the keyboard.
## The [code]SUITES[/code] manifest is worse still: a test file missing from it
## simply never runs, and the gate reports every remaining test passing and exits
## 0, so the omission reads as green. Asserting on them here turns a silent
## problem into a failed test.
extends TestCase

const RUNNER_PATH := "res://tests/run_tests.gd"
const TESTS_DIR := "res://tests"
const EXPORT_PRESETS := "res://export_presets.cfg"

const REQUIRED_ACTIONS := [
	"move_up",
	"move_down",
	"move_left",
	"move_right",
	"undo_move",
	"restart_level",
	"back",
	"toggle_mute",
]

const REQUIRED_AUTOLOADS := ["LevelLibrary", "SaveManager"]

## Every screen the router can raise. The router preloads all three, so a broken
## one also takes the main scene down with it — but named here as well, so the
## failure says which file rather than just "the game".
const SCREEN_SCENES := [
	"res://scenes/ui/main_menu.tscn",
	"res://scenes/ui/level_select.tscn",
	"res://scenes/game/game_screen.tscn",
]


func test_all_input_actions_exist() -> void:
	for action: String in REQUIRED_ACTIONS:
		assert_true(InputMap.has_action(action), "input action '%s' is defined" % action)


func test_every_action_has_at_least_one_binding() -> void:
	for action: String in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			continue  # already reported above
		var events := InputMap.action_get_events(action)
		assert_true(events.size() > 0, "action '%s' has a key bound" % action)


func test_movement_uses_physical_keycodes() -> void:
	# Physical codes keep WASD in the same physical position on AZERTY/Dvorak.
	for action: String in ["move_up", "move_down", "move_left", "move_right"]:
		if not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key == null:
				continue
			assert_ne(key.physical_keycode, 0, "'%s' binds a physical key" % action)


func test_main_scene_is_set_and_loadable() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")

	assert_ne(main_scene, "", "a main scene is configured")
	if main_scene.is_empty():
		return

	_assert_scene_instantiates(main_scene, "main scene")


func test_every_screen_scene_instantiates() -> void:
	for path: String in SCREEN_SCENES:
		_assert_scene_instantiates(path, "screen")


## Asserts a scene can actually run, not merely that the file parses.
##
## [method load] is not enough on its own: a `.tscn` whose script fails to
## compile still loads cleanly as a resource, so a broken main scene passed this
## test while the engine logged a parse error beside it. Instantiating is what
## separates the two — the script either attaches or comes back null.
##
## This is the cheap half of what a hand-written `.tscn` gets wrong. It cannot
## see a node *path* that no longer matches an [code]@onready[/code], because
## those resolve in [code]_ready[/code] and [method PackedScene.instantiate] does
## not run it. That half stays a hand-check — tech-design §11.
func _assert_scene_instantiates(path: String, label: String) -> void:
	if not ResourceLoader.exists(path):
		fail("%s '%s' does not exist" % [label, path])
		return

	var packed := load(path) as PackedScene
	if packed == null:
		fail("%s '%s' is not a PackedScene" % [label, path])
		return

	var root := packed.instantiate()
	if root == null:
		fail("%s '%s' does not instantiate" % [label, path])
		return

	assert_ne(root.get_script(), null, "%s '%s' kept its script" % [label, path])
	root.free()


func test_autoloads_are_registered() -> void:
	for name: String in REQUIRED_AUTOLOADS:
		assert_true(
			ProjectSettings.has_setting("autoload/" + name), "autoload '%s' is registered" % name
		)


func test_project_identity() -> void:
	assert_eq(
		ProjectSettings.get_setting("application/config/name", ""),
		"Boxpush",
		"project name",
	)


## The single most likely way to ship a broken build, turned into a failing test.
##
## `.xsb` files are not imported resources — they are copied verbatim, and only
## if the export preset's non-resource filter names them. A preset without
## `*.xsb` produces a build that launches, renders and responds perfectly, and
## has no levels in it.
##
## Until v0.5 this requirement lived in a document and `export_presets.cfg` was
## git-ignored, so every machine had to re-enter it from memory. A document
## cannot fail; this can.
func test_the_export_preset_ships_the_levels() -> void:
	var config := ConfigFile.new()
	if config.load(EXPORT_PRESETS) != OK:
		fail("no %s — the project cannot be exported without one" % EXPORT_PRESETS)
		return

	var presets := 0
	for section: String in config.get_sections():
		# "preset.0" is the preset; "preset.0.options" is its platform settings.
		if not section.begins_with("preset.") or section.contains(".options"):
			continue

		presets += 1
		var name: String = config.get_value(section, "name", section)
		assert_contains(
			str(config.get_value(section, "include_filter", "")),
			"*.xsb",
			"preset '%s' includes the levels in the build" % name,
		)
		assert_ne(
			str(config.get_value(section, "export_path", "")),
			"",
			"preset '%s' says where the build goes" % name,
		)

		# The default filter is "all resources", which means the test harness and
		# the developer tools are resources too. The first build made from this
		# preset shipped every suite in tests/ and every screenshot in shots/.
		var excluded := str(config.get_value(section, "exclude_filter", ""))
		for unwanted: String in ["tests/*", "tools/*", "shots/*"]:
			assert_contains(
				excluded, unwanted, "preset '%s' keeps %s out of the build" % [name, unwanted]
			)

	assert_true(presets > 0, "%s defines at least one preset" % EXPORT_PRESETS)


## Every test suite on disk must be listed in run_tests.gd's SUITES manifest.
##
## Without this, adding a test file and forgetting the manifest leaves the new
## tests unrun while the gate still exits 0 — the one failure mode the manifest
## cannot report on itself.
func test_every_suite_is_registered() -> void:
	var registered := _registered_suites()
	for path: String in _discovered_suites():
		assert_true(
			registered.has(path),
			"'%s' declares test_* methods but is missing from SUITES in %s" % [path, RUNNER_PATH],
		)


## The paths listed in [code]run_tests.gd[/code]'s SUITES const, read by
## reflection so that this test cannot drift from the manifest it guards.
func _registered_suites() -> Array:
	var runner := load(RUNNER_PATH) as GDScript
	if runner == null:
		fail("could not load %s" % RUNNER_PATH)
		return []
	return runner.get_script_constant_map().get("SUITES", [])


## Every script in [constant TESTS_DIR] that declares at least one
## [code]test_*[/code] method.
##
## Suites are identified by what they declare rather than by filename, so a
## suite is caught whatever it is called. test_case.gd declares only assertions
## and run_tests.gd only [code]_[/code]-prefixed helpers, so both drop out
## without needing to be named here.
##
## Scanning the directory is sound only because the suite runs from the project
## folder; in an exported build [DirAccess] would see nothing. That is the same
## constraint that makes [constant LevelIndex.LEVEL_PATHS] a manifest, and it is
## why the manifest is what ships and this scan is only its guard.
func _discovered_suites() -> PackedStringArray:
	var found := PackedStringArray()

	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		fail("could not open %s" % TESTS_DIR)
		return found

	for file in dir.get_files():
		if not file.ends_with(".gd"):
			continue

		var path := "%s/%s" % [TESTS_DIR, file]
		var script := load(path) as GDScript
		if script == null:
			fail("could not load %s" % path)
			continue

		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if method_name.begins_with("test_"):
				found.append(path)
				break

	found.sort()
	return found
