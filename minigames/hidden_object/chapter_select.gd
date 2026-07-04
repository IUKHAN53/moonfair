extends Control
## Hidden Grove — chapter select. One card per scene pack; each chapter holds
## 12 stages on the same background with a growing item count.

func _ready() -> void:
	_build()

func _build() -> void:
	add_child(UI.gradient_bg([T.BG_DUSK, T.BG_NIGHT, T.BG_NIGHT_DEEP], [0.0, 0.42, 1.0]))

	# top bar: back + title
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 18
	top.add_theme_constant_override("separation", 12)
	add_child(top)
	var back := UI.circle_button("back", 44, false, 8, Vector2(-1, 0))
	back.pressed.connect(Game.go_hub)
	top.add_child(back)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(UI.label("Hidden Grove", 24, T.TEXT_WARM, true))
	tv.add_child(UI.caps_label("Choose a chapter", T.LAVENDER))
	top.add_child(tv)

	# chapter cards
	var list := VBoxContainer.new()
	list.set_anchors_preset(Control.PRESET_TOP_WIDE)
	list.offset_left = 16
	list.offset_right = -16
	list.offset_top = 92
	list.add_theme_constant_override("separation", 12)
	add_child(list)
	for chapter_id in Game.chapters():
		list.add_child(_card(chapter_id))

func _card(chapter_id: String) -> PanelContainer:
	var pack = JSON.parse_string(FileAccess.get_file_as_string(Game.pack_path(chapter_id)))
	var unlocked: bool = Game.is_chapter_unlocked(chapter_id)
	var cleared: int = SaveData.stages_cleared(chapter_id)
	var num: int = Game.chapter_number(chapter_id)

	var p := PanelContainer.new()
	var style: StyleBoxFlat
	if unlocked:
		style = UI.sb(Color(0.149, 0.137, 0.278, 0.92), T.RADIUS_CARD, Color(1, 1, 1, 0.09), 1)
		style.shadow_color = Color(0.04, 0.03, 0.09, 0.45)
		style.shadow_size = 10
	else:
		style = UI.sb(Color(0.118, 0.106, 0.227, 0.75), T.RADIUS_CARD, Color(T.LAVENDER, 0.3), 1)
	UI.sb_pad(style, 12, 12)
	p.add_theme_stylebox_override("panel", style)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)

	h.add_child(ChapterThumb.new(pack, unlocked))

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 2)
	var title_col := T.TEXT_WARM if unlocked else Color(T.TEXT_BODY, 0.6)
	v.add_child(UI.label("%d · %s" % [num, pack["name"]], T.SIZE_TITLE_CARD, title_col, true))
	if unlocked:
		var done := cleared >= Game.STAGES_PER_CHAPTER
		var sub := "Complete! Replay any time" if done else "Stage %d of %d" % [mini(cleared + 1, Game.STAGES_PER_CHAPTER), Game.STAGES_PER_CHAPTER]
		v.add_child(UI.label(sub, 12, T.TEXT_DIM))
		v.add_child(ProgressPips.new(cleared))
	else:
		v.add_child(UI.label("Clear the previous chapter", 12, T.LAVENDER))
	h.add_child(v)

	if unlocked:
		var play := UI.circle_button("play", 54, true, 9, Vector2(2, 0))
		play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var next_stage: int = mini(cleared + 1, Game.STAGES_PER_CHAPTER)
		play.pressed.connect(func(): Game.play(chapter_id, next_stage))
		h.add_child(play)
		p.gui_input.connect(func(e: InputEvent):
			if e is InputEventScreenTouch and e.pressed:
				Game.play(chapter_id, next_stage))
	else:
		var lock := UI.Icon.new("lock", T.LAVENDER, 10)
		lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(lock)
	return p

class ProgressPips extends Control:
	## 12 tiny stage pips, lit for cleared stages.
	var cleared: int
	func _init(n: int) -> void:
		cleared = n
		custom_minimum_size = Vector2(12 * 13, 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		for i in range(12):
			var col := T.GOLD if i < cleared else Color(T.TEXT_BODY, 0.15)
			draw_circle(Vector2(4 + i * 13, size.y / 2.0), 3.0, col)

class ChapterThumb extends Control:
	## 82x82 rounded thumb: pack background art when present, gradient placeholder otherwise.
	var pack: Dictionary
	var unlocked: bool
	var tex: Texture2D
	func _init(p: Dictionary, u: bool) -> void:
		pack = p
		unlocked = u
		custom_minimum_size = Vector2(82, 82)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		var bg_path: String = pack.get("background", "")
		if bg_path != "" and ResourceLoader.exists(bg_path):
			tex = load(bg_path)
	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(20)
		var cols: Array = pack.get("bg_gradient", ["#2D2A52", "#1E1B3A", "#171430"])
		box.bg_color = Color(cols[0])
		box.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
		if tex:
			# cover-fit crop of the background art, inset to keep rounded corners visible
			var side := size.x - 6
			var tw := float(tex.get_width())
			var th := float(tex.get_height())
			var crop := minf(tw, th)
			var src := Rect2((tw - crop) / 2.0, (th - crop) / 2.0, crop, crop)
			draw_texture_rect_region(tex, Rect2(Vector2(3, 3), Vector2(side, side)), src)
		else:
			# placeholder: lower gradient band + a couple of item glyphs
			var band := StyleBoxFlat.new()
			band.bg_color = Color(cols[2])
			band.set_corner_radius_all(20)
			band.draw(get_canvas_item(), Rect2(Vector2(0, size.y * 0.55), Vector2(size.x, size.y * 0.45)))
			var glyph_items: Array = pack.get("items", [])
			if glyph_items.size() >= 2:
				UI.draw_glyph(self, glyph_items[0]["shape"], Color(glyph_items[0]["color"]),
						Vector2(size.x * 0.34, size.y * 0.44), 9)
				UI.draw_glyph(self, glyph_items[1]["shape"], Color(glyph_items[1]["color"]),
						Vector2(size.x * 0.68, size.y * 0.62), 8)
		if not unlocked:
			var dim := StyleBoxFlat.new()
			dim.bg_color = Color(0.07, 0.06, 0.14, 0.55)
			dim.set_corner_radius_all(20)
			dim.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
