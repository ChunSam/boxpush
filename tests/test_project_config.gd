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

const CLAUDE_MD_PATH := "res://CLAUDE.md"
const CLAUDE_MD_MAX_LINES := 200

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


## CLAUDE.md is loaded into every context window, so its length is a cost paid on
## every turn rather than once. The global conventions cap it at
## [constant CLAUDE_MD_MAX_LINES] lines; this is that cap made binding, because a
## budget nothing checks is a wish.
##
## A prose-length check is an odd thing to find in a game's test suite. It lives
## here because the gate is the only thing in this project that runs on every
## change, and a rule enforced nowhere decays.
func test_claude_md_within_budget() -> void:
	if not FileAccess.file_exists(CLAUDE_MD_PATH):
		fail("%s is missing" % CLAUDE_MD_PATH)
		return

	var lines := _line_count(FileAccess.get_file_as_string(CLAUDE_MD_PATH))
	var message := (
		"CLAUDE.md is %d lines, over the %d-line budget. Evict an entry; do not compress one."
		% [lines, CLAUDE_MD_MAX_LINES]
	)
	assert_true(lines <= CLAUDE_MD_MAX_LINES, message)


## Lines counted the way git and every editor count them: newline terminators,
## with the final one closing the last line rather than opening a new one.
##
## To check by hand, use [code]Get-Content CLAUDE.md -Encoding utf8[/code]. The
## flag is not optional: without it PowerShell 5.1 decodes the file as the ANSI
## codepage, and under CP949 a line ending in an em dash loses its newline —
## byte 0x94 is a lead byte and swallows the 0x0A that follows. That undercounts
## this file by two and disagrees with the number reported here.
func _line_count(text: String) -> int:
	var normalised := text.replace("\r\n", "\n")
	if normalised.ends_with("\n"):
		normalised = normalised.substr(0, normalised.length() - 1)
	return normalised.split("\n").size()


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
