class_name GameUI
extends CanvasLayer

## HUD layout:
##   Left  (260px) — TabContainer: Tools / World / Sound
##   Right (260px) — Cluster Evolution Panel: sparklines + live cluster cards
##   Top   (44px)  — minimal single-row bar
##   Bottom         — piano visualiser + status bar

signal seed_requested(pattern: String)
signal clear_requested
signal speed_changed(tps: float)
signal pause_toggled
signal like_cluster(cluster_id: int)
signal mute_cluster(cluster_id: int)
signal save_melody_requested(cluster_id: int)
signal event_requested(event_name: String, cluster_id: int)
signal grid_resize_requested(w: int, h: int, cs: int)
signal quad_mode_requested
signal chips_mode_requested

var grid: LifeGrid = null
var cluster_mgr: ClusterManager = null
var fitness_mgr: FitnessManager = null
var tool_mgr: ToolManager = null
var catalyst: CatalystEvents = null
var tonal: TonalRegions = null

# ── Cached nodes ──────────────────────────────────────────────────────────────
var _tick_label: Label = null
var _speed_slider: HSlider = null
var _pause_btn: Button = null
var _tool_buttons: Array = []
var _tool_ids: Array = []
var _status_label: Label = null
var _token_label: Label = null
var _library_panel: Panel = null
var _library_list: VBoxContainer = null
var _settings_panel: Panel = null
var _instrument_btns: Array = []
var _inst_option: OptionButton = null

# Evolution / right panel
var evolution_tracker: EvolutionTracker = null
var _sparkline_cells_lbl: Label = null
var _sparkline_fit_lbl: Label = null
var _milestone_lbl: Label = null
var _evo_rules_body: VBoxContainer = null
var _evo_rules_collapsed: bool = false
var _evo_cluster_cards_vbox: VBoxContainer = null  # dynamic cluster cards area
## Cached per-cluster-id card nodes: cid → {card, hdr, bar, notes_hb, notes: Array[Button], sep}
## Reused across ticks to avoid queue_free/alloc cycles (prev. ~750 Node frees/sec).
var _card_nodes: Dictionary = {}
var _last_sparkline_tick: int = -1

# Panels
var _top_bar: Panel = null
var _info_panel: Panel = null   # LEFT tabs panel
var _evo_panel: Panel = null    # RIGHT evolution panel
var _status_bar: Panel = null

const PANEL_BG  := Color(0.08, 0.08, 0.12, 0.88)
const BTN_NORMAL := Color(0.15, 0.15, 0.22)
const BTN_ACTIVE := Color(0.25, 0.55, 0.90)
const TEXT_COLOR := Color(0.88, 0.88, 0.95)
const DIM_COLOR  := Color(0.55, 0.55, 0.65)

const NOTE_NAMES: Array = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
const ARTIC_SHORT: Array = ["leg","stac","ten","acc"]

# ── Piano ─────────────────────────────────────────────────────────────────────
const PIANO_MIDI_LO: int = 36
const PIANO_MIDI_HI: int = 84
const PIANO_H: int = 74

var _piano_panel: Panel = null
var _piano_container: Control = null
var _piano_keys: Dictionary = {}
var _piano_brightness: Dictionary = {}

var audio_engine: AudioEngine = null


func setup(g: LifeGrid, cm: ClusterManager, fm: FitnessManager,
		   tm: ToolManager, ce: CatalystEvents, t: TonalRegions,
		   et: EvolutionTracker = null) -> void:
	grid = g; cluster_mgr = cm; fitness_mgr = fm
	tool_mgr = tm; catalyst = ce; tonal = t; evolution_tracker = et


func set_audio_engine(ae: AudioEngine) -> void:
	audio_engine = ae
	if is_instance_valid(_inst_option):
		_inst_option.selected = ae.current_instrument


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
	_build_info_panel()          # left tabs panel
	_build_cluster_evo_panel()   # right evolution panel
	_build_status_bar()
	_build_library_panel()
	_build_settings_panel()
	_build_piano_panel()
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	var vp := _get_vp_size()
	if _top_bar:
		_top_bar.size.x = vp.x
	if _info_panel:
		_info_panel.size.y = vp.y - 44
	if _evo_panel:
		_evo_panel.position.x = vp.x - 260
		_evo_panel.size.y = vp.y - 44
	if _status_bar:
		_status_bar.position.y = vp.y - 24
		_status_bar.size.x = vp.x - 520
	if _library_panel:
		_library_panel.size.y = vp.y - 68
	if _piano_panel:
		_piano_panel.position.y = vp.y - 24 - PIANO_H
		_piano_panel.size.x = vp.x - 520
		_rebuild_piano_keys()


# ── Top bar (44px single row) ─────────────────────────────────────────────────

