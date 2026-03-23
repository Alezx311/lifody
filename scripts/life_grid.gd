class_name LifeGrid
extends Node2D

## Game of Life simulation grid with melodic DNA system.
## Handles: simulation ticks, DNA crossover/mutation, heat zones, beacons,
##          frozen cells, snapshots, and custom grid rendering.

signal tick_completed(tick_num: int)
signal grid_clicked(gx: int, gy: int, button: int)
signal grid_dragged(gx: int, gy: int, button: int)

# ── Grid dimensions (static so external code can read LifeGrid.GRID_W etc.) ─
static var GRID_W: int = 80
static var GRID_H: int = 60
static var CELL_SIZE: int = 12
## Computed; always equals GRID_W * CELL_SIZE
var total_w: int:
	get: return GRID_W * CELL_SIZE
## Computed; always equals GRID_H * CELL_SIZE
var total_h: int:
	get: return GRID_H * CELL_SIZE

# ── State arrays ─────────────────────────────────────────────────────────────
var cells: Array = []       # [y][x] → CellState
var heat_map: Array = []    # [y][x] → float  -1..+1
var beacon_map: Array = []  # [y][x] → int  -1=repel 0=none 1=attract 2=resonance

# ── Simulation parameters ────────────────────────────────────────────────────
var tick: int = 0
var base_mutation_rate: float = 0.05
## Neighbour counts that birth a new cell (Conway default: [3])
var birth_rule: Array = [3]
## Neighbour counts that keep a cell alive (Conway default: [2, 3])
var survival_rule: Array = [2, 3]
var tick_interval: float = 0.2   # seconds between ticks (5 tps)
var running: bool = false
var _tick_timer: float = 0.0
var _anim_time: float = 0.0      # wall-clock seconds; drives smooth animations

# ── Tonal system reference ───────────────────────────────────────────────────
var tonal: TonalRegions = null

## Listening zone radius in grid cells (0 = play everything).
var listening_radius: int = 20

# ── Snapshot ring buffer for Rewind tool ────────────────────────────────────
const SNAPSHOT_INTERVAL: int = 5    # ticks between snapshots
const MAX_SNAPSHOTS: int = 10
var snapshots: Array = []           # Array of cell grid copies

# ── Mouse drag state ─────────────────────────────────────────────────────────
var _mouse_pressed: bool = false
var _last_drag_grid: Vector2i = Vector2i(-1, -1)

# ── Render colors ─────────────────────────────────────────────────────────────
const C_BG          := Color(0.02, 0.02, 0.05)
const C_JUVENILE    := Color(0.45, 1.00, 0.58)
const C_MATURE      := Color(0.15, 0.92, 0.40)
const C_OLD         := Color(0.80, 0.96, 0.25)
const C_FROZEN      := Color(0.38, 0.82, 1.00)
const C_HOT         := Color(1.00, 0.22, 0.05, 0.22)
const C_COLD        := Color(0.12, 0.45, 1.00, 0.22)
const C_ATTRACT     := Color(0.10, 1.00, 0.35, 0.55)
const C_REPEL       := Color(1.00, 0.30, 0.05, 0.55)
const C_RESONANCE   := Color(1.00, 0.95, 0.08, 0.55)
const C_BOUNDARY    := Color(0.65, 0.65, 0.30, 0.40)
const C_TRANSITION  := Color(0.90, 0.90, 0.20, 0.14)

## When true cells are coloured by their first note's pitch instead of by age.
var color_by_note: bool = false


# ────────────────────────────────────────────────────────────────────────────
#  Initialisation
# ────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_alloc_arrays()
	set_process(true)
	# Enable mouse input
	set_process_input(true)


func _alloc_arrays() -> void:
	cells = []
	heat_map = []
	beacon_map = []
	for _y in GRID_H:
		var cr: Array = []
		var hr: Array = []
		var br: Array = []
		for _x in GRID_W:
			cr.append(CellState.new())
			hr.append(0.0)
			br.append(0)
		cells.append(cr)
		heat_map.append(hr)
		beacon_map.append(br)


func setup_tonal(t: TonalRegions) -> void:
	tonal = t


# ────────────────────────────────────────────────────────────────────────────
#  Seeding helpers
# ────────────────────────────────────────────────────────────────────────────

