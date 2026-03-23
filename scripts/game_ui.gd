class_name GameUI
extends CanvasLayer

## All game HUD created programmatically.
## Panels: TopBar | ToolPanel (left) | InfoPanel (right) | StatusBar (bottom) | LibraryPanel

signal seed_requested(pattern: String)
signal clear_requested
signal speed_changed(tps: float)
signal pause_toggled
signal like_cluster(cluster_id: int)
signal mute_cluster(cluster_id: int)
signal save_melody_requested(cluster_id: int)
signal event_requested(event_name: String, cluster_id: int)
signal grid_resize_requested(w: int, h: int, cs: int)

# References set via setup()
var grid: LifeGrid = null
var cluster_mgr: ClusterManager = null
var fitness_mgr: FitnessManager = null
var tool_mgr: ToolManager = null
var catalyst: CatalystEvents = null
var tonal: TonalRegions = null

# Cached UI nodes
var _tick_label: Label = null
var _speed_slider: HSlider = null
var _pause_btn: Button = null
var _tool_buttons: Array = []
var _tool_ids: Array = []      # Parallel to _tool_buttons: the Tool enum value
var _cluster_list: VBoxContainer = null
var _selected_info: VBoxContainer = null
var _status_label: Label = null
var _token_label: Label = null
var _library_panel: Panel = null
var _library_list: VBoxContainer = null
var _show_library_btn: Button = null
var _settings_panel: Panel = null
var _sound_panel: Panel = null
var _instrument_btns: Array = []

# Panel references for responsive resizing
var _top_bar: Panel = null
var _tool_panel: Panel = null
var _info_panel: Panel = null
var _status_bar: Panel = null

const PANEL_BG := Color(0.08, 0.08, 0.12, 0.88)
const BTN_NORMAL := Color(0.15, 0.15, 0.22)
const BTN_ACTIVE := Color(0.25, 0.55, 0.90)
const TEXT_COLOR := Color(0.88, 0.88, 0.95)
const DIM_COLOR  := Color(0.55, 0.55, 0.65)

# ── Piano keyboard ───────────────────────────────────────────────────────────
const PIANO_MIDI_LO: int = 36   # C2
const PIANO_MIDI_HI: int = 84   # C6  (covers all cluster octave offsets -1..+1)
const PIANO_H: int = 74         # panel height px

var _piano_panel: Panel = null
var _piano_container: Control = null
var _piano_keys: Dictionary = {}        # midi(int) → ColorRect
var _piano_brightness: Dictionary = {}  # midi(int) → float 0..1 (decays)


func setup(g: LifeGrid, cm: ClusterManager, fm: FitnessManager,
		   tm: ToolManager, ce: CatalystEvents, t: TonalRegions) -> void:
	grid = g
	cluster_mgr = cm
	fitness_mgr = fm
	tool_mgr = tm
	catalyst = ce
	tonal = t


func _ready() -> void:
	_build_ui()
	_connect_signals()


# ────────────────────────────────────────────────────────────────────────────
#  UI construction
# ────────────────────────────────────────────────────────────────────────────

func _get_vp_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _build_ui() -> void:
	_build_top_bar()
	_build_tool_panel()
	_build_info_panel()
	_build_status_bar()
	_build_library_panel()
	_build_settings_panel()
	_build_sound_panel()
	_build_piano_panel()
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	var vp := _get_vp_size()
	if _top_bar:
		_top_bar.size.x = vp.x
	if _tool_panel:
		_tool_panel.size.y = vp.y - 64
	if _info_panel:
		_info_panel.position.x = vp.x - 200
		_info_panel.size.y = vp.y - 64
	if _status_bar:
		_status_bar.position.y = vp.y - 24
		_status_bar.size.x = vp.x - 320
	if _library_panel:
		_library_panel.size.y = vp.y - 88
	if _piano_panel:
		_piano_panel.position.y = vp.y - 24 - PIANO_H
		_piano_panel.size.x = vp.x - 320
		_rebuild_piano_keys()


