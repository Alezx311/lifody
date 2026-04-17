extends Node2D

## Main game controller for Lifody.
## Creates all child systems, wires signals, and runs the game loop.

var tonal: TonalRegions
var grid: LifeGrid
var cluster_mgr: ClusterManager
var audio: AudioEngine
var fitness_mgr: FitnessManager
var tool_mgr: ToolManager
var catalyst: CatalystEvents
var ui: GameUI
var evolution_tracker: EvolutionTracker = null
var camera: Camera2D

var quad_mode: QuadGridMode = null
var quad_ui: QuadGridUI = null
var _in_quad_mode: bool = false

# ── Chips From Audio panel (overlay on the main game) ────────────────────────
var _chips_analyzer: ChipsAudioAnalyzer = null
var _chips_panel:    ChipsDebugPanel    = null
var _chips_dialog:   FileDialog         = null
var _chips_active:   bool = false
var _chips_energy:   Array = []   # latest [oct][12] energy snapshot
var _chips_dominant: int  = 0     # pitch with highest energy
var _chips_affinity: Array = []   # 12×12 music-theory affinity for consonance display
var _chips_pitch_cells: Dictionary = {}  # pitch → Array[Vector2i] (precomputed per tonal layout)

var _panning: bool = false
var _fit_zoom: float = 1.0


func _ready() -> void:
	_create_systems()
	_wire_signals()
	_show_intro_menu()


# ────────────────────────────────────────────────────────────────────────────
#  System creation
# ────────────────────────────────────────────────────────────────────────────

func _create_systems() -> void:
	# 1. Tonal regions
	tonal = TonalRegions.new()
	tonal.setup(LifeGrid.GRID_W, LifeGrid.GRID_H)
	add_child(tonal)

	# 2. Life grid (left panel 260px + top bar 44px)
	grid = LifeGrid.new()
	grid.position = Vector2(260, 44)
	grid.setup_tonal(tonal)
	add_child(grid)

	# 3. Cluster manager
	cluster_mgr = ClusterManager.new()
	cluster_mgr.setup(grid, tonal)
	add_child(cluster_mgr)

	# 4. Audio engine
	audio = AudioEngine.new()
	audio.setup_tonal(tonal)
	audio.setup_grid(grid)
	add_child(audio)

	# Camera — add before UI so CanvasLayer renders on top unaffected
	camera = Camera2D.new()
	add_child(camera)

	# 5. Fitness manager
	fitness_mgr = FitnessManager.new()
	fitness_mgr.setup(cluster_mgr, audio)
	add_child(fitness_mgr)
	audio.setup_fitness(fitness_mgr)

	# 6. Tool manager
	tool_mgr = ToolManager.new()
	tool_mgr.setup(grid, cluster_mgr, fitness_mgr, audio)
	add_child(tool_mgr)

	# 7. Catalyst events
	catalyst = CatalystEvents.new()
	catalyst.setup(grid, cluster_mgr, fitness_mgr)
	add_child(catalyst)

	# 7.5. Evolution tracker
	evolution_tracker = EvolutionTracker.new()
	evolution_tracker.setup(grid, cluster_mgr)
	add_child(evolution_tracker)

	# 7.75. Chips audio analyser (always present, panel shown on demand)
	_chips_analyzer = ChipsAudioAnalyzer.new()
	add_child(_chips_analyzer)
	_build_chips_affinity()

	# 8. Game UI (CanvasLayer — renders on top)
	ui = GameUI.new()
	ui.setup(grid, cluster_mgr, fitness_mgr, tool_mgr, catalyst, tonal, evolution_tracker)
	ui.set_audio_engine(audio)
	add_child(ui)


# ────────────────────────────────────────────────────────────────────────────
#  Signal wiring
# ────────────────────────────────────────────────────────────────────────────

