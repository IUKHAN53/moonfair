extends Control
## Hidden Grove — hidden object minigame.
## Design source: design/ref/2b_HIDDEN_GROVE.html
## Level data: data/levels/*.json — items live in 390x820 design-space coordinates.
## Until real scene art lands (level "scene_image"), items render as drawn glyphs.

const LEVEL_PATH := "res://data/levels/grove_01.json"
const TAP_SLOP := 14.0

var level: Dictionary = {}
var items: Array = []
var found: Dictionary = {}
var score := 0
var time_left := 90.0
var running := false

var _scene_view: SceneView
var _timer_lbl: Label
var _timer_style: StyleBoxFlat
var _count_found_lbl: Label
var _count_total_lbl: Label
var _tray_thumbs: HBoxContainer
var _tray_left_lbl: Label

func _ready() -> void:
	_load_level()
	_build()
	running = true

func _load_level() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(LEVEL_PATH))
	assert(typeof(parsed) == TYPE_DICTIONARY, "bad level json: " + LEVEL_PATH)
	level = parsed
	items = level["items"]
	time_left = float(level.get("time_limit", 90))

func _process(delta: float) -> void:
	if not running:
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		running = false
		_on_lose()
	_update_timer()

# ---------- build ----------

func _build() -> void:
	# grove backdrop gradient
	add_child(UI.gradient_bg([Color("#2A5248"), Color("#1D3A33"), Color("#122720")], [0.0, 0.45, 1.0]))

	_scene_view = SceneView.new()
	_scene_view.items_ref = items
	_scene_view.found_ref = found
	_scene_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scene_view.tapped.connect(_on_tap)
	add_child(_scene_view)

	# ---- top HUD ----
	var hud := HBoxContainer.new()
	hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud.offset_left = 16
	hud.offset_right = -16
	hud.offset_top = 16
	hud.add_theme_constant_override("separation", 10)
	add_child(hud)

	# pause button
	var pause := Button.new()
	pause.focus_mode = Control.FOCUS_NONE
	pause.custom_minimum_size = Vector2(44, 44)
	var psb := UI.sb(Color(0.0784, 0.0706, 0.1412, 0.78), T.RADIUS_PILL, Color(1, 1, 1, 0.14), 1)
	pause.add_theme_stylebox_override("normal", psb)
	pause.add_theme_stylebox_override("hover", psb)
	pause.add_theme_stylebox_override("pressed", UI.sb(Color(0.0784, 0.0706, 0.1412, 0.95), T.RADIUS_PILL, Color(1, 1, 1, 0.2), 1))
	var pi := UI.Icon.new("pause", T.TEXT_BODY, 7)
	pi.set_anchors_preset(Control.PRESET_CENTER)
	pause.add_child(pi)
	pause.pressed.connect(_on_pause)
	hud.add_child(pause)

	# timer pill (center)
	var mid := CenterContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(mid)
	var timer_pill := PanelContainer.new()
	_timer_style = UI.sb(Color(0.0784, 0.0706, 0.1412, 0.82), T.RADIUS_PILL,
			Color(T.AMBER, 0.55), 2, Color(T.AMBER, 0.25), 8)
	UI.sb_pad(_timer_style, 20, 8)
	timer_pill.add_theme_stylebox_override("panel", _timer_style)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 8)
	th.add_child(UI.Icon.new("ball", T.AMBER, 5))
	_timer_lbl = UI.label("0:00", T.SIZE_HUD_NUM, T.GOLD, true)
	th.add_child(_timer_lbl)
	timer_pill.add_child(th)
	mid.add_child(timer_pill)

	# found counter
	var count := PanelContainer.new()
	var csb := UI.sb(Color(0.0784, 0.0706, 0.1412, 0.78), T.RADIUS_PILL, Color(1, 1, 1, 0.14), 1)
	UI.sb_pad(csb, 14, 8)
	count.add_theme_stylebox_override("panel", csb)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 0)
	_count_found_lbl = UI.label("0", 16, T.TEAL, true)
	_count_total_lbl = UI.label("/%d" % items.size(), 13, Color(T.TEXT_BODY, 0.5), true)
	ch.add_child(_count_found_lbl)
	ch.add_child(_count_total_lbl)
	count.add_child(ch)
	hud.add_child(count)

	# ---- target tray ----
	var tray := PanelContainer.new()
	var tsb := UI.sb(Color(0.0784, 0.0706, 0.1412, 0.86), T.RADIUS_CARD, Color(1, 1, 1, 0.12), 1)
	UI.sb_pad(tsb, 12, 12)
	tray.add_theme_stylebox_override("panel", tsb)
	tray.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tray.offset_left = 12
	tray.offset_right = -12
	tray.offset_top = -140
	tray.offset_bottom = -14
	add_child(tray)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 8)
	tray.add_child(tv)
	var thead := HBoxContainer.new()
	var tcap := UI.caps_label("Find these", T.LAVENDER)
	tcap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thead.add_child(tcap)
	_tray_left_lbl = UI.label("%d left" % items.size(), 11, Color(T.TEXT_BODY, 0.5))
	thead.add_child(_tray_left_lbl)
	tv.add_child(thead)
	_tray_thumbs = HBoxContainer.new()
	_tray_thumbs.add_theme_constant_override("separation", 8)
	tv.add_child(_tray_thumbs)
	_refresh_tray()
	_update_timer()

