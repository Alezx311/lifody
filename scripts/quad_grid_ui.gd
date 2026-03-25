class_name QuadGridUI
extends CanvasLayer

## HUD overlay for Quad Grid Mode.
## Renders a 32px top bar, 4 panel headers with per-panel controls,
## and 4 panel border outlines (active = blue, inactive = dim).

const PANEL_BG    := Color(0.08, 0.08, 0.12, 0.95)
const BTN_NORMAL  := Color(0.15, 0.15, 0.22)
const BTN_ACTIVE  := Color(0.25, 0.55, 0.90)
const TEXT_COLOR  := Color(0.88, 0.88, 0.95)
const DIM_COLOR   := Color(0.55, 0.55, 0.65)
const BORDER_ACTIVE := Color(0.35, 0.70, 1.00)
const BORDER_NORMAL := Color(0.25, 0.25, 0.35, 0.50)

const INST_LABELS: Array = [
	"🎸 Guitar", "🎹 Piano", "🎹 Organ", "🎻 Strings",
	"🎸 Acoustic", "🎷 Wind", "🎸 Bass", "🎻 Pad"
]

var quad_mode: QuadGridMode = null

var _pause_btns: Array = []   # Button per panel
var _borders: Array = []      # Panel outlines per panel
var _headers: Array = []      # Panel header Panel nodes per panel
var _panel_num_btns: Array = [] # Panel number buttons (for active highlight)

signal back_requested


func setup(qm: QuadGridMode) -> void:
	quad_mode = qm
	_build_top_bar()
	_build_panel_headers()
	_build_panel_outlines()
	_update_active_highlight()
	quad_mode.panel_changed.connect(_update_active_highlight)


# ────────────────────────────────────────────────────────────────────────────
#  Top bar
# ────────────────────────────────────────────────────────────────────────────

func _build_top_bar() -> void:
	var vp := get_viewport().get_visible_rect().size
	var bar := _make_panel(Rect2(0, 0, vp.x, 32))

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 8)
	bar.add_child(hbox)

	# Back button
	var back_btn := _make_btn("← Back", 11)
	back_btn.custom_minimum_size = Vector2(64, 0)
	back_btn.tooltip_text = "Return to main game"
	back_btn.pressed.connect(func() -> void: back_requested.emit())
	hbox.add_child(back_btn)

	# Separator
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(4, 0)
	hbox.add_child(sep)

	# Title
	var title := _make_label("⊞ Quad Grid Mode", 12)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(title)

	# Pause All button
	var pause_all := _make_btn("⏸ Pause All", 11)
	pause_all.custom_minimum_size = Vector2(80, 0)
	pause_all.pressed.connect(func() -> void:
		if quad_mode:
			for i in QuadGridMode.PANEL_COUNT:
				var g := quad_mode.get_panel_grid(i)
				g.running = false
			_refresh_all_pause_btns()
	)
	hbox.add_child(pause_all)

	# Play All button
	var play_all := _make_btn("▶ Play All", 11)
	play_all.custom_minimum_size = Vector2(72, 0)
	play_all.pressed.connect(func() -> void:
		if quad_mode:
			for i in QuadGridMode.PANEL_COUNT:
				var g := quad_mode.get_panel_grid(i)
				g.running = true
			_refresh_all_pause_btns()
	)
	hbox.add_child(play_all)


# ────────────────────────────────────────────────────────────────────────────
#  Panel headers
# ────────────────────────────────────────────────────────────────────────────

func _build_panel_headers() -> void:
	_pause_btns.clear()
	_headers.clear()
	_panel_num_btns.clear()

	for i in QuadGridMode.PANEL_COUNT:
		var rect := quad_mode.get_header_screen_rect(i)
		var header := _make_panel(rect)
		_headers.append(header)

		var hbox := HBoxContainer.new()
		hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hbox.add_theme_constant_override("separation", 4)
		header.add_child(hbox)

		# Panel number button (click to activate)
		var num_btn := _make_btn("Panel %d" % (i + 1), 10)
		num_btn.custom_minimum_size = Vector2(56, 0)
		var capture_i := i
		num_btn.pressed.connect(func() -> void:
			if quad_mode:
				quad_mode.set_active(capture_i)
		)
		_panel_num_btns.append(num_btn)
		hbox.add_child(num_btn)

		# Instrument OptionButton
		var inst_opt := OptionButton.new()
		inst_opt.custom_minimum_size = Vector2(100, 0)
		inst_opt.tooltip_text = "Select instrument for panel %d" % (i + 1)
		for lbl in INST_LABELS:
			inst_opt.add_item(lbl as String)
		inst_opt.selected = 0
		inst_opt.item_selected.connect(func(idx: int) -> void:
			if quad_mode:
				quad_mode.set_panel_instrument(capture_i, idx)
		)
		_style_option_button(inst_opt)
		hbox.add_child(inst_opt)

		# Volume slider
		var vol_lbl := _make_label("Vol:", 10)
		vol_lbl.add_theme_color_override("font_color", DIM_COLOR)
		hbox.add_child(vol_lbl)

		var vol_slider := HSlider.new()
		vol_slider.min_value = 0.0
		vol_slider.max_value = 1.0
		vol_slider.step = 0.01
		vol_slider.value = 0.7
		vol_slider.custom_minimum_size = Vector2(70, 0)
		vol_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		vol_slider.tooltip_text = "Volume for panel %d" % (i + 1)
		vol_slider.value_changed.connect(func(v: float) -> void:
			if quad_mode:
				quad_mode.set_panel_volume(capture_i, v)
		)
		hbox.add_child(vol_slider)

		# Pause/Play toggle button
		var pause_btn := _make_btn("⏸", 11)
		pause_btn.custom_minimum_size = Vector2(28, 0)
		pause_btn.tooltip_text = "Pause/play panel %d" % (i + 1)
		pause_btn.pressed.connect(func() -> void:
			_toggle_panel_pause(capture_i)
		)
		_pause_btns.append(pause_btn)
		hbox.add_child(pause_btn)

		# Seed random button
		var seed_btn := _make_btn("🎲", 11)
		seed_btn.custom_minimum_size = Vector2(28, 0)
		seed_btn.tooltip_text = "Seed random for panel %d" % (i + 1)
		seed_btn.pressed.connect(func() -> void:
			if quad_mode:
				quad_mode.seed_panel(capture_i, "random")
		)
		hbox.add_child(seed_btn)

		# Clear button
		var clr_btn := _make_btn("🗑", 11)
		clr_btn.custom_minimum_size = Vector2(28, 0)
		clr_btn.tooltip_text = "Clear panel %d" % (i + 1)
		clr_btn.pressed.connect(func() -> void:
			if quad_mode:
				quad_mode.clear_panel(capture_i)
		)
		hbox.add_child(clr_btn)