func _wire_signals() -> void:
	# Grid tick → update everything
	grid.tick_completed.connect(_on_tick)

	# UI controls
	ui.seed_requested.connect(_on_seed)
	ui.clear_requested.connect(_on_clear)
	ui.speed_changed.connect(_on_speed_changed)
	ui.pause_toggled.connect(_on_pause_toggled)
	ui.event_requested.connect(_on_event)

	# Cluster updates → audio
	cluster_mgr.clusters_updated.connect(audio.play_clusters)

	# Settings: grid resize
	ui.grid_resize_requested.connect(_on_grid_resize)

	# Viewport resize → re-center camera
	get_viewport().size_changed.connect(_on_viewport_resized)

	ui.quad_mode_requested.connect(_on_quad_mode_requested)
	ui.chips_mode_requested.connect(_toggle_chips_panel)


# ────────────────────────────────────────────────────────────────────────────
#  Game loop
# ────────────────────────────────────────────────────────────────────────────

func _show_intro_menu() -> void:
	var menu := IntroMenu.new()
	add_child(menu)
	menu.start_requested.connect(func(cfg: Dictionary) -> void:
		_start_game(cfg)
	)


func _start_game(config: Dictionary = {}) -> void:
	grid.resize_grid(30, 20, 28)
	tonal.setup(30, 20)
	_reset_camera()
	grid.running = false

	# Instrument
	var inst: int = config.get("instrument", 0)
	audio.set_instrument(inst)
	if ui._inst_option:
		ui._inst_option.selected = inst

	# Tempo + speed
	var tps: float = config.get("speed_tps", 5.0)
	var tempo: float = config.get("tempo", 120.0)
	audio.set_tempo(tempo)
	grid.tick_interval = 1.0 / tps
	ui.set_speed_slider(tps)

	# Mutation rate
	grid.base_mutation_rate = config.get("mutation_rate", 0.05)

	# Life rules (use defaults unless provided)
	var birth: Array = config.get("birth_rule", [3])
	var surv: Array   = config.get("survival_rule", [2, 3])
	grid.birth_rule    = birth.duplicate()
	grid.survival_rule = surv.duplicate()

	# Tonal preset
	var preset_methods := {
		"classic": "apply_preset_classic",
		"12maj":   "apply_preset_all_major",
		"12min":   "apply_preset_all_minor",
		"5ths":    "apply_preset_circle_of_5ths",
		"7modes":  "apply_preset_7modes_c",
		"dorian":  "apply_preset_all_dorian",
	}
	var method: String = preset_methods.get(config.get("scale_preset", "classic"), "apply_preset_classic")
	tonal.map_mode = TonalRegions.MAP_STANDARD
	tonal.call(method)

	# Starting pattern
	var pattern: String = config.get("pattern", "empty")
	_on_seed(pattern)

	# Master volume
	audio.master_volume = config.get("master_volume", 0.7)

	# Cell color mode
	var color_mode: String = config.get("color_mode", "age")
	grid.color_by_note = (color_mode == "note")

	# Fullscreen (may have been toggled live in menu already)
	if config.get("fullscreen", false):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	grid.queue_redraw()
	tool_mgr.set_tool(ToolManager.Tool.DRAW)
	ui.sync_pause_button()


func _process(_delta: float) -> void:
	# Chips panel: update freq display + progress at frame rate for smooth visuals
	if _chips_active and _chips_analyzer.is_playing() and _chips_panel:
		_chips_energy   = _chips_analyzer.analyze()
		_chips_dominant = _chips_calc_dominant()
		_chips_panel.update_freq_display(_chips_energy)
		_chips_panel.update_progress(_chips_analyzer.get_position(), _chips_analyzer.get_length())
		_chips_panel.update_consonance_display(_chips_dominant, _chips_affinity)


func _on_tick(tick_num: int) -> void:
	cluster_mgr.detect_clusters()
	fitness_mgr.on_tick(tick_num)
	catalyst.on_tick(tick_num)
	ui.update_tick(tick_num)
	_chips_tick_spawn()


