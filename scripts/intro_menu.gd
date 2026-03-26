class_name IntroMenu
extends CanvasLayer

## Main menu shown before gameplay. Uses stack-based navigation:
## navigate() clears _content_area and rebuilds it for each screen.
##
## Screens: main / sandbox / settings_audio / settings_video / settings_hotkeys

signal start_requested(config: Dictionary)

# ── Visual style ──────────────────────────────────────────────────────────────
const PANEL_BG   := Color(0.06, 0.06, 0.10, 0.97)
const BTN_NORMAL := Color(0.14, 0.14, 0.22)
const BTN_HOVER  := Color(0.22, 0.22, 0.35)
const TEXT_COLOR := Color(0.88, 0.88, 0.95)
const DIM_COLOR  := Color(0.55, 0.55, 0.65)
const ACCENT     := Color(0.20, 0.48, 0.85)
const ACCENT_QS  := Color(0.15, 0.60, 0.30)   # green for Quick Start
const DANGER     := Color(0.50, 0.10, 0.10)    # dark red for Quit

# ── Default world config ──────────────────────────────────────────────────────
const DEFAULT_WORLD_CFG := {
	"pattern":       "random",
	"scale_preset":  "classic",
	"mutation_rate": 0.05,
	"instrument":    0,
	"tempo":         120.0,
	"speed_tps":     5.0,
}

# ── State ─────────────────────────────────────────────────────────────────────
var _world_cfg: Dictionary = {}
var _av_cfg: Dictionary = {
	"master_volume": 0.7,
	"fullscreen":    false,
	"color_mode":    "age",
}
var _current_settings_tab: String = "audio"

# ── Persistent node refs ──────────────────────────────────────────────────────
var _panel: Panel = null
var _content_area: VBoxContainer = null


func _ready() -> void:
	_world_cfg = DEFAULT_WORLD_CFG.duplicate(true)
	_build_frame()
	_navigate("main")


# ─────────────────────────────────────────────────────────────────────────────
#  Frame (built once; only _content_area changes)
# ─────────────────────────────────────────────────────────────────────────────

func _build_frame() -> void:
	# Full-screen dim overlay
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.80)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	# Centered panel
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.30, 0.30, 0.50, 0.80)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	# Outer vbox (title + separator + content)
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 10)
	outer.offset_left   = 24.0
	outer.offset_right  = -24.0
	outer.offset_top    = 20.0
	outer.offset_bottom = -20.0
	_panel.add_child(outer)

	# Title block
	var title := _label("LIFODY", 34)
	title.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	var sub := _label("Conway's Life  ×  Musical Evolution", 11)
	sub.add_theme_color_override("font_color", DIM_COLOR)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(sub)

	outer.add_child(HSeparator.new())

	# Dynamic content area
	_content_area = VBoxContainer.new()
	_content_area.add_theme_constant_override("separation", 8)
	outer.add_child(_content_area)


# ─────────────────────────────────────────────────────────────────────────────
#  Navigation
# ─────────────────────────────────────────────────────────────────────────────

func _navigate(screen: String) -> void:
	for ch in _content_area.get_children().duplicate():
		_content_area.remove_child(ch)
		ch.queue_free()
	match screen:
		"main":             _show_main()
		"sandbox":          _show_sandbox()
		"settings_audio":   _show_settings_audio()
		"settings_video":   _show_settings_video()
		"settings_hotkeys": _show_settings_hotkeys()
	_resize_panel_deferred()


func _resize_panel_deferred() -> void:
	await get_tree().process_frame
	await get_tree().process_frame  # two frames so all children have computed sizes
	_resize_panel()


func _resize_panel() -> void:
	var outer := _panel.get_child(0) as VBoxContainer
	var h := outer.get_combined_minimum_size().y + 40.0
	h = maxf(h, 200.0)
	_panel.custom_minimum_size = Vector2(440.0, h)
	_panel.offset_top    = -h * 0.5
	_panel.offset_bottom =  h * 0.5
	_panel.offset_left   = -220.0
	_panel.offset_right  =  220.0


# ─────────────────────────────────────────────────────────────────────────────
#  Screen: Main
# ─────────────────────────────────────────────────────────────────────────────