func _build_top_bar() -> void:
	var vp := _get_vp_size()
	var bar := _panel(Rect2(0, 0, vp.x, 64))
	_top_bar = bar

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 2)
	bar.add_child(vbox)

	# ── Row 1: title, tick, speed, pause, seed, clear, camera hint ──
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	# ── Row 2: map presets, color modes, settings, fullscreen, tokens ──
	var hbox2 := HBoxContainer.new()
	hbox2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox2.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox2)

	# Title
	var title := _label("🧬 Lifody", 13)
	title.custom_minimum_size = Vector2(90, 0)
	hbox.add_child(title)

	# Tick counter
	_tick_label = _label("Tick: 0", 12)
	_tick_label.custom_minimum_size = Vector2(80, 0)
	hbox.add_child(_tick_label)

	# Speed slider
	hbox.add_child(_label("Speed:", 11))
	_speed_slider = HSlider.new()
	_speed_slider.min_value = 1
	_speed_slider.max_value = 20
	_speed_slider.value = 5
	_speed_slider.custom_minimum_size = Vector2(120, 0)
	_speed_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(_speed_slider)

	# Pause button
	_pause_btn = _button("⏸ Pause", 11)
	_pause_btn.custom_minimum_size = Vector2(72, 0)
	hbox.add_child(_pause_btn)

	# Seed buttons
	for pattern in ["Random", "Glider", "R-Pentomino"]:
		var btn := _button(pattern, 10)
		btn.custom_minimum_size = Vector2(76, 0)
		btn.pressed.connect(func() -> void:
			seed_requested.emit(pattern.to_lower().replace("-", "_").replace(" ", "_"))
		)
		hbox.add_child(btn)

	# Clear button
	var clr := _button("🗑 Clear", 10)
	clr.custom_minimum_size = Vector2(60, 0)
	clr.pressed.connect(func() -> void: clear_requested.emit())
	hbox.add_child(clr)

	# Camera hint
	var cam_hint := _label("🖱 Wheel=zoom  MMB=pan  F=reset", 9)
	cam_hint.add_theme_color_override("font_color", DIM_COLOR)
	hbox.add_child(cam_hint)

	# ── Map mode + presets (row 2) ───────────────────────────────────────────
	var map_std_btn := _button("🗺 Map", 10)
	map_std_btn.tooltip_text = "Standard configurable region map"
	map_std_btn.custom_minimum_size = Vector2(52, 0)
	map_std_btn.pressed.connect(func() -> void:
		tonal.map_mode = TonalRegions.MAP_STANDARD
		grid.queue_redraw()
		_on_status("Standard map mode")
	)
	hbox2.add_child(map_std_btn)

	## Map presets (only meaningful in standard mode — click activates standard mode too)
	var preset_defs: Array = [
		["12Maj",    "All 12 roots, Major scale (4×3)",        "apply_preset_all_major"],
		["12Min",    "All 12 roots, Natural Minor (4×3)",       "apply_preset_all_minor"],
		["5ths",     "Circle of 5ths, all Major (4×3)",         "apply_preset_circle_of_5ths"],
		["7Modes",   "7 modes of C major (4×2)",                "apply_preset_7modes_c"],
		["Dorian",   "All 12 roots, Dorian mode (4×3)",         "apply_preset_all_dorian"],
		["Classic",  "Original 6 regions (3×2)",                "apply_preset_classic"],
	]
	for pd in preset_defs:
		var pb := _button(pd[0] as String, 9)
		pb.custom_minimum_size = Vector2(44, 0)
		pb.tooltip_text = pd[1] as String
		var method_name: String = pd[2]
		var label: String = pd[0]
		pb.pressed.connect(func() -> void:
			tonal.map_mode = TonalRegions.MAP_STANDARD
			tonal.call(method_name)
			grid.queue_redraw()
			_on_status("Map preset: " + label)
		)
		hbox2.add_child(pb)

	var map_isle_btn := _button("🏝 Islands", 10)
	map_isle_btn.tooltip_text = "Island map: 12 note islands, paint tonal zones freely"
	map_isle_btn.custom_minimum_size = Vector2(64, 0)
	map_isle_btn.pressed.connect(func() -> void:
		tonal.map_mode = TonalRegions.MAP_ISLAND
		grid.queue_redraw()
		_on_status("Island map mode — use Paint Zone tool to draw zones")
	)
	hbox2.add_child(map_isle_btn)

	# ── Cell color mode toggle ─────────────────────────────────────────────────
	var col_age_btn := _button("🎨 Age", 10)
	col_age_btn.tooltip_text = "Color cells by age (green → yellow)"
	col_age_btn.custom_minimum_size = Vector2(50, 0)
	col_age_btn.pressed.connect(func() -> void:
		grid.color_by_note = false
		grid.queue_redraw()
		_on_status("Cell color: by age")
	)
	hbox2.add_child(col_age_btn)

	var col_note_btn := _button("🎵 Note", 10)
	col_note_btn.tooltip_text = "Color cells by musical pitch (12-color wheel)"
	col_note_btn.custom_minimum_size = Vector2(54, 0)
	col_note_btn.pressed.connect(func() -> void:
		grid.color_by_note = true
		grid.queue_redraw()
		_on_status("Cell color: by note pitch")
	)
	hbox2.add_child(col_note_btn)

	# ── Settings button ────────────────────────────────────────────────────────
	var cfg_btn := _button("⚙", 12)
	cfg_btn.tooltip_text = "Settings: grid size, life rules, audio"
	cfg_btn.custom_minimum_size = Vector2(26, 0)
	cfg_btn.pressed.connect(func() -> void:
		if _settings_panel:
			_settings_panel.visible = not _settings_panel.visible
			if _settings_panel.visible and _sound_panel:
				_sound_panel.visible = false
	)
	hbox2.add_child(cfg_btn)

	# ── Sound button ────────────────────────────────────────────────────────────
	var snd_btn := _button("🎵", 12)
	snd_btn.tooltip_text = "Sound: instruments & genre presets"
	snd_btn.custom_minimum_size = Vector2(26, 0)
	snd_btn.pressed.connect(func() -> void:
		if _sound_panel:
			_sound_panel.visible = not _sound_panel.visible
			if _sound_panel.visible and _settings_panel:
				_settings_panel.visible = false
	)
	hbox2.add_child(snd_btn)

	# ── Fullscreen button ──────────────────────────────────────────────────────
	var fs_btn := _button("⛶", 12)
	fs_btn.tooltip_text = "Toggle fullscreen (F11)"
	fs_btn.custom_minimum_size = Vector2(26, 0)
	fs_btn.pressed.connect(func() -> void:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	)
	hbox2.add_child(fs_btn)

	# Token display
	_token_label = _label("🎭 ×1", 12)
	_token_label.custom_minimum_size = Vector2(50, 0)
	hbox2.add_child(_token_label)