# ────────────────────────────────────────────────────────────────────────────
#  UI events
# ────────────────────────────────────────────────────────────────────────────

func _on_seed(pattern: String) -> void:
	match pattern:
		"random":
			grid.seed_random(0.28)
		"glider":
			var cx: int = LifeGrid.GRID_W / 2
			var cy: int = LifeGrid.GRID_H / 2
			grid.seed_glider(cx, cy)
		"r_pentomino":
			grid.seed_r_pentomino(LifeGrid.GRID_W / 2, LifeGrid.GRID_H / 2)
		"empty":
			pass  # start with blank grid
		_:
			grid.seed_random(0.28)


func _on_clear() -> void:
	grid.clear()
	cluster_mgr.clusters.clear()
	cluster_mgr._prev_clusters.clear()
	ui.update_cluster_display([])
	ui.update_tick(0)


func _on_speed_changed(tps: float) -> void:
	grid.tick_interval = 1.0 / tps
	audio.set_tempo(60.0 * tps * 0.5)


func _set_speed(tps: float) -> void:
	grid.tick_interval = 1.0 / tps
	audio.set_tempo(60.0 * tps * 0.5)
	ui.set_speed_slider(tps)


func _on_pause_toggled() -> void:
	grid.running = not grid.running
	ui.sync_pause_button()


func _on_event(event_name: String, cluster_id: int) -> void:
	match event_name:
		"event_meteorite":
			var center: Vector2i = _cluster_center_or_grid_center(cluster_id)
			catalyst.event_meteorite(center.x, center.y)
		"event_resonance":
			catalyst.event_resonance()
		"event_freeze":
			catalyst.event_freeze(cluster_id)
		"event_mutation_wave":
			catalyst.event_mutation_wave()
		"event_mirror":
			catalyst.event_mirror(cluster_id)
	if evolution_tracker:
		var label_map := {
			"event_meteorite": "☄️ Метеорит",
			"event_resonance": "🤝 Резонанс",
			"event_freeze": "❄️ Заморозка",
			"event_mutation_wave": "🌊 Хвиля мутацій",
			"event_mirror": "🎭 Дзеркало",
		}
		evolution_tracker.record_event(grid.tick, label_map.get(event_name, event_name))


func _cluster_center_or_grid_center(cluster_id: int) -> Vector2i:
	var cl := cluster_mgr.get_cluster_by_id(cluster_id)
	if cl and not cl.cells.is_empty():
		var sum := Vector2i.ZERO
		for p in cl.cells:
			sum += p as Vector2i
		return sum / cl.cells.size()
	return Vector2i(LifeGrid.GRID_W / 2, LifeGrid.GRID_H / 2)