func _build_top_bar() -> void:
	var vp := _get_vp_size()
	var bar := _panel(Rect2(0, 0, vp.x, 44))
	_top_bar = bar

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 6)
	bar.add_child(hbox)

	var title := _label("🧬 Lifody", 13)
	title.custom_minimum_size = Vector2(86, 0)
	hbox.add_child(title)

	_tick_label = _label("Tick: 0", 12)
	_tick_label.custom_minimum_size = Vector2(68, 0)
	hbox.add_child(_tick_label)

	hbox.add_child(_label("⚡", 11))
	_speed_slider = HSlider.new()
	_speed_slider.min_value = 1; _speed_slider.max_value = 20; _speed_slider.value = 5
	_speed_slider.custom_minimum_size = Vector2(100, 0)
	_speed_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(_speed_slider)

	_pause_btn = _button("▶ Play", 11)
	_pause_btn.custom_minimum_size = Vector2(72, 0)
	hbox.add_child(_pause_btn)

	var rnd_btn := _button("Random", 10)
	rnd_btn.custom_minimum_size = Vector2(56, 0)
	rnd_btn.pressed.connect(func() -> void: seed_requested.emit("random"))
	hbox.add_child(rnd_btn)

	var clr_btn := _button("Clear", 10)
	clr_btn.custom_minimum_size = Vector2(56, 0)
	clr_btn.tooltip_text = "Clear grid"
	clr_btn.pressed.connect(func() -> void: clear_requested.emit())
	hbox.add_child(clr_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var cfg_btn := _button("⚙", 12)
	cfg_btn.tooltip_text = "Settings: grid size, life rules, audio"
	cfg_btn.custom_minimum_size = Vector2(26, 0)
	cfg_btn.pressed.connect(func() -> void:
		if _settings_panel:
			_settings_panel.visible = not _settings_panel.visible
	)
	hbox.add_child(cfg_btn)

	var fs_btn := _button("⛶", 12)
	fs_btn.tooltip_text = "Toggle fullscreen (F11)"
	fs_btn.custom_minimum_size = Vector2(26, 0)
	fs_btn.pressed.connect(func() -> void:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	)
	hbox.add_child(fs_btn)

	var quad_btn := _button("⊞", 11)
	quad_btn.tooltip_text = "Switch to 4-panel grid mode"
	quad_btn.custom_minimum_size = Vector2(26, 0)
	quad_btn.pressed.connect(func() -> void: quad_mode_requested.emit())
	hbox.add_child(quad_btn)

	var chips_btn := _button("🎮", 11)
	chips_btn.tooltip_text = "Chips From Audio mode"
	chips_btn.custom_minimum_size = Vector2(26, 0)
	chips_btn.pressed.connect(func() -> void: chips_mode_requested.emit())
	hbox.add_child(chips_btn)

	_token_label = _label("🎭×1", 12)
	_token_label.custom_minimum_size = Vector2(44, 0)
	hbox.add_child(_token_label)


# ── Left panel: TabContainer (Tools / World / Sound) ─────────────────────────

func _build_info_panel() -> void:
	var vp := _get_vp_size()
	var panel := _panel(Rect2(0, 44, 260, vp.y - 44))
	_info_panel = panel

	var tc := TabContainer.new()
	tc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tc.add_theme_constant_override("side_margin", 2)
	panel.add_child(tc)

	_build_tools_tab(_make_tab_vbox(tc, "🔧"))
	_build_world_tab(_make_tab_vbox(tc, "🌍"))
	_build_sound_tab(_make_tab_vbox(tc, "🎵"))

	tc.tab_changed.connect(func(idx: int) -> void:
		_fade_in(tc.get_tab_control(idx))
	)


func _make_tab_vbox(tc: TabContainer, tab_name: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = tab_name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tc.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)
	sc.add_child(vb)
	return vb


# ── Tab: Tools ────────────────────────────────────────────────────────────────

func _build_tools_tab(vbox: VBoxContainer) -> void:
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
		[ToolManager.Tool.REWIND,         "⏪ Rewind",       "Rewind a cluster"],
		[ToolManager.Tool.SPLIT,          "✂ Split",         "Split cluster along a line"],
	]

	_tool_buttons = []
	_tool_ids = []
	var tg := GridContainer.new()
	tg.columns = 2
	tg.add_theme_constant_override("h_separation", 3)
	tg.add_theme_constant_override("v_separation", 3)
	for td in tool_defs:
		var btn := _button(td[1] as String, 10)
		btn.custom_minimum_size = Vector2(120, 24)
		btn.tooltip_text = td[2] as String
		var tid: int = td[0]
		btn.pressed.connect(func() -> void:
			_btn_press_anim(btn)
			_select_tool(tid)
		)
		tg.add_child(btn)
		_tool_buttons.append(btn)
		_tool_ids.append(tid)
	vbox.add_child(tg)

	_highlight_tool(ToolManager.Tool.DRAW)

	# Piano keyboard
	vbox.add_child(HSeparator.new())
	vbox.add_child(_label("Draw pitch:", 10))
	_build_piano_keyboard(vbox)

	var chrom_btn := _button("Chromatic ✓", 9)
	chrom_btn.custom_minimum_size = Vector2(248, 20)
	chrom_btn.tooltip_text = "Toggle: use all 12 notes vs region scale"
	chrom_btn.pressed.connect(func() -> void:
		tool_mgr.draw_chromatic = not tool_mgr.draw_chromatic
		chrom_btn.text = "Chromatic ✓" if tool_mgr.draw_chromatic else "Scale only"
	)
	vbox.add_child(chrom_btn)

	# Listening zone
	vbox.add_child(HSeparator.new())
	var listen_hdr := HBoxContainer.new()
	listen_hdr.add_child(_label("Listen:", 10))
	var zone_btn := _button("🎧 Zone", 9)
	zone_btn.custom_minimum_size = Vector2(52, 18)
	zone_btn.tooltip_text = "Toggle: hear whole grid vs mouse zone only"
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
	var listen_hb := HBoxContainer.new()
	var listen_slider := HSlider.new()
	listen_slider.min_value = 0; listen_slider.max_value = 50; listen_slider.value = 20
	listen_slider.custom_minimum_size = Vector2(190, 0)
	listen_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var listen_val_lbl := _label("20", 10)
	listen_val_lbl.custom_minimum_size = Vector2(22, 0)
	listen_slider.value_changed.connect(func(v: float) -> void:
		var r: int = int(v)
		grid.listening_radius = r
		listen_val_lbl.text = "∞" if r == 0 else str(r)
	)
	listen_hb.add_child(listen_slider); listen_hb.add_child(listen_val_lbl)
	vbox.add_child(listen_hb)

	# Paint zone
	vbox.add_child(HSeparator.new())
	vbox.add_child(_label("Paint zone:", 10))
	_build_region_selector(vbox)

	# Events
	vbox.add_child(HSeparator.new())
	vbox.add_child(_label("— EVENTS —", 10))
	var event_defs: Array = [
		["☄ Meteorite",  "event_meteorite"],
		["🤝 Resonance",  "event_resonance"],
		["❄ Freeze",      "event_freeze"],
		["🌊 Mut. Wave",  "event_mutation_wave"],
		["🎭 Mirror",     "event_mirror"],
	]
	var eg := GridContainer.new()
	eg.columns = 2
	eg.add_theme_constant_override("h_separation", 3)
	eg.add_theme_constant_override("v_separation", 3)
	for ed in event_defs:
		var btn := _button(ed[0] as String, 10)
		btn.custom_minimum_size = Vector2(120, 24)
		var ev: String = ed[1]
		btn.pressed.connect(func() -> void:
			_btn_press_anim(btn)
			event_requested.emit(ev, tool_mgr.selected_cluster_id)
		)
		eg.add_child(btn)
	vbox.add_child(eg)


func _build_piano_keyboard(parent: VBoxContainer) -> void:
	const NAMES: Array = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
	const IS_BLACK: Array = [false,true,false,true,false,false,true,false,true,false,true,false]
	var gc := GridContainer.new()
	gc.columns = 6
	parent.add_child(gc)
	for i in 12:
		var btn := Button.new()
		btn.text = NAMES[i]
		btn.add_theme_font_size_override("font_size", 9)
		btn.custom_minimum_size = Vector2(15, 20)
		var style := StyleBoxFlat.new()
		style.set_border_width_all(1)
		style.corner_radius_top_left = 2; style.corner_radius_top_right = 2
		style.corner_radius_bottom_left = 2; style.corner_radius_bottom_right = 2
		if IS_BLACK[i]:
			style.bg_color = Color(0.15, 0.15, 0.18); style.border_color = Color(0.5, 0.5, 0.6)
			btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
		else:
			style.bg_color = Color(0.88, 0.88, 0.92); style.border_color = Color(0.4, 0.4, 0.5)
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
			if audio_engine:
				audio_engine.play_midi_note(60 + pitch_idx, 0.4, 0.7)
			_on_status("Draw pitch: %s" % NAMES[pitch_idx])
		)
		gc.add_child(btn)


func _build_region_selector(parent: VBoxContainer) -> void:
	const RLABELS: Array = ["CMaj", "GMaj", "DMaj", "AMin", "EMin", "EPhr", "Chr", "✕"]
	const RIDS:    Array  = [0, 77, 22, 100, 45, 47, 132, -1]
	const RCOLORS: Array  = [
		Color(0.80,0.15,0.15), Color(0.15,0.70,0.20), Color(0.15,0.25,0.85),
		Color(0.85,0.75,0.10), Color(0.75,0.15,0.80), Color(0.10,0.75,0.80),
		Color(0.55,0.55,0.55), Color(0.35,0.35,0.40),
	]
	var gc := GridContainer.new()
	gc.columns = 4
	parent.add_child(gc)
	for i in 8:
		var btn := Button.new()
		btn.text = RLABELS[i]
		btn.add_theme_font_size_override("font_size", 8)
		btn.custom_minimum_size = Vector2(26, 18)
		var style := StyleBoxFlat.new()
		style.bg_color = RCOLORS[i]; style.bg_color.a = 0.75
		style.set_border_width_all(1); style.border_color = Color(0.8,0.8,0.9,0.4)
		style.corner_radius_top_left = 2; style.corner_radius_top_right = 2
		style.corner_radius_bottom_left = 2; style.corner_radius_bottom_right = 2
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate() as StyleBoxFlat
		hover.border_color = Color(1,1,1,0.8); hover.border_width_left = 2
		hover.border_width_right = 2; hover.border_width_top = 2; hover.border_width_bottom = 2
		btn.add_theme_stylebox_override("hover", hover)
		var rid: int = RIDS[i]; var lbl: String = RLABELS[i]
		btn.pressed.connect(func() -> void:
			tool_mgr.paint_region_id = rid
			tool_mgr.set_tool(ToolManager.Tool.PAINT_REGION)
			_highlight_tool(ToolManager.Tool.PAINT_REGION)
			_on_status("Paint zone: %s" % lbl)
		)
		gc.add_child(btn)