func _build_tool_panel() -> void:
	var vp := _get_vp_size()
	var panel := _panel(Rect2(0, 64, 120, vp.y - 64))
	_tool_panel = panel
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	vbox.add_child(_label("— TOOLS —", 10))

	var tool_defs: Array = [
		[ToolManager.Tool.SELECT,         "🖱 Select",      "Click to inspect clusters"],
		[ToolManager.Tool.DRAW,           "✏ Draw",         "Paint cells (L=draw, R=erase). Pitch set below."],
		[ToolManager.Tool.ERASE,          "⬛ Erase",        "Click/drag to erase cells"],
		[ToolManager.Tool.PAINT_REGION,   "🖌 Paint Zone",  "Paint tonal zones (select region below)"],
		[ToolManager.Tool.HEAT_HOT,       "🌡 Hot Zone",    "Draw hot area (L=hot, R=cool)"],
		[ToolManager.Tool.HEAT_COLD,      "❄ Cold Zone",    "Draw cold area"],
		[ToolManager.Tool.BEACON_ATTRACT, "🧲 Attractor",   "Place attractor beacon (max 5)"],
		[ToolManager.Tool.BEACON_REPEL,   "↩ Repeller",     "Place repeller beacon"],
		[ToolManager.Tool.DNA_INJECT,     "💉 Inject DNA",  "Inject melody into grid"],
		[ToolManager.Tool.REWIND,         "⏪ Rewind",       "Rewind a cluster (%d left)"],
		[ToolManager.Tool.SPLIT,          "✂ Split",         "Split cluster along a line"],
	]

	_tool_buttons = []
	_tool_ids = []
	for td in tool_defs:
		var btn := _button(td[1] as String, 10)
		btn.custom_minimum_size = Vector2(110, 24)
		btn.tooltip_text = td[2] as String
		var tid: int = td[0]
		btn.pressed.connect(func() -> void: _select_tool(tid))
		vbox.add_child(btn)
		_tool_buttons.append(btn)
		_tool_ids.append(tid)

	_highlight_tool(ToolManager.Tool.SELECT)

	# ── Piano keyboard for Draw tool ─────────────────────────────────────────
	vbox.add_child(HSeparator.new())
	vbox.add_child(_label("Draw pitch:", 10))
	_build_piano_keyboard(vbox)

	# Chromatic / Scale toggle
	var chrom_btn := _button("Chromatic ✓", 9)
	chrom_btn.custom_minimum_size = Vector2(100, 20)
	chrom_btn.tooltip_text = "Toggle: use all 12 notes vs region scale"
	chrom_btn.pressed.connect(func() -> void:
		tool_mgr.draw_chromatic = not tool_mgr.draw_chromatic
		chrom_btn.text = "Chromatic ✓" if tool_mgr.draw_chromatic else "Scale only"
	)
	vbox.add_child(chrom_btn)

	# ── Listening zone ────────────────────────────────────────────────────
	vbox.add_child(HSeparator.new())
	var listen_hdr := HBoxContainer.new()
	listen_hdr.add_child(_label("Listen:", 10))
	var zone_btn := _button("🎧 Zone", 9)
	zone_btn.custom_minimum_size = Vector2(52, 18)
	zone_btn.tooltip_text = "Toggle: hear whole grid (∞) vs mouse zone only"
	zone_btn.pressed.connect(func() -> void:
		if grid.listening_radius == 0:
			grid.listening_radius = 20
			zone_btn.text = "🎧 Zone"
		else:
			grid.listening_radius = 0
			zone_btn.text = "🔊 All"
	)
	listen_hdr.add_child(zone_btn)
	vbox.add_child(listen_hdr)
	vbox.add_child(_label("Radius:", 10))
	var listen_hb := HBoxContainer.new()
	var listen_slider := HSlider.new()
	listen_slider.min_value = 0
	listen_slider.max_value = 50
	listen_slider.value = 20
	listen_slider.custom_minimum_size = Vector2(70, 0)
	listen_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var listen_val_lbl := _label("20", 10)
	listen_val_lbl.custom_minimum_size = Vector2(22, 0)
	listen_slider.value_changed.connect(func(v: float) -> void:
		var r: int = int(v)
		grid.listening_radius = r
		listen_val_lbl.text = "∞" if r == 0 else str(r)
	)
	listen_hb.add_child(listen_slider)
	listen_hb.add_child(listen_val_lbl)
	vbox.add_child(listen_hb)

	# ── Paint Zone region selector ─────────────────────────────────────────
	vbox.add_child(HSeparator.new())
	vbox.add_child(_label("Paint zone:", 10))
	_build_region_selector(vbox)

	vbox.add_child(HSeparator.new())
	vbox.add_child(_label("— EVENTS —", 10))

	var event_defs: Array = [
		["☄ Meteorite",  "event_meteorite"],
		["🤝 Resonance",  "event_resonance"],
		["❄ Freeze",      "event_freeze"],
		["🌊 Mut. Wave",  "event_mutation_wave"],
		["🎭 Mirror",     "event_mirror"],
	]
	for ed in event_defs:
		var btn := _button(ed[0] as String, 10)
		btn.custom_minimum_size = Vector2(100, 24)
		var ev: String = ed[1]
		btn.pressed.connect(func() -> void:
			event_requested.emit(ev, tool_mgr.selected_cluster_id)
		)
		vbox.add_child(btn)


func _build_piano_keyboard(parent: VBoxContainer) -> void:
	## 12 note buttons in two rows (white / black keys visual grouping).
	const NAMES: Array = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
	const IS_BLACK: Array = [false,true,false,true,false,false,true,false,true,false,true,false]

	var grid_container := GridContainer.new()
	grid_container.columns = 6
	parent.add_child(grid_container)

	for i in 12:
		var btn := Button.new()
		btn.text = NAMES[i]
		btn.add_theme_font_size_override("font_size", 9)
		btn.custom_minimum_size = Vector2(15, 20)
		# White or black key colouring
		var style := StyleBoxFlat.new()
		style.set_border_width_all(1)
		style.corner_radius_top_left = 2
		style.corner_radius_top_right = 2
		style.corner_radius_bottom_left = 2
		style.corner_radius_bottom_right = 2
		if IS_BLACK[i]:
			style.bg_color = Color(0.15, 0.15, 0.18)
			style.border_color = Color(0.5, 0.5, 0.6)
			btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
		else:
			style.bg_color = Color(0.88, 0.88, 0.92)
			style.border_color = Color(0.4, 0.4, 0.5)
			btn.add_theme_color_override("font_color", Color(0.05, 0.05, 0.1))
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.4, 0.7, 1.0)
		btn.add_theme_stylebox_override("hover", hover)
		var pitch_idx: int = i
		btn.pressed.connect(func() -> void:
			tool_mgr.draw_pitch = pitch_idx
			tool_mgr.set_tool(ToolManager.Tool.DRAW)
			_highlight_tool(ToolManager.Tool.DRAW)
			# Preview note
			if audio_engine:
				audio_engine.play_midi_note(60 + pitch_idx, 0.4, 0.7)
			_on_status("Draw pitch: %s (key 9 to activate Draw tool)" % NAMES[pitch_idx])
		)
		grid_container.add_child(btn)


