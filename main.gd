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
var camera: Camera2D

var _panning: bool = false


func _ready() -> void:
	_create_systems()
	_wire_signals()
	_start_game()


# ────────────────────────────────────────────────────────────────────────────
#  System creation
# ────────────────────────────────────────────────────────────────────────────

func _create_systems() -> void:
	# 1. Tonal regions
	tonal = TonalRegions.new()
	tonal.setup(LifeGrid.GRID_W, LifeGrid.GRID_H)
	add_child(tonal)

	# 2. Life grid (positioned to leave room for tool panel on the left)
	grid = LifeGrid.new()
	grid.position = Vector2(122, 34)   # offset for UI panels
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

	# 6. Tool manager
	tool_mgr = ToolManager.new()
	tool_mgr.setup(grid, cluster_mgr, fitness_mgr, audio)
	add_child(tool_mgr)

	# 7. Catalyst events
	catalyst = CatalystEvents.new()
	catalyst.setup(grid, cluster_mgr, fitness_mgr)
	add_child(catalyst)

	# 8. Game UI (CanvasLayer — renders on top)
	ui = GameUI.new()
	ui.setup(grid, cluster_mgr, fitness_mgr, tool_mgr, catalyst, tonal)
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


# ────────────────────────────────────────────────────────────────────────────
#  Game loop
# ────────────────────────────────────────────────────────────────────────────

func _start_game() -> void:
	_reset_camera()
	grid.seed_random(0.28)
	grid.running = true
	audio.set_tempo(120.0)


func _on_tick(tick_num: int) -> void:
	cluster_mgr.detect_clusters()
	fitness_mgr.on_tick(tick_num)
	catalyst.on_tick(tick_num)
	ui.update_tick(tick_num)


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


func _on_pause_toggled() -> void:
	grid.running = not grid.running


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
		get_viewport().set_input_as_handled()

	# ── Keyboard shortcuts ───────────────────────────────────────────────────
	elif event is InputEventKey and (event as InputEventKey).pressed:
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
			KEY_1:
				tool_mgr.set_tool(ToolManager.Tool.SELECT)
			KEY_2:
				tool_mgr.set_tool(ToolManager.Tool.HEAT_HOT)
			KEY_3:
				tool_mgr.set_tool(ToolManager.Tool.HEAT_COLD)
			KEY_4:
				tool_mgr.set_tool(ToolManager.Tool.BEACON_ATTRACT)
			KEY_5:
				tool_mgr.set_tool(ToolManager.Tool.BEACON_REPEL)
			KEY_6:
				tool_mgr.set_tool(ToolManager.Tool.DNA_INJECT)
			KEY_7:
				tool_mgr.set_tool(ToolManager.Tool.REWIND)
			KEY_8:
				tool_mgr.set_tool(ToolManager.Tool.SPLIT)
			KEY_9:
				tool_mgr.set_tool(ToolManager.Tool.DRAW)
			KEY_0:
				tool_mgr.set_tool(ToolManager.Tool.ERASE)
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
	grid.seed_random(0.28)
	ui.update_cluster_display([])
	ui.update_tick(0)
	_reset_camera()


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
	var new_zoom: float = clampf(old_zoom * factor, 0.12, 6.0)
	if new_zoom == old_zoom:
		return
	# Zoom toward cursor — keep the world point under the mouse fixed
	var viewport_half := get_viewport().get_visible_rect().size * 0.5
	var cursor_offset: Vector2 = screen_pos - viewport_half
	camera.position += cursor_offset / old_zoom - cursor_offset / new_zoom
	camera.zoom = Vector2(new_zoom, new_zoom)


func _reset_camera() -> void:
	# Center grid in the area between UI panels (120px left, 200px right)
	var vp := get_viewport().get_visible_rect().size
	var panel_left: float = 120.0
	var panel_right: float = 200.0
	var available_w: float = vp.x - panel_left - panel_right
	var available_h: float = vp.y - 32.0  # top bar
	# Zoom to fit grid in available area
	var zoom_x: float = available_w / float(grid.total_w)
	var zoom_y: float = available_h / float(grid.total_h)
	var fit_zoom: float = minf(zoom_x, zoom_y) * 0.95
	fit_zoom = clampf(fit_zoom, 0.3, 4.0)
	# Center: offset camera so grid appears centered between panels
	var center_screen_x: float = panel_left + available_w * 0.5
	var center_screen_y: float = 32.0 + available_h * 0.5
	var world_center := Vector2(
		grid.position.x + grid.total_w * 0.5,
		grid.position.y + grid.total_h * 0.5
	)
	# Offset = difference between viewport center and desired screen center, in world coords
	var vp_center := vp * 0.5
	var screen_offset := Vector2(center_screen_x - vp_center.x, center_screen_y - vp_center.y)
	camera.position = world_center + screen_offset / fit_zoom
	camera.zoom = Vector2(fit_zoom, fit_zoom)