# ── Tab: World ────────────────────────────────────────────────────────────────

func _build_world_tab(vbox: VBoxContainer) -> void:
	vbox.add_child(_label("MAP MODE", 10))
	var map_hb := HBoxContainer.new()
	map_hb.add_theme_constant_override("separation", 4)
	var map_std_btn := _button("🗺 Standard", 10)
	map_std_btn.custom_minimum_size = Vector2(120, 24)
	map_std_btn.pressed.connect(func() -> void:
		tonal.map_mode = TonalRegions.MAP_STANDARD; grid.queue_redraw()
		_on_status("Standard map mode")
	)
	map_hb.add_child(map_std_btn)
	var map_isle_btn := _button("🏝 Islands", 10)
	map_isle_btn.custom_minimum_size = Vector2(120, 24)
	map_isle_btn.pressed.connect(func() -> void:
		tonal.map_mode = TonalRegions.MAP_ISLAND; grid.queue_redraw()
		_on_status("Island map mode")
	)
	map_hb.add_child(map_isle_btn)
	vbox.add_child(map_hb)

	vbox.add_child(HSeparator.new())
	vbox.add_child(_label("PRESETS", 10))
	var preset_defs: Array = [
		["12Maj",   "apply_preset_all_major"],
		["12Min",   "apply_preset_all_minor"],
		["5ths",    "apply_preset_circle_of_5ths"],
		["7Modes",  "apply_preset_7modes_c"],
		["Dorian",  "apply_preset_all_dorian"],
		["Classic", "apply_preset_classic"],
	]
	var pg := GridContainer.new()
	pg.columns = 3
	pg.add_theme_constant_override("h_separation", 3); pg.add_theme_constant_override("v_separation", 3)
	for pd in preset_defs:
		var pb := _button(pd[0] as String, 9)
		pb.custom_minimum_size = Vector2(80, 22)
		var method_name: String = pd[1]; var label: String = pd[0]
		pb.pressed.connect(func() -> void:
			tonal.map_mode = TonalRegions.MAP_STANDARD
			tonal.call(method_name); grid.queue_redraw()
			_on_status("Map preset: " + label)
		)
		pg.add_child(pb)
	vbox.add_child(pg)

	vbox.add_child(HSeparator.new())
	vbox.add_child(_label("CELL COLOR", 10))
	var col_hb := HBoxContainer.new()
	col_hb.add_theme_constant_override("separation", 4)
	var col_age := _button("🎨 Age", 10)
	col_age.custom_minimum_size = Vector2(120, 24)
	col_age.pressed.connect(func() -> void: grid.color_by_note = false; grid.queue_redraw())
	col_hb.add_child(col_age)
	var col_note := _button("🎵 Note", 10)
	col_note.custom_minimum_size = Vector2(120, 24)
	col_note.pressed.connect(func() -> void: grid.color_by_note = true; grid.queue_redraw())
	col_hb.add_child(col_note)
	vbox.add_child(col_hb)

	vbox.add_child(HSeparator.new())
	vbox.add_child(_label("SEED", 10))
	var seed_hb := HBoxContainer.new()
	seed_hb.add_theme_constant_override("separation", 3)
	for pattern in ["Random", "Glider", "R-Pentomino"]:
		var btn := _button(pattern, 9)
		btn.custom_minimum_size = Vector2(78, 22)
		btn.pressed.connect(func() -> void:
			seed_requested.emit(pattern.to_lower().replace("-","_").replace(" ","_"))
		)
		seed_hb.add_child(btn)
	vbox.add_child(seed_hb)


# ── Tab: Sound ────────────────────────────────────────────────────────────────

func _build_sound_tab(vbox: VBoxContainer) -> void:
	vbox.add_child(_label("INSTRUMENT", 10))
	var inst_grid := GridContainer.new()
	inst_grid.columns = 2
	inst_grid.add_theme_constant_override("h_separation", 4); inst_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(inst_grid)

	_instrument_btns = []
	var inst_names: Array = ["Guitar","Piano","Organ","Strings","Acoustic","Wind","Bass","Pad"]
	var inst_icons: Array = ["🎸","🎹","🎸","🎻","🎸","🎷","🎸","🎻"]
	for i in inst_names.size():
		var btn := _button("%s %s" % [inst_icons[i], inst_names[i]], 10)
		btn.custom_minimum_size = Vector2(120, 28)
		var idx: int = i
		btn.pressed.connect(func() -> void:
			_btn_press_anim(btn)
			if audio_engine: audio_engine.set_instrument(idx)
			_highlight_instrument(idx)
			_on_status("Instrument: %s" % inst_names[idx])
		)
		inst_grid.add_child(btn)
		_instrument_btns.append(btn)

	_inst_option = OptionButton.new()
	_inst_option.visible = false
	var _inst_labels: Array = ["🎸 Guitar","🎹 Piano","🎸 Organ","🎻 Strings",
							   "🎸 Acoustic","🎷 Wind","🎸 Bass","🎻 Pad"]
	for lbl in _inst_labels:
		_inst_option.add_item(lbl as String)
	if audio_engine:
		_inst_option.selected = audio_engine.current_instrument
		_highlight_instrument(audio_engine.current_instrument)
	_inst_option.item_selected.connect(func(idx: int) -> void:
		if audio_engine: audio_engine.set_instrument(idx)
		_highlight_instrument(idx)
	)
	vbox.add_child(_inst_option)

	vbox.add_child(HSeparator.new())
	vbox.add_child(_label("GENRE PRESET", 10))
	var genre_grid := GridContainer.new()
	genre_grid.columns = 2
	genre_grid.add_theme_constant_override("h_separation", 4); genre_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(genre_grid)

	var genre_defs: Array = [
		["Classical","🎼",3,4.0, 0.03,[3],         [2,3],          "apply_preset_classic"],
		["Ambient",  "🌙",7,2.0, 0.02,[3],         [2,3],          "apply_preset_all_major"],
		["Rock",     "🎸",2,8.0, 0.07,[3,6],       [2,3],          "apply_preset_circle_of_5ths"],
		["Jazz",     "🎷",1,6.0, 0.05,[3],         [2,3],          "apply_preset_7modes_c"],
		["Bells",    "🔔",4,3.0, 0.04,[3],         [2,3],          "apply_preset_classic"],
		["Orchestra","🎶",3,5.0, 0.03,[3],         [2,3],          "apply_preset_all_major"],
		["Chaos",    "⚡",0,12.0,0.15,[3,6,7,8],   [3,4,6,7,8],    "apply_preset_all_minor"],
		["Folk",     "🪈",5,5.0, 0.04,[3],         [2,3],          "apply_preset_all_dorian"],
	]
	for gd in genre_defs:
		var gb := _button("%s %s" % [gd[1] as String, gd[0] as String], 10)
		gb.custom_minimum_size = Vector2(120, 28)
		var g_inst: int = gd[2]; var g_tps: float = gd[3]; var g_mut: float = gd[4]
		var g_birth: Array = gd[5]; var g_surv: Array = gd[6]; var g_tonal: String = gd[7]
		var g_name: String = gd[0]
		gb.pressed.connect(func() -> void:
			if audio_engine: audio_engine.set_instrument(g_inst)
			_highlight_instrument(g_inst)
			if grid: grid.tick_interval = 1.0 / g_tps
			if audio_engine: audio_engine.set_tempo(60.0 * g_tps * 0.5)
			if _speed_slider: _speed_slider.value = g_tps
			if grid:
				grid.base_mutation_rate = g_mut
				grid.birth_rule = g_birth.duplicate()
				grid.survival_rule = g_surv.duplicate()
			if tonal:
				tonal.map_mode = TonalRegions.MAP_STANDARD
				tonal.call(g_tonal)
				if grid: grid.queue_redraw()
			_on_status("Genre: %s — %d BPM, mut %d%%" % [g_name, int(g_tps*30), int(g_mut*100)])
		)
		genre_grid.add_child(gb)

	vbox.add_child(HSeparator.new())
	var vol_hb := HBoxContainer.new()
	vol_hb.add_child(_label("Volume: ", 10))
	var vol_slider := HSlider.new()
	vol_slider.min_value = 0.0; vol_slider.max_value = 1.0; vol_slider.step = 0.01
	vol_slider.value = audio_engine.master_volume if audio_engine else 0.7
	vol_slider.custom_minimum_size = Vector2(150, 0)
	vol_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vol_lbl := _label("%d%%" % [int(vol_slider.value * 100)], 10)
	vol_lbl.custom_minimum_size = Vector2(38, 0)
	vol_slider.value_changed.connect(func(v: float) -> void:
		if audio_engine: audio_engine.master_volume = v
		vol_lbl.text = "%d%%" % [int(v * 100)]
	)
	vol_hb.add_child(vol_slider); vol_hb.add_child(vol_lbl); vbox.add_child(vol_hb)

	var harm_hb := HBoxContainer.new()
	harm_hb.add_child(_label("Timbre: ", 10))
	var harm_slider := HSlider.new()
	harm_slider.min_value = 0.0; harm_slider.max_value = 1.0; harm_slider.step = 0.01
	harm_slider.value = audio_engine.harmonic_mix if audio_engine else 1.0
	harm_slider.custom_minimum_size = Vector2(150, 0)
	harm_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var harm_lbl := _label("Rich", 10); harm_lbl.custom_minimum_size = Vector2(38, 0)
	harm_slider.value_changed.connect(func(v: float) -> void:
		if audio_engine: audio_engine.harmonic_mix = v
		harm_lbl.text = "Pure" if v < 0.25 else ("Mid" if v < 0.75 else "Rich")
	)
	harm_hb.add_child(harm_slider); harm_hb.add_child(harm_lbl); vbox.add_child(harm_hb)

	var mut_hb := HBoxContainer.new()
	mut_hb.add_child(_label("Mutation:", 10))
	var mut_slider := HSlider.new()
	mut_slider.min_value = 0.01; mut_slider.max_value = 0.25; mut_slider.step = 0.005
	mut_slider.value = grid.base_mutation_rate if grid else 0.05
	mut_slider.custom_minimum_size = Vector2(150, 0)
	mut_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mut_lbl := _label("%d%%" % [int(mut_slider.value * 100)], 10); mut_lbl.custom_minimum_size = Vector2(38, 0)
	mut_slider.value_changed.connect(func(v: float) -> void:
		if grid: grid.base_mutation_rate = v
		mut_lbl.text = "%d%%" % [int(v * 100)]
	)
	mut_hb.add_child(mut_slider); mut_hb.add_child(mut_lbl); vbox.add_child(mut_hb)