func seed_random(density: float = 0.30) -> void:
	for y in GRID_H:
		for x in GRID_W:
			if randf() < density:
				_spawn_cell(x, y)
	queue_redraw()


func seed_glider(ox: int, oy: int) -> void:
	## Standard glider: 5 cells
	for p in [[1,0],[2,1],[0,2],[1,2],[2,2]]:
		var px: int = ox + p[0]
		var py: int = oy + p[1]
		if _in_bounds(px, py):
			_spawn_cell(px, py)
	queue_redraw()


func seed_blinker(ox: int, oy: int) -> void:
	## Horizontal blinker
	for dx in [-1, 0, 1]:
		_spawn_cell(ox + dx, oy)
	queue_redraw()


func seed_r_pentomino(ox: int, oy: int) -> void:
	## R-pentomino — chaotic generator
	for p in [[1,0],[2,0],[0,1],[1,1],[1,2]]:
		_spawn_cell(ox + p[0], oy + p[1])
	queue_redraw()


func _spawn_cell(x: int, y: int) -> void:
	if not _in_bounds(x, y):
		return
	var region: int = 0
	if tonal:
		region = tonal.get_region_id(x, y)
	var scale_len: int = 7 if not tonal else tonal.get_scale_len(region)
	var genome: Array = []
	for _i in range(4):
		genome.append(DNANote.random_note(scale_len))
	cells[y][x] = CellState.create_alive(genome)
	cells[y][x].tonal_region = region


func clear() -> void:
	_alloc_arrays()
	tick = 0
	snapshots.clear()
	queue_redraw()


## Change grid dimensions and reset. Caller is responsible for re-seeding and
## updating TonalRegions.
func resize_grid(w: int, h: int, cell_sz: int) -> void:
	LifeGrid.GRID_W    = w
	LifeGrid.GRID_H    = h
	LifeGrid.CELL_SIZE = cell_sz
	clear()


# ────────────────────────────────────────────────────────────────────────────
#  Simulation loop
# ────────────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()   # 60 fps redraw for smooth animations (beacons, ring pulse, glow)
	if not running:
		return
	_tick_timer += delta
	if _tick_timer >= tick_interval:
		_tick_timer -= tick_interval
		tick_simulation()


func tick_simulation() -> void:
	_dissipate_heat()
	cells = _next_generation()
	tick += 1
	if tick % SNAPSHOT_INTERVAL == 0:
		_push_snapshot()
	queue_redraw()
	tick_completed.emit(tick)


func _next_generation() -> Array:
	var next: Array = []
	for _y in GRID_H:
		var row: Array = []
		for _x in GRID_W:
			row.append(CellState.new())
		next.append(row)

	for y in GRID_H:
		for x in GRID_W:
			var cell: CellState = cells[y][x]

			# Frozen cells survive unchanged
			if cell.frozen:
				next[y][x] = cell.copy()
				next[y][x].age += 1
				continue

			var alive_nb: Array = _alive_neighbors(x, y)
			var cnt: int = alive_nb.size()
			var heat: float = heat_map[y][x]
			var beacon: int = beacon_map[y][x]

			# Rule modification by heat zone
			var will_survive: bool
			var will_born: bool
			if heat > 0.5:         # Hot zone
				will_survive = cnt >= 1 and cnt <= 3
				will_born    = cnt == 2 or cnt == 3
			elif heat < -0.5:      # Cold zone
				will_survive = cnt == 3
				will_born    = cnt == 3
			else:                  # Configurable rules (B/S notation)
				will_survive = survival_rule.has(cnt)
				will_born    = birth_rule.has(cnt)

			# Beacon modifies survival probability
			if cell.alive and not will_survive and beacon != 0:
				var bonus: float = 0.12 * float(beacon)
				if randf() < bonus:
					will_survive = beacon > 0

			var region: int = tonal.get_region_id(x, y) if tonal else 0
			var in_trans: bool = tonal.is_transition(x, y) if tonal else false

			var mut_rate: float = base_mutation_rate
			if heat > 0.5:   mut_rate *= 2.5
			elif heat < -0.5: mut_rate *= 0.2
			if in_trans:      mut_rate *= 1.5

			var scale_len: int = tonal.get_scale_len(region) if tonal else 7

			if cell.alive:
				if will_survive:
					next[y][x] = cell.copy()
					next[y][x].age += 1
					next[y][x].tonal_region = region
					# Old cells drift their pitch
					if next[y][x].age > 20:
						for note in next[y][x].genome:
							(note as DNANote).age_drift(scale_len)
			else:
				if will_born and not alive_nb.is_empty():
					next[y][x] = CellState.crossover(alive_nb, mut_rate, region, scale_len)

	return next


