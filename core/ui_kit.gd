class_name UI
## Shared UI builders + drawn icons for Moonfair.
## All sizes are in design units (390x820 viewport, see project.godot).

# ---------- styleboxes ----------

static func sb(bg: Color, radius := 12, border_col := Color.TRANSPARENT, border_w := 0,
		glow := Color.TRANSPARENT, glow_size := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border_w > 0:
		s.set_border_width_all(border_w)
		s.border_color = border_col
	if glow_size > 0:
		s.shadow_color = glow
		s.shadow_size = glow_size
	s.anti_aliasing = true
	return s

static func sb_pad(style: StyleBoxFlat, h: int, v: int) -> StyleBoxFlat:
	style.content_margin_left = h
	style.content_margin_right = h
	style.content_margin_top = v
	style.content_margin_bottom = v
	return style

# ---------- basic nodes ----------

static func gradient_bg(cols: Array, offs: Array) -> TextureRect:
	var g := Gradient.new()
	var pc := PackedColorArray()
	for c in cols:
		pc.append(c)
	g.colors = pc
	g.offsets = PackedFloat32Array(offs)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.height = 512
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

static func label(txt: String, size: int, col: Color, display := false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", T.display() if display else T.body())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func caps_label(txt: String, col: Color) -> Label:
	# label/caps: 11 · Nunito · letter-spaced uppercase (spacing approximated)
	return label(txt.to_upper(), T.SIZE_CAPS, col)

static func spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

# ---------- layout helpers ----------

static func center_in(parent: Control, child: Control, nudge := Vector2.ZERO) -> void:
	## True centering with explicit offsets (anchor presets compute from the
	## pre-layout size of 0 and leave children hanging out of their parents).
	var sz := child.custom_minimum_size
	child.anchor_left = 0.5
	child.anchor_top = 0.5
	child.anchor_right = 0.5
	child.anchor_bottom = 0.5
	child.offset_left = -sz.x / 2.0 + nudge.x
	child.offset_top = -sz.y / 2.0 + nudge.y
	child.offset_right = sz.x / 2.0 + nudge.x
	child.offset_bottom = sz.y / 2.0 + nudge.y
	parent.add_child(child)

# ---------- soft radial glow (no banding) ----------

static var _glow_cache: Dictionary = {}

static func glow_tex(col: Color) -> GradientTexture2D:
	var key := col.to_html()
	if not _glow_cache.has(key):
		var g := Gradient.new()
		g.colors = PackedColorArray([col, Color(col, 0.0)])
		g.offsets = PackedFloat32Array([0.0, 1.0])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 128
		t.height = 128
		_glow_cache[key] = t
	return _glow_cache[key]

static func draw_glow(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_texture_rect(glow_tex(col), Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)

# ---------- buttons ----------

static func circle_button(icon_kind: String, d: int, primary: bool, icon_r: float,
		nudge := Vector2.ZERO) -> Button:
	## Round icon button with the icon actually centered.
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(d, d)
	var icon_col: Color
	if primary:
		var n := sb(T.BTN_AMBER, T.RADIUS_PILL, Color.TRANSPARENT, 0,
				Color(1.0, 0.63, 0.24, 0.45), 8)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", n)
		b.add_theme_stylebox_override("pressed", sb(T.BTN_AMBER_PRESSED, T.RADIUS_PILL))
		icon_col = T.TEXT_ON_AMBER
	else:
		var n := sb(Color(0.0784, 0.0706, 0.1412, 0.75), T.RADIUS_PILL, Color(1, 1, 1, 0.14), 1)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", n)
		b.add_theme_stylebox_override("pressed",
				sb(Color(0.0784, 0.0706, 0.1412, 0.95), T.RADIUS_PILL, Color(1, 1, 1, 0.2), 1))
		icon_col = Color(T.TEXT_BODY, 0.85)
	center_in(b, Icon.new(icon_kind, icon_col, icon_r), nudge)
	pressify(b)
	return b

static func pill_button(txt: String, primary := true, h := 44, font_size := 14) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_override("font", T.display())
	b.add_theme_font_size_override("font_size", font_size)
	if primary:
		var n := sb(T.BTN_AMBER, T.RADIUS_PILL, Color.TRANSPARENT, 0,
				Color(1.0, 0.63, 0.24, 0.45), 8)
		var p := sb(T.BTN_AMBER_PRESSED, T.RADIUS_PILL)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", n)
		b.add_theme_stylebox_override("pressed", p)
		b.add_theme_color_override("font_color", T.TEXT_ON_AMBER)
		b.add_theme_color_override("font_pressed_color", T.TEXT_ON_AMBER)
		b.add_theme_color_override("font_hover_color", T.TEXT_ON_AMBER)
	else:
		var n := sb(Color.TRANSPARENT, T.RADIUS_PILL, Color(T.LAVENDER, 0.45), 2)
		var p := sb(Color(T.LAVENDER, 0.12), T.RADIUS_PILL, Color(T.LAVENDER, 0.6), 2)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", n)
		b.add_theme_stylebox_override("pressed", p)
		b.add_theme_color_override("font_color", T.LAVENDER)
		b.add_theme_color_override("font_pressed_color", T.LAVENDER)
		b.add_theme_color_override("font_hover_color", T.LAVENDER)
	pressify(b)
	return b

static func pressify(b: Button) -> void:
	# press state per tokens: scale .96
	b.button_down.connect(func():
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2(0.96, 0.96), 0.05))
	b.button_up.connect(func():
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.08))

# ---------- chips / pills ----------

static func chip(icon_kind: String, icon_col: Color, txt: String, txt_col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var style := sb(Color(0.0784, 0.0706, 0.1412, 0.72), T.RADIUS_PILL,
			Color(1, 1, 1, 0.12), 1)
	sb_pad(style, 12, 6)
	p.add_theme_stylebox_override("panel", style)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	if icon_kind != "":
		h.add_child(Icon.new(icon_kind, icon_col, 7))
	var l := label(txt, 14, txt_col, true)
	h.add_child(l)
	p.add_child(h)
	return p

# ---------- toast ----------

static func toast(host: Control, txt: String) -> void:
	var p := PanelContainer.new()
	var style := sb(Color(0.0784, 0.0706, 0.1412, 0.92), T.RADIUS_PILL,
			Color(T.LAVENDER, 0.4), 1)
	sb_pad(style, 16, 8)
	p.add_theme_stylebox_override("panel", style)
	p.add_child(label(txt, 13, T.TEXT_BODY))
	p.modulate.a = 0.0
	host.add_child(p)
	p.reset_size()
	await host.get_tree().process_frame
	p.position = Vector2((host.size.x - p.size.x) / 2.0, host.size.y - 180)
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.4)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(p.queue_free)

# ---------- helpers ----------

static func fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

static func draw_star(ci: CanvasItem, c: Vector2, r: float, col: Color, points := 5) -> void:
	# points=5 -> currency/rating star, points=4 -> sparkle
	var pts := PackedVector2Array()
	var inner := r * (0.5 if points == 5 else 0.38)
	var n := points * 2
	for i in range(n):
		var rad := r if i % 2 == 0 else inner
		var a := -PI / 2.0 + TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	ci.draw_colored_polygon(pts, col)

static func draw_glyph(ci: CanvasItem, shape: String, col: Color, c: Vector2, s: float) -> void:
	## Placeholder item glyphs (used by hidden-object scene + target tray until real art lands).
	## s = half-size in px.
	match shape:
		"ring":
			ci.draw_arc(c, s, 0, TAU, 32, col, s * 0.28, true)
		"gem":
			var pts := PackedVector2Array([
				c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)])
			ci.draw_colored_polygon(pts, col)
		"lantern":
			# paper lantern: warm glow, capped ribbed body, tassel
			var dark := col.darkened(0.35)
			draw_glow(ci, c, s * 2.4, Color(col, 0.30))
			# hanger + top cap
			ci.draw_line(c + Vector2(0, -s * 1.55), c + Vector2(0, -s * 1.15), dark, maxf(1.5, s * 0.12))
			var cap := StyleBoxFlat.new()
			cap.bg_color = dark
			cap.set_corner_radius_all(maxi(1, int(s * 0.12)))
			cap.draw(ci.get_canvas_item(), Rect2(c + Vector2(-s * 0.38, -s * 1.22), Vector2(s * 0.76, s * 0.26)))
			# body (squashed circle) with inner light
			ci.draw_set_transform(c, 0, Vector2(0.88, 1.0))
			ci.draw_circle(Vector2.ZERO, s, col)
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			ci.draw_circle(c + Vector2(0, -s * 0.12), s * 0.4, Color(1.0, 0.98, 0.88, 0.55))
			# vertical ribs
			for f in [0.32, 0.62]:
				ci.draw_set_transform(c, 0, Vector2(0.88 * f, 1.0))
				ci.draw_arc(Vector2.ZERO, s * 0.99, 0, TAU, 24, Color(dark, 0.45), maxf(1.0, s * 0.07), true)
				ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			# bottom cap + tassel
			cap.draw(ci.get_canvas_item(), Rect2(c + Vector2(-s * 0.3, s * 0.92), Vector2(s * 0.6, s * 0.22)))
			ci.draw_line(c + Vector2(0, s * 1.14), c + Vector2(0, s * 1.5), Color(dark, 0.9), maxf(1.2, s * 0.1))
		"ball":
			ci.draw_circle(c, s, col)
			ci.draw_circle(c - Vector2(s * 0.3, s * 0.35), s * 0.25, Color(1, 1, 1, 0.35))
		"stick":
			ci.draw_set_transform(c, -0.5, Vector2.ONE)
			var r2 := StyleBoxFlat.new()
			r2.bg_color = col
			r2.set_corner_radius_all(int(s * 0.3))
			r2.draw(ci.get_canvas_item(), Rect2(Vector2(-s, -s * 0.28), Vector2(s * 2, s * 0.56)))
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"watch":
			ci.draw_arc(c, s * 0.85, 0, TAU, 32, col, s * 0.22, true)
			ci.draw_line(c, c + Vector2(0, -s * 0.5), col, s * 0.14)
			ci.draw_line(c, c + Vector2(s * 0.32, 0), col, s * 0.14)
			ci.draw_circle(c - Vector2(0, s * 1.05), s * 0.16, col)
		"star":
			draw_star(ci, c, s, col, 5)
		"spark":
			draw_star(ci, c, s, col, 4)
		"key":
			ci.draw_arc(c - Vector2(s * 0.45, 0), s * 0.45, 0, TAU, 24, col, s * 0.2, true)
			ci.draw_line(c, c + Vector2(s, 0), col, s * 0.2)
			ci.draw_line(c + Vector2(s * 0.75, 0), c + Vector2(s * 0.75, s * 0.35), col, s * 0.16)
		"tri":
			var pts2 := PackedVector2Array([
				c + Vector2(0, -s), c + Vector2(s * 0.9, s * 0.8), c + Vector2(-s * 0.9, s * 0.8)])
			ci.draw_colored_polygon(pts2, col)
		_:
			ci.draw_circle(c, s, col)

