extends Control
## Moonfair hub — the fairground at dusk.
## Design source: design/ref/2a_HUB_Moonfair_rebrand.html

var _star_chip_label: Label
var _spark_chip_label: Label
var _gift_banner: Control

const GAMES := [
	{"id": "hidden_object", "title": "Hidden Grove", "sub": "Hidden object", "art": "grove", "playable": true},
	{"id": "lantern_break", "title": "Lantern Break", "sub": "Brick breaker · Coming soon", "art": "lanterns", "playable": false, "locked": true},
	{"id": "star_threads", "title": "Star Threads", "sub": "Connect puzzle · Coming soon", "art": "sky", "playable": false, "locked": true},
	{"id": "carousel", "title": "Clockwork Carousel", "sub": "Opens soon", "art": "lock", "playable": false, "locked": true},
]

func _ready() -> void:
	_build()

func _build() -> void:
	# sky gradient: dusk -> night -> night_deep
	add_child(UI.gradient_bg([T.BG_DUSK, T.BG_NIGHT, T.BG_NIGHT_DEEP], [0.0, 0.42, 1.0]))

	# fairground panorama (placeholder art, replaced by hand-painted panorama later)
	var header := HeaderArt.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.custom_minimum_size = Vector2(0, 250)
	header.offset_bottom = 250
	add_child(header)

	# top chips row
	var chips := HBoxContainer.new()
	chips.set_anchors_preset(Control.PRESET_TOP_WIDE)
	chips.offset_left = 16
	chips.offset_right = -16
	chips.offset_top = 18
	chips.add_theme_constant_override("separation", 8)
	add_child(chips)
	var star_chip := UI.chip("star", T.GOLD, UI.fmt(SaveData.stars), T.GOLD)
	_star_chip_label = star_chip.get_child(0).get_child(1) as Label
	chips.add_child(star_chip)
	var spark_chip := UI.chip("spark", T.TEAL, str(SaveData.sparks), T.TEAL)
	_spark_chip_label = spark_chip.get_child(0).get_child(1) as Label
	chips.add_child(spark_chip)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips.add_child(sp)
	var gear := UI.circle_button("gear", 36, false, 7)
	gear.pressed.connect(func(): UI.toast(self, "Settings live in the pause menu for now"))
	chips.add_child(gear)

	# Moonfair lockup
	var lockup := VBoxContainer.new()
	lockup.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lockup.offset_top = 78
	lockup.add_theme_constant_override("separation", 2)
	add_child(lockup)
	var moon := CenterContainer.new()
	moon.add_child(MoonIcon.new())
	lockup.add_child(moon)
	var title := UI.label("Moonfair", T.SIZE_DISPLAY_XL, T.TEXT_WARM, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lockup.add_child(title)
	var tag := UI.caps_label("The fair is open tonight", T.LAVENDER)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lockup.add_child(tag)

	# attraction cards
	var cards := CardsBox.new()
	cards.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cards.offset_left = 16
	cards.offset_right = -16
	cards.offset_top = 226
	cards.add_theme_constant_override("separation", 12)
	add_child(cards)
	for g in GAMES:
		cards.add_child(_card(g))

	# evening gift banner (pinned bottom)
	if SaveData.gift_available():
		_gift_banner = _build_gift_banner()
		add_child(_gift_banner)

func _refresh_chips() -> void:
	_star_chip_label.text = UI.fmt(SaveData.stars)
	_spark_chip_label.text = str(SaveData.sparks)

# ---------- attraction card ----------

func _card(g: Dictionary) -> PanelContainer:
	var locked: bool = g.get("locked", false)
	var p := PanelContainer.new()
	var style: StyleBoxFlat
	if locked:
		style = UI.sb(Color(0.118, 0.106, 0.227, 0.75), T.RADIUS_CARD, Color(T.LAVENDER, 0.3), 1)
	else:
		style = UI.sb(Color(0.149, 0.137, 0.278, 0.92), T.RADIUS_CARD, Color(1, 1, 1, 0.09), 1)
		style.shadow_color = Color(0.04, 0.03, 0.09, 0.45)
		style.shadow_size = 10
	UI.sb_pad(style, 12, 12)
	p.add_theme_stylebox_override("panel", style)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)

	h.add_child(MiniArt.new(g["art"]))

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 2)
	var title_col := T.TEXT_WARM if not locked else Color(T.TEXT_BODY, 0.6)
	v.add_child(UI.label(g["title"], T.SIZE_TITLE_CARD, title_col, true))
	var sub_txt: String = g["sub"]
	if not locked:
		if g["id"] == "hidden_object":
			var total_cleared := 0
			for ch in Game.chapters():
				total_cleared += SaveData.stages_cleared(ch)
			if total_cleared > 0:
				sub_txt += " · %d/%d" % [total_cleared, Game.chapters().size() * Game.STAGES_PER_CHAPTER]
		var b := int(SaveData.best.get(g["id"], 0))
		if b > 0:
			sub_txt += " · Best %s" % UI.fmt(b)
	var sub_col := T.TEXT_DIM if not locked else T.LAVENDER
	v.add_child(UI.label(sub_txt, 12, sub_col))
	if not locked:
		v.add_child(UI.Stars.new(int(SaveData.game_stars.get(g["id"], 0))))
	h.add_child(v)

	if not locked:
		var play := UI.circle_button("play", 54, true, 9, Vector2(2, 0))
		play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		play.pressed.connect(_launch.bind(g))
		h.add_child(play)
	p.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenTouch and e.pressed:
			_launch(g))
	return p