func _alive_neighbors(x: int, y: int) -> Array:
	var result: Array = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nx: int = x + dx
			var ny: int = y + dy
			if _in_bounds(nx, ny) and cells[ny][nx].alive:
				result.append(cells[ny][nx])
	return result


func _in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < GRID_W and y >= 0 and y < GRID_H


# ────────────────────────────────────────────────────────────────────────────
#  Heat zones & beacons
# ────────────────────────────────────────────────────────────────────────────

func add_heat(gx: int, gy: int, radius: int, strength: float) -> void:
	for y in GRID_H:
		for x in GRID_W:
			var d: float = Vector2(x - gx, y - gy).length()
			if d <= radius:
				var f: float = 1.0 - d / float(radius)
				heat_map[y][x] = clampf(heat_map[y][x] + strength * f, -1.0, 1.0)
	queue_redraw()


func _dissipate_heat() -> void:
	for y in GRID_H:
		for x in GRID_W:
			heat_map[y][x] *= 0.966   # ~30 ticks to dissipate


func set_beacon(gx: int, gy: int, btype: int, radius: int = 8) -> void:
	for y in GRID_H:
		for x in GRID_W:
			if Vector2(x - gx, y - gy).length() <= radius:
				beacon_map[y][x] = btype
	queue_redraw()


func clear_beacon(gx: int, gy: int, radius: int = 10) -> void:
	set_beacon(gx, gy, 0, radius)


# ────────────────────────────────────────────────────────────────────────────
#  DNA injection
# ────────────────────────────────────────────────────────────────────────────

func inject_dna(gx: int, gy: int, genome: Array) -> void:
	var spawned: int = 0
	var target: int = randi_range(1, 3)
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if spawned >= target:
				return
			var nx: int = gx + dx
			var ny: int = gy + dy
			if _in_bounds(nx, ny) and not cells[ny][nx].alive and randf() < 0.35:
				var new_genome: Array = []
				for n in genome:
					new_genome.append((n as DNANote).copy())
				cells[ny][nx] = CellState.create_alive(new_genome)
				if tonal:
					cells[ny][nx].tonal_region = tonal.get_region_id(nx, ny)
				spawned += 1
	queue_redraw()


# ────────────────────────────────────────────────────────────────────────────
#  Freeze a cluster
# ────────────────────────────────────────────────────────────────────────────

func freeze_cells(cell_positions: Array, frozen: bool) -> void:
	for pos in cell_positions:
		var v := pos as Vector2i
		if _in_bounds(v.x, v.y) and cells[v.y][v.x].alive:
			cells[v.y][v.x].frozen = frozen
	queue_redraw()


# ────────────────────────────────────────────────────────────────────────────
#  Snapshots / Rewind
# ────────────────────────────────────────────────────────────────────────────

func _push_snapshot() -> void:
	if snapshots.size() >= MAX_SNAPSHOTS:
		snapshots.pop_front()
	snapshots.append(_copy_cells())


func _copy_cells() -> Array:
	var snap: Array = []
	for y in GRID_H:
		var row: Array = []
		for x in GRID_W:
			row.append((cells[y][x] as CellState).copy())
		snap.append(row)
	return snap


func get_snapshot(idx: int) -> Array:
	if idx < 0 or idx >= snapshots.size():
		return []
	return snapshots[idx]


## Restore specific cells from a snapshot (cluster rewind).
func restore_cells(snapshot_cells: Array, cell_positions: Array) -> void:
	if snapshot_cells.is_empty():
		return
	for pos in cell_positions:
		var v := pos as Vector2i
		if _in_bounds(v.x, v.y):
			cells[v.y][v.x] = (snapshot_cells[v.y][v.x] as CellState).copy()
	queue_redraw()