# ── Right panel: Cluster Evolution ───────────────────────────────────────────

func _build_cluster_evo_panel() -> void:
	var vp := _get_vp_size()
	_evo_panel = _panel(Rect2(vp.x - 260, 44, 260, vp.y - 44))

	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_evo_panel.add_child(sc)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.add_theme_constant_override("separation", 4)
	sc.add_child(outer_vbox)

	# ── Static header: sparklines + rules + library ────────────────────────
	outer_vbox.add_child(_label("🧬 EVOLUTION", 11))

	var cells_row := HBoxContainer.new()
	cells_row.add_child(_label("Клітини: ", 9))
	_sparkline_cells_lbl = _label("─────────────────────────", 9)
	_sparkline_cells_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	cells_row.add_child(_sparkline_cells_lbl)
	outer_vbox.add_child(cells_row)

	var fit_row := HBoxContainer.new()
	fit_row.add_child(_label("Фітнес:  ", 9))
	_sparkline_fit_lbl = _label("─────────────────────────", 9)
	_sparkline_fit_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	fit_row.add_child(_sparkline_fit_lbl)
	outer_vbox.add_child(fit_row)

	_milestone_lbl = _label("", 9)
	_milestone_lbl.add_theme_color_override("font_color", DIM_COLOR)
	outer_vbox.add_child(_milestone_lbl)

	# Rules toggle + Library button in one row
	var hdr_btns := HBoxContainer.new()
	hdr_btns.add_theme_constant_override("separation", 3)
	var rules_btn := _button("⚙ Правила ▼", 9)
	rules_btn.custom_minimum_size = Vector2(130, 20)
	rules_btn.pressed.connect(func() -> void:
		_evo_rules_collapsed = not _evo_rules_collapsed
		_evo_rules_body.visible = not _evo_rules_collapsed
		rules_btn.text = "⚙ Правила ▲" if not _evo_rules_collapsed else "⚙ Правила ▼"
		if not _evo_rules_collapsed:
			_refresh_rules_display()
	)
	hdr_btns.add_child(rules_btn)
	var lib_btn := _button("📚 Library", 9)
	lib_btn.custom_minimum_size = Vector2(108, 20)
	lib_btn.pressed.connect(_toggle_library)
	hdr_btns.add_child(lib_btn)
	outer_vbox.add_child(hdr_btns)

	_evo_rules_body = VBoxContainer.new()
	_evo_rules_body.add_theme_constant_override("separation", 2)
	_evo_rules_body.visible = false
	outer_vbox.add_child(_evo_rules_body)

	outer_vbox.add_child(HSeparator.new())

	# ── Dynamic cluster cards area ─────────────────────────────────────────
	_evo_cluster_cards_vbox = VBoxContainer.new()
	_evo_cluster_cards_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_evo_cluster_cards_vbox.add_theme_constant_override("separation", 4)
	outer_vbox.add_child(_evo_cluster_cards_vbox)


# ── Cluster cards ─────────────────────────────────────────────────────────────

