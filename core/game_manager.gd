extends Node
## Autoload: Game — hub <-> minigame scene routing.

const SCENES := {
	"hub": "res://hub/hub.tscn",
	"hidden_object": "res://minigames/hidden_object/hidden_object.tscn",
}

func go_hub() -> void:
	_change("hub")

func start(game_id: String) -> void:
	if SCENES.has(game_id):
		_change(game_id)

func restart_current() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _change(id: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(SCENES[id])
