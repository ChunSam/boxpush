## Guards the parts of project.godot that nothing else would notice were broken.
##
## Input actions in particular are stored in an engine-specific serialised form;
## a bad hand-edit there produces a game that runs perfectly and ignores the
## keyboard. Asserting on them here turns that into a failed test instead.
extends TestCase

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