func _build_region_selector(parent: VBoxContainer) -> void:
	## 8 buttons: 6 common tonal regions + Chromatic + Erase (in a 4-column grid).
	## IDs use the new formula: root * SCALE_COUNT + scale_type_idx.
	## C Maj=0, G Maj=77, D Maj=22, A Nat.Min=100, E Nat.Min=45, E Phr=47, Chr=132, Erase=-1
	const RLABELS: Array = ["CMaj", "GMaj", "DMaj", "AMin", "EMin", "EPhr", "Chr", "✕"]
	const RIDS:    Array  = [0, 77, 22, 100, 45, 47, 132, -1]
	const RCOLORS: Array  = [
		Color(0.80, 0.15, 0.15), Color(0.15, 0.70, 0.20), Color(0.15, 0.25, 0.85),
		Color(0.85, 0.75, 0.10), Color(0.75, 0.15, 0.80), Color(0.10, 0.75, 0.80),
		Color(0.55, 0.55, 0.55), Color(0.35, 0.35, 0.40),
	]
	var grid_c := GridContainer.new()
	grid_c.columns = 4
	parent.add_child(grid_c)

	for i in 8:
		var btn := Button.new()
		btn.text = RLABELS[i]
		btn.add_theme_font_size_override("font_size", 8)
		btn.custom_minimum_size = Vector2(26, 18)
		var style := StyleBoxFlat.new()
		style.bg_color = RCOLORS[i]
		style.bg_color.a = 0.75
		style.set_border_width_all(1)
		style.border_color = Color(0.8, 0.8, 0.9, 0.4)
		style.corner_radius_top_left = 2
		style.corner_radius_top_right = 2
		style.corner_radius_bottom_left = 2
		style.corner_radius_bottom_right = 2
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate() as StyleBoxFlat
		hover.border_color = Color(1.0, 1.0, 1.0, 0.8)
		hover.border_width_left = 2
		hover.border_width_right = 2
		hover.border_width_top = 2
		hover.border_width_bottom = 2
		btn.add_theme_stylebox_override("hover", hover)
		var rid: int = RIDS[i]
		var lbl: String = RLABELS[i]
		btn.pressed.connect(func() -> void:
			tool_mgr.paint_region_id = rid
			tool_mgr.set_tool(ToolManager.Tool.PAINT_REGION)
			_highlight_tool(ToolManager.Tool.PAINT_REGION)
			_on_status("Paint zone: %s (drag to paint)" % lbl)
		)
		grid_c.add_child(btn)


func _build_info_panel() -> void:
	var vp := _get_vp_size()
	var panel := _panel(Rect2(vp.x - 200, 64, 200, vp.y - 64))
	_info_panel = panel
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	scroll.add_child(vbox)

	vbox.add_child(_label("CLUSTERS", 11))
	_cluster_list = VBoxContainer.new()
	_cluster_list.add_theme_constant_override("separation", 2)
	vbox.add_child(_cluster_list)

	vbox.add_child(HSeparator.new())
	vbox.add_child(_label("SELECTED", 11))

	_selected_info = VBoxContainer.new()
	_selected_info.add_theme_constant_override("separation", 2)
	vbox.add_child(_selected_info)

	# Library button
	_show_library_btn = _button("📚 Library", 10)
	_show_library_btn.custom_minimum_size = Vector2(90, 24)
	_show_library_btn.pressed.connect(_toggle_library)
	vbox.add_child(_show_library_btn)


func _build_status_bar() -> void:
	var vp := _get_vp_size()
	var bar := _panel(Rect2(120, vp.y - 24, vp.x - 320, 24))
	_status_bar = bar
	_status_label = _label("Ready. Seed the grid to begin.", 11)
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status_label.clip_text = true
	bar.add_child(_status_label)


