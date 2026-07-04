extends CanvasLayer
## Autoload: Overlays — shared win / lose / pause / reward panels.
## Design source: design/ref/2d_OVERLAYS.html (same panel + button family everywhere).

var _root: Control
var _cb_a: Callable  # primary action
var _cb_b: Callable  # secondary action
var _cb_c: Callable  # tertiary (pause: leave to fair)

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

func is_open() -> bool:
	return _root != null

# ---------- public ----------

func show_win(title: String, score: int, rating: int, star_reward: int,
		on_next: Callable, on_replay: Callable, next_label := "Next round") -> void:
	var v := _shell(Color(T.GOLD, 0.35))
	v.add_child(_center(UI.label(title, 26, T.GOLD, true)))
	var stars_row := HBoxContainer.new()
	stars_row.add_theme_constant_override("separation", 6)
	stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in range(3):
		var lit := i < rating
		var r := 17.0 if i == 1 else 13.0
		stars_row.add_child(UI.Icon.new("star", T.GOLD if lit else Color(T.GOLD, 0.25), r))
	v.add_child(stars_row)
	v.add_child(UI.spacer(6))
	v.add_child(_center(UI.caps_label("Score", T.TEXT_DIM)))
	v.add_child(_center(UI.label(UI.fmt(score), 28, T.TEXT_WARM, true)))
	if star_reward > 0:
		v.add_child(UI.spacer(4))
		v.add_child(_center(_reward_chip("star", T.GOLD, "+%d" % star_reward)))
	v.add_child(UI.spacer(10))
	_cb_a = on_next
	_cb_b = on_replay
	var next_btn := UI.pill_button(next_label, true, 44)
	next_btn.pressed.connect(_do_a)
	v.add_child(next_btn)
	var replay_btn := UI.pill_button("Replay", false, 38, 12)
	replay_btn.pressed.connect(_do_b)
	v.add_child(replay_btn)

func show_lose(title: String, sub: String, on_retry: Callable, on_exit: Callable) -> void:
	var v := _shell(Color(T.LAVENDER, 0.3))
	var lantern := UI.Icon.new("lantern", Color("#6B628F"), 14)
	v.add_child(_center(lantern))
	v.add_child(UI.spacer(4))
	v.add_child(_center(UI.label(title, 20, Color("#E8E3FF"), true)))
	var sub_l := _center(UI.label(sub, 12, T.TEXT_DIM))
	v.add_child(sub_l)
	v.add_child(UI.spacer(10))
	_cb_a = on_retry
	_cb_b = on_exit
	var retry := UI.pill_button("Try again", true, 44)
	retry.pressed.connect(_do_a)
	v.add_child(retry)
	var back := UI.pill_button("Back to fair", false, 38, 12)
	back.pressed.connect(_do_b)
	v.add_child(back)

func show_pause(on_resume: Callable, on_restart: Callable, on_exit: Callable) -> void:
	get_tree().paused = true
	var v := _shell(Color(1, 1, 1, 0.12))
	v.add_child(_center(UI.label("Paused", 22, T.TEXT_WARM, true)))
	v.add_child(UI.spacer(6))
	_cb_a = on_resume
	_cb_b = on_restart
	_cb_c = on_exit
	var resume := UI.pill_button("Resume", true, 46, 15)
	resume.pressed.connect(_do_a_unpause)
	v.add_child(resume)
	var restart := UI.pill_button("Restart", false, 38, 12)
	restart.pressed.connect(_do_b_unpause)
	v.add_child(restart)
	v.add_child(UI.spacer(8))
	v.add_child(_toggle_row("Music", SaveData.music_on, func(on): SaveData.music_on = on; SaveData.save()))
	v.add_child(_toggle_row("Sounds", SaveData.sfx_on, func(on): SaveData.sfx_on = on; SaveData.save()))
	v.add_child(UI.spacer(8))
	var leave := Button.new()
	leave.text = "Leave to fair"
	leave.flat = true
	leave.focus_mode = Control.FOCUS_NONE
	leave.add_theme_font_override("font", T.body())
	leave.add_theme_font_size_override("font_size", 12)
	leave.add_theme_color_override("font_color", Color(T.TEXT_BODY, 0.45))
	leave.pressed.connect(_do_c_unpause)
	v.add_child(leave)