func _show_main() -> void:
	_content_area.add_child(_spacer(4))

	var qs := _accent_button("▶   Quick Start", ACCENT_QS)
	qs.tooltip_text = "Старт з налаштуваннями за замовчуванням"
	qs.pressed.connect(func() -> void:
		start_requested.emit(DEFAULT_WORLD_CFG.merged(_av_cfg))
		queue_free()
	)
	_content_area.add_child(qs)

	var sb := _accent_button("⚙   Sandbox", ACCENT)
	sb.tooltip_text = "Налаштувати параметри світу перед стартом"
	sb.pressed.connect(func() -> void: _navigate("sandbox"))
	_content_area.add_child(sb)

	var st := _wide_button("🔧   Налаштування", 14)
	st.pressed.connect(func() -> void: _navigate("settings_" + _current_settings_tab))
	_content_area.add_child(st)

	var qt := _wide_button("✕   Вийти", 14)
	var qt_sb := StyleBoxFlat.new()
	qt_sb.bg_color = DANGER
	qt_sb.set_corner_radius_all(4)
	qt_sb.set_border_width_all(1)
	qt_sb.border_color = Color(0.8, 0.3, 0.3, 0.6)
	qt.add_theme_stylebox_override("normal", qt_sb)
	var qt_h := qt_sb.duplicate() as StyleBoxFlat
	qt_h.bg_color = DANGER.lightened(0.1)
	qt.add_theme_stylebox_override("hover", qt_h)
	qt.pressed.connect(func() -> void: get_tree().quit())
	_content_area.add_child(qt)

	_content_area.add_child(_spacer(4))


# ─────────────────────────────────────────────────────────────────────────────
#  Screen: Sandbox
# ─────────────────────────────────────────────────────────────────────────────

