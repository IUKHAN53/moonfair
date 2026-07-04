extends Control
## Hidden Grove — hidden object minigame: chapters of 12 stages.
## Design source: design/ref/2b_HIDDEN_GROVE.html
##
## Content comes from a *scene pack* (data/scenes/<chapter>/pack.json).
## Two modes:
##
## PATCHES (production): the AI pipeline (tools/generate_scene_pack.py) makes a
## clean base scene plus one feather-edged patch PNG per item at known
## image-pixel coordinates. Unfound items' patches are layered over the base at
## runtime, so a found item visibly disappears. Each stage asks for a random
## subset of the pool; only 3 targets are active at a time (names only) —
## tapping a non-active item counts as a miss.
##
## GLYPH (dev fallback): packs without generated patches scatter drawn glyphs
## at random screen positions so a pack is playable before its art exists.

const TAP_SLOP := 14.0
const ITEM_R := 15.0
# playfield safe area (clear of HUD + tray) in design units
const FIELD := Rect2(26, 100, 338, 540)
const MIN_ITEM_DIST := 52.0

const ACTIVE_TARGETS := 3
const DISTRACTORS := 4  # planted items visible this stage but never asked for

var pack: Dictionary = {}
var chapter_id := "grove"
var stage := 1
var baked := false          # items live at fixed image coords with patch textures
var bg_tex: Texture2D = null
var active: Array = []      # item ids currently asked for (max ACTIVE_TARGETS)
var distracts: Array = []   # planted this stage, tappable-but-wrong (Whiteout-style)
var items: Array = []       # this round's picks: {id,name,shape,color,sprite,x,y,r}
var found: Dictionary = {}
var score := 0
var time_limit := 90.0
var time_left := 90.0
var running := false

var _patches: Dictionary = {}  # item id -> Texture2D
var _scene_view: SceneView
var _timer_lbl: Label
var _timer_style: StyleBoxFlat
var _count_lbl: Label
var _tray_chips: HFlowContainer
var _tray_left_lbl: Label

func _ready() -> void:
	chapter_id = Game.chapter
	stage = Game.stage
	_load_pack()
	_setup_stage()
	_build()
	running = true

# ---------- stage setup ----------

func _load_pack() -> void:
	var path := Game.pack_path(chapter_id)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(typeof(parsed) == TYPE_DICTIONARY, "bad pack json: " + path)
	pack = parsed
	var bg_path: String = pack.get("background", "")
	if bg_path != "" and ResourceLoader.exists(bg_path):
		bg_tex = load(bg_path)
	# baked mode: background art exists and items carry generated patches
	# (planted props) and/or detected native scene objects
	baked = false
	if bg_tex != null:
		for it in pack["items"]:
			var patch_path: String = it.get("patch", "")
			if patch_path != "" and ResourceLoader.exists(patch_path):
				_patches[it["id"]] = load(patch_path)
				baked = true
			elif it.get("kind", "") == "native" and it.has("bx"):
				baked = true

func _setup_stage() -> void:
	# difficulty curve: stage 1 = 6 items, +2 per stage, capped by pool size;
	# once the pool caps, later stages squeeze the timer instead
	var pool: Array = []
	for it in pack["items"]:
		if baked:
			var is_native: bool = it.get("kind", "") == "native"
			if is_native and not it.has("bx"):
				continue
			if not is_native and not _patches.has(it["id"]):
				continue  # pipeline failed to generate/verify — never ask for it
		pool.append(it)
	pool.shuffle()
	var count: int = min(6 + 2 * (stage - 1), pool.size())
	var cap_stage := (pool.size() - 6) / 2 + 1
	var over_cap: int = max(0, stage - cap_stage)
	time_limit = clampf(30.0 + 4.0 * count - 6.0 * over_cap, 35.0, 110.0)
	time_left = time_limit
	items = []
	distracts = []
	if baked:
		# fixed positions inside the art; the stage varies WHICH items you seek
		for i in range(count):
			var it: Dictionary = pool[i].duplicate()
			if not it.has("bw"):
				# planted props: tight hit radius — the item graphic is well
				# inside its edit patch, and a generous radius makes taps on
				# nearby decor "collect" listed items
				it["r"] = int(float(it.get("ps", 280)) * 0.22)
			items.append(it)
		# spawn a few planted items that are NOT on this stage's list — present
		# in the scene, always a miss (natives are already always visible)
		for i in range(count, pool.size()):
			if distracts.size() >= DISTRACTORS:
				break
			if pool[i].get("kind", "") == "native":
				continue
			var d: Dictionary = pool[i].duplicate()
			d["r"] = int(float(d.get("ps", 280)) * 0.22)
			distracts.append(d)
	else:
		var placed: Array[Vector2] = []
		for i in range(count):
			var it: Dictionary = pool[i].duplicate()
			var pos := _pick_position(placed)
			placed.append(pos)
			it["x"] = pos.x
			it["y"] = pos.y
			it["r"] = ITEM_R
			items.append(it)
	# only a few targets are "asked for" at once; the rest queue up
	active = []
	for i in range(mini(ACTIVE_TARGETS, items.size())):
		active.append(items[i]["id"])