func _build_settings_panel() -> void:
	_settings_panel = _panel(Rect2(140, 72, 520, 400))
	_settings_panel.visible = false

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 5)
	_settings_panel.add_child(vbox)

	# Header
	var hdr := HBoxContainer.new()
	hdr.add_child(_label("⚙  SETTINGS", 13))
	var hdr_spacer := Control.new()
	hdr_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(hdr_spacer)
	var close_btn := _button("✕", 11)
	close_btn.custom_minimum_size = Vector2(24, 0)
	close_btn.pressed.connect(func() -> void: _settings_panel.visible = false)
	hdr.add_child(close_btn)
	vbox.add_child(hdr)
	vbox.add_child(HSeparator.new())

	# ── Grid Size ────────────────────────────────────────────────────────────
	vbox.add_child(_label("GRID SIZE  (applies immediately — grid is reseeded)", 11))
	var size_hb := HBoxContainer.new()
	size_hb.add_theme_constant_override("separation", 6)
	var size_presets: Array = [
		["Test Small\n10×10", 10, 10, 16],
		["Small\n40×30", 40, 30, 16],
		["Medium\n80×60", 80, 60, 12],
		["Large\n120×90", 120, 90, 8],
		["XL\n160×120", 160, 120, 6],
	]
	var size_btns: Array = []
	for sp in size_presets:
		var sb := _button(sp[0] as String, 9)
		sb.custom_minimum_size = Vector2(68, 36)
		if LifeGrid.GRID_W == (sp[1] as int) and LifeGrid.GRID_H == (sp[2] as int):
			sb.modulate = Color(0.4, 0.8, 1.0)
		var sw: int = sp[1]; var sh: int = sp[2]; var sc: int = sp[3]
		sb.pressed.connect(func() -> void:
			grid_resize_requested.emit(sw, sh, sc)
			_on_status("Grid → %d×%d  cell=%dpx" % [sw, sh, sc])
			for b in size_btns:
				b.modulate = Color.WHITE
			sb.modulate = Color(0.4, 0.8, 1.0)
		)
		size_hb.add_child(sb)
		size_btns.append(sb)
	vbox.add_child(size_hb)
	vbox.add_child(HSeparator.new())

	# ── Life Rules ───────────────────────────────────────────────────────────
	vbox.add_child(_label("LIFE RULES  (takes effect on next tick)", 11))

	# Will be populated below — defined here so preset closures can reference them
	var birth_btns: Array = []
	var surv_btns: Array = []

	# Rule presets row
	var rp_hb := HBoxContainer.new()
	rp_hb.add_theme_constant_override("separation", 4)
	rp_hb.add_child(_label("Preset:", 10))
	var rule_presets: Array = [
		["Conway",    [3],          [2, 3]],
		["HighLife",  [3, 6],       [2, 3]],
		["Day&Night", [3, 6, 7, 8], [3, 4, 6, 7, 8]],
		["Maze",      [3],          [1, 2, 3, 4, 5]],
		["Life 34",   [3, 4],       [3, 4]],
	]
	for rp in rule_presets:
		var rb := _button(rp[0] as String, 9)
		rb.custom_minimum_size = Vector2(58, 20)
		var rb_b: Array = rp[1]; var rb_s: Array = rp[2]
		rb.pressed.connect(func() -> void:
			grid.birth_rule    = rb_b.duplicate()
			grid.survival_rule = rb_s.duplicate()
			for i in 9:
				(birth_btns[i] as Button).modulate = Color(0.4, 0.8, 1.0) if rb_b.has(i) else Color.WHITE
				(surv_btns[i] as Button).modulate  = Color(0.4, 0.8, 1.0) if rb_s.has(i) else Color.WHITE
			_on_status("Rules: B%s / S%s" % [_rule_str(rb_b), _rule_str(rb_s)])
		)
		rp_hb.add_child(rb)
	vbox.add_child(rp_hb)

	# Birth toggles
	var b_hb := HBoxContainer.new()
	b_hb.add_theme_constant_override("separation", 2)
	b_hb.add_child(_label("Birth  B:", 10))
	for i in 9:
		var bt := _button(str(i), 10)
		bt.custom_minimum_size = Vector2(26, 22)
		bt.modulate = Color(0.4, 0.8, 1.0) if grid.birth_rule.has(i) else Color.WHITE
		var bc: int = i
		bt.pressed.connect(func() -> void:
			if grid.birth_rule.has(bc):
				grid.birth_rule.erase(bc)
				bt.modulate = Color.WHITE
			else:
				grid.birth_rule.append(bc)
				grid.birth_rule.sort()
				bt.modulate = Color(0.4, 0.8, 1.0)
			_on_status("Birth rule: B%s" % _rule_str(grid.birth_rule))
		)
		b_hb.add_child(bt)
		birth_btns.append(bt)
	vbox.add_child(b_hb)

	# Survival toggles
	var s_hb := HBoxContainer.new()
	s_hb.add_theme_constant_override("separation", 2)
	s_hb.add_child(_label("Survive S:", 10))
	for i in 9:
		var st := _button(str(i), 10)
		st.custom_minimum_size = Vector2(26, 22)
		st.modulate = Color(0.4, 0.8, 1.0) if grid.survival_rule.has(i) else Color.WHITE
		var sc2: int = i
		st.pressed.connect(func() -> void:
			if grid.survival_rule.has(sc2):
				grid.survival_rule.erase(sc2)
				st.modulate = Color.WHITE
			else:
				grid.survival_rule.append(sc2)
				grid.survival_rule.sort()
				st.modulate = Color(0.4, 0.8, 1.0)
			_on_status("Survival rule: S%s" % _rule_str(grid.survival_rule))
		)
		s_hb.add_child(st)
		surv_btns.append(st)
	vbox.add_child(s_hb)
	vbox.add_child(HSeparator.new())

	# ── Audio ────────────────────────────────────────────────────────────────
	vbox.add_child(_label("AUDIO", 11))

	# Volume
	var vol_hb := HBoxContainer.new()
	vol_hb.add_child(_label("Volume:    ", 10))
	var vol_slider := HSlider.new()
	vol_slider.min_value = 0.0; vol_slider.max_value = 1.0; vol_slider.step = 0.01
	vol_slider.value = audio_engine.master_volume if audio_engine else 0.7
	vol_slider.custom_minimum_size = Vector2(180, 0)
	vol_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vol_lbl := _label("%d%%" % [int(vol_slider.value * 100)], 10)
	vol_lbl.custom_minimum_size = Vector2(38, 0)
	vol_slider.value_changed.connect(func(v: float) -> void:
		if audio_engine: audio_engine.master_volume = v
		vol_lbl.text = "%d%%" % [int(v * 100)]
	)
	vol_hb.add_child(vol_slider); vol_hb.add_child(vol_lbl)
	vbox.add_child(vol_hb)

	# Timbre (harmonic mix)
	var harm_hb := HBoxContainer.new()
	harm_hb.add_child(_label("Timbre:    ", 10))
	var harm_slider := HSlider.new()
	harm_slider.min_value = 0.0; harm_slider.max_value = 1.0; harm_slider.step = 0.01
	harm_slider.value = audio_engine.harmonic_mix if audio_engine else 1.0
	harm_slider.custom_minimum_size = Vector2(180, 0)
	harm_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var harm_lbl := _label("Rich", 10)
	harm_lbl.custom_minimum_size = Vector2(38, 0)
	harm_slider.value_changed.connect(func(v: float) -> void:
		if audio_engine: audio_engine.harmonic_mix = v
		harm_lbl.text = "Pure" if v < 0.25 else ("Mid" if v < 0.75 else "Rich")
	)
	harm_hb.add_child(harm_slider); harm_hb.add_child(harm_lbl)
	vbox.add_child(harm_hb)

	# Mutation rate
	var mut_hb := HBoxContainer.new()
	mut_hb.add_child(_label("Mutation:  ", 10))
	var mut_slider := HSlider.new()
	mut_slider.min_value = 0.01; mut_slider.max_value = 0.25; mut_slider.step = 0.005
	mut_slider.value = grid.base_mutation_rate if grid else 0.05
	mut_slider.custom_minimum_size = Vector2(180, 0)
	mut_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mut_lbl := _label("%d%%" % [int(mut_slider.value * 100)], 10)
	mut_lbl.custom_minimum_size = Vector2(38, 0)
	mut_slider.value_changed.connect(func(v: float) -> void:
		if grid: grid.base_mutation_rate = v
		mut_lbl.text = "%d%%" % [int(v * 100)]
	)
	mut_hb.add_child(mut_slider); mut_hb.add_child(mut_lbl)
	vbox.add_child(mut_hb)


func _rule_str(rule: Array) -> String:
	var s: String = ""
	for n in rule:
		s += str(n)
	return s