func show_reward(title: String, star_amt: int, spark_amt: int, on_claim: Callable) -> void:
	var v := _shell(Color(T.GOLD, 0.4))
	v.add_child(_center(UI.Icon.new("lantern", T.GOLD, 16)))
	v.add_child(UI.spacer(6))
	v.add_child(_center(UI.label(title, 20, T.TEXT_WARM, true)))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	if star_amt > 0:
		row.add_child(_reward_chip("star", T.GOLD, "+%d" % star_amt))
	if spark_amt > 0:
		row.add_child(_reward_chip("spark", T.TEAL, "+%d" % spark_amt))
	v.add_child(row)
	v.add_child(UI.spacer(10))
	_cb_a = on_claim
	var claim := UI.pill_button("Claim", true, 44)
	claim.pressed.connect(_do_a)
	v.add_child(claim)

func close() -> void:
	if _root:
		_root.queue_free()
		_root = null
	_cb_a = Callable()
	_cb_b = Callable()
	_cb_c = Callable()

# ---------- internals ----------

func _do_a() -> void:
	var cb := _cb_a
	close()
	if cb.is_valid(): cb.call()

func _do_b() -> void:
	var cb := _cb_b
	close()
	if cb.is_valid(): cb.call()

func _do_a_unpause() -> void:
	get_tree().paused = false
	_do_a()

func _do_b_unpause() -> void:
	get_tree().paused = false
	_do_b()

func _do_c_unpause() -> void:
	get_tree().paused = false
	var cb := _cb_c
	close()
	if cb.is_valid(): cb.call()

func _shell(border: Color) -> VBoxContainer:
	close()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var scrim := ColorRect.new()
	scrim.color = Color(0.05, 0.045, 0.1, 0.6)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(scrim)
	var panel := PanelContainer.new()
	var style := UI.sb(T.SURFACE_PANEL, 22, border, 1)
	UI.sb_pad(style, 20, 20)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 24
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(320, 0)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	# panel pop-in
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2(0.9, 0.9)
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.12)
	return v

func _center(n: Control) -> Control:
	var c := CenterContainer.new()
	c.add_child(n)
	return c

func _reward_chip(icon: String, col: Color, txt: String) -> PanelContainer:
	var p := PanelContainer.new()
	var style := UI.sb(Color(col, 0.15), T.RADIUS_PILL, Color(col, 0.4), 1)
	UI.sb_pad(style, 12, 4)
	p.add_theme_stylebox_override("panel", style)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.add_child(UI.Icon.new(icon, col, 6))
	h.add_child(UI.label(txt, 12, col, true))
	p.add_child(h)
	return p

func _toggle_row(txt: String, initial: bool, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := UI.label(txt, 12, Color(T.TEXT_BODY, 0.7))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(Switch.new(initial, on_change))
	return row

class Switch extends Control:
	var on: bool
	var cb: Callable

	func _init(initial: bool, on_change: Callable) -> void:
		on = initial
		cb = on_change
		custom_minimum_size = Vector2(44, 26)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventScreenTouch and e.pressed:
			on = not on
			queue_redraw()
			if cb.is_valid(): cb.call(on)

	func _draw() -> void:
		var track := StyleBoxFlat.new()
		track.bg_color = Color("#3FBFA9") if on else Color(T.TEXT_BODY, 0.18)
		track.set_corner_radius_all(13)
		track.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
		var knob_x := size.x - 13.0 if on else 13.0
		draw_circle(Vector2(knob_x, size.y / 2.0), 10.0,
				T.TEXT_WARM if on else Color(T.TEXT_BODY, 0.6))