func _refresh_cluster_cards(clusters: Array) -> void:
	if not is_instance_valid(_evo_cluster_cards_vbox):
		return

	if clusters.is_empty():
		_clear_all_cluster_cards()
		# Show placeholder (only if not already shown)
		var has_placeholder: bool = false
		for ch in _evo_cluster_cards_vbox.get_children():
			if ch.has_meta("_placeholder"):
				has_placeholder = true
				break
		if not has_placeholder:
			var empty_lbl := _label("Немає кластерів.\nПосій сітку → Play.", 10)
			empty_lbl.add_theme_color_override("font_color", DIM_COLOR)
			empty_lbl.set_meta("_placeholder", true)
			_evo_cluster_cards_vbox.add_child(empty_lbl)
		return

	# Remove any placeholder from an earlier empty frame
	for ch in _evo_cluster_cards_vbox.get_children():
		if ch.has_meta("_placeholder"):
			ch.queue_free()

	var sorted: Array = clusters.duplicate()
	sorted.sort_custom(func(a: Cluster, b: Cluster) -> bool:
		return a.get_size() > b.get_size()
	)
	var limit: int = mini(sorted.size(), 6)
	var top: Array = sorted.slice(0, limit)

	# Build set of current top-N ids
	var top_ids: Dictionary = {}
	for cl_raw in top:
		top_ids[(cl_raw as Cluster).id] = true

	# Evict cached cards for clusters that fell out of the top-N
	for cid in _card_nodes.keys().duplicate():
		if not top_ids.has(cid):
			var entry: Dictionary = _card_nodes[cid]
			var card_node: Node = entry.get("card")
			var sep_node: Node = entry.get("sep")
			if card_node and is_instance_valid(card_node):
				card_node.queue_free()
			if sep_node and is_instance_valid(sep_node):
				sep_node.queue_free()
			_card_nodes.erase(cid)

	# Create or update each card, then re-order to match ranking
	for i in top.size():
		var cl := top[i] as Cluster
		if not _card_nodes.has(cl.id):
			_card_nodes[cl.id] = _make_cluster_card(cl)
			_evo_cluster_cards_vbox.add_child(_card_nodes[cl.id]["card"])
			if _card_nodes[cl.id].get("sep"):
				_evo_cluster_cards_vbox.add_child(_card_nodes[cl.id]["sep"])
		else:
			_update_cluster_card(cl, _card_nodes[cl.id])

	# Re-order children: card, sep, card, sep, ... in ranking order
	var child_idx: int = 0
	for i in top.size():
		var cl := top[i] as Cluster
		var entry: Dictionary = _card_nodes[cl.id]
		_evo_cluster_cards_vbox.move_child(entry["card"], child_idx)
		child_idx += 1
		var sep_node: Node = entry.get("sep")
		if sep_node and is_instance_valid(sep_node):
			var should_show: bool = (i < top.size() - 1)
			(sep_node as CanvasItem).visible = should_show
			if should_show:
				_evo_cluster_cards_vbox.move_child(sep_node, child_idx)
				child_idx += 1


func _clear_all_cluster_cards() -> void:
	for cid in _card_nodes.keys().duplicate():
		var entry: Dictionary = _card_nodes[cid]
		var card_node: Node = entry.get("card")
		var sep_node: Node = entry.get("sep")
		if card_node and is_instance_valid(card_node):
			card_node.queue_free()
		if sep_node and is_instance_valid(sep_node):
			sep_node.queue_free()
	_card_nodes.clear()


func _cluster_state_color(state: String) -> Color:
	match state:
		"stable":       return Color(0.5, 0.7, 1.0)
		"oscillating":  return Color(1.0, 0.8, 0.3)
		"glider":       return Color(1.0, 0.4, 1.0)
		_:              return Color(0.6, 0.9, 0.6)  # evolving = green


func _cluster_region_name(cl: Cluster) -> String:
	if cl.cells.is_empty():
		return "?"
	var cp := cl.cells[0] as Vector2i
	return tonal.get_region_name(tonal.get_region_id(cp.x, cp.y))


func _cluster_header_text(cl: Cluster, region_name: String) -> String:
	return "#%d · %s · %s  t:%d" % [cl.id, cl.state, region_name, cl.get_age(grid.tick)]


func _cluster_bar_text(cl: Cluster) -> String:
	var filled: int = clampi(int(cl.fitness_score / 5.0), 0, 20)
	return "sz:%d  [%s%s] %.0f" % [cl.get_size(), "█".repeat(filled), "░".repeat(20 - filled), cl.fitness_score]


func _update_cluster_card(cl: Cluster, entry: Dictionary) -> void:
	var region_name: String = _cluster_region_name(cl)
	var hdr: Label = entry.get("hdr")
	if hdr and is_instance_valid(hdr):
		hdr.text = _cluster_header_text(cl, region_name)
		hdr.add_theme_color_override("font_color", _cluster_state_color(cl.state))

	var bar: Label = entry.get("bar")
	if bar and is_instance_valid(bar):
		bar.text = _cluster_bar_text(cl)

	# Notes: if length matches, update in place; otherwise rebuild the row
	var notes_hb: HBoxContainer = entry.get("notes_hb")
	var cached_notes: Array = entry.get("notes", [])
	var melody_len: int = cl.melody.size()

	if notes_hb and is_instance_valid(notes_hb):
		if melody_len == cached_notes.size() and melody_len > 0:
			for i in melody_len:
				var note := cl.melody[i] as DNANote
				_restyle_note_block(cached_notes[i] as Button, note, i == cl.melody_index)
		else:
			for n in cached_notes:
				if is_instance_valid(n):
					(n as Node).queue_free()
			cached_notes = []
			if melody_len > 0:
				for i in melody_len:
					var note := cl.melody[i] as DNANote
					var nb := _make_note_block(note, i == cl.melody_index)
					notes_hb.add_child(nb)
					cached_notes.append(nb)
			entry["notes"] = cached_notes


func _make_cluster_card(cl: Cluster) -> Dictionary:
	var entry: Dictionary = {"card": null, "hdr": null, "bar": null,
		"notes_hb": null, "notes": [], "sep": null}

	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 3)
	entry["card"] = card

	# ── Header: #ID · state · region  t:age ───────────────────────────────
	var region_name: String = _cluster_region_name(cl)
	var hdr_lbl := _label(_cluster_header_text(cl, region_name), 9)
	hdr_lbl.add_theme_color_override("font_color", _cluster_state_color(cl.state))
	card.add_child(hdr_lbl)
	entry["hdr"] = hdr_lbl

	# ── Size + fitness bar ─────────────────────────────────────────────────
	var bar_lbl := _label(_cluster_bar_text(cl), 9)
	card.add_child(bar_lbl)
	entry["bar"] = bar_lbl

	# ── Note blocks ────────────────────────────────────────────────────────
	var notes_hb := HBoxContainer.new()
	notes_hb.add_theme_constant_override("separation", 2)
	card.add_child(notes_hb)
	entry["notes_hb"] = notes_hb
	var note_refs: Array = []
	if not cl.melody.is_empty():
		for i in cl.melody.size():
			var note := cl.melody[i] as DNANote
			var nb := _make_note_block(note, i == cl.melody_index)
			notes_hb.add_child(nb)
			note_refs.append(nb)
	entry["notes"] = note_refs

	# ── Action buttons ─────────────────────────────────────────────────────
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 3)

	var sel_btn := _button("●", 9)
	sel_btn.custom_minimum_size = Vector2(22, 20)
	sel_btn.tooltip_text = "Select cluster"
	sel_btn.pressed.connect(func() -> void:
		tool_mgr.selected_cluster_id = cl.id
		_on_status("Selected cluster #%d" % cl.id)
	)
	actions.add_child(sel_btn)

	var like_btn := _button("♥", 9)
	like_btn.custom_minimum_size = Vector2(22, 20)
	like_btn.tooltip_text = "Like (+15 fitness)"
	like_btn.pressed.connect(func() -> void:
		like_cluster.emit(cl.id)
		fitness_mgr.like_cluster(cl.id)
	)
	actions.add_child(like_btn)

	var mute_btn := _button("🔇", 9)
	mute_btn.custom_minimum_size = Vector2(22, 20)
	mute_btn.tooltip_text = "Mute (-20 fitness)"
	mute_btn.pressed.connect(func() -> void:
		mute_cluster.emit(cl.id)
		fitness_mgr.mute_cluster(cl.id)
	)
	actions.add_child(mute_btn)

	var save_btn := _button("💾", 9)
	save_btn.custom_minimum_size = Vector2(22, 20)
	save_btn.tooltip_text = "Save melody to library"
	save_btn.pressed.connect(func() -> void:
		fitness_mgr.save_melody(cl.id)
		_refresh_library()
		_on_status("Melody #%d saved!" % cl.id)
	)
	actions.add_child(save_btn)

	var freeze_btn := _button("❄", 9)
	freeze_btn.custom_minimum_size = Vector2(22, 20)
	freeze_btn.tooltip_text = "Freeze cluster"
	freeze_btn.pressed.connect(func() -> void:
		event_requested.emit("event_freeze", cl.id)
	)
	actions.add_child(freeze_btn)

	var mirror_btn := _button("🎭", 9)
	mirror_btn.custom_minimum_size = Vector2(22, 20)
	mirror_btn.tooltip_text = "Mirror cluster"
	mirror_btn.pressed.connect(func() -> void:
		event_requested.emit("event_mirror", cl.id)
	)
	actions.add_child(mirror_btn)

	card.add_child(actions)

	# Separator below this card (may be hidden if it's the last in ranking)
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.25, 0.25, 0.40))
	entry["sep"] = sep

	return entry