func _build_sound_panel() -> void:
	_sound_panel = _panel(Rect2(140, 72, 480, 320))
	_sound_panel.visible = false

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	_sound_panel.add_child(vbox)

	# Header
	var hdr := HBoxContainer.new()
	hdr.add_child(_label("🎵  SOUND", 13))
	var hdr_spacer := Control.new()
	hdr_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(hdr_spacer)
	var close_btn := _button("✕", 11)
	close_btn.custom_minimum_size = Vector2(24, 0)
	close_btn.pressed.connect(func() -> void: _sound_panel.visible = false)
	hdr.add_child(close_btn)
	vbox.add_child(hdr)
	vbox.add_child(HSeparator.new())

	# ── Instruments ───────────────────────────────────────────────────────────
	vbox.add_child(_label("INSTRUMENT", 11))
	var inst_grid := GridContainer.new()
	inst_grid.columns = 4
	inst_grid.add_theme_constant_override("h_separation", 4)
	inst_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(inst_grid)

	_instrument_btns = []
	var inst_names: Array = ["Synth", "Piano", "Organ", "Strings", "Bell", "Flute", "Bass", "Pad"]
	var inst_icons: Array = ["〰", "🎹", "🎸", "🎻", "🔔", "🪈", "🎸", "🌊"]
	for i in inst_names.size():
		var btn := _button("%s\n%s" % [inst_icons[i], inst_names[i]], 9)
		btn.custom_minimum_size = Vector2(100, 36)
		var idx: int = i
		btn.pressed.connect(func() -> void:
			if audio_engine:
				audio_engine.set_instrument(idx)
			_highlight_instrument(idx)
			_on_status("Instrument: %s" % inst_names[idx])
		)
		inst_grid.add_child(btn)
		_instrument_btns.append(btn)

	# Highlight current instrument on open
	if audio_engine:
		_highlight_instrument(audio_engine.current_instrument)
	vbox.add_child(HSeparator.new())

	# ── Genre Presets ─────────────────────────────────────────────────────────
	vbox.add_child(_label("GENRE PRESET  (sets instrument, tempo, mutation & tonal map)", 11))
	var genre_grid := GridContainer.new()
	genre_grid.columns = 4
	genre_grid.add_theme_constant_override("h_separation", 4)
	genre_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(genre_grid)

	# genre_defs: [label, icon, instrument_idx, tps, mutation, birth_rule, surv_rule, tonal_method]
	var genre_defs: Array = [
		["Classical", "🎼", 3, 4.0,  0.03, [3],          [2, 3],       "apply_preset_classic"],
		["Ambient",   "🌙", 7, 2.0,  0.02, [3],          [2, 3],       "apply_preset_all_major"],
		["Rock",      "🎸", 2, 8.0,  0.07, [3, 6],       [2, 3],       "apply_preset_circle_of_5ths"],
		["Jazz",      "🎷", 1, 6.0,  0.05, [3],          [2, 3],       "apply_preset_7modes_c"],
		["Bells",     "🔔", 4, 3.0,  0.04, [3],          [2, 3],       "apply_preset_classic"],
		["Orchestra", "🎶", 3, 5.0,  0.03, [3],          [2, 3],       "apply_preset_all_major"],
		["Chaos",     "⚡", 0, 12.0, 0.15, [3, 6, 7, 8], [3, 4, 6, 7, 8], "apply_preset_all_minor"],
		["Folk",      "🪈", 5, 5.0,  0.04, [3],          [2, 3],       "apply_preset_all_dorian"],
	]

	for gd in genre_defs:
		var gb := _button("%s %s" % [gd[1] as String, gd[0] as String], 10)
		gb.custom_minimum_size = Vector2(100, 28)
		var g_inst: int    = gd[2]
		var g_tps: float   = gd[3]
		var g_mut: float   = gd[4]
		var g_birth: Array = gd[5]
		var g_surv: Array  = gd[6]
		var g_tonal: String = gd[7]
		var g_name: String = gd[0]
		gb.pressed.connect(func() -> void:
			# Set instrument
			if audio_engine:
				audio_engine.set_instrument(g_inst)
			_highlight_instrument(g_inst)
			# Set tempo
			if grid:
				grid.tick_interval = 1.0 / g_tps
			if audio_engine:
				audio_engine.set_tempo(60.0 * g_tps * 0.5)
			if _speed_slider:
				_speed_slider.value = g_tps
			# Set mutation
			if grid:
				grid.base_mutation_rate = g_mut
			# Set life rules
			if grid:
				grid.birth_rule    = g_birth.duplicate()
				grid.survival_rule = g_surv.duplicate()
			# Set tonal map
			if tonal:
				tonal.map_mode = TonalRegions.MAP_STANDARD
				tonal.call(g_tonal)
				if grid:
					grid.queue_redraw()
			_on_status("Genre: %s — tempo %.0f BPM, mutation %d%%" % [
				g_name, g_tps * 30.0, int(g_mut * 100)])
		)
		genre_grid.add_child(gb)


func _highlight_instrument(idx: int) -> void:
	for i in _instrument_btns.size():
		(_instrument_btns[i] as Button).modulate = \
			Color(0.4, 0.8, 1.0) if i == idx else Color.WHITE


func _build_piano_panel() -> void:
	var vp := _get_vp_size()
	_piano_panel = _panel(Rect2(120, vp.y - 24 - PIANO_H, vp.x - 320, PIANO_H))
	_piano_container = Control.new()
	_piano_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_piano_panel.add_child(_piano_container)
	_rebuild_piano_keys()


