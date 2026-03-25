class_name ToolManager
extends Node

## Manages the 5 player tools and routes grid input to the active tool.

signal tool_changed(new_tool: int)
signal status_message(msg: String)

enum Tool {
	HEAT_HOT,       # 0 – draw hot zone
	HEAT_COLD,      # 1 – draw cold zone
	BEACON_ATTRACT, # 2 – place attractor beacon
	BEACON_REPEL,   # 3 – place repeller beacon
	DNA_INJECT,     # 4 – inject a melody
	REWIND,         # 5 – rewind a cluster
	SPLIT,          # 6 – split a cluster (line draw)
	SELECT,         # 7 – select / inspect (default)
	DRAW,           # 8 – manually paint live cells
	ERASE,          # 9 – erase cells
	PAINT_REGION,   # 10 – paint a tonal zone onto the grid (island mode)
}

var active_tool: int = Tool.SELECT
var grid: LifeGrid = null
var cluster_mgr: ClusterManager = null
var fitness_mgr: FitnessManager = null
var audio_engine: AudioEngine = null

## Heat tool parameters
var heat_radius: int = 6

## Beacon list: Array of {x, y, type}  (max 5)
var beacons: Array = []
const MAX_BEACONS: int = 5

## DNA injection genome to inject
var inject_genome: Array = []   # Array[DNANote]

## Draw tool state
var draw_pitch: int = 0           # chromatic pitch 0-11
var draw_chromatic: bool = true   # true = chromatic region, false = use cell's scale region

## Paint region tool state
var paint_region_id: int = 0      # which region to paint (0-6); -1 = erase paint
var paint_region_radius: int = 5  # brush radius in grid cells

## Split tool line in progress
var _split_start: Vector2i = Vector2i(-1, -1)
var _split_end: Vector2i   = Vector2i(-1, -1)
var _splitting: bool = false

## Currently selected cluster id (for UI highlight)
var selected_cluster_id: int = -1


func setup(g: LifeGrid, cm: ClusterManager, fm: FitnessManager, ae: AudioEngine) -> void:
	grid = g
	cluster_mgr = cm
	fitness_mgr = fm
	audio_engine = ae
	g.grid_clicked.connect(_on_grid_click)
	g.grid_dragged.connect(_on_grid_drag)


## Switch the tool manager to target a different grid (used in quad mode).
func switch_target(g: LifeGrid, cm: ClusterManager, fm: FitnessManager, ae: AudioEngine) -> void:
	# Disconnect from old grid
	if grid != null:
		if grid.grid_clicked.is_connected(_on_grid_click):
			grid.grid_clicked.disconnect(_on_grid_click)
		if grid.grid_dragged.is_connected(_on_grid_drag):
			grid.grid_dragged.disconnect(_on_grid_drag)
	grid = g
	cluster_mgr = cm
	fitness_mgr = fm
	audio_engine = ae
	g.grid_clicked.connect(_on_grid_click)
	g.grid_dragged.connect(_on_grid_drag)


func set_tool(t: int) -> void:
	active_tool = t
	_splitting = false
	tool_changed.emit(t)


# ────────────────────────────────────────────────────────────────────────────
#  Grid events
# ────────────────────────────────────────────────────────────────────────────

func _on_grid_click(gx: int, gy: int, button: int) -> void:
	match active_tool:
		Tool.HEAT_HOT:
			var strength: float = 1.0 if button == MOUSE_BUTTON_LEFT else -0.5
			grid.add_heat(gx, gy, heat_radius, strength)

		Tool.HEAT_COLD:
			var strength: float = -1.0 if button == MOUSE_BUTTON_LEFT else 0.5
			grid.add_heat(gx, gy, heat_radius, strength)

		Tool.BEACON_ATTRACT:
			_place_beacon(gx, gy, 1)

		Tool.BEACON_REPEL:
			_place_beacon(gx, gy, -1)

		Tool.DNA_INJECT:
			if not fitness_mgr.can_inject():
				status_message.emit("DNA injection on cooldown!")
				return
			if inject_genome.is_empty():
				_build_default_inject_genome(gx, gy)
			grid.inject_dna(gx, gy, inject_genome)
			fitness_mgr.trigger_inject_cooldown()
			status_message.emit("DNA injected at (%d,%d)" % [gx, gy])

		Tool.REWIND:
			var cl := cluster_mgr.get_cluster_at(gx, gy)
			if cl and fitness_mgr.can_rewind():
				var snap_idx: int = grid.snapshots.size() - 1
				if snap_idx >= 0:
					var snap := grid.get_snapshot(snap_idx)
					fitness_mgr.use_rewind()
					grid.restore_cells(snap, cl.cells)
					status_message.emit("Cluster rewound. Rewinds left: %d" % fitness_mgr.rewinds_left)
			elif not fitness_mgr.can_rewind():
				status_message.emit("No rewinds left!")

		Tool.DRAW:
			if button == MOUSE_BUTTON_LEFT:
				grid.draw_cell(gx, gy, draw_pitch, draw_chromatic)
			else:
				grid.erase_cell(gx, gy)

		Tool.ERASE:
			grid.erase_cell(gx, gy)

		Tool.PAINT_REGION:
			if grid.tonal:
				grid.tonal.paint_region(gx, gy, paint_region_radius, paint_region_id)
				grid.queue_redraw()

		Tool.SELECT:
			var cl := cluster_mgr.get_cluster_at(gx, gy)
			selected_cluster_id = cl.id if cl else -1

		Tool.SPLIT:
			if not _splitting:
				_split_start = Vector2i(gx, gy)
				_splitting = true
				status_message.emit("Split: drag to draw cut line, release to split")
			else:
				_split_end = Vector2i(gx, gy)
				_do_split()
				_splitting = false