func _show_sandbox() -> void:
	_content_area.add_child(_back_button("main"))

	# ── Genre presets ─────────────────────────────────────────────────────────
	_content_area.add_child(_section_label("Жанровий пресет:"))
	var genre_defs := [
		["🎼 Classical", 3, 120.0, 0.03, "classic",  5.0],
		["🌙 Ambient",   7,  60.0, 0.02, "12maj",    2.0],
		["🎸 Rock",      2, 150.0, 0.07, "5ths",     8.0],
		["🎷 Jazz",      1, 120.0, 0.05, "7modes",   5.0],
		["🔔 Bells",     4,  90.0, 0.04, "classic",  3.0],
		["⚡ Chaos",     0, 180.0, 0.15, "12min",   10.0],
	]
	var gg := GridContainer.new()
	gg.columns = 3
	gg.add_theme_constant_override("h_separation", 4)
	gg.add_theme_constant_override("v_separation", 4)
	_content_area.add_child(gg)
	for gd in genre_defs:
		var n: String = gd[0]; var inst: int = gd[1]; var t: float = gd[2]
		var m: float = gd[3]; var sc: String = gd[4]; var sp: float = gd[5]
		var gb := _button(n, 10)
		gb.custom_minimum_size = Vector2(130.0, 26.0)
		gb.pressed.connect(func() -> void:
			_world_cfg["instrument"]    = inst
			_world_cfg["tempo"]         = t
			_world_cfg["mutation_rate"] = m
			_world_cfg["scale_preset"]  = sc
			_world_cfg["speed_tps"]     = sp
		)
		gg.add_child(gb)

	_content_area.add_child(HSeparator.new())

	# ── Pattern ───────────────────────────────────────────────────────────────
	_build_choice_row("Паттерн:", [
		["Порожньо",    func(): _world_cfg["pattern"] = "empty"],
		["Random",      func(): _world_cfg["pattern"] = "random"],
		["Glider",      func(): _world_cfg["pattern"] = "glider"],
		["R-Pentomino", func(): _world_cfg["pattern"] = "r_pentomino"],
	])

	# ── Scale ─────────────────────────────────────────────────────────────────
	_build_choice_row("Гама:", [
		["Classic", func(): _world_cfg["scale_preset"] = "classic"],
		["12Maj",   func(): _world_cfg["scale_preset"] = "12maj"],
		["12Min",   func(): _world_cfg["scale_preset"] = "12min"],
		["5ths",    func(): _world_cfg["scale_preset"] = "5ths"],
		["7Modes",  func(): _world_cfg["scale_preset"] = "7modes"],
		["Dorian",  func(): _world_cfg["scale_preset"] = "dorian"],
	])

	# ── Mutation ──────────────────────────────────────────────────────────────
	_build_choice_row("Мутація:", [
		["Повільна (2%)",  func(): _world_cfg["mutation_rate"] = 0.02],
		["Нормальна (5%)", func(): _world_cfg["mutation_rate"] = 0.05],
		["Швидка (12%)",   func(): _world_cfg["mutation_rate"] = 0.12],
	])

	# ── Instrument ────────────────────────────────────────────────────────────
	var ir := HBoxContainer.new()
	ir.add_theme_constant_override("separation", 6)
	_content_area.add_child(ir)
	var il := _label("Інструмент:", 11)
	il.custom_minimum_size = Vector2(110.0, 0.0)
	ir.add_child(il)
	var inst_opt := OptionButton.new()
	inst_opt.custom_minimum_size = Vector2(150.0, 0.0)
	for nm in ["🎸 Guitar","🎹 Piano","🎸 Organ","🎻 Strings","🎸 Acoustic","🎷 Wind","🎸 Bass","🎻 Pad"]:
		inst_opt.add_item(nm as String)
	inst_opt.selected = _world_cfg.get("instrument", 0)
	inst_opt.item_selected.connect(func(idx: int) -> void: _world_cfg["instrument"] = idx)
	ir.add_child(inst_opt)

	# ── Tempo ─────────────────────────────────────────────────────────────────
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 4)
	_content_area.add_child(tr)
	var tl := _label("Темп BPM:", 11)
	tl.custom_minimum_size = Vector2(110.0, 0.0)
	tr.add_child(tl)
	for td in [[60.0, 2.0, "60"], [90.0, 3.0, "90"], [120.0, 5.0, "120"], [150.0, 8.0, "150"], [180.0, 10.0, "180"]]:
		var tv: float = td[0]; var sv: float = td[1]; var tl2: String = td[2]
		var tb := _button(tl2, 10)
		tb.pressed.connect(func() -> void:
			_world_cfg["tempo"]     = tv
			_world_cfg["speed_tps"] = sv
		)
		tr.add_child(tb)

	_content_area.add_child(HSeparator.new())

	var play := _accent_button("▶   Грати!", ACCENT_QS)
	play.pressed.connect(func() -> void:
		start_requested.emit(_world_cfg.merged(_av_cfg))
		queue_free()
	)
	_content_area.add_child(play)
	_content_area.add_child(_spacer(4))


# ─────────────────────────────────────────────────────────────────────────────
#  Settings: tab helpers
# ─────────────────────────────────────────────────────────────────────────────

func _build_settings_header(active: String, back_to: String) -> void:
	_content_area.add_child(_back_button(back_to))

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	_content_area.add_child(hb)

	var tabs := [["audio", "🔊 Аудіо"], ["video", "🖥 Відео"], ["hotkeys", "⌨ Клавіші"]]
	for tab in tabs:
		var tid: String = tab[0]; var tlbl: String = tab[1]
		var tb := _button(tlbl, 10)
		tb.custom_minimum_size = Vector2(120.0, 28.0)
		if tid == active:
			var sb := StyleBoxFlat.new()
			sb.bg_color = ACCENT
			sb.set_corner_radius_all(4)
			sb.set_border_width_all(1)
			sb.border_color = Color(0.5, 0.7, 1.0, 0.8)
			tb.add_theme_stylebox_override("normal", sb)
			var sh := sb.duplicate() as StyleBoxFlat
			sh.bg_color = ACCENT.lightened(0.1)
			tb.add_theme_stylebox_override("hover", sh)
		tb.pressed.connect(func() -> void:
			_current_settings_tab = tid
			_navigate("settings_" + tid)
		)
		hb.add_child(tb)

	_content_area.add_child(HSeparator.new())


# ─────────────────────────────────────────────────────────────────────────────
#  Screen: Settings — Audio
# ─────────────────────────────────────────────────────────────────────────────