# ---------- gameplay ----------

func _on_tap(pos: Vector2) -> void:
	if not running or Overlays.is_open():
		return
	var best_id := ""
	var best_d := INF
	for it in items:
		if found.has(it["id"]):
			continue
		var d := pos.distance_to(Vector2(it["x"], it["y"]))
		if d <= float(it.get("r", 20)) + TAP_SLOP and d < best_d:
			best_d = d
			best_id = it["id"]
	if best_id == "":
		_scene_view.miss_ripple(pos)
		return
	_find_item(best_id)

func _find_item(id: String) -> void:
	var it: Dictionary = _item_by_id(id)
	found[id] = true
	var pts := int(level.get("score_per_item", 150))
	score += pts
	var pos := Vector2(it["x"], it["y"])
	_scene_view.sparkle(pos)
	_found_toast(it["name"], pts, pos)
	_count_found_lbl.text = str(found.size())
	_refresh_tray()
	_scene_view.queue_redraw()
	if found.size() == items.size():
		running = false
		_on_win()

func _item_by_id(id: String) -> Dictionary:
	for it in items:
		if it["id"] == id:
			return it
	return {}

func _on_win() -> void:
	var bonus := int(time_left) * 10
	score += bonus
	var frac := time_left / float(level.get("time_limit", 90))
	var rating := 3 if frac >= 0.5 else (2 if frac >= 0.25 else 1)
	var star_reward := score / 100
	SaveData.record_result("hidden_object", score, rating)
	SaveData.add_currency(star_reward, 0)
	await get_tree().create_timer(0.9).timeout
	Overlays.show_win("Wonderful!", score, rating, star_reward,
			Game.go_hub, Game.restart_current)

func _on_lose() -> void:
	var left := items.size() - found.size()
	Overlays.show_lose("The lanterns dimmed…",
			"So close — %d trinket%s left" % [left, "" if left == 1 else "s"],
			Game.restart_current, Game.go_hub)

func _on_pause() -> void:
	Overlays.show_pause(Callable(), Game.restart_current, Game.go_hub)

# ---------- HUD updates ----------

func _update_timer() -> void:
	var s := int(ceil(time_left))
	_timer_lbl.text = "%d:%02d" % [s / 60, s % 60]
	# urgency: border shifts coral + pulses under 10s
	if time_left < 10.0 and running:
		var pulse := 0.5 + 0.5 * sin(time_left * 8.0)
		_timer_style.border_color = Color(T.CORAL, 0.5 + 0.4 * pulse)
		_timer_lbl.add_theme_color_override("font_color", T.CORAL)

func _refresh_tray() -> void:
	for c in _tray_thumbs.get_children():
		c.queue_free()
	var unfound: Array = []
	for it in items:
		if not found.has(it["id"]):
			unfound.append(it)
	_tray_left_lbl.text = "%d left" % unfound.size()
	var show_count: int = min(5, unfound.size())
	for i in range(show_count):
		_tray_thumbs.add_child(TrayThumb.new(unfound[i]))
	var extra: int = unfound.size() - show_count
	if extra > 0:
		_tray_thumbs.add_child(TrayThumb.new({"more": extra}))

func _found_toast(item_name: String, pts: int, pos: Vector2) -> void:
	var p := PanelContainer.new()
	var style := UI.sb(Color(T.TEAL, 0.92), T.RADIUS_PILL)
	UI.sb_pad(style, 10, 4)
	p.add_theme_stylebox_override("panel", style)
	p.add_child(UI.label("%s! +%d" % [item_name.capitalize(), pts], 12, T.TEXT_ON_TEAL, true))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	add_child(p)
	p.reset_size()
	await get_tree().process_frame
	p.visible = true
	p.position = Vector2(
		clamp(pos.x - p.size.x / 2.0, 8, size.x - p.size.x - 8),
		clamp(pos.y - 52, 76, size.y - 170))
	var tw := p.create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "position:y", p.position.y - 22, 0.8).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 0.0, 0.8).set_delay(0.35)
	tw.chain().tween_callback(p.queue_free)

# ---------- inner classes ----------

