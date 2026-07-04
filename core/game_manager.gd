extends Node
## Autoload: Game — hub <-> minigame routing + hidden-object chapter/stage state.
##
## Hidden Grove structure: chapters (one scene pack / background each), 12 stages
## per chapter. Stage N reuses the chapter's background with a growing item count,
## so 3 generated images = 36 levels.

const SCENES := {
	"hub": "res://hub/hub.tscn",
	"chapter_select": "res://minigames/hidden_object/chapter_select.tscn",
	"hidden_object": "res://minigames/hidden_object/hidden_object.tscn",
}
const CHAPTERS_INDEX := "res://data/scenes/chapters.json"
const STAGES_PER_CHAPTER := 12

var chapter := "jungle"
var stage := 1
var _chapters: Array = []

func chapters() -> Array:
	if _chapters.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CHAPTERS_INDEX))
		if typeof(parsed) == TYPE_ARRAY:
			_chapters = parsed
	return _chapters

func pack_path(chapter_id: String) -> String:
	return "res://data/scenes/%s/pack.json" % chapter_id

func chapter_number(chapter_id: String) -> int:
	return chapters().find(chapter_id) + 1

func is_chapter_unlocked(chapter_id: String) -> bool:
	var idx := chapters().find(chapter_id)
	if idx <= 0:
		return idx == 0
	return SaveData.stages_cleared(chapters()[idx - 1]) >= STAGES_PER_CHAPTER

func go_hub() -> void:
	_change("hub")

func start(game_id: String) -> void:
	if game_id == "hidden_object":
		_change("chapter_select")
	elif SCENES.has(game_id):
		_change(game_id)

func to_chapter_select() -> void:
	_change("chapter_select")

func play(chapter_id: String, stage_num: int) -> void:
	chapter = chapter_id
	stage = clampi(stage_num, 1, STAGES_PER_CHAPTER)
	_change("hidden_object")

func next_stage() -> void:
	if stage >= STAGES_PER_CHAPTER:
		_change("chapter_select")
	else:
		stage += 1
		get_tree().paused = false
		get_tree().reload_current_scene()

func restart_current() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _change(id: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(SCENES[id])