func _show_settings_audio() -> void:
	_current_settings_tab = "audio"
	_build_settings_header("audio", "main")

	# Volume slider
	var vr := HBoxContainer.new()
	vr.add_theme_constant_override("separation", 8)
	_content_area.add_child(vr)
	var vl := _label("Гучність:", 11)
	vl.custom_minimum_size = Vector2(90.0, 0.0)
	vr.add_child(vl)
	var vs := HSlider.new()
	vs.min_value = 0.0
	vs.max_value = 1.0
	vs.step = 0.01
	vs.value = _av_cfg.get("master_volume", 0.7)
	vs.custom_minimum_size = Vector2(180.0, 0.0)
	vs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vr.add_child(vs)
	var vpct := _label("%d%%" % int(_av_cfg.get("master_volume", 0.7) * 100.0), 11)
	vpct.custom_minimum_size = Vector2(36.0, 0.0)
	vr.add_child(vpct)
	vs.value_changed.connect(func(v: float) -> void:
		_av_cfg["master_volume"] = v
		vpct.text = "%d%%" % int(v * 100.0)
	)

	# Instrument
	var ir := HBoxContainer.new()
	ir.add_theme_constant_override("separation", 8)
	_content_area.add_child(ir)
	var il := _label("Інструмент:", 11)
	il.custom_minimum_size = Vector2(90.0, 0.0)
	ir.add_child(il)
	var io := OptionButton.new()
	io.custom_minimum_size = Vector2(160.0, 0.0)
	for nm in ["🎸 Guitar","🎹 Piano","🎸 Organ","🎻 Strings","🎸 Acoustic","🎷 Wind","🎸 Bass","🎻 Pad"]:
		io.add_item(nm as String)
	io.selected = _world_cfg.get("instrument", 0)
	io.item_selected.connect(func(idx: int) -> void: _world_cfg["instrument"] = idx)
	ir.add_child(io)

	var hint := _label("Ці налаштування зберігаються при зміні екрану", 9)
	hint.add_theme_color_override("font_color", DIM_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_area.add_child(hint)
	_content_area.add_child(_spacer(4))


# ─────────────────────────────────────────────────────────────────────────────
#  Screen: Settings — Video
# ─────────────────────────────────────────────────────────────────────────────

func _show_settings_video() -> void:
	_current_settings_tab = "video"
	_build_settings_header("video", "main")

	# Fullscreen
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 8)
	_content_area.add_child(fr)
	fr.add_child(_label("Повноекранний:", 11))
	var is_fs: bool = _av_cfg.get("fullscreen", false)
	var fs_btn := _button("Увімкнено" if is_fs else "Вимкнено", 11)
	fs_btn.custom_minimum_size = Vector2(100.0, 0.0)
	fs_btn.pressed.connect(func() -> void:
		_av_cfg["fullscreen"] = not _av_cfg.get("fullscreen", false)
		fs_btn.text = "Увімкнено" if _av_cfg["fullscreen"] else "Вимкнено"
		_apply_fullscreen()
	)
	fr.add_child(fs_btn)

	# Color mode
	var cr := HBoxContainer.new()
	cr.add_theme_constant_override("separation", 8)
	_content_area.add_child(cr)
	cr.add_child(_label("Колір клітин:", 11))
	var cur_mode: String = _av_cfg.get("color_mode", "age")
	for md in [["age", "🎨 За віком"], ["note", "🎵 За нотою"]]:
		var mid: String = md[0]; var mlbl: String = md[1]
		var mb := _button(mlbl, 10)
		mb.custom_minimum_size = Vector2(110.0, 0.0)
		if mid == cur_mode:
			var sb := StyleBoxFlat.new()
			sb.bg_color = ACCENT
			sb.set_corner_radius_all(4)
			sb.set_border_width_all(1)
			sb.border_color = Color(0.5, 0.7, 1.0, 0.8)
			mb.add_theme_stylebox_override("normal", sb)
		mb.pressed.connect(func() -> void:
			_av_cfg["color_mode"] = mid
			# Rebuild to reflect new active button
			_navigate("settings_video")
		)
		cr.add_child(mb)

	_content_area.add_child(_spacer(4))


# ─────────────────────────────────────────────────────────────────────────────
#  Screen: Settings — Hotkeys
# ─────────────────────────────────────────────────────────────────────────────