func _on_grid_drag(gx: int, gy: int, button: int) -> void:
	match active_tool:
		Tool.HEAT_HOT:
			var s: float = 0.5 if button == MOUSE_BUTTON_LEFT else -0.3
			grid.add_heat(gx, gy, heat_radius, s)
		Tool.HEAT_COLD:
			var s: float = -0.5 if button == MOUSE_BUTTON_LEFT else 0.3
			grid.add_heat(gx, gy, heat_radius, s)
		Tool.DRAW:
			if button == MOUSE_BUTTON_LEFT:
				grid.draw_cell(gx, gy, draw_pitch, draw_chromatic)
			else:
				grid.erase_cell(gx, gy)
		Tool.ERASE:
			grid.erase_cell(gx, gy)
		Tool.PAINT_REGION:
			if grid.tonal:
				grid.tonal.paint_region(gx, gy, paint_region_radius, paint_region_id)
				grid.queue_redraw()
		Tool.SPLIT:
			if _splitting:
				_split_end = Vector2i(gx, gy)
		Tool.BEACON_ATTRACT:
			_place_beacon(gx, gy, 1)
		Tool.BEACON_REPEL:
			_place_beacon(gx, gy, -1)


# ────────────────────────────────────────────────────────────────────────────
#  Beacon placement
# ────────────────────────────────────────────────────────────────────────────

func _place_beacon(gx: int, gy: int, btype: int) -> void:
	# Clear any existing beacon at this spot
	for i in range(beacons.size() - 1, -1, -1):
		var b: Dictionary = beacons[i]
		if b["x"] == gx and b["y"] == gy:
			grid.clear_beacon(b["x"], b["y"])
			beacons.remove_at(i)

	if beacons.size() >= MAX_BEACONS:
		var oldest: Dictionary = beacons.pop_front()
		grid.clear_beacon(oldest["x"], oldest["y"])
		status_message.emit("Beacon limit reached, oldest removed.")

	beacons.append({"x": gx, "y": gy, "type": btype})
	grid.set_beacon(gx, gy, btype, 8)
	var name_str: String = "Attractor" if btype == 1 else "Repeller"
	status_message.emit("%s placed at (%d,%d)" % [name_str, gx, gy])


func clear_all_beacons() -> void:
	for b in beacons:
		grid.clear_beacon(b["x"], b["y"])
	beacons.clear()


# ────────────────────────────────────────────────────────────────────────────
#  Cluster splitting
# ────────────────────────────────────────────────────────────────────────────

func _do_split() -> void:
	if _split_start == _split_end:
		return
	var cl := cluster_mgr.get_cluster_at(_split_start.x, _split_start.y)
	if cl == null:
		cl = cluster_mgr.get_cluster_at(_split_end.x, _split_end.y)
	if cl == null:
		status_message.emit("No cluster found to split.")
		return

	# Partition cells by which side of the split line they fall on
	var side_a: Array = []
	var side_b: Array = []
	var line_dir: Vector2 = Vector2(_split_end - _split_start)
	for pos in cl.cells:
		var v := pos as Vector2i
		var rel: Vector2 = Vector2(v - _split_start)
		var cross: float = line_dir.x * rel.y - line_dir.y * rel.x
		if cross >= 0:
			side_a.append(v)
		else:
			side_b.append(v)

	if side_a.is_empty() or side_b.is_empty():
		status_message.emit("Can't split: all cells on one side.")
		return

	# Kill cells on side_b boundary (mutation zone)
	for pos in side_b:
		var v := pos as Vector2i
		var dist: float = _point_to_line_dist(v, _split_start, _split_end)
		if dist <= 1.5:
			grid.cells[v.y][v.x] = CellState.new()

	status_message.emit("Cluster split into %d + %d cells." % [side_a.size(), side_b.size()])
	grid.queue_redraw()


func _point_to_line_dist(pt: Vector2i, la: Vector2i, lb: Vector2i) -> float:
	var ab: Vector2 = Vector2(lb - la)
	var ap: Vector2 = Vector2(pt - la)
	var len2: float = ab.length_squared()
	if len2 == 0.0:
		return ap.length()
	var t: float = clampf(ap.dot(ab) / len2, 0.0, 1.0)
	var closest: Vector2 = Vector2(la) + ab * t
	return Vector2(pt).distance_to(closest)


# ────────────────────────────────────────────────────────────────────────────
#  DNA injection helpers
# ────────────────────────────────────────────────────────────────────────────

func set_inject_genome(genome: Array) -> void:
	inject_genome = genome


func _build_default_inject_genome(gx: int, gy: int) -> void:
	## Build a simple 4-note ascending motif in the region's scale
	var region: int = 0
	if grid.tonal:
		region = grid.tonal.get_region_id(gx, gy)
	var scale_len: int = 7 if not grid.tonal else grid.tonal.get_scale_len(region)
	inject_genome = []
	for i in range(4):
		inject_genome.append(DNANote.create(i % scale_len, 4, 80, 0))