func _pick_position(placed: Array[Vector2]) -> Vector2:
	for attempt in range(200):
		var p := Vector2(
			randf_range(FIELD.position.x, FIELD.end.x),
			randf_range(FIELD.position.y, FIELD.end.y))
		var ok := true
		for q in placed:
			if p.distance_to(q) < MIN_ITEM_DIST:
				ok = false
				break
		if ok:
			return p
	# dense fallback: accept closest-fit random point
	return Vector2(
		randf_range(FIELD.position.x, FIELD.end.x),
		randf_range(FIELD.position.y, FIELD.end.y))

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
	# backdrop: real painted scene when the pack has one, gradient placeholder otherwise
	if bg_tex != null:
		var tr := TextureRect.new()
		tr.texture = bg_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
	else:
		var cols: Array = []
		for c in pack.get("bg_gradient", ["#2A5248", "#1D3A33", "#122720"]):
			cols.append(Color(c))
		add_child(UI.gradient_bg(cols, [0.0, 0.45, 1.0]))

	_scene_view = SceneView.new()
	_scene_view.game = self
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

	# quit button — no pausing mid-stage (pausing would freeze the timer while
	# the scene stays visible, letting players scan it for free)
	var quit_btn := UI.circle_button("close", 44, false, 7)
	quit_btn.pressed.connect(_on_quit)
	hud.add_child(quit_btn)

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
	var csb := UI.sb(Color(0.0784, 0.0706, 0.1412, 0.78), 21, Color(1, 1, 1, 0.14), 1)
	UI.sb_pad(csb, 14, 8)
	count.add_theme_stylebox_override("panel", csb)
	_count_lbl = UI.label("0/%d" % items.size(), 15, T.TEAL, true)
	count.add_child(_count_lbl)
	hud.add_child(count)

	# ---- target tray ----
	var tray := PanelContainer.new()
	var tsb := UI.sb(Color(0.0784, 0.0706, 0.1412, 0.86), T.RADIUS_CARD, Color(1, 1, 1, 0.12), 1)
	UI.sb_pad(tsb, 12, 12)
	tray.add_theme_stylebox_override("panel", tsb)
	tray.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tray.offset_left = 12
	tray.offset_right = -12
	tray.offset_top = -104
	tray.offset_bottom = -14
	add_child(tray)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 8)
	tray.add_child(tv)
	var thead := HBoxContainer.new()
	var tcap := UI.caps_label("Stage %d.%d · Find these" % [Game.chapter_number(chapter_id), stage], T.LAVENDER)
	tcap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thead.add_child(tcap)
	_tray_left_lbl = UI.label("%d left" % items.size(), 11, Color(T.TEXT_BODY, 0.5))
	thead.add_child(_tray_left_lbl)
	tv.add_child(thead)
	_tray_chips = HFlowContainer.new()
	_tray_chips.add_theme_constant_override("h_separation", 6)
	_tray_chips.add_theme_constant_override("v_separation", 6)
	tv.add_child(_tray_chips)
	_refresh_tray()
	_update_timer()

# ---------- gameplay ----------

func _on_tap(pos: Vector2) -> void:
	if not running or Overlays.is_open():
		return
	# baked items live in image pixels; convert the tap into that space
	var hit_pos := _scene_view.screen_to_img(pos) if baked else pos
	var slop := TAP_SLOP / _scene_view.img_scale() if baked else TAP_SLOP
	# nearest-object-wins: find the closest unfound object, active or not.
	# Only collect when the closest one is an active target — a tap aimed at a
	# queued item that merely grazes an active hotspot must NOT collect.
	# Ties (tap inside two overlapping bounds) go to the smaller object.
	var best_id := ""
	var best_m := INF
	var best_area := INF
	for it in items + distracts:
		if found.has(it["id"]):
			continue
		var m := _obj_margin(hit_pos, it)
		var area := _obj_area(it)
		if m < best_m or (m == best_m and area < best_area):
			best_m = m
			best_area = area
			best_id = it["id"]
	if best_id == "":
		return
	if best_m > slop or not active.has(best_id):
		_scene_view.miss_ripple(pos)
		return
	_find_item(best_id)

func _obj_margin(hit: Vector2, it: Dictionary) -> float:
	## Distance from the tap to the item's bounds (0 = inside).
	if it.has("bw"):
		var rx := clampf(hit.x, float(it["bx"]), float(it["bx"]) + float(it["bw"]))
		var ry := clampf(hit.y, float(it["by"]), float(it["by"]) + float(it["bh"]))
		return hit.distance_to(Vector2(rx, ry))
	return maxf(0.0, hit.distance_to(Vector2(it["x"], it["y"])) - float(it["r"]))

func _obj_area(it: Dictionary) -> float:
	if it.has("bw"):
		return float(it["bw"]) * float(it["bh"])
	return PI * float(it["r"]) * float(it["r"])