# ────────────────────────────────────────────────────────────────────────────
#  Keyboard shortcuts
# ────────────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	# ── Quad mode: route keyboard shortcuts, block camera pan/zoom ───────────
	if _in_quad_mode and quad_mode:
		if event is InputEventKey and (event as InputEventKey).pressed:
			var key := (event as InputEventKey).keycode
			match key:
				KEY_SPACE:
					quad_mode.toggle_panel_pause(quad_mode.active_panel)
				KEY_R:
					quad_mode.seed_panel(quad_mode.active_panel, "random")
				KEY_C:
					quad_mode.clear_panel(quad_mode.active_panel)
				KEY_1, KEY_2, KEY_3, KEY_4:
					quad_mode.set_active(key - KEY_1)
		return

	# ── Camera: pan with middle mouse ───────────────────────────────────────
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton
		match mbe.button_index:
			MOUSE_BUTTON_MIDDLE:
				_panning = mbe.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_camera(1.15, mbe.position)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_camera(1.0 / 1.15, mbe.position)
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _panning:
		var mme := event as InputEventMouseMotion
		camera.position -= mme.relative / camera.zoom.x
		_clamp_camera()
		get_viewport().set_input_as_handled()

	# ── Keyboard shortcuts ───────────────────────────────────────────────────
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key := (event as InputEventKey).keycode
		match key:
			KEY_SPACE:
				_on_pause_toggled()
			KEY_R:
				grid.seed_random(0.28)
			KEY_C:
				_on_clear()
			KEY_F, KEY_HOME:          # Reset camera
				_reset_camera()
			# Keys 1-9 control simulation speed
			KEY_1: _set_speed(1.0)
			KEY_2: _set_speed(2.0)
			KEY_3: _set_speed(3.0)
			KEY_4: _set_speed(5.0)
			KEY_5: _set_speed(8.0)
			KEY_6: _set_speed(10.0)
			KEY_7: _set_speed(13.0)
			KEY_8: _set_speed(16.0)
			KEY_9: _set_speed(20.0)
			KEY_EQUAL, KEY_KP_ADD:
				grid.tick_interval = maxf(grid.tick_interval * 0.8, 0.05)
			KEY_MINUS, KEY_KP_SUBTRACT:
				grid.tick_interval = minf(grid.tick_interval * 1.25, 2.0)
			KEY_F11:
				_toggle_fullscreen()


func _on_grid_resize(w: int, h: int, cs: int) -> void:
	grid.resize_grid(w, h, cs)
	tonal.setup(w, h)
	cluster_mgr.clusters.clear()
	cluster_mgr._prev_clusters.clear()
	ui.update_cluster_display([])
	ui.update_tick(0)
	_reset_camera()
	_update_camera_limits()
	_chips_rebuild_pitch_cells()


func _on_viewport_resized() -> void:
	# Re-center camera when window is resized / fullscreen toggled
	_reset_camera()


func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _zoom_camera(factor: float, screen_pos: Vector2) -> void:
	var old_zoom: float = camera.zoom.x
	var new_zoom: float = clampf(old_zoom * factor, _fit_zoom, 6.0)
	if new_zoom == old_zoom:
		return
	var viewport_half := get_viewport().get_visible_rect().size * 0.5
	var cursor_offset: Vector2 = screen_pos - viewport_half
	camera.position += cursor_offset / old_zoom - cursor_offset / new_zoom
	camera.zoom = Vector2(new_zoom, new_zoom)
	_clamp_camera()


func _reset_camera() -> void:
	var vp := get_viewport().get_visible_rect().size
	var panel_left: float = 260.0
	var panel_right: float = 260.0
	var available_w: float = vp.x - panel_left - panel_right
	var available_h: float = vp.y - 44.0
	var zoom_x: float = available_w / float(grid.total_w)
	var zoom_y: float = available_h / float(grid.total_h)
	var fit_zoom: float = minf(zoom_x, zoom_y) * 0.95
	fit_zoom = clampf(fit_zoom, 0.3, 4.0)
	_fit_zoom = fit_zoom
	var center_screen_x: float = panel_left + available_w * 0.5
	var center_screen_y: float = 44.0 + available_h * 0.5
	var world_center := Vector2(
		grid.position.x + grid.total_w * 0.5,
		grid.position.y + grid.total_h * 0.5
	)
	var vp_center := vp * 0.5
	var screen_offset := Vector2(center_screen_x - vp_center.x, center_screen_y - vp_center.y)
	camera.position = world_center + screen_offset / fit_zoom
	camera.zoom = Vector2(fit_zoom, fit_zoom)
	_update_camera_limits()


## Set Camera2D hard limits so the viewport never shows beyond the grid edges.
func _update_camera_limits() -> void:
	camera.limit_left   = int(grid.position.x)
	camera.limit_top    = int(grid.position.y)
	camera.limit_right  = int(grid.position.x + grid.total_w)
	camera.limit_bottom = int(grid.position.y + grid.total_h)