# ────────────────────────────────────────────────────────────────────────────
#  Coordinates
# ────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────
#  Manual draw / erase
# ────────────────────────────────────────────────────────────────────────────

## Place a single live cell at (gx,gy) with a specific pitch.
## chromatic=true  → chromatic region, pitch 0-11 = C4..B4
## chromatic=false → pitch is scale degree of the cell's tonal region
func draw_cell(gx: int, gy: int, pitch: int, chromatic: bool = false) -> void:
	if not _in_bounds(gx, gy):
		return
	var region: int
	var scale_len: int
	if chromatic:
		region = tonal.CHROMATIC_REGION if tonal else 132
		scale_len = 12
	else:
		region = tonal.get_region_id(gx, gy) if tonal else 0
		scale_len = tonal.get_scale_len(region) if tonal else 7
	var genome: Array = [DNANote.create(pitch % scale_len, randi_range(2, 6), randi_range(60, 110), 0)]
	cells[gy][gx] = CellState.create_alive(genome)
	cells[gy][gx].tonal_region = region
	queue_redraw()


func erase_cell(gx: int, gy: int) -> void:
	if _in_bounds(gx, gy):
		cells[gy][gx] = CellState.new()
		queue_redraw()


func pixel_to_grid(px: Vector2) -> Vector2i:
	return Vector2i(int(px.x / CELL_SIZE), int(px.y / CELL_SIZE))


func grid_to_pixel_center(gx: int, gy: int) -> Vector2:
	return Vector2(gx * CELL_SIZE + CELL_SIZE * 0.5, gy * CELL_SIZE + CELL_SIZE * 0.5)


# ────────────────────────────────────────────────────────────────────────────
#  Input
# ────────────────────────────────────────────────────────────────────────────

func _local_mouse() -> Vector2:
	## Camera-aware local mouse position.
	return to_local(get_global_mouse_position())


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton
		if mbe.button_index == MOUSE_BUTTON_LEFT or mbe.button_index == MOUSE_BUTTON_RIGHT:
			if mbe.pressed:
				_mouse_pressed = true
				var gp := pixel_to_grid(_local_mouse())
				if _in_bounds(gp.x, gp.y):
					_last_drag_grid = gp
					grid_clicked.emit(gp.x, gp.y, mbe.button_index)
			else:
				_mouse_pressed = false
				_last_drag_grid = Vector2i(-1, -1)

	elif event is InputEventMouseMotion:
		# Always track mouse for listening zone overlay
		var gp := pixel_to_grid(_local_mouse())
		if is_instance_valid(self):
			queue_redraw()   # repaint listening zone ring
		if _mouse_pressed:
			if _in_bounds(gp.x, gp.y) and gp != _last_drag_grid:
				_last_drag_grid = gp
				var mme := event as InputEventMouseMotion
				var btn: int = MOUSE_BUTTON_LEFT if mme.button_mask & MOUSE_BUTTON_MASK_LEFT else MOUSE_BUTTON_RIGHT
				grid_dragged.emit(gp.x, gp.y, btn)


# ────────────────────────────────────────────────────────────────────────────
#  Rendering
# ────────────────────────────────────────────────────────────────────────────

func _draw() -> void:
	draw_rect(Rect2(0, 0, total_w, total_h), C_BG)
	_draw_bg_grid()

	if tonal:
		if tonal.map_mode == TonalRegions.MAP_ISLAND:
			_draw_island_map()
			_draw_custom_regions()
		else:
			_draw_tonal_regions()

	_draw_heat_map()
	_draw_beacons()
	_draw_cells()
	_draw_vignette()
	_draw_listening_ring()


