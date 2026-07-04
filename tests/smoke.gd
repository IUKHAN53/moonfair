extends Node
## Headless smoke test: plays a full Hidden Grove round to a win.
## Run: godot --headless res://tests/smoke.tscn

var _save_backup: String = ""

func _ready() -> void:
	# snapshot the player's real save so the test run doesn't pollute it
	if FileAccess.file_exists(SaveData.PATH):
		_save_backup = FileAccess.get_file_as_string(SaveData.PATH)
	# deterministic baseline for assertions (restored from backup at the end)
	SaveData.best = {}
	SaveData.chapter_progress = {}
	await get_tree().process_frame

	# chapter select must build without errors
	var select: Control = load("res://minigames/hidden_object/chapter_select.tscn").instantiate()
	add_child(select)
	await get_tree().process_frame
	select.queue_free()

	Game.chapter = "grove"
	Game.stage = 1
	var game: Control = load("res://minigames/hidden_object/hidden_object.tscn").instantiate()
	add_child(game)
	game.set_deferred("size", Vector2(390, 820))
	await get_tree().process_frame

	var items: Array = game.items
	var fail := func(msg: String):
		printerr("SMOKE FAIL: " + msg)
		_restore_save()
		get_tree().quit(1)
	# stage 1 picks 6 items from the pack pool
	if items.size() != 6:
		fail.call("expected 6 items in stage 1, got %d" % items.size())
		return
	# procedural placement stays inside the safe field, min distance apart
	for i in range(items.size()):
		var a: Dictionary = items[i]
		var p := Vector2(a["x"], a["y"])
		if not Rect2(20, 94, 350, 552).has_point(p):
			fail.call("item %s placed outside safe field: %s" % [a["id"], p])
			return
		for j in range(i + 1, items.size()):
			var q := Vector2(items[j]["x"], items[j]["y"])
			if p.distance_to(q) < 40.0:
				fail.call("items %s/%s too close: %.0f px" % [a["id"], items[j]["id"], p.distance_to(q)])
				return

	# a miss must not register a find
	game._on_tap(Vector2(5, 5))
	if game.found.size() != 0:
		fail.call("miss tap registered a find")
		return

	# find everything
	for it in items:
		game._on_tap(Vector2(it["x"], it["y"]))
		await get_tree().process_frame
	if game.found.size() != items.size():
		fail.call("only %d/%d found" % [game.found.size(), items.size()])
		return

	# win overlay appears after the 0.9s beat
	await get_tree().create_timer(1.4).timeout
	if not Overlays.is_open():
		fail.call("win overlay did not open")
		return
	if game.score <= 0:
		fail.call("score not accumulated")
		return
	if int(SaveData.best.get("hidden_object", 0)) < game.score:
		fail.call("best score not recorded")
		return
	if SaveData.stages_cleared("grove") < 1:
		fail.call("stage clear not recorded")
		return
	# other chapters stay locked until grove is finished
	if Game.is_chapter_unlocked("kitchen"):
		fail.call("kitchen should be locked with grove incomplete")
		return

	print("SMOKE PASS: score=%d found=%d/%d" % [game.score, game.found.size(), items.size()])
	_restore_save()
	get_tree().quit(0)

func _restore_save() -> void:
	if _save_backup != "":
		var f := FileAccess.open(SaveData.PATH, FileAccess.WRITE)
		if f:
			f.store_string(_save_backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.PATH))