func _on_quad_mode_requested() -> void:
	if _in_quad_mode:
		_exit_quad_mode()
	else:
		_enter_quad_mode()


func _enter_quad_mode() -> void:
	_in_quad_mode = true
	# Hide main systems
	grid.visible = false
	grid.set_process(false)
	grid.set_process_input(false)
	ui.visible = false
	# Set camera to show all 4 panels
	var vp := get_viewport().get_visible_rect().size
	camera.position = Vector2(vp.x * 0.5, vp.y * 0.5)
	camera.zoom = Vector2.ONE
	camera.limit_left = -9999; camera.limit_right = 99999
	camera.limit_top  = -9999; camera.limit_bottom = 99999
	# Create quad systems
	quad_mode = QuadGridMode.new()
	add_child(quad_mode)
	quad_mode.setup(vp)
	# Wire tool manager to active panel
	var ag := quad_mode.get_active_grid()
	var acm := quad_mode.get_active_cluster_mgr()
	tool_mgr.switch_target(ag, acm, fitness_mgr, quad_mode.get_active_audio())
	quad_mode.panel_changed.connect(func(_idx: int):
		var g2 := quad_mode.get_active_grid()
		var cm2 := quad_mode.get_active_cluster_mgr()
		tool_mgr.switch_target(g2, cm2, fitness_mgr, quad_mode.get_active_audio())
	)
	# Create quad UI
	quad_ui = QuadGridUI.new()
	add_child(quad_ui)
	quad_ui.setup(quad_mode)
	quad_ui.back_requested.connect(_exit_quad_mode)


func _exit_quad_mode() -> void:
	_in_quad_mode = false
	# Destroy quad systems
	if quad_ui:
		quad_ui.queue_free(); quad_ui = null
	if quad_mode:
		quad_mode.queue_free(); quad_mode = null
	# Restore main systems
	grid.visible = true
	grid.set_process(true)
	grid.set_process_input(true)
	ui.visible = true
	# Reconnect tool manager to main grid
	tool_mgr.switch_target(grid, cluster_mgr, fitness_mgr, audio)
	# Restore camera
	_start_game()


## Clamp camera position after manual pan so it stays within limits.
func _clamp_camera() -> void:
	var vp := get_viewport().get_visible_rect().size
	var half_w: float = vp.x * 0.5 / camera.zoom.x
	var half_h: float = vp.y * 0.5 / camera.zoom.y
	var min_x: float = float(camera.limit_left)  + half_w
	var max_x: float = float(camera.limit_right) - half_w
	var min_y: float = float(camera.limit_top)   + half_h
	var max_y: float = float(camera.limit_bottom) - half_h
	camera.position.x = clampf(camera.position.x, minf(min_x, max_x), maxf(min_x, max_x))
	camera.position.y = clampf(camera.position.y, minf(min_y, max_y), maxf(min_y, max_y))


# ────────────────────────────────────────────────────────────────────────────
#  Chips From Audio panel (overlay — main game keeps running)
# ────────────────────────────────────────────────────────────────────────────

func _toggle_chips_panel() -> void:
	if _chips_active:
		_chips_active = false
		_chips_analyzer.stop()
		if _chips_panel:
			_chips_panel.queue_free()
			_chips_panel = null
		if _chips_dialog:
			_chips_dialog.queue_free()
			_chips_dialog = null
	else:
		_chips_active = true
		_chips_rebuild_pitch_cells()

		_chips_panel = ChipsDebugPanel.new()
		add_child(_chips_panel)
		_chips_panel.setup(_chips_analyzer, null, audio)
		_chips_panel.back_requested.connect(_toggle_chips_panel)
		_chips_panel.file_open_requested.connect(func() -> void:
			if _chips_dialog: _chips_dialog.popup_centered()
		)
		_chips_panel.play_requested.connect(func() -> void: _chips_analyzer.play())
		_chips_panel.stop_requested.connect(func() -> void: _chips_analyzer.stop())
		_chips_panel.spawn_note_requested.connect(func(pitch: int) -> void:
			var rate: int = _chips_panel.get_spawn_rate() if _chips_panel else 3
			_chips_spawn_in_region(pitch, rate * 4)
		)
		_chips_analyzer.file_loaded.connect(func(path: String) -> void:
			if _chips_panel: _chips_panel.set_file_label(path.get_file())
		)

		_chips_dialog = FileDialog.new()
		_chips_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_chips_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_chips_dialog.filters = ["*.ogg ; OGG Vorbis", "*.mp3 ; MP3"]
		_chips_dialog.size = Vector2i(720, 480)
		_chips_dialog.file_selected.connect(func(path: String) -> void:
			_chips_analyzer.load_file(path)
		)
		add_child(_chips_dialog)