func _draw_tonal_regions() -> void:
	var cols: int   = tonal.std_cols
	var rows: int   = tonal.std_rows
	var cw:   float = float(total_w) / float(cols)
	var ch:   float = float(total_h) / float(rows)
	var font := ThemeDB.fallback_font
	# Choose font size based on cell size so labels fit
	var fs: int = clampi(int(cw / 5.5), 7, 11)

	# Coloured region backgrounds
	for row in rows:
		for col in cols:
			var rid: int = tonal.region_grid[row][col]
			draw_rect(Rect2(col * cw, row * ch, cw, ch), tonal.get_color(rid))

	# Grid boundary lines
	for i in range(1, cols):
		draw_line(Vector2(i * cw, 0), Vector2(i * cw, total_h), C_BOUNDARY, 1.2)
	for i in range(1, rows):
		draw_line(Vector2(0, i * ch), Vector2(total_w, i * ch), C_BOUNDARY, 1.2)

	# Transition zone shading near each boundary
	var tw3: float = float(TonalRegions.TRANSITION_WIDTH) * CELL_SIZE
	for i in range(1, cols):
		draw_rect(Rect2(i * cw - tw3, 0, tw3 * 2, total_h), C_TRANSITION)
	for i in range(1, rows):
		draw_rect(Rect2(0, i * ch - tw3, total_w, tw3 * 2), C_TRANSITION)

	# Region name labels centred in each cell
	for row in rows:
		for col in cols:
			var rid: int = tonal.region_grid[row][col]
			var lc: Color = tonal.get_color(rid)
			lc.a = 0.70
			var cx: float = (float(col) + 0.5) * cw
			var cy: float = float(row) * ch + float(fs) + 2.0
			draw_string(font, Vector2(cx, cy), tonal.get_region_name(rid),
						HORIZONTAL_ALIGNMENT_CENTER, -1, fs, lc)


func _draw_heat_map() -> void:
	for y in GRID_H:
		for x in GRID_W:
			var h: float = heat_map[y][x]
			if absf(h) < 0.04:
				continue
			var intensity: float = absf(h)
			var c: Color = C_HOT if h > 0 else C_COLD
			c.a = intensity * intensity * 0.42   # quadratic: softer edges, brighter core
			draw_rect(Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE), c)


func _draw_beacons() -> void:
	var pulse: float = sin(_anim_time * 3.2) * 0.05
	for y in GRID_H:
		for x in GRID_W:
			var b: int = beacon_map[y][x]
			if b == 0:
				continue
			var c: Color
			match b:
				1:  c = C_ATTRACT
				-1: c = C_REPEL
				2:  c = C_RESONANCE
				_:  c = Color.WHITE
			c.a = 0.18 + pulse
			draw_rect(Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE), c)


## Returns the display color for a live cell based on age / note / frozen state.
func _cell_color(cell: CellState) -> Color:
	if cell.frozen:
		return C_FROZEN
	if color_by_note and not cell.genome.is_empty():
		var pitch: int = (cell.genome[0] as DNANote).pitch % 12
		var base_c: Color = tonal.get_note_color(pitch) if tonal else C_MATURE
		var brightness: float = 1.0 - clampf(float(cell.age) / 50.0, 0.0, 0.30)
		return Color(base_c.r * brightness, base_c.g * brightness, base_c.b * brightness)
	if cell.age == 1:
		return C_JUVENILE.lightened(0.28)   # birth flash
	if cell.age < 6:
		return C_JUVENILE.lerp(C_MATURE, float(cell.age) / 6.0)
	if cell.age < 21:
		return C_MATURE
	return C_MATURE.lerp(C_OLD, clampf(float(cell.age - 21) / 20.0, 0.0, 1.0))


func _draw_cells() -> void:
	var gp: float = CELL_SIZE * 0.45   # glow padding in pixels

	# Pass 1 — soft outer glow halos (rendered behind all cells)
	for y in GRID_H:
		for x in GRID_W:
			var cell: CellState = cells[y][x]
			if not cell.alive:
				continue
			var c := _cell_color(cell)
			draw_rect(
				Rect2(x * CELL_SIZE - gp, y * CELL_SIZE - gp,
					  CELL_SIZE + gp * 2.0, CELL_SIZE + gp * 2.0),
				Color(c.r, c.g, c.b, 0.11)
			)

	# Pass 2 — main cell bodies
	for y in GRID_H:
		for x in GRID_W:
			var cell: CellState = cells[y][x]
			if not cell.alive:
				continue
			var c := _cell_color(cell)
			draw_rect(
				Rect2(x * CELL_SIZE + 1, y * CELL_SIZE + 1,
					  CELL_SIZE - 2, CELL_SIZE - 2),
				c
			)


