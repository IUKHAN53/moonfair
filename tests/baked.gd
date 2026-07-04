extends Node
## Baked-mode (jungle) test: taps on non-active items must NEVER collect.
## Run: godot --headless res://tests/baked.tscn

var _save_backup: String = ""

func _ready() -> void:
	if FileAccess.file_exists(SaveData.PATH):
		_save_backup = FileAccess.get_file_as_string(SaveData.PATH)
	SaveData.best = {}
	SaveData.chapter_progress = {}
	await get_tree().process_frame

	Game.chapter = "jungle"
	Game.stage = 1
	var game: Control = load("res://minigames/hidden_object/hidden_object.tscn").instantiate()
	add_child(game)
	game.set_deferred("size", Vector2(390, 820))
	await get_tree().process_frame

	var fail := func(msg: String):
		printerr("BAKED FAIL: " + msg)
		_restore_save()
		get_tree().quit(1)

	if not game.baked:
		fail.call("jungle pack did not load in baked/patch mode")
		return
	if game.items.size() != 6:
		fail.call("expected 6 items in stage 1, got %d" % game.items.size())
		return
	if game.active.size() != 3:
		fail.call("expected 3 active targets, got %d" % game.active.size())
		return

	var sv = game._scene_view

	# 1) tapping every QUEUED (visible but not asked-for) item dead-center: no collect
	for it in game.items:
		if game.active.has(it["id"]):
			continue
		var screen: Vector2 = sv.img_to_screen(Vector2(it["x"], it["y"]))
		game._on_tap(screen)
		if game.found.size() != 0:
			fail.call("queued item '%s' was collected by a direct tap" % it["id"])
			return

	# 2) a tap far from every item's bounds: no collect
	var far := Vector2.ZERO
	var far_margin := 0.0
	for gx in range(60, 720, 60):
		for gy in range(140, 1000, 60):
			var p := Vector2(gx, gy)
			var m_min := INF
			for it in game.items:
				m_min = minf(m_min, game._obj_margin(p, it))
			if m_min > far_margin:
				far_margin = m_min
				far = p
	game._on_tap(sv.img_to_screen(far))
	if game.found.size() != 0:
		fail.call("tap %s px away from everything still collected" % far_margin)
		return

	# 3) distractors: planted this stage, dead-center taps never collect
	if game.distracts.size() == 0:
		fail.call("expected planted distractors in stage 1")
		return
	for d in game.distracts:
		game._on_tap(sv.img_to_screen(Vector2(d["x"], d["y"])))
		if game.found.size() != 0:
			fail.call("distractor '%s' was collected" % d["id"])
			return

	# 3) full clear via active targets only — and after each find, re-poke a
	#    queued item to prove the rule holds mid-game
	while game.found.size() < game.items.size():
		var target: Dictionary = game._item_by_id(game.active[0])
		game._on_tap(sv.img_to_screen(Vector2(target["x"], target["y"])))
		await get_tree().process_frame
		for it in game.items:
			if not game.found.has(it["id"]) and not game.active.has(it["id"]):
				var before: int = game.found.size()
				game._on_tap(sv.img_to_screen(Vector2(it["x"], it["y"])))
				if game.found.size() != before:
					fail.call("queued item '%s' collected mid-game" % it["id"])
					return
				break

	if game.found.size() != game.items.size():
		fail.call("did not clear the stage")
		return
	print("BAKED PASS: %d/%d found, non-active taps always rejected" % [game.found.size(), game.items.size()])
	_restore_save()
	get_tree().quit(0)

func _restore_save() -> void:
	if _save_backup != "":
		var f := FileAccess.open(SaveData.PATH, FileAccess.WRITE)
		if f:
			f.store_string(_save_backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.PATH))