func _rebuild_piano_keys() -> void:
	if _piano_container == null:
		return
	# Free old key rects and labels
	var old := _piano_container.get_children()
	for ch in old:
		ch.free()
	_piano_keys.clear()
	# Keep brightness values — they'll naturally fade out

	var pw: float = _piano_panel.size.x

	# Count white keys in range to determine key width
	var white_count: int = 0
	for m in range(PIANO_MIDI_LO, PIANO_MIDI_HI + 1):
		if not _is_black_key(m):
			white_count += 1
	if white_count == 0:
		return

	var wkw: float = pw / float(white_count)  # white key width
	var wkh: float = float(PIANO_H) - 2.0      # white key height
	var bkw: float = wkw * 0.56               # black key width
	var bkh: float = wkh * 0.60               # black key height
	var font := ThemeDB.fallback_font

	# ── White keys ────────────────────────────────────────────────────────
	var wi: int = 0
	for m in range(PIANO_MIDI_LO, PIANO_MIDI_HI + 1):
		if _is_black_key(m):
			continue
		var rect := ColorRect.new()
		rect.color    = Color(0.93, 0.93, 0.97)
		rect.position = Vector2(wi * wkw + 0.5, 1.0)
		rect.size     = Vector2(wkw - 1.0, wkh)
		_piano_container.add_child(rect)
		_piano_keys[m] = rect
		# Top highlight strip
		var whi := ColorRect.new()
		whi.color    = Color(1.0, 1.0, 1.0, 0.55)
		whi.position = Vector2(0.0, 0.0)
		whi.size     = Vector2(wkw - 1.0, 2.5)
		rect.add_child(whi)
		# Right separator
		var sep := ColorRect.new()
		sep.color    = Color(0.30, 0.30, 0.40, 0.55)
		sep.position = Vector2(wkw - 1.5, 0.0)
		sep.size     = Vector2(1.0, wkh)
		rect.add_child(sep)
		# Octave label on every C
		if m % 12 == 0:
			var lbl := Label.new()
			lbl.text   = "C%d" % [(m / 12) - 1]
			lbl.add_theme_font_size_override("font_size", 8)
			lbl.add_theme_color_override("font_color", Color(0.30, 0.30, 0.42))
			lbl.position = Vector2(1.0, wkh - 13.0)
			lbl.size     = Vector2(wkw - 2.0, 12.0)
			rect.add_child(lbl)
		wi += 1

	# ── Black keys (rendered after so they appear on top) ─────────────────
	for m in range(PIANO_MIDI_LO, PIANO_MIDI_HI + 1):
		if not _is_black_key(m):
			continue
		var note: int = m % 12
		var oct_from_lo: int = (m - PIANO_MIDI_LO) / 12
		var oct_x: float = float(oct_from_lo * 7) * wkw
		# Center position of this black key within its octave (in white-key-width units)
		var center_mult: float
		match note:
			1:  center_mult = 1.0   # C# — between C(0) and D(1)
			3:  center_mult = 2.0   # D# — between D(1) and E(2)
			6:  center_mult = 4.0   # F# — between F(3) and G(4)
			8:  center_mult = 5.0   # G# — between G(4) and A(5)
			10: center_mult = 6.0   # A# — between A(5) and B(6)
			_:  center_mult = 0.0
		var bx: float = oct_x + center_mult * wkw - bkw * 0.5
		# Drop shadow (added before key so it renders behind it)
		var shadow := ColorRect.new()
		shadow.color    = Color(0.0, 0.0, 0.0, 0.45)
		shadow.position = Vector2(bx + 1.5, 2.0)
		shadow.size     = Vector2(bkw, bkh + 3.0)
		_piano_container.add_child(shadow)
		# Main black key
		var rect := ColorRect.new()
		rect.color    = Color(0.10, 0.10, 0.16)
		rect.position = Vector2(bx, 1.0)
		rect.size     = Vector2(bkw, bkh)
		_piano_container.add_child(rect)
		_piano_keys[m] = rect
		# Top specular highlight
		var bhi := ColorRect.new()
		bhi.color    = Color(0.32, 0.32, 0.48, 0.65)
		bhi.position = Vector2(1.5, 0.0)
		bhi.size     = Vector2(bkw - 3.0, 3.0)
		rect.add_child(bhi)


func _is_black_key(midi: int) -> bool:
	var note: int = midi % 12
	return note == 1 or note == 3 or note == 6 or note == 8 or note == 10


func _process(delta: float) -> void:
	if _piano_keys.is_empty() or audio_engine == null:
		return
	if audio_engine.active_midi_notes.is_empty() and _piano_brightness.is_empty():
		return

	# Set brightness for currently sounding notes
	for midi in audio_engine.active_midi_notes:
		if midi >= PIANO_MIDI_LO and midi <= PIANO_MIDI_HI:
			_piano_brightness[midi] = 1.0

	# Decay all brightnesses and collect finished ones
	var done: Array = []
	for midi in _piano_brightness:
		_piano_brightness[midi] = maxf(_piano_brightness[midi] - delta * 4.0, 0.0)
		if _piano_brightness[midi] < 0.004:
			done.append(midi)
	for midi in done:
		_piano_brightness.erase(midi)

	# Update key colors
	for midi in _piano_keys:
		var brightness: float = _piano_brightness.get(midi, 0.0)
		var rect := _piano_keys[midi] as ColorRect
		if _is_black_key(midi):
			rect.color = Color(0.10, 0.10, 0.16).lerp(Color(0.02, 0.88, 1.00), brightness)
		else:
			rect.color = Color(0.93, 0.93, 0.97).lerp(Color(0.28, 1.00, 0.48), brightness)


func _build_library_panel() -> void:
	var vp := _get_vp_size()
	_library_panel = _panel(Rect2(120, 64, 280, vp.y - 88))
	_library_panel.visible = false
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	_library_panel.add_child(vbox)

	var hdr := HBoxContainer.new()
	hdr.add_child(_label("📚 MELODY LIBRARY", 12))
	var close := _button("✕", 10)
	close.custom_minimum_size = Vector2(24, 0)
	close.pressed.connect(_toggle_library)
	hdr.add_child(close)
	vbox.add_child(hdr)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_library_list = VBoxContainer.new()
	_library_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_library_list)


# ────────────────────────────────────────────────────────────────────────────
#  Signal wiring
# ────────────────────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	_speed_slider.value_changed.connect(func(v: float) -> void:
		speed_changed.emit(v)
	)
	_pause_btn.pressed.connect(func() -> void:
		pause_toggled.emit()
		_pause_btn.text = "▶ Resume" if not grid.running else "⏸ Pause"
	)
	tool_mgr.status_message.connect(_on_status)
	catalyst.status_message.connect(_on_status)
	catalyst.event_tokens_changed.connect(_on_tokens_changed)
	cluster_mgr.clusters_updated.connect(update_cluster_display)


# ────────────────────────────────────────────────────────────────────────────
#  Public update methods
# ────────────────────────────────────────────────────────────────────────────

func update_tick(n: int) -> void:
	if _tick_label:
		_tick_label.text = "Tick: %d" % n


func update_cluster_display(clusters: Array) -> void:
	if not is_instance_valid(_cluster_list):
		return
	# Clear old entries
	for ch in _cluster_list.get_children():
		ch.queue_free()
	# Top 8 clusters by size
	var sorted: Array = clusters.duplicate()
	sorted.sort_custom(func(a: Cluster, b: Cluster) -> bool:
		return a.get_size() > b.get_size()
	)
	var limit: int = mini(sorted.size(), 8)
	for i in range(limit):
		var cl := sorted[i] as Cluster
		var row := _cluster_row(cl)
		_cluster_list.add_child(row)

	_refresh_selected_info()