func _show_settings_hotkeys() -> void:
	_current_settings_tab = "hotkeys"
	_build_settings_header("hotkeys", "main")

	var hotkeys := [
		["Space",           "Пауза / Старт симуляції"],
		["R",               "Випадковий паттерн (Random)"],
		["C",               "Очистити поле"],
		["F / Home",        "Скинути камеру"],
		["1",               "Швидкість: 1 tps (повільно)"],
		["2",               "Швидкість: 2 tps"],
		["3",               "Швидкість: 3 tps"],
		["4",               "Швидкість: 5 tps"],
		["5",               "Швидкість: 8 tps"],
		["6",               "Швидкість: 10 tps"],
		["7",               "Швидкість: 13 tps"],
		["8",               "Швидкість: 16 tps"],
		["9",               "Швидкість: 20 tps (швидко)"],
		["+ / =",           "Плавне збільшення швидкості"],
		["- ",              "Плавне зменшення швидкості"],
		["F11",             "Повноекранний режим"],
		["Колесо миші",     "Зум камери"],
		["ПКМ + перетяг",   "Переміщення камери"],
	]

	# ScrollContainer so list doesn't overflow the panel
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0.0, 220.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_area.add_child(sc)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	sc.add_child(grid)

	for hk in hotkeys:
		var key_lbl := _label(hk[0] as String, 10)
		key_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		key_lbl.custom_minimum_size = Vector2(110.0, 0.0)
		grid.add_child(key_lbl)

		var act_lbl := _label(hk[1] as String, 10)
		act_lbl.add_theme_color_override("font_color", TEXT_COLOR)
		grid.add_child(act_lbl)

	_content_area.add_child(_spacer(4))


# ─────────────────────────────────────────────────────────────────────────────
#  Helpers: apply live settings
# ─────────────────────────────────────────────────────────────────────────────

func _apply_fullscreen() -> void:
	var fs: bool = _av_cfg.get("fullscreen", false)
	if fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


# ─────────────────────────────────────────────────────────────────────────────
#  Helpers: widgets
# ─────────────────────────────────────────────────────────────────────────────

func _back_button(target: String) -> Button:
	var btn := _button("← Назад", 10)
	btn.custom_minimum_size = Vector2(90.0, 24.0)
	btn.pressed.connect(func() -> void: _navigate(target))
	return btn


func _section_label(text: String) -> Label:
	var lbl := _label(text, 11)
	lbl.add_theme_color_override("font_color", DIM_COLOR)
	return lbl


func _build_choice_row(row_label: String, options: Array) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	_content_area.add_child(hb)
	var lbl := _label(row_label, 11)
	lbl.custom_minimum_size = Vector2(110.0, 0.0)
	hb.add_child(lbl)
	for opt in options:
		var opt_lbl: String = opt[0]
		var opt_fn: Callable = opt[1]
		var btn := _button(opt_lbl, 10)
		btn.pressed.connect(opt_fn)
		hb.add_child(btn)


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0.0, float(h))
	return s


func _label(text: String, size: int = 12) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", TEXT_COLOR)
	return lbl


func _button(text: String, size: int = 11) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", size)
	btn.add_theme_color_override("font_color", TEXT_COLOR)
	var sn := StyleBoxFlat.new()
	sn.bg_color = BTN_NORMAL
	sn.set_corner_radius_all(4)
	sn.set_border_width_all(1)
	sn.border_color = Color(0.30, 0.30, 0.45, 0.70)
	btn.add_theme_stylebox_override("normal", sn)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = BTN_HOVER
	btn.add_theme_stylebox_override("hover", sh)
	return btn


func _wide_button(text: String, size: int = 14) -> Button:
	var btn := _button(text, size)
	btn.custom_minimum_size = Vector2(392.0, 40.0)
	return btn


func _accent_button(text: String, color: Color) -> Button:
	var btn := _wide_button(text)
	var sn := StyleBoxFlat.new()
	sn.bg_color = color
	sn.set_corner_radius_all(4)
	sn.set_border_width_all(1)
	sn.border_color = color.lightened(0.25)
	btn.add_theme_stylebox_override("normal", sn)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = color.lightened(0.12)
	btn.add_theme_stylebox_override("hover", sh)
	return btn
