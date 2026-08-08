## Guards the hand-maintained configuration that nothing else would notice was
## broken.
##
## Input actions are stored in an engine-specific serialised form; a bad
## hand-edit there produces a game that runs perfectly and ignores the keyboard.
## The [code]SUITES[/code] manifest is worse still: a test file missing from it
## simply never runs, and the gate reports every remaining test passing and exits
## 0, so the omission reads as green. Asserting on both here turns a silent
## problem into a failed test.
extends TestCase

const RUNNER_PATH := "res://tests/run_tests.gd"
const TESTS_DIR := "res://tests"

const REQUIRED_ACTIONS := [
	"move_up",
	"move_down",
	"move_left",
	"move_right",
	"undo_move",
	"restart_level",
	"back",
]

const REQUIRED_AUTOLOADS := ["LevelLibrary", "SaveManager"]


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
	assert_true(ResourceLoader.exists(main_scene), "main scene '%s' exists" % main_scene)
	assert_ne(load(main_scene), null, "main scene '%s' loads" % main_scene)


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