func _draw_listening_ring() -> void:
	if listening_radius <= 0:
		return
	var mouse_gp := pixel_to_grid(_local_mouse())
	var center_px := Vector2(
		mouse_gp.x * CELL_SIZE + CELL_SIZE * 0.5,
		mouse_gp.y * CELL_SIZE + CELL_SIZE * 0.5
	)
	var r_px: float = listening_radius * CELL_SIZE

	# Outer pulse — expands and fades rhythmically
	var pulse: float = (sin(_anim_time * 2.5) + 1.0) * 0.5   # 0..1
	draw_arc(center_px, r_px + pulse * CELL_SIZE * 2.2, 0.0, TAU, 64,
			 Color(0.90, 0.90, 0.22, 0.10 * pulse), 1.0)

	# Secondary steady ring
	draw_arc(center_px, r_px + CELL_SIZE * 0.6, 0.0, TAU, 64,
			 Color(0.88, 0.88, 0.22, 0.22), 1.0)

	# Main ring
	draw_arc(center_px, r_px, 0.0, TAU, 64,
			 Color(0.92, 0.92, 0.28, 0.68), 1.8)

	# Crosshair at cursor
	draw_line(center_px + Vector2(-7, 0), center_px + Vector2(7, 0),
			  Color(0.9, 0.9, 0.3, 0.9), 1.2)
	draw_line(center_px + Vector2(0, -7), center_px + Vector2(0, 7),
			  Color(0.9, 0.9, 0.3, 0.9), 1.2)


func _draw_bg_grid() -> void:
	## Subtle dot pattern at every 4th cell intersection.
	var c := Color(0.13, 0.13, 0.20, 0.52)
	for y in range(0, GRID_H + 1, 4):
		for x in range(0, GRID_W + 1, 4):
			draw_rect(Rect2(x * CELL_SIZE - 0.5, y * CELL_SIZE - 0.5, 1.5, 1.5), c)


func _draw_vignette() -> void:
	## Dark gradient at grid edges for depth.
	var edge: float = CELL_SIZE * 4.0
	for i in 5:
		var t: float = float(i) / 5.0
		var w: float = edge * (1.0 - t * 0.6)
		var a: float = 0.26 * (1.0 - t)
		var vc := Color(0.0, 0.0, 0.04, a)
		draw_rect(Rect2(0.0,           0.0,           w,       total_h), vc)
		draw_rect(Rect2(total_w - w,   0.0,           w,       total_h), vc)
		draw_rect(Rect2(0.0,           0.0,           total_w, w),       vc)
		draw_rect(Rect2(0.0,           total_h - w,   total_w, w),       vc)


func _draw_island_map() -> void:
	## Draw 12 note-island circles (piano keyboard layout) for MAP_ISLAND mode.
	if not tonal:
		return
	var font := ThemeDB.fallback_font
	var fs: int = 10
	for isl in tonal.islands:
		var cx_px: float = isl["cx"] * CELL_SIZE + CELL_SIZE * 0.5
		var cy_px: float = isl["cy"] * CELL_SIZE + CELL_SIZE * 0.5
		var r_px:  float = (float(isl["radius"]) + 0.5) * CELL_SIZE
		var note: int = isl["note"]
		var fill_c: Color = TonalRegions.NOTE_COLORS[note]
		fill_c.a = 0.13
		draw_circle(Vector2(cx_px, cy_px), r_px, fill_c)
		var border_c: Color = TonalRegions.NOTE_COLORS[note]
		border_c.a = 0.60
		draw_arc(Vector2(cx_px, cy_px), r_px, 0.0, TAU, 40, border_c, 1.5)
		var lbl_c: Color = TonalRegions.NOTE_COLORS[note]
		lbl_c.a = 0.90
		draw_string(font, Vector2(cx_px - 8, cy_px + 4), isl["name"],
					HORIZONTAL_ALIGNMENT_CENTER, -1, fs, lbl_c)


func _draw_custom_regions() -> void:
	## Overlay painted tonal zones. Works in both modes; prominently visible in island mode.
	if not tonal:
		return
	for y in GRID_H:
		for x in GRID_W:
			var rid: int = tonal.custom_region_map[y][x]
			if rid < 0:
				continue
			var c: Color = tonal.get_color(rid)
			c.a = 0.38
			draw_rect(Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE), c)