func _make_note_block(note: DNANote, is_playing: bool) -> Button:
	var btn := Button.new()
	btn.add_theme_font_size_override("font_size", 8)
	btn.focus_mode = Control.FOCUS_NONE
	_restyle_note_block(btn, note, is_playing)
	return btn


## In-place update of a pre-existing note button (used by _update_cluster_card).
func _restyle_note_block(btn: Button, note: DNANote, is_playing: bool) -> void:
	btn.text = NOTE_NAMES[note.pitch]
	# Width proportional to duration (1→15px, 8→50px)
	btn.custom_minimum_size = Vector2(10 + note.duration * 5, 22)
	btn.tooltip_text = "%s · d:%d · v:%d · %s" % [
		NOTE_NAMES[note.pitch], note.duration, note.velocity, ARTIC_SHORT[note.articulation]]

	var style := StyleBoxFlat.new()
	style.bg_color = Color.from_hsv(float(note.pitch) / 12.0, 0.65, 0.80)
	style.corner_radius_top_left = 2; style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2; style.corner_radius_bottom_right = 2
	if is_playing:
		style.border_color = Color(1.0, 1.0, 0.25, 1.0)
		style.set_border_width_all(2)
	else:
		style.set_border_width_all(0)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)

	var lum := style.bg_color.r * 0.299 + style.bg_color.g * 0.587 + style.bg_color.b * 0.114
	btn.add_theme_color_override("font_color",
		Color(0.05, 0.05, 0.08) if lum > 0.55 else Color(0.95, 0.95, 1.0))


# ── Evolution sparkline helpers ───────────────────────────────────────────────

func _refresh_rules_display() -> void:
	if not is_instance_valid(_evo_rules_body):
		return
	for ch in _evo_rules_body.get_children():
		ch.queue_free()
	var dim := DIM_COLOR
	_evo_rules_body.add_child(_label("Правила Life:", 9))
	var birth_nums := ",".join(PackedStringArray(grid.birth_rule.map(func(x): return str(x))))
	var surv_nums  := ",".join(PackedStringArray(grid.survival_rule.map(func(x): return str(x))))
	for txt in ["  Народж.:  B" + birth_nums, "  Виживан.: S" + surv_nums]:
		var l := _label(txt, 9); l.add_theme_color_override("font_color", dim); _evo_rules_body.add_child(l)
	_evo_rules_body.add_child(_label("Мутації:", 9))
	for txt in [
		"  База:    %d%%" % int(grid.base_mutation_rate * 100),
		"  Гаряче:  %d%%  (×2.5)" % int(grid.base_mutation_rate * 2.5 * 100),
		"  Холодне: %d%%  (×0.2)" % int(grid.base_mutation_rate * 0.2 * 100),
	]:
		var l := _label(txt, 9); l.add_theme_color_override("font_color", dim); _evo_rules_body.add_child(l)
	_evo_rules_body.add_child(_label("Фітнес (+/-):", 9))
	for txt in ["  ♥ Лайк: +15","  🔇 Мьют: -20","  Розпад: -0.1/тік","  Стабільн.: +5","  Бібліотека: +5/+10"]:
		var l := _label(txt, 9); l.add_theme_color_override("font_color", dim); _evo_rules_body.add_child(l)


const _SPARKLINE_BLOCKS := "▁▂▃▄▅▆▇█"
const _SPARKLINE_WIDTH   := 20
const _SPARKLINE_SAMPLE  := 50

func _refresh_sparkline() -> void:
	if not is_instance_valid(_sparkline_cells_lbl) or not evolution_tracker:
		return
	_sparkline_cells_lbl.text = _to_sparkline(evolution_tracker.get_cell_history(_SPARKLINE_SAMPLE), _SPARKLINE_WIDTH)
	_sparkline_fit_lbl.text   = _to_sparkline(evolution_tracker.get_fitness_history(_SPARKLINE_SAMPLE), _SPARKLINE_WIDTH)
	var ms := evolution_tracker.get_milestones()
	if ms.size() > 0:
		var last: Dictionary = ms.back()
		_milestone_lbl.text = "t%d: %s" % [last["tick"], last["label"]]


func _to_sparkline(data: Array, width: int) -> String:
	if data.is_empty():
		return "─".repeat(width)
	var lo: float = INF; var hi: float = -INF
	for v in data:
		var fv := float(v)
		if fv < lo: lo = fv
		if fv > hi: hi = fv
	if hi == lo:
		return "▄".repeat(width)
	var result := ""
	for i in width:
		var src_idx := clampi(int(float(i) / float(width) * float(data.size())), 0, data.size() - 1)
		result += _SPARKLINE_BLOCKS[clampi(int((float(data[src_idx]) - lo) / (hi - lo) * 7.0), 0, 7)]
	return result


# ── Status bar ────────────────────────────────────────────────────────────────

func _build_status_bar() -> void:
	var vp := _get_vp_size()
	var bar := _panel(Rect2(260, vp.y - 24, vp.x - 520, 24))
	_status_bar = bar
	_status_label = _label("Ready. Seed the grid to begin.", 11)
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status_label.clip_text = true
	bar.add_child(_status_label)


# ── Settings overlay (floating) ───────────────────────────────────────────────

