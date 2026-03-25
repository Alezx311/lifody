class_name QuadGridMode
extends Node2D

## Manages 4 independent Life Grid panels for the Quad Grid game mode.

const PANEL_COUNT: int = 4
const TOP_BAR_H: float = 32.0
const HEADER_H: float = 24.0

var panels: Array = []  # [{grid, cluster_mgr, audio, tonal}]
var active_panel: int = 0

## Computed geometry
var _grid_w: int = 80
var _grid_h: int = 40
var _cell_sz: int = 8
var _panel_w: float = 640.0
var _panel_h: float = 344.0

signal panel_changed(idx: int)

## Called by main.gd after adding to scene tree
func setup(vp_size: Vector2) -> void:
	_compute_geometry(vp_size)
	for i in PANEL_COUNT:
		panels.append(_create_panel(i))
	# Resize all grids (static vars shared; each gets own cells array)
	for p in panels:
		(p["grid"] as LifeGrid).resize_grid(_grid_w, _grid_h, _cell_sz)
		(p["tonal"] as TonalRegions).setup(_grid_w, _grid_h)
		(p["grid"] as LifeGrid).running = false
	_layout_panels(vp_size)
	# Only first panel active initially
	for i in PANEL_COUNT:
		(panels[i]["grid"] as LifeGrid).set_process_input(i == 0)


func _compute_geometry(vp: Vector2) -> void:
	_panel_w = vp.x / 2.0
	_panel_h = (vp.y - TOP_BAR_H) / 2.0
	_cell_sz = 8
	_grid_w = int(_panel_w / float(_cell_sz))
	_grid_h = int((_panel_h - HEADER_H) / float(_cell_sz))


func _create_panel(idx: int) -> Dictionary:
	var t := TonalRegions.new()
	add_child(t)
	var g := LifeGrid.new()
	g.setup_tonal(t)
	add_child(g)
	var cm := ClusterManager.new()
	cm.setup(g, t)
	add_child(cm)
	var ae := AudioEngine.new()
	ae.setup_tonal(t)
	ae.setup_grid(g)
	add_child(ae)
	# tick -> detect clusters -> play audio
	g.tick_completed.connect(func(_tn: int):
		cm.detect_clusters()
	)
	cm.clusters_updated.connect(ae.play_clusters)
	return {"grid": g, "cluster_mgr": cm, "audio": ae, "tonal": t}


func _layout_panels(vp: Vector2) -> void:
	var positions := [
		Vector2(0,        TOP_BAR_H + HEADER_H),
		Vector2(_panel_w, TOP_BAR_H + HEADER_H),
		Vector2(0,        TOP_BAR_H + _panel_h + HEADER_H),
		Vector2(_panel_w, TOP_BAR_H + _panel_h + HEADER_H),
	]
	for i in PANEL_COUNT:
		(panels[i]["grid"] as LifeGrid).position = positions[i]


func set_active(idx: int) -> void:
	(panels[active_panel]["grid"] as LifeGrid).set_process_input(false)
	active_panel = clampi(idx, 0, PANEL_COUNT - 1)
	(panels[active_panel]["grid"] as LifeGrid).set_process_input(true)
	panel_changed.emit(active_panel)


func get_active_grid() -> LifeGrid:
	return panels[active_panel]["grid"] as LifeGrid


func get_active_cluster_mgr() -> ClusterManager:
	return panels[active_panel]["cluster_mgr"] as ClusterManager


func get_active_audio() -> AudioEngine:
	return panels[active_panel]["audio"] as AudioEngine


func get_panel_grid(idx: int) -> LifeGrid:
	return panels[idx]["grid"] as LifeGrid


func get_panel_audio(idx: int) -> AudioEngine:
	return panels[idx]["audio"] as AudioEngine


func set_panel_instrument(panel_idx: int, inst_idx: int) -> void:
	(panels[panel_idx]["audio"] as AudioEngine).set_instrument(inst_idx)


func set_panel_volume(panel_idx: int, vol: float) -> void:
	(panels[panel_idx]["audio"] as AudioEngine).master_volume = vol


func toggle_panel_pause(panel_idx: int) -> void:
	var g := panels[panel_idx]["grid"] as LifeGrid
	g.running = not g.running


func seed_panel(panel_idx: int, pattern: String) -> void:
	var g := panels[panel_idx]["grid"] as LifeGrid
	match pattern:
		"random":      g.seed_random(0.28)
		"glider":      g.seed_glider(_grid_w / 2, _grid_h / 2)
		"r_pentomino": g.seed_r_pentomino(_grid_w / 2, _grid_h / 2)


func clear_panel(panel_idx: int) -> void:
	var p: Dictionary = panels[panel_idx]
	(p["grid"] as LifeGrid).clear()
	(p["cluster_mgr"] as ClusterManager).clusters.clear()
	(p["cluster_mgr"] as ClusterManager)._prev_clusters.clear()


## Returns the screen-space rect of the header for panel_idx
func get_header_screen_rect(panel_idx: int) -> Rect2:
	var col: int = panel_idx % 2
	var row: int = panel_idx / 2
	return Rect2(col * _panel_w, TOP_BAR_H + row * _panel_h, _panel_w, HEADER_H)


## Returns the full screen-space rect of the panel (header + grid)
func get_panel_screen_rect(panel_idx: int) -> Rect2:
	var col: int = panel_idx % 2
	var row: int = panel_idx / 2
	return Rect2(col * _panel_w, TOP_BAR_H + row * _panel_h, _panel_w, _panel_h)