# ────────────────────────────────────────────────────────────────────────────
#  Panel border outlines
# ────────────────────────────────────────────────────────────────────────────

func _build_panel_outlines() -> void:
	_borders.clear()
	for i in QuadGridMode.PANEL_COUNT:
		var rect := quad_mode.get_panel_screen_rect(i)
		var border_panel := Panel.new()
		border_panel.position = rect.position
		border_panel.size = rect.size

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = BORDER_NORMAL
		style.set_border_width_all(2)
		style.set_corner_radius_all(0)
		border_panel.add_theme_stylebox_override("panel", style)

		add_child(border_panel)
		_borders.append(border_panel)


# ────────────────────────────────────────────────────────────────────────────
#  Active panel highlight
# ────────────────────────────────────────────────────────────────────────────

func _update_active_highlight(_idx: int = 0) -> void:
	if not quad_mode:
		return
	var active := quad_mode.active_panel
	for i in QuadGridMode.PANEL_COUNT:
		# Update border color
		if i < _borders.size():
			var style := (_borders[i] as Panel).get_theme_stylebox("panel") as StyleBoxFlat
			if style:
				style.border_color = BORDER_ACTIVE if i == active else BORDER_NORMAL

		# Update panel number button color
		if i < _panel_num_btns.size():
			var btn := _panel_num_btns[i] as Button
			var btn_style := StyleBoxFlat.new()
			btn_style.bg_color = BTN_ACTIVE if i == active else BTN_NORMAL
			btn_style.set_corner_radius_all(3)
			btn.add_theme_stylebox_override("normal", btn_style)
			btn.add_theme_stylebox_override("hover", btn_style)
			btn.add_theme_stylebox_override("pressed", btn_style)

		# Update header background tint
		if i < _headers.size():
			var h_panel := _headers[i] as Panel
			var h_style := StyleBoxFlat.new()
			h_style.bg_color = Color(0.10, 0.18, 0.28, 0.97) if i == active else PANEL_BG
			h_style.set_corner_radius_all(0)
			h_panel.add_theme_stylebox_override("panel", h_style)


# ────────────────────────────────────────────────────────────────────────────
#  Panel pause toggle
# ────────────────────────────────────────────────────────────────────────────

func _toggle_panel_pause(panel_idx: int) -> void:
	if not quad_mode:
		return
	quad_mode.toggle_panel_pause(panel_idx)
	var g := quad_mode.get_panel_grid(panel_idx)
	if panel_idx < _pause_btns.size():
		(_pause_btns[panel_idx] as Button).text = "▶" if not g.running else "⏸"


func _refresh_all_pause_btns() -> void:
	if not quad_mode:
		return
	for i in QuadGridMode.PANEL_COUNT:
		if i < _pause_btns.size():
			var g := quad_mode.get_panel_grid(i)
			(_pause_btns[i] as Button).text = "▶" if not g.running else "⏸"


# ────────────────────────────────────────────────────────────────────────────
#  Helper factory methods
# ────────────────────────────────────────────────────────────────────────────

func _make_panel(rect: Rect2) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_corner_radius_all(0)
	p.add_theme_stylebox_override("panel", style)
	add_child(p)
	return p


func _make_btn(text: String, font_size: int = 11) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", TEXT_COLOR)
	var style := StyleBoxFlat.new()
	style.bg_color = BTN_NORMAL
	style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", style)
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = BTN_NORMAL.lightened(0.15)
	hover_style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("hover", hover_style)
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = BTN_ACTIVE
	pressed_style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	return btn


func _make_label(text: String, font_size: int = 11) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", TEXT_COLOR)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


func _style_option_button(opt: OptionButton) -> void:
	opt.add_theme_font_size_override("font_size", 10)
	opt.add_theme_color_override("font_color", TEXT_COLOR)
	var style := StyleBoxFlat.new()
	style.bg_color = BTN_NORMAL
	style.set_corner_radius_all(3)
	opt.add_theme_stylebox_override("normal", style)