func _build_settings_panel() -> void:
	_settings_panel = _panel(Rect2(270, 54, 520, 400))
	_settings_panel.visible = false

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 5)
	_settings_panel.add_child(vbox)

	var hdr := HBoxContainer.new()
	hdr.add_child(_label("⚙  SETTINGS", 13))
	var hdr_spacer := Control.new(); hdr_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(hdr_spacer)
	var close_btn := _button("✕", 11); close_btn.custom_minimum_size = Vector2(24, 0)
	close_btn.pressed.connect(func() -> void: _settings_panel.visible = false)
	hdr.add_child(close_btn)
	vbox.add_child(hdr)
	vbox.add_child(HSeparator.new())

	vbox.add_child(_label("GRID SIZE  (applies immediately)", 11))
	var size_hb := HBoxContainer.new(); size_hb.add_theme_constant_override("separation", 6)
	var size_presets: Array = [
		["Test\n10×10",10,10,16], ["Small\n40×30",40,30,16],
		["Med\n80×60",80,60,12], ["Large\n120×90",120,90,8], ["XL\n160×120",160,120,6],
	]
	var size_btns: Array = []
	for sp in size_presets:
		var sb := _button(sp[0] as String, 9); sb.custom_minimum_size = Vector2(68, 36)
		if LifeGrid.GRID_W == (sp[1] as int) and LifeGrid.GRID_H == (sp[2] as int):
			sb.modulate = Color(0.4, 0.8, 1.0)
		var sw: int = sp[1]; var sh: int = sp[2]; var sc: int = sp[3]
		sb.pressed.connect(func() -> void:
			grid_resize_requested.emit(sw, sh, sc)
			_on_status("Grid → %d×%d cell=%dpx" % [sw, sh, sc])
			for b in size_btns: b.modulate = Color.WHITE
			sb.modulate = Color(0.4, 0.8, 1.0)
		)
		size_hb.add_child(sb); size_btns.append(sb)
	vbox.add_child(size_hb)
	vbox.add_child(HSeparator.new())

	vbox.add_child(_label("LIFE RULES  (next tick)", 11))
	var birth_btns: Array = []; var surv_btns: Array = []

	var rp_hb := HBoxContainer.new(); rp_hb.add_theme_constant_override("separation", 4)
	rp_hb.add_child(_label("Preset:", 10))
	var rule_presets: Array = [
		["Conway",[3],[2,3]], ["HighLife",[3,6],[2,3]],
		["Day&Night",[3,6,7,8],[3,4,6,7,8]], ["Maze",[3],[1,2,3,4,5]], ["Life 34",[3,4],[3,4]],
	]
	for rp in rule_presets:
		var rb := _button(rp[0] as String, 9); rb.custom_minimum_size = Vector2(58, 20)
		var rb_b: Array = rp[1]; var rb_s: Array = rp[2]
		rb.pressed.connect(func() -> void:
			grid.birth_rule = rb_b.duplicate(); grid.survival_rule = rb_s.duplicate()
			for i in 9:
				(birth_btns[i] as Button).modulate = Color(0.4,0.8,1.0) if rb_b.has(i) else Color.WHITE
				(surv_btns[i] as Button).modulate  = Color(0.4,0.8,1.0) if rb_s.has(i) else Color.WHITE
			_on_status("Rules: B%s / S%s" % [_rule_str(rb_b), _rule_str(rb_s)])
		)
		rp_hb.add_child(rb)
	vbox.add_child(rp_hb)

	var b_hb := HBoxContainer.new(); b_hb.add_theme_constant_override("separation", 2)
	b_hb.add_child(_label("Birth  B:", 10))
	for i in 9:
		var bt := _button(str(i), 10); bt.custom_minimum_size = Vector2(26, 22)
		bt.modulate = Color(0.4, 0.8, 1.0) if grid.birth_rule.has(i) else Color.WHITE
		var bc: int = i
		bt.pressed.connect(func() -> void:
			if grid.birth_rule.has(bc): grid.birth_rule.erase(bc); bt.modulate = Color.WHITE
			else: grid.birth_rule.append(bc); grid.birth_rule.sort(); bt.modulate = Color(0.4,0.8,1.0)
			_on_status("Birth rule: B%s" % _rule_str(grid.birth_rule))
		)
		b_hb.add_child(bt); birth_btns.append(bt)
	vbox.add_child(b_hb)

	var s_hb := HBoxContainer.new(); s_hb.add_theme_constant_override("separation", 2)
	s_hb.add_child(_label("Survive S:", 10))
	for i in 9:
		var st := _button(str(i), 10); st.custom_minimum_size = Vector2(26, 22)
		st.modulate = Color(0.4, 0.8, 1.0) if grid.survival_rule.has(i) else Color.WHITE
		var sc2: int = i
		st.pressed.connect(func() -> void:
			if grid.survival_rule.has(sc2): grid.survival_rule.erase(sc2); st.modulate = Color.WHITE
			else: grid.survival_rule.append(sc2); grid.survival_rule.sort(); st.modulate = Color(0.4,0.8,1.0)
			_on_status("Survival: S%s" % _rule_str(grid.survival_rule))
		)
		s_hb.add_child(st); surv_btns.append(st)
	vbox.add_child(s_hb)


func _rule_str(rule: Array) -> String:
	var s := ""
	for n in rule: s += str(n)
	return s


# ── Library panel (floating) ──────────────────────────────────────────────────

func _build_library_panel() -> void:
	var vp := _get_vp_size()
	_library_panel = _panel(Rect2(260, 44, 280, vp.y - 68))
	_library_panel.visible = false
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	_library_panel.add_child(vbox)

	var hdr := HBoxContainer.new()
	hdr.add_child(_label("📚 MELODY LIBRARY", 12))
	var close := _button("✕", 10); close.custom_minimum_size = Vector2(24, 0)
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


# ── Piano panel (bottom visualiser) ──────────────────────────────────────────

func _build_piano_panel() -> void:
	var vp := _get_vp_size()
	_piano_panel = _panel(Rect2(260, vp.y - 24 - PIANO_H, vp.x - 520, PIANO_H))
	_piano_container = Control.new()
	_piano_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_piano_panel.add_child(_piano_container)
	_rebuild_piano_keys()


func _rebuild_piano_keys() -> void:
	if _piano_container == null: return
	for ch in _piano_container.get_children(): ch.free()
	_piano_keys.clear()
	var pw: float = _piano_panel.size.x
	var white_count: int = 0
	for m in range(PIANO_MIDI_LO, PIANO_MIDI_HI + 1):
		if not _is_black_key(m): white_count += 1
	if white_count == 0: return
	var wkw: float = pw / float(white_count)
	var wkh: float = float(PIANO_H) - 2.0
	var bkw: float = wkw * 0.56
	var bkh: float = wkh * 0.60
	var wi: int = 0
	for m in range(PIANO_MIDI_LO, PIANO_MIDI_HI + 1):
		if _is_black_key(m): continue
		var rect := ColorRect.new()
		rect.color = Color(0.93, 0.93, 0.97)
		rect.position = Vector2(wi * wkw + 0.5, 1.0)
		rect.size = Vector2(wkw - 1.0, wkh)
		_piano_container.add_child(rect)
		_piano_keys[m] = rect
		var whi := ColorRect.new(); whi.color = Color(1,1,1,0.55)
		whi.position = Vector2(0,0); whi.size = Vector2(wkw-1,2.5); rect.add_child(whi)
		var sep := ColorRect.new(); sep.color = Color(0.30,0.30,0.40,0.55)
		sep.position = Vector2(wkw-1.5,0); sep.size = Vector2(1.0,wkh); rect.add_child(sep)
		if m % 12 == 0:
			var lbl := Label.new(); lbl.text = "C%d" % [(m/12)-1]
			lbl.add_theme_font_size_override("font_size", 8)
			lbl.add_theme_color_override("font_color", Color(0.30,0.30,0.42))
			lbl.position = Vector2(1.0, wkh-13.0); lbl.size = Vector2(wkw-2.0,12.0)
			rect.add_child(lbl)
		wi += 1
	for m in range(PIANO_MIDI_LO, PIANO_MIDI_HI + 1):
		if not _is_black_key(m): continue
		var note: int = m % 12
		var oct_from_lo: int = (m - PIANO_MIDI_LO) / 12
		var oct_x: float = float(oct_from_lo * 7) * wkw
		var center_mult: float
		match note:
			1: center_mult = 1.0
			3: center_mult = 2.0
			6: center_mult = 4.0
			8: center_mult = 5.0
			10: center_mult = 6.0
			_: center_mult = 0.0
		var bx: float = oct_x + center_mult * wkw - bkw * 0.5
		var shadow := ColorRect.new(); shadow.color = Color(0,0,0,0.45)
		shadow.position = Vector2(bx+1.5,2.0); shadow.size = Vector2(bkw,bkh+3.0)
		_piano_container.add_child(shadow)
		var rect := ColorRect.new(); rect.color = Color(0.10,0.10,0.16)
		rect.position = Vector2(bx,1.0); rect.size = Vector2(bkw,bkh)
		_piano_container.add_child(rect); _piano_keys[m] = rect
		var bhi := ColorRect.new(); bhi.color = Color(0.32,0.32,0.48,0.65)
		bhi.position = Vector2(1.5,0); bhi.size = Vector2(bkw-3.0,3.0); rect.add_child(bhi)