# ---------- drawn icon control ----------

class Icon extends Control:
	var kind: String
	var col: Color
	var r: float

	func _init(k: String, c: Color, radius: float) -> void:
		kind = k
		col = c
		r = radius
		if k == "lantern":  # hanger-to-tassel is taller than wide
			custom_minimum_size = Vector2(r * 2.4, r * 3.2)
		else:
			custom_minimum_size = Vector2(r * 2 + 2, r * 2 + 2)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c2 := size / 2.0
		match kind:
			"play":
				var pts := PackedVector2Array([
					c2 + Vector2(-r * 0.55, -r), c2 + Vector2(r, 0), c2 + Vector2(-r * 0.55, r)])
				draw_colored_polygon(pts, col)
			"pause":
				var w := r * 0.42
				var box := StyleBoxFlat.new()
				box.bg_color = col
				box.set_corner_radius_all(2)
				box.draw(get_canvas_item(), Rect2(c2 + Vector2(-w * 1.9, -r), Vector2(w, r * 2)))
				box.draw(get_canvas_item(), Rect2(c2 + Vector2(w * 0.9, -r), Vector2(w, r * 2)))
			"gear":
				draw_arc(c2, r * 0.85, 0, TAU, 24, col, r * 0.3, true)
				for i in range(6):
					var a := TAU * float(i) / 6.0
					draw_line(c2 + Vector2(cos(a), sin(a)) * r * 0.75,
							c2 + Vector2(cos(a), sin(a)) * r * 1.15, col, r * 0.28)
			"lock":
				var box2 := StyleBoxFlat.new()
				box2.bg_color = col
				box2.set_corner_radius_all(int(r * 0.3))
				box2.draw(get_canvas_item(), Rect2(c2 + Vector2(-r, -r * 0.2), Vector2(r * 2, r * 1.4)))
				draw_arc(c2 + Vector2(0, -r * 0.25), r * 0.55, PI, TAU, 16, col, r * 0.25, true)
			"back":
				draw_line(c2 + Vector2(r * 0.4, -r * 0.8), c2 + Vector2(-r * 0.5, 0), col, r * 0.32, true)
				draw_line(c2 + Vector2(-r * 0.5, 0), c2 + Vector2(r * 0.4, r * 0.8), col, r * 0.32, true)
			_:
				UI.draw_glyph(self, kind, col, c2, r)

class Stars extends Control:
	## Row of 3 rating stars, `filled` lit.
	var filled: int
	var star_r := 7.0

	func _init(f: int, radius := 7.0) -> void:
		filled = f
		star_r = radius
		custom_minimum_size = Vector2((star_r * 2 + 5) * 3, star_r * 2 + 2)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in range(3):
			var col := T.GOLD if i < filled else Color(T.GOLD, 0.3)
			var c := Vector2(star_r + (star_r * 2 + 5) * i, size.y / 2.0)
			UI.draw_star(self, c, star_r, col, 5)