func _launch(g: Dictionary) -> void:
	if g.get("playable", false):
		Game.start(g["id"])
	else:
		UI.toast(self, "%s opens soon ✨" % g["title"])

# ---------- evening gift ----------

func _build_gift_banner() -> PanelContainer:
	var p := PanelContainer.new()
	var style := UI.sb(Color(1.0, 0.63, 0.24, 0.14), T.RADIUS_PILL, Color(T.GOLD, 0.35), 1)
	UI.sb_pad(style, 14, 10)
	p.add_theme_stylebox_override("panel", style)
	p.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	p.offset_left = 16
	p.offset_right = -16
	p.offset_top = -74
	p.offset_bottom = -16
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	h.add_child(UI.Icon.new("lantern", T.GOLD, 12))
	var txt := UI.label("Your evening gift is glowing", T.SIZE_BODY, Color("#FFEBC7"))
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(txt)
	var claim := UI.pill_button("Claim", true, 38, 14)
	claim.pressed.connect(_on_gift)
	h.add_child(claim)
	return p

func _on_gift() -> void:
	Overlays.show_reward("Evening gift", 150, 5, func():
		SaveData.claim_gift(150, 5)
		_refresh_chips()
		if _gift_banner:
			_gift_banner.queue_free()
			_gift_banner = null)

# ---------- drawn placeholder art ----------

class MoonIcon extends Control:
	## Full moon with soft glow and faint craters (no overlay-circle crescent —
	## it reads as a dark blob against the panorama glow).
	func _init() -> void:
		custom_minimum_size = Vector2(38, 38)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size / 2.0
		UI.draw_glow(self, c, 30, Color(T.GOLD, 0.4))
		draw_circle(c, 14, T.GOLD)
		var crater := T.GOLD.darkened(0.13)
		draw_circle(c + Vector2(-4, -3), 3.2, crater)
		draw_circle(c + Vector2(5, 2), 2.4, crater)
		draw_circle(c + Vector2(-1, 6), 1.8, crater)

class HeaderArt extends Control:
	## Placeholder fairground panorama: glow, hills, striped tents, swaying
	## lanterns, fireflies, fading into the night bg at the bottom.
	var t := 0.0
	var _fade: GradientTexture2D
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(T.BG_NIGHT, 0.0), T.BG_NIGHT])
		g.offsets = PackedFloat32Array([0.0, 1.0])
		_fade = GradientTexture2D.new()
		_fade.gradient = g
		_fade.fill_from = Vector2(0, 0)
		_fade.fill_to = Vector2(0, 1)
		_fade.height = 128
	func _process(delta: float) -> void:
		t += delta
		queue_redraw()
	func _draw() -> void:
		var w := size.x
		var h := size.y
		# soft moon glow behind the lockup
		var pulse := 0.85 + 0.15 * sin(t * 0.8)
		UI.draw_glow(self, Vector2(w / 2.0, 70), 150 * pulse, Color(T.GOLD, 0.22))
		# hills
		draw_set_transform(Vector2(90, 250), 0, Vector2(1, 0.5))
		draw_circle(Vector2.ZERO, 130, Color("#232048"))
		draw_set_transform(Vector2(w - 90, 260), 0, Vector2(1, 0.5))
		draw_circle(Vector2.ZERO, 150, Color("#1D1A3E"))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		# tents, pushed to the edges so the lockup breathes
		_tent(Vector2(58, 190), 74, 52, T.CORAL, Color("#E86753"))
		_tent(Vector2(w - 60, 194), 64, 44, T.LAVENDER, Color("#9887E8"))
		# hanging lanterns
		_lantern(Vector2(37, 30), 30, T.AMBER, 4.5, 0.0)
		_lantern(Vector2(119, 48), 48, T.CORAL, 5.5, 1.4)
		_lantern(Vector2(w - 104, 40), 40, Color("#C7BBFF"), 5.0, 2.6)
		_lantern(Vector2(w - 35, 26), 26, T.AMBER, 4.0, 0.8)
		# fireflies
		for i in range(6):
			var fx := fmod(w * 0.15 * i + t * (6.0 + i * 1.5), w)
			var fy := 120.0 + 40.0 * sin(t * 0.6 + i * 1.7)
			var fa := 0.3 + 0.25 * sin(t * 2.0 + i)
			draw_circle(Vector2(fx, fy), 1.6, Color(T.GOLD, fa))
		# blend into the night background
		draw_texture_rect(_fade, Rect2(0, h - 80, w, 80), false)
	func _tent(base: Vector2, tw: float, th: float, main: Color, dark: Color) -> void:
		# ground shadow
		draw_set_transform(base + Vector2(0, 3), 0, Vector2(1, 0.28))
		draw_circle(Vector2.ZERO, tw * 0.62, Color(0, 0, 0, 0.22))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		var apex := base + Vector2(0, -th)
		var half := tw / 2.0
		# canopy with slightly kicked-out feet
		draw_colored_polygon(PackedVector2Array([
			apex, base + Vector2(half, 0), base + Vector2(half * 0.86, 2),
			base + Vector2(-half * 0.86, 2), base + Vector2(-half, 0)]), main)
		# stripes
		draw_colored_polygon(PackedVector2Array([
			apex, base + Vector2(half * 0.32, 0), base + Vector2(-half * 0.32, 0)]), dark)
		draw_colored_polygon(PackedVector2Array([
			apex, base + Vector2(half, 0), base + Vector2(half * 0.68, 0)]), dark)
		draw_colored_polygon(PackedVector2Array([
			apex, base + Vector2(-half, 0), base + Vector2(-half * 0.68, 0)]), dark)
		# door
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-half * 0.14, 0), base + Vector2(half * 0.14, 0),
			base + Vector2(0, -th * 0.28)]), Color(0.08, 0.06, 0.14, 0.6))
		# pole + pennant
		draw_line(apex, apex + Vector2(0, -9), Color(dark, 0.9), 2)
		var flap := sin(t * 3.0 + base.x) * 2.0
		draw_colored_polygon(PackedVector2Array([
			apex + Vector2(0, -9), apex + Vector2(12 + flap, -6.5), apex + Vector2(0, -4)]), T.GOLD)
	func _lantern(anchor: Vector2, string_len: float, col: Color, period: float, phase: float) -> void:
		var ang := sin(t * TAU / period + phase) * 0.09
		draw_set_transform(anchor, ang, Vector2.ONE)
		draw_line(Vector2.ZERO, Vector2(0, string_len), Color(T.GOLD, 0.25), 2)
		UI.draw_glyph(self, "lantern", col, Vector2(0, string_len + 12), 9)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

