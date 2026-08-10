## Headless test runner. This is the project's CI-equivalent gate.
##
##     godot --headless --path . --script res://tests/run_tests.gd
##
## or, on Windows, [code]tools\test.ps1[/code], which also resolves the engine
## path and forwards the exit code. Exits 0 when every test passes and 1
## otherwise, so it drops straight into a CI job or a pre-commit hook.
##
## It runs as a [SceneTree]-derived MainLoop, which means no window is opened and
## no main scene is instantiated — the tests exercise the pure logic classes
## directly, which is exactly why those classes were kept node-free.
extends SceneTree

const SUITES := [
	"res://tests/test_board_view.gd",
	"res://tests/test_level_data.gd",
	"res://tests/test_levels.gd",
	"res://tests/test_project_config.gd",
	"res://tests/test_save_manager.gd",
	"res://tests/test_sokoban_state.gd",
]


func _initialize() -> void:
	var passed := 0
	var failed := 0

	print("")
	print("Boxpush test run")
	print("================")

	for suite_path: String in SUITES:
		print("")
		print(suite_path.get_file())

		var script: GDScript = load(suite_path)
		if script == null:
			print("  FAIL  could not load suite")
			failed += 1
			continue

		for method_name in _test_methods(script):
			# A fresh instance per test so that one test's state can never leak
			# into the next.
			var suite: TestCase = script.new()
			suite.call(method_name)
			# Unconditional, so a failing test still releases its files and nodes
			# and cannot take the rest of the run down with it.
			suite.teardown()

			if suite.failures.is_empty():
				passed += 1
				print("  ok    %s" % method_name)
			else:
				failed += 1
				print("  FAIL  %s" % method_name)
				for failure in suite.failures:
					print("          %s" % failure)

	print("")
	print("----------------")
	print("%d passed, %d failed" % [passed, failed])
	print("")

	quit(1 if failed > 0 else 0)


## Names of the [code]test_*[/code] methods a suite declares, sorted so the run
## order does not depend on declaration order.
func _test_methods(script: GDScript) -> PackedStringArray:
	var names := PackedStringArray()
	var probe: RefCounted = script.new()

	for method in probe.get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_"):
			names.append(method_name)

	names.sort()
	return names
