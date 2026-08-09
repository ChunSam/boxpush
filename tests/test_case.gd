## Minimal assertion base class for the headless test suite.
##
## The project deliberately does not depend on GUT or any other test addon: the
## whole harness is this file plus [code]run_tests.gd[/code], it has no version
## to keep in step with the engine, and it runs anywhere Godot runs. If the suite
## ever outgrows it, swapping in GUT is a contained change.
##
## Subclass it, name methods [code]test_*[/code], and call the assertions below.
## A test fails by recording a message, not by aborting, so one method reports
## every problem it finds rather than only the first.
class_name TestCase
extends RefCounted

var failures := PackedStringArray()


## Called by the runner after every [code]test_*[/code] method, pass or fail.
##
## There is no matching setup hook and there does not need to be: the runner
## builds a fresh suite instance per test, so a member initialiser already is
## setup. Teardown has no such equivalent, and a suite that opens files or builds
## [Node]s has to undo both — a leaked node is reported at exit as an ObjectDB
## leak with no hint of which test dropped it, and a leftover file silently
## changes what the next test sees.
func teardown() -> void:
	pass


func assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func assert_false(condition: bool, message: String) -> void:
	assert_true(not condition, message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s — expected %s, got %s" % [message, expected, actual])


func assert_ne(actual: Variant, unexpected: Variant, message: String) -> void:
	if actual == unexpected:
		failures.append("%s — should not be %s" % [message, unexpected])


## Asserts that [param haystack] contains [param needle], case-insensitively.
## Used to check that a parser rejection says *why*, without pinning the tests to
## exact wording.
func assert_contains(haystack: String, needle: String, message: String) -> void:
	if not haystack.to_lower().contains(needle.to_lower()):
		failures.append("%s — %s does not contain '%s'" % [message, haystack, needle])


func fail(message: String) -> void:
	failures.append(message)
