## Progress and personal bests: the save file, the records, and the unlock chain.
##
## [code]save_manager.gd[/code] shipped in v0.1 and went untested until v0.3,
## which made it the least-trustworthy code in the project — and the code every
## menu in v0.3 is built on.
##
## Nothing here touches the [code]SaveManager[/code] autoload. Autoloads *are*
## alive during a headless [code]--script[/code] run, so calling the singleton
## would rewrite the developer's own progress and pass while doing it. Each test
## builds its own instance and points it at [constant TEST_SAVE_PATH] instead;
## see tech-design §9.
extends TestCase

const SaveManagerScript := preload("res://scripts/autoload/save_manager.gd")

## Beside the real save, never on top of it. Removed after every test.
const TEST_SAVE_PATH := "user://test_save_manager.cfg"

var _managers: Array[Node] = []


## Frees every instance the test built and removes the scratch file, so the next
## test genuinely starts from "no save on disk" rather than from whatever the
## last one left behind.
func teardown() -> void:
	for manager in _managers:
		manager.free()
	_managers.clear()
	_delete_save()


func test_a_fresh_install_has_no_progress() -> void:
	var manager := _fresh_manager()
	var first := _id(0)

	assert_false(manager.is_cleared(first), "nothing is cleared on a fresh install")
	assert_eq(manager.best_moves(first), SaveManagerScript.NO_RECORD, "no move record yet")
	assert_eq(manager.best_pushes(first), SaveManagerScript.NO_RECORD, "no push record yet")
	assert_eq(manager.resume_index(), 0, "Play starts at the first level")


func test_loading_a_missing_save_reports_nothing_loaded() -> void:
	var manager := _fresh_manager()
	assert_false(manager.load_progress(), "a missing save file reports as not loaded")


func test_a_first_clear_is_reported_as_a_first_clear() -> void:
	var manager := _fresh_manager()
	var first := _id(0)

	var outcome := manager.record_clear(first, 12, 3)

	assert_true(outcome["first_clear"], "the first clear of a level says so")
	assert_false(outcome["beat_moves"], "a first clear does not also read as beating a record")
	assert_false(outcome["beat_pushes"], "a first clear does not also read as beating a record")
	assert_true(manager.is_cleared(first), "the level is cleared afterwards")
	assert_eq(manager.best_moves(first), 12, "the first run sets the move record")
	assert_eq(manager.best_pushes(first), 3, "the first run sets the push record")


func test_a_worse_run_leaves_both_records_alone() -> void:
	var manager := _fresh_manager()
	var first := _id(0)
	manager.record_clear(first, 12, 3)

	var outcome := manager.record_clear(first, 20, 9)

	assert_false(outcome["first_clear"], "the second clear is not a first clear")
	assert_false(outcome["beat_moves"], "more moves is not a better run")
	assert_false(outcome["beat_pushes"], "more pushes is not a better run")
	assert_eq(manager.best_moves(first), 12, "the move record survives a worse run")
	assert_eq(manager.best_pushes(first), 3, "the push record survives a worse run")


## Fewest moves and fewest pushes are different problems — GDD §4 tracks both
## precisely so that optimising one is not forced to spoil the other.
func test_move_and_push_records_move_independently() -> void:
	var manager := _fresh_manager()
	var first := _id(0)
	manager.record_clear(first, 12, 3)

	var outcome := manager.record_clear(first, 10, 8)

	assert_true(outcome["beat_moves"], "ten moves beats twelve")
	assert_false(outcome["beat_pushes"], "eight pushes does not beat three")
	assert_eq(manager.best_moves(first), 10, "the move record improves")
	assert_eq(manager.best_pushes(first), 3, "the push record is untouched by a move record")


func test_progress_survives_a_relaunch() -> void:
	var manager := _fresh_manager()
	var first := _id(0)
	manager.record_clear(first, 12, 3)

	var reopened := _open_manager()

	assert_true(reopened.is_cleared(first), "a cleared level is still cleared after a relaunch")
	assert_eq(reopened.best_moves(first), 12, "the move record is still there")
	assert_eq(reopened.best_pushes(first), 3, "the push record is still there")


## The save is keyed by level id so that inserting or reordering a level cannot
## reassign someone's progress to a different level. Asserted against the file
## itself, because that promise lives on disk and not in the API.
func test_the_save_file_is_keyed_by_level_id_not_by_index() -> void:
	var manager := _fresh_manager()
	var third := _id(2)
	manager.record_clear(third, 7, 2)

	var config := ConfigFile.new()
	if config.load(TEST_SAVE_PATH) != OK:
		fail("record_clear did not write %s" % TEST_SAVE_PATH)
		return

	assert_eq(
		config.get_value(SaveManagerScript.SECTION_META, "format_version", 0),
		SaveManagerScript.SAVE_FORMAT_VERSION,
		"the file stamps its format version",
	)

	var keys := config.get_section_keys(SaveManagerScript.SECTION_PROGRESS)
	assert_true(keys.has(third), "progress is keyed by the level id '%s'" % third)
	assert_false(keys.has("2"), "progress is not keyed by the index into LEVEL_PATHS")


func test_a_save_from_another_format_version_is_discarded() -> void:
	_delete_save()
	var config := ConfigFile.new()
	config.set_value(
		SaveManagerScript.SECTION_META,
		"format_version",
		SaveManagerScript.SAVE_FORMAT_VERSION + 1,
	)
	config.set_value(
		SaveManagerScript.SECTION_PROGRESS,
		_id(0),
		{"cleared": true, "best_moves": 1, "best_pushes": 1},
	)
	config.save(TEST_SAVE_PATH)

	var manager := _open_manager()

	assert_false(manager.load_progress(), "a save from another format reports as not loaded")
	assert_false(manager.is_cleared(_id(0)), "its progress is discarded rather than trusted")


