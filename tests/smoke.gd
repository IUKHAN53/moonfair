extends Node
## Headless smoke test: plays a full Hidden Grove round to a win.
## Run: godot --headless res://tests/smoke.tscn

func _ready() -> void:
	await get_tree().process_frame
	var game: Control = load("res://minigames/hidden_object/hidden_object.tscn").instantiate()
	add_child(game)
	game.set_deferred("size", Vector2(390, 820))
	await get_tree().process_frame

	var items: Array = game.items
	var fail := func(msg: String):
		printerr("SMOKE FAIL: " + msg)
		get_tree().quit(1)
	if items.size() != 12:
		fail.call("expected 12 items, got %d" % items.size())
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

	print("SMOKE PASS: score=%d found=%d/%d" % [game.score, game.found.size(), items.size()])
	get_tree().quit(0)