class SceneView extends Control:
	## Full-bleed scene. Draws placeholder ambience + unfound item glyphs;
	## with real art, swap ambience for a TextureRect and keep glyphs hidden.
	signal tapped(pos: Vector2)
	var items_ref: Array
	var found_ref: Dictionary
	var t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventScreenTouch and e.pressed:
			tapped.emit(e.position)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# ambient: canopy blobs + teal moon-glow (placeholder for painted scene)
		draw_circle(Vector2(w / 2.0, 200), 160, Color(T.TEAL, 0.10 + 0.02 * sin(t * 0.7)))
		draw_set_transform(Vector2(40, 40), 0, Vector2(1, 1))
		draw_circle(Vector2.ZERO, 120, Color("#16302A"))
		draw_set_transform(Vector2(w - 30, 60), 0, Vector2(1, 1))
		draw_circle(Vector2.ZERO, 140, Color("#183630"))
		draw_set_transform(Vector2(60, h - 160), 0, Vector2(1, 0.5))
		draw_circle(Vector2.ZERO, 110, Color("#0F221D"))
		draw_set_transform(Vector2(w - 70, h - 150), 0, Vector2(1, 0.5))
		draw_circle(Vector2.ZERO, 130, Color("#122822"))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		# ambient lanterns — deliberately dim + edge-placed so they never read as findable items
		var f1 := 0.25 + 0.08 * sin(t * 5.0)
		draw_circle(Vector2(24, 660), 14, Color(T.AMBER, f1))
		UI.draw_glyph(self, "lantern", Color(T.AMBER, 0.45), Vector2(24, 660), 9)
		draw_circle(Vector2(w - 22, 120), 10, Color(T.CORAL, 0.2))
		UI.draw_glyph(self, "lantern", Color(T.CORAL, 0.4), Vector2(w - 22, 120), 7)
		# fireflies
		for i in range(8):
			var fx := fmod(w * 0.13 * i + t * (5.0 + i), w)
			var fy := 140.0 + 180.0 * fposmod(sin(t * 0.35 + i * 2.1), 1.0)
			draw_circle(Vector2(fx, fy), 1.5, Color(T.GOLD, 0.25 + 0.2 * sin(t * 2.0 + i)))
		# hidden items (glyph placeholders; hidden once found)
		for it in items_ref:
			if found_ref.has(it["id"]):
				continue
			UI.draw_glyph(self, it["shape"], Color(it["color"]),
					Vector2(it["x"], it["y"]), float(it.get("r", 14)))

	func sparkle(pos: Vector2) -> void:
		add_child(Sparkle.new(pos))

	func miss_ripple(pos: Vector2) -> void:
		add_child(Ripple.new(pos))

class Sparkle extends Node2D:
	## Find burst: expanding gold ring + orbiting sparks. Auto-frees.
	var age := 0.0
	const LIFE := 0.7
	func _init(pos: Vector2) -> void:
		position = pos
	func _process(delta: float) -> void:
		age += delta
		if age >= LIFE:
			queue_free()
			return
		queue_redraw()
	func _draw() -> void:
		var k := age / LIFE
		var alpha := 1.0 - k
		draw_arc(Vector2.ZERO, 8.0 + 26.0 * k, 0, TAU, 24, Color(T.GOLD, alpha * 0.85), 2.5, true)
		draw_circle(Vector2.ZERO, 10.0 * (1.0 - k), Color("#FFF3D6", alpha * 0.9))
		for i in range(4):
			var a := TAU * i / 4.0 + k * 2.0
			var d := 14.0 + 22.0 * k
			var col: Color = [T.GOLD, T.TEAL, Color("#FFF3D6"), T.LAVENDER][i]
			UI.draw_star(self, Vector2(cos(a), sin(a)) * d, 4.0 * (1.0 - k * 0.5), Color(col, alpha), 4)

class Ripple extends Node2D:
	## Gentle miss feedback. Auto-frees.
	var age := 0.0
	const LIFE := 0.35
	func _init(pos: Vector2) -> void:
		position = pos
	func _process(delta: float) -> void:
		age += delta
		if age >= LIFE:
			queue_free()
			return
		queue_redraw()
	func _draw() -> void:
		var k := age / LIFE
		draw_arc(Vector2.ZERO, 6.0 + 18.0 * k, 0, TAU, 20, Color(1, 1, 1, 0.35 * (1.0 - k)), 2.0, true)

class TrayThumb extends Control:
	## Target-tray tile: glyph + name, or "+N" spillover chip.
	var item: Dictionary
	func _init(it: Dictionary) -> void:
		item = it
		custom_minimum_size = Vector2(52, 62)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var bg := StyleBoxFlat.new()
		bg.bg_color = T.SURFACE_PANEL
		bg.set_corner_radius_all(16)
		bg.border_color = Color(1, 1, 1, 0.1)
		bg.set_border_width_all(1)
		bg.draw(get_canvas_item(), Rect2(Vector2.ZERO, Vector2(size.x, size.x)))
		var c := Vector2(size.x / 2.0, size.x / 2.0 - 4)
		if item.has("more"):
			var f := T.display()
			var txt := "+%d" % int(item["more"])
			var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
			draw_string(f, c + Vector2(-ts.x / 2.0, 5), txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(T.TEXT_BODY, 0.5))
			return
		UI.draw_glyph(self, item["shape"], Color(item["color"]), c, min(11.0, size.x * 0.2))
		var f2 := T.body()
		var name_txt: String = item["name"]
		var ns := f2.get_string_size(name_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 8)
		draw_string(f2, Vector2(size.x / 2.0 - ns.x / 2.0, size.x - 6), name_txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(T.TEXT_BODY, 0.5))