func _cluster_row(cl: Cluster) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)

	var lbl := _label("%d: sz=%d f=%.0f" % [cl.id, cl.get_size(), cl.fitness_score], 10)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lbl)

	var sel_btn := _button("●", 9)
	sel_btn.custom_minimum_size = Vector2(18, 18)
	sel_btn.tooltip_text = "Select"
	sel_btn.pressed.connect(func() -> void:
		tool_mgr.selected_cluster_id = cl.id
		_refresh_selected_info()
	)
	hb.add_child(sel_btn)

	var like_btn := _button("♥", 9)
	like_btn.custom_minimum_size = Vector2(18, 18)
	like_btn.tooltip_text = "Like (+15 fitness)"
	like_btn.pressed.connect(func() -> void:
		like_cluster.emit(cl.id)
		fitness_mgr.like_cluster(cl.id)
	)
	hb.add_child(like_btn)

	var mute_btn := _button("🔇", 9)
	mute_btn.custom_minimum_size = Vector2(18, 18)
	mute_btn.tooltip_text = "Mute (-20 fitness)"
	mute_btn.pressed.connect(func() -> void:
		mute_cluster.emit(cl.id)
		fitness_mgr.mute_cluster(cl.id)
	)
	hb.add_child(mute_btn)

	var save_btn := _button("💾", 9)
	save_btn.custom_minimum_size = Vector2(18, 18)
	save_btn.tooltip_text = "Save melody to library"
	save_btn.pressed.connect(func() -> void:
		fitness_mgr.save_melody(cl.id)
		_refresh_library()
		_on_status("Melody saved to library!")
	)
	hb.add_child(save_btn)

	return hb


func _refresh_selected_info() -> void:
	if not is_instance_valid(_selected_info):
		return
	for ch in _selected_info.get_children():
		ch.queue_free()

	var cid: int = tool_mgr.selected_cluster_id
	if cid < 0:
		_selected_info.add_child(_label("(none)", 10))
		return

	var cl := cluster_mgr.get_cluster_by_id(cid)
	if cl == null:
		_selected_info.add_child(_label("(cluster gone)", 10))
		return

	var info_lines: Array = [
		"ID: %d  State: %s" % [cl.id, cl.state],
		"Size: %d  Density: %.2f" % [cl.get_size(), cl.get_density()],
		"Age: %d ticks" % [cl.get_age(grid.tick)],
		"Fitness: %.1f / 100" % [cl.fitness_score],
		"Region: %s" % [tonal.get_region_name(tonal.get_region_id(
			(cl.cells[0] as Vector2i).x,
			(cl.cells[0] as Vector2i).y
		)) if not cl.cells.is_empty() else "?"],
		"Melody: %d notes" % [cl.melody.size()],
	]
	for line in info_lines:
		_selected_info.add_child(_label(line, 10))

	# Fitness bar
	var bar_lbl := _label("", 10)
	var filled: int = int(cl.fitness_score / 5.0)
	bar_lbl.text = "[" + "█".repeat(filled) + "░".repeat(20 - filled) + "]"
	_selected_info.add_child(bar_lbl)

	# Freeze button
	var freeze_btn := _button("❄ Freeze cluster", 10)
	freeze_btn.pressed.connect(func() -> void:
		event_requested.emit("event_freeze", cid)
	)
	_selected_info.add_child(freeze_btn)

	var mirror_btn := _button("🎭 Mirror cluster", 10)
	mirror_btn.pressed.connect(func() -> void:
		event_requested.emit("event_mirror", cid)
	)
	_selected_info.add_child(mirror_btn)


func _refresh_library() -> void:
	if not is_instance_valid(_library_list):
		return
	for ch in _library_list.get_children():
		ch.queue_free()

	for i in range(fitness_mgr.melody_library.size()):
		var entry: Dictionary = fitness_mgr.melody_library[i]
		var hb := HBoxContainer.new()
		var lbl := _label(entry["name"] as String, 10)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(lbl)

		var play_btn := _button("▶", 9)
		play_btn.custom_minimum_size = Vector2(18, 0)
		var idx := i
		play_btn.pressed.connect(func() -> void:
			_play_library_entry(idx)
		)
		hb.add_child(play_btn)

		var del_btn := _button("✕", 9)
		del_btn.custom_minimum_size = Vector2(18, 0)
		del_btn.pressed.connect(func() -> void:
			fitness_mgr.delete_library_entry(idx)
			_refresh_library()
		)
		hb.add_child(del_btn)
		_library_list.add_child(hb)


func _play_library_entry(idx: int) -> void:
	if idx < 0 or idx >= fitness_mgr.melody_library.size():
		return
	var entry: Dictionary = fitness_mgr.melody_library[idx]
	var melody: Array = entry["melody"]
	if melody.is_empty():
		return
	# Play first few notes sequentially
	var delay: float = 0.0
	for note_raw in melody.slice(0, 8):
		var note := note_raw as DNANote
		var midi: int = 60 + note.pitch   # simple C4 + offset preview
		var dur: float = float(note.duration) * 0.15
		# Schedule with delay via timer
		var t := get_tree().create_timer(delay)
		t.timeout.connect(func() -> void:
			audio_engine.play_midi_note(midi, dur, float(note.velocity) / 127.0)
		)
		delay += dur * 0.9

var audio_engine: AudioEngine = null

func set_audio_engine(ae: AudioEngine) -> void:
	audio_engine = ae


# ────────────────────────────────────────────────────────────────────────────
#  Misc handlers
# ────────────────────────────────────────────────────────────────────────────

func _on_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg


func _on_tokens_changed(count: int) -> void:
	if _token_label:
		_token_label.text = "🎭 ×%d" % count


func _select_tool(tid: int) -> void:
	tool_mgr.set_tool(tid)
	_highlight_tool(tid)


func _highlight_tool(tid: int) -> void:
	for i in _tool_buttons.size():
		var btn := _tool_buttons[i] as Button
		btn.modulate = Color(0.4, 0.8, 1.0) if _tool_ids[i] == tid else Color.WHITE


func _toggle_library() -> void:
	_library_panel.visible = not _library_panel.visible
	if _library_panel.visible:
		_refresh_library()


# ────────────────────────────────────────────────────────────────────────────
#  UI factory helpers
# ────────────────────────────────────────────────────────────────────────────

func _panel(rect: Rect2) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = Color(0.25, 0.25, 0.35)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	p.add_theme_stylebox_override("panel", style)
	add_child(p)
	return p


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
	var style := StyleBoxFlat.new()
	style.bg_color = BTN_NORMAL
	style.border_color = Color(0.3, 0.3, 0.45)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	btn.add_theme_stylebox_override("normal", style)
	var hover_style := style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.22, 0.22, 0.32)
	btn.add_theme_stylebox_override("hover", hover_style)
	return btn