class CardsBox extends VBoxContainer:
	## Card column with the dashed lantern-path line behind it.
	func _draw() -> void:
		draw_dashed_line(Vector2(40, 4), Vector2(40, size.y - 4), Color(T.GOLD, 0.28), 3, 9)

class MiniArt extends Control:
	## 82x82 rounded thumbnail with drawn placeholder art per attraction.
	var kind: String
	var t := 0.0
	func _init(k: String) -> void:
		kind = k
		custom_minimum_size = Vector2(82, 82)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
	func _process(delta: float) -> void:
		if kind == "lanterns":
			t += delta
			queue_redraw()
	func _draw() -> void:
		var bg := StyleBoxFlat.new()
		bg.set_corner_radius_all(20)
		var c := size / 2.0
		match kind:
			"grove":
				bg.bg_color = Color("#2E574B")
				bg.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
				draw_circle(Vector2(c.x, 26), 24, Color(T.TEAL, 0.25))
				draw_colored_polygon(PackedVector2Array([
					Vector2(c.x, 32), Vector2(c.x + 21, 66), Vector2(c.x - 21, 66)]), T.TEAL)
				draw_colored_polygon(PackedVector2Array([
					Vector2(c.x, 32), Vector2(c.x + 8, 66), Vector2(c.x - 8, 66)]), Color("#3FBFA9"))
			"lanterns":
				bg.bg_color = Color("#3B2F5C")
				bg.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
				UI.draw_glyph(self, "lantern", T.AMBER, Vector2(26, 30), 10)
				UI.draw_glyph(self, "lantern", T.CORAL, Vector2(56, 38), 8)
				var base := StyleBoxFlat.new()
				base.bg_color = T.GOLD
				base.set_corner_radius_all(4)
				base.draw(get_canvas_item(), Rect2(Vector2(c.x - 20, 64), Vector2(40, 7)))
			"sky":
				bg.bg_color = Color("#1F2657")
				bg.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
				UI.draw_star(self, Vector2(20, 20), 4, T.GOLD, 4)
				UI.draw_star(self, Vector2(46, 34), 4, T.LAVENDER, 4)
				UI.draw_star(self, Vector2(64, 16), 4, T.TEAL, 4)
				UI.draw_star(self, Vector2(24, 54), 4, T.GOLD, 4)
				UI.draw_star(self, Vector2(52, 60), 4, T.LAVENDER, 4)
				draw_line(Vector2(20, 20), Vector2(46, 34), Color(T.TEXT_BODY, 0.25), 1)
				draw_line(Vector2(46, 34), Vector2(64, 16), Color(T.TEXT_BODY, 0.25), 1)
			"lock":
				bg.bg_color = Color("#211E44")
				bg.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
				draw_arc(c + Vector2(0, -6), 8, PI, TAU, 16, T.LAVENDER, 3.5, true)
				var body := StyleBoxFlat.new()
				body.bg_color = T.LAVENDER
				body.set_corner_radius_all(5)
				body.draw(get_canvas_item(), Rect2(c + Vector2(-11, -4), Vector2(22, 16)))