## Precompute pitch(0-11) → grid positions whose tonal region has that root.
func _chips_rebuild_pitch_cells() -> void:
	_chips_pitch_cells = {}
	for n in 12:
		_chips_pitch_cells[n] = []
	for y in LifeGrid.GRID_H:
		for x in LifeGrid.GRID_W:
			var reg: int = tonal.get_region_id(x, y)
			var root: int = tonal.get_root(reg)
			(_chips_pitch_cells[root] as Array).append(Vector2i(x, y))


## Spawn cells in tonal regions whose root == pitch. Count is capped.
func _chips_spawn_in_region(pitch: int, count: int) -> void:
	var positions: Array = _chips_pitch_cells.get(pitch, [])
	if positions.is_empty():
		return
	var spawned: int = 0
	var tries: int = 0
	while spawned < count and tries < count * 6:
		var idx: int = randi() % positions.size()
		var pos := positions[idx] as Vector2i
		if not grid.cells[pos.y][pos.x].alive:
			grid._spawn_cell(pos.x, pos.y)
			spawned += 1
		tries += 1
	if spawned > 0:
		grid.queue_redraw()


## Called each tick to spawn cells from audio analysis.
func _chips_tick_spawn() -> void:
	if not _chips_active or not _chips_analyzer.is_playing() or _chips_energy.is_empty():
		return
	var threshold: float = _chips_panel.get_spawn_threshold() if _chips_panel else 0.15
	var rate: int        = _chips_panel.get_spawn_rate() if _chips_panel else 2

	for o in _chips_energy.size():
		var row: Array = _chips_energy[o]
		for n in 12:
			if float(row[n]) > threshold:
				_chips_spawn_in_region(n, rate)

	# Auto-consonant: additionally spawn harmonically related notes
	var auto_str: float = _chips_panel.get_auto_consonant_strength() if _chips_panel else 0.0
	if auto_str > 0.01:
		for n in 12:
			var aff: float = _chips_affinity[_chips_dominant][n]
			if aff > 0.4 and randf() < aff * auto_str * 0.4:
				_chips_spawn_in_region(n, 1)


## Returns the pitch class (0–11) with the highest total energy.
func _chips_calc_dominant() -> int:
	if _chips_energy.is_empty():
		return 0
	var sums: Array = []
	for _n in 12:
		sums.append(0.0)
	for oct_data in _chips_energy:
		for n in 12:
			sums[n] += float(oct_data[n])
	var best_e := 0.0
	var best_n := 0
	for n in 12:
		if sums[n] > best_e:
			best_e = sums[n]
			best_n = n
	return best_n


## Build 12×12 music-theory affinity (used for consonance button colouring).
func _build_chips_affinity() -> void:
	var by_interval: Array = [1.0, -0.8, -0.2, 0.6, 0.8, 0.5, -0.9, 0.9, 0.4, 0.6, -0.1, -0.7]
	_chips_affinity = []
	for i in 12:
		var row: Array = []
		for j in 12:
			row.append(by_interval[(j - i + 12) % 12])
		_chips_affinity.append(row)