## A save with no [code][meta][/code] section at all — a hand-edit, or a file
## from before the format was stamped. The version defaults to 0, which is not
## the current version, so the same discard path catches it.
func test_a_save_with_no_format_stamp_is_discarded() -> void:
	_write_raw_save("[progress]\n%s={\"cleared\": true}\n" % _id(0))

	var manager := _open_manager()

	assert_false(manager.load_progress(), "an unstamped save reports as not loaded")
	assert_false(manager.is_cleared(_id(0)), "and its progress is not trusted")


## A save file that cannot be parsed must degrade to "no progress", not to a
## broken session. Losing records is bad; a game that will not start is worse.
##
## [ConfigFile] prints its own parse error while this runs, so one engine ERROR
## line in an otherwise green gate is this test working, not this test breaking.
func test_an_unparseable_save_starts_fresh_instead_of_failing() -> void:
	# An unclosed section header. Most malformed text parses to an empty config
	# rather than an error — this is one of the few shapes ConfigFile rejects.
	_write_raw_save("[progress\ncleared=true\n")

	var manager := _open_manager()

	assert_false(manager.load_progress(), "a corrupt save reports as not loaded")
	assert_false(manager.is_cleared(_id(0)), "and leaves progress empty")
	assert_eq(manager.resume_index(), 0, "so the player starts over rather than being stuck")


func test_reset_wipes_memory_and_disk() -> void:
	var manager := _fresh_manager()
	var first := _id(0)
	manager.record_clear(first, 12, 3)

	manager.reset_progress()

	assert_false(manager.is_cleared(first), "reset clears progress in memory")
	assert_eq(manager.best_moves(first), SaveManagerScript.NO_RECORD, "and the records with it")
	var reopened := _open_manager()
	assert_false(reopened.is_cleared(first), "reset clears progress on disk too")


func test_progress_changed_names_the_level_that_changed() -> void:
	var manager := _fresh_manager()
	var seen: Array[String] = []
	manager.progress_changed.connect(func(level_id: String) -> void: seen.append(level_id))

	manager.record_clear(_id(0), 12, 3)
	manager.reset_progress()

	assert_eq(seen, [_id(0), ""], "a clear names its level; a reset names nothing in particular")


func test_the_unlock_chain_opens_one_level_at_a_time() -> void:
	var manager := _fresh_manager()

	assert_true(manager.is_unlocked(0), "the first level is always open")
	assert_false(manager.is_unlocked(1), "the second is not, on a fresh save")

	manager.record_clear(_id(0), 12, 3)

	assert_true(manager.is_unlocked(1), "clearing the first level opens the second")
	assert_false(manager.is_unlocked(2), "and opens only the second")


func test_a_level_cleared_out_of_order_stays_open() -> void:
	var manager := _fresh_manager()
	manager.record_clear(_id(2), 7, 2)

	assert_true(manager.is_unlocked(2), "a cleared level stays open with the chain behind it unfinished")
	assert_false(manager.is_unlocked(1), "without opening the level before it")


## [method LevelLibrary.next_index] returns -1 past the end of the set, so a
## router asking "is the next level unlocked?" hands this a negative index as a
## matter of course. It has to answer no.
func test_an_index_outside_the_set_is_locked() -> void:
	var manager := _fresh_manager()

	assert_false(manager.is_unlocked(-1), "-1 is not a level, and next_index() returns it")
	assert_false(manager.is_unlocked(LevelIndex.count()), "there is no level past the last one")
	assert_false(manager.is_unlocked(LevelIndex.count() + 5), "nor well past it")


func test_resume_index_walks_to_the_first_uncleared_level() -> void:
	var manager := _fresh_manager()

	assert_eq(manager.resume_index(), 0, "a fresh save resumes at the first level")

	manager.record_clear(_id(0), 12, 3)

	assert_eq(manager.resume_index(), 1, "clearing the first level resumes at the second")


func test_resume_index_stops_at_the_last_level_once_the_set_is_finished() -> void:
	var manager := _fresh_manager()
	for i in LevelIndex.count():
		manager.record_clear(_id(i), 10, 2)

	assert_eq(
		manager.resume_index(),
		LevelIndex.count() - 1,
		"a finished game resumes at the last level rather than running off the end",
	)


## A manager over an empty disk: the state of a fresh install.
func _fresh_manager() -> SaveManagerScript:
	_delete_save()
	return _open_manager()


## A manager over whatever is already on disk — the shape of a relaunch.
##
## [method Node._ready] never runs, because the instance is deliberately not
## added to a tree, so the load the autoload gets for free has to be explicit.
func _open_manager() -> SaveManagerScript:
	var manager := SaveManagerScript.new()
	_managers.append(manager)
	manager.save_path = TEST_SAVE_PATH
	manager.load_progress()
	return manager


## Puts exact bytes on disk where the manager will look, for the cases that are
## about what a *file* says rather than about what the API did.
func _write_raw_save(text: String) -> void:
	_delete_save()
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		fail("could not write the scratch save at %s" % TEST_SAVE_PATH)
		return
	file.store_string(text)
	file.close()


func _delete_save() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))


func _id(index: int) -> String:
	return LevelIndex.id_for_path(LevelIndex.path_at(index))