func _find_item(id: String) -> void:
	var it: Dictionary = _item_by_id(id)
	found[id] = true
	active.erase(id)
	# next queued target takes the freed slot
	for cand in items:
		if not found.has(cand["id"]) and not active.has(cand["id"]):
			active.append(cand["id"])
			break
	var pts := 150
	score += pts
	var pos := Vector2(it["x"], it["y"])
	if baked:
		pos = _scene_view.img_to_screen(pos)
	_scene_view.sparkle(pos)
	_found_toast(it["name"], pts, pos)
	_count_lbl.text = "%d/%d" % [found.size(), items.size()]
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
	var frac := time_left / time_limit
	var rating := 3 if frac >= 0.5 else (2 if frac >= 0.25 else 1)
	var star_reward := score / 100
	SaveData.record_result("hidden_object", score, rating)
	SaveData.record_stage_clear(chapter_id, stage)
	SaveData.add_currency(star_reward, 0)
	var chapter_done := stage >= Game.STAGES_PER_CHAPTER
	var num := Game.chapter_number(chapter_id)
	var title := "Chapter %d clear!" % num if chapter_done else "Stage %d.%d clear!" % [num, stage]
	await get_tree().create_timer(0.9).timeout
	Overlays.show_win(title, score, rating, star_reward,
			Game.next_stage, Game.restart_current,
			"Back to chapters" if chapter_done else "Next stage")

func _on_lose() -> void:
	var left := items.size() - found.size()
	Overlays.show_lose("The lanterns dimmed…",
			"So close — %d trinket%s left" % [left, "" if left == 1 else "s"],
			Game.restart_current, Game.to_chapter_select)

func _on_quit() -> void:
	# timer keeps running behind the confirm — leaving is free, stalling isn't
	Overlays.show_confirm("Leave the stage?", "The timer keeps running!",
			"Keep playing", "Leave", Game.to_chapter_select)

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
	# names only, 3 active targets at a time — the Whiteout way
	for c in _tray_chips.get_children():
		c.queue_free()
	var unfound := items.size() - found.size()
	_tray_left_lbl.text = "%d left" % unfound
	for id in active:
		_tray_chips.add_child(_name_chip(_item_by_id(id)["name"]))

func _name_chip(txt: String) -> PanelContainer:
	var p := PanelContainer.new()
	var style := UI.sb(T.SURFACE_PANEL, T.RADIUS_PILL, Color(T.LAVENDER, 0.4), 1)
	UI.sb_pad(style, 14, 7)
	p.add_theme_stylebox_override("panel", style)
	p.add_child(UI.label(txt, 13, T.TEXT_BODY, true))
	return p

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
	## Full-bleed scene layer. Draws the items (sprites or glyph placeholders)
	## plus placeholder ambience when no painted background exists.
	signal tapped(pos: Vector2)
	var game: Control
	var t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventScreenTouch and e.pressed:
			tapped.emit(e.position)

	# ---- image <-> screen mapping (STRETCH_KEEP_ASPECT_COVERED math) ----

	func img_scale() -> float:
		if game.bg_tex == null:
			return 1.0
		return maxf(size.x / game.bg_tex.get_width(), size.y / game.bg_tex.get_height())

	func _img_offset() -> Vector2:
		var s := img_scale()
		return Vector2(game.bg_tex.get_width() * s - size.x,
				game.bg_tex.get_height() * s - size.y) / 2.0

	func img_to_screen(p: Vector2) -> Vector2:
		return p * img_scale() - _img_offset()

	func screen_to_img(p: Vector2) -> Vector2:
		return (p + _img_offset()) / img_scale()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if game.bg_tex == null:
			_draw_ambience(w, h)
		if game.baked:
			# layer unfound targets' + distractors' patches over the base —
			# found items vanish, distractors stay all stage
			var s := img_scale()
			var off := _img_offset()
			for it in game.items + game.distracts:
				if game.found.has(it["id"]):
					continue
				var tex: Texture2D = game._patches.get(it["id"])
				if tex:
					var dst := Rect2(
							Vector2(it["px"], it["py"]) * s - off,
							Vector2(it["ps"], it["ps"]) * s)
					draw_texture_rect(tex, dst, false)
			# hotspot tuning overlay: godot ... -- --show-hotspots
			if OS.get_cmdline_user_args().has("--show-hotspots"):
				for it in game.items + game.distracts:
					if game.found.has(it["id"]):
						continue
					var ring := Color(1, 1, 1, 0.4)  # distractor
					if game.active.has(it["id"]):
						ring = Color(T.TEAL, 0.9)
					elif game._item_by_id(it["id"]) != {}:
						ring = Color(T.CORAL, 0.6)
					if it.has("bw"):
						draw_rect(Rect2(img_to_screen(Vector2(it["bx"], it["by"])),
								Vector2(it["bw"], it["bh"]) * s), ring, false, 2.0)
					else:
						draw_arc(img_to_screen(Vector2(it["x"], it["y"])),
								float(it["r"]) * s, 0, TAU, 24, ring, 2.0, true)
			return
		# glyph fallback: draw placeholder items
		for it in game.items:
			if game.found.has(it["id"]):
				continue
			UI.draw_glyph(self, it["shape"], Color(it["color"]),
					Vector2(it["x"], it["y"]), float(it["r"]))

	func _draw_ambience(w: float, h: float) -> void:
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