func _is_black_key(midi: int) -> bool:
	var note: int = midi % 12
	return note == 1 or note == 3 or note == 6 or note == 8 or note == 10


# ────────────────────────────────────────────────────────────────────────────
#  Signal wiring
# ────────────────────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	_speed_slider.value_changed.connect(func(v: float) -> void: speed_changed.emit(v))
	_pause_btn.pressed.connect(func() -> void: pause_toggled.emit())
	tool_mgr.tool_changed.connect(_highlight_tool)
	tool_mgr.status_message.connect(_on_status)
	catalyst.status_message.connect(_on_status)
	catalyst.event_tokens_changed.connect(_on_tokens_changed)
	cluster_mgr.clusters_updated.connect(update_cluster_display)


# ────────────────────────────────────────────────────────────────────────────
#  Public update methods
# ────────────────────────────────────────────────────────────────────────────

func sync_pause_button() -> void:
	if not _pause_btn: return
	_pause_btn.text = "⏸ Pause" if grid.running else "▶ Resume"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.62, 0.10, 0.10) if grid.running else Color(0.10, 0.42, 0.18)
	style.border_color = Color(0.9, 0.3, 0.3) if grid.running else Color(0.3, 0.8, 0.4)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2; style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2; style.corner_radius_bottom_right = 2
	_pause_btn.add_theme_stylebox_override("normal", style)


func set_speed_slider(tps: float) -> void:
	if _speed_slider: _speed_slider.value = tps


func update_tick(n: int) -> void:
	if _tick_label: _tick_label.text = "Tick: %d" % n
	if evolution_tracker and (n - _last_sparkline_tick) >= 2:
		_last_sparkline_tick = n
		_refresh_sparkline()


func update_cluster_display(clusters: Array) -> void:
	_refresh_cluster_cards(clusters)


# ────────────────────────────────────────────────────────────────────────────
#  Library
# ────────────────────────────────────────────────────────────────────────────

func _refresh_library() -> void:
	if not is_instance_valid(_library_list): return
	for ch in _library_list.get_children(): ch.queue_free()
	for i in range(fitness_mgr.melody_library.size()):
		var entry: Dictionary = fitness_mgr.melody_library[i]
		var hb := HBoxContainer.new()
		var lbl := _label(entry["name"] as String, 10)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(lbl)
		var play_btn := _button("▶", 9); play_btn.custom_minimum_size = Vector2(18, 0)
		var idx := i
		play_btn.pressed.connect(func() -> void: _play_library_entry(idx))
		hb.add_child(play_btn)
		var del_btn := _button("✕", 9); del_btn.custom_minimum_size = Vector2(18, 0)
		del_btn.pressed.connect(func() -> void:
			fitness_mgr.delete_library_entry(idx); _refresh_library()
		)
		hb.add_child(del_btn)
		_library_list.add_child(hb)


func _play_library_entry(idx: int) -> void:
	if idx < 0 or idx >= fitness_mgr.melody_library.size(): return
	var entry: Dictionary = fitness_mgr.melody_library[idx]
	var melody: Array = entry["melody"]
	if melody.is_empty(): return
	var delay: float = 0.0
	for note_raw in melody.slice(0, 8):
		var note := note_raw as DNANote
		var midi: int = 60 + note.pitch
		var dur: float = float(note.duration) * 0.15
		var t := get_tree().create_timer(delay)
		t.timeout.connect(func() -> void:
			audio_engine.play_midi_note(midi, dur, float(note.velocity) / 127.0)
		)
		delay += dur * 0.9


func _toggle_library() -> void:
	_library_panel.visible = not _library_panel.visible
	if _library_panel.visible: _refresh_library()


# ────────────────────────────────────────────────────────────────────────────
#  Piano key brightness (_process)
# ────────────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _piano_keys.is_empty() or audio_engine == null: return
	if audio_engine.active_midi_notes.is_empty() and _piano_brightness.is_empty(): return
	for midi in audio_engine.active_midi_notes:
		if midi >= PIANO_MIDI_LO and midi <= PIANO_MIDI_HI:
			_piano_brightness[midi] = 1.0
	var done: Array = []
	for midi in _piano_brightness:
		_piano_brightness[midi] = maxf(_piano_brightness[midi] - delta * 4.0, 0.0)
		if _piano_brightness[midi] < 0.004: done.append(midi)
	for midi in done: _piano_brightness.erase(midi)
	for midi in _piano_keys:
		var brightness: float = _piano_brightness.get(midi, 0.0)
		var rect := _piano_keys[midi] as ColorRect
		if _is_black_key(midi):
			rect.color = Color(0.10,0.10,0.16).lerp(Color(0.02,0.88,1.00), brightness)
		else:
			rect.color = Color(0.93,0.93,0.97).lerp(Color(0.28,1.00,0.48), brightness)


# ────────────────────────────────────────────────────────────────────────────
#  Misc handlers
# ────────────────────────────────────────────────────────────────────────────

func _on_status(msg: String) -> void:
	if _status_label: _status_label.text = msg


func _on_tokens_changed(count: int) -> void:
	if _token_label: _token_label.text = "🎭×%d" % count


func _select_tool(tid: int) -> void:
	tool_mgr.set_tool(tid)
	_highlight_tool(tid)


func _highlight_tool(tid: int) -> void:
	for i in _tool_buttons.size():
		var btn := _tool_buttons[i] as Button
		var style := StyleBoxFlat.new()
		if _tool_ids[i] == tid:
			style.bg_color = Color(0.18, 0.42, 0.78)
			style.border_color = Color(0.4, 0.65, 1.0)
			style.set_border_width_all(2)
		else:
			style.bg_color = BTN_NORMAL
			style.border_color = Color(0.3, 0.3, 0.45)
			style.set_border_width_all(1)
		style.corner_radius_top_left = 2; style.corner_radius_top_right = 2
		style.corner_radius_bottom_left = 2; style.corner_radius_bottom_right = 2
		btn.add_theme_stylebox_override("normal", style)


func _highlight_instrument(idx: int) -> void:
	for i in _instrument_btns.size():
		(_instrument_btns[i] as Button).modulate = Color(0.4,0.8,1.0) if i == idx else Color.WHITE
	if is_instance_valid(_inst_option) and _inst_option.selected != idx:
		_inst_option.selected = idx


# ────────────────────────────────────────────────────────────────────────────
#  Animation helpers
# ────────────────────────────────────────────────────────────────────────────

func _btn_press_anim(btn: Button) -> void:
	var tw := create_tween()
	tw.tween_property(btn, "scale", Vector2(0.92, 0.92), 0.06)
	tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.08)


func _fade_in(node: Control, duration: float = 0.12) -> void:
	if not is_instance_valid(node): return
	node.modulate.a = 0.0
	create_tween().tween_property(node, "modulate:a", 1.0, duration)


# ────────────────────────────────────────────────────────────────────────────
#  UI factory helpers
# ────────────────────────────────────────────────────────────────────────────

func _panel(rect: Rect2) -> Panel:
	var p := Panel.new()
	p.position = rect.position; p.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG; style.border_color = Color(0.25, 0.25, 0.35)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3; style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3; style.corner_radius_bottom_right = 3
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
	style.bg_color = BTN_NORMAL; style.border_color = Color(0.3, 0.3, 0.45)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2; style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2; style.corner_radius_bottom_right = 2
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.22, 0.32)
	btn.add_theme_stylebox_override("hover", hover)
	return btn
