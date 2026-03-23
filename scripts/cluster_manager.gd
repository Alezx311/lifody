class_name ClusterManager
extends Node

## Detects and tracks clusters (connected groups of live cells) each tick.
## Uses BFS flood-fill. Maintains cluster identity across ticks via spatial overlap.

signal clusters_updated(clusters: Array)   # Array[Cluster]

var grid: LifeGrid = null
var tonal: TonalRegions = null

var clusters: Array = []        # Array[Cluster] — current tick
var _prev_clusters: Array = []  # Array[Cluster] — previous tick (for ID reuse)
var _next_id: int = 0

## Map from cluster id → fitness score, so fitness persists across ticks.
var _fitness_store: Dictionary = {}  # int → float
## Birth tick per cluster id.
var _birth_ticks: Dictionary = {}    # int → int


func setup(g: LifeGrid, t: TonalRegions) -> void:
	grid = g
	tonal = t


# ────────────────────────────────────────────────────────────────────────────
#  Public API
# ────────────────────────────────────────────────────────────────────────────

func detect_clusters() -> void:
	var raw: Array = _flood_fill()
	clusters = _assign_ids(raw)
	clusters_updated.emit(clusters)


func get_cluster_at(gx: int, gy: int) -> Cluster:
	for cl in clusters:
		for pos in cl.cells:
			if (pos as Vector2i) == Vector2i(gx, gy):
				return cl
	return null


func get_cluster_by_id(cid: int) -> Cluster:
	for cl in clusters:
		if cl.id == cid:
			return cl
	return null


# ────────────────────────────────────────────────────────────────────────────
#  BFS flood-fill
# ────────────────────────────────────────────────────────────────────────────

func _flood_fill() -> Array:
	var visited: Array = []
	for _y in LifeGrid.GRID_H:
		var row: Array = []
		for _x in LifeGrid.GRID_W:
			row.append(false)
		visited.append(row)

	var result: Array = []   # Array of Array[Vector2i]

	for y in LifeGrid.GRID_H:
		for x in LifeGrid.GRID_W:
			if (grid.cells[y][x] as CellState).alive and not visited[y][x]:
				var group: Array = []
				var queue: Array = [Vector2i(x, y)]
				visited[y][x] = true
				while not queue.is_empty():
					var cur := queue.pop_front() as Vector2i
					group.append(cur)
					for nb in _nb4(cur.x, cur.y):
						var nv := nb as Vector2i
						if not visited[nv.y][nv.x] and (grid.cells[nv.y][nv.x] as CellState).alive:
							visited[nv.y][nv.x] = true
							queue.append(nv)
				result.append(group)

	return result


func _nb4(x: int, y: int) -> Array:
	var r: Array = []
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
			  Vector2i(1,1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(-1,-1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if nx >= 0 and nx < LifeGrid.GRID_W and ny >= 0 and ny < LifeGrid.GRID_H:
			r.append(Vector2i(nx, ny))
	return r


# ────────────────────────────────────────────────────────────────────────────
#  ID assignment & metadata
# ────────────────────────────────────────────────────────────────────────────

func _assign_ids(raw: Array) -> Array:
	var new_clusters: Array = []

	for group in raw:
		var cl := Cluster.new()
		cl.cells = group

		# Find overlapping previous cluster
		var best_id: int = -1
		var best_overlap: int = 0
		var pos_set: Dictionary = {}
		for p in group:
			pos_set[p] = true

		for prev in _prev_clusters:
			var overlap: int = 0
			for pp in prev.cells:
				if pos_set.has(pp):
					overlap += 1
			if overlap > best_overlap:
				best_overlap = overlap
				best_id = prev.id

		if best_id >= 0 and best_overlap > 0:
			cl.id = best_id
			cl.birth_tick = _birth_ticks.get(best_id, grid.tick)
		else:
			cl.id = _next_id
			_next_id += 1
			cl.birth_tick = grid.tick
			_birth_ticks[cl.id] = cl.birth_tick

		# Restore or initialise fitness
		cl.fitness_score = _fitness_store.get(cl.id, 50.0)

		# Build ordered melody from cells (top→bottom, left→right)
		cl.melody = _build_melody(group)

		# Classify cluster state
		cl.state = _classify(group)

		new_clusters.append(cl)

	# Persist fitness for surviving cluster IDs
	var current_ids: Dictionary = {}
	for cl in new_clusters:
		current_ids[cl.id] = true
	for cid in _fitness_store.keys().duplicate():
		if not current_ids.has(cid):
			_fitness_store.erase(cid)
			_birth_ticks.erase(cid)
	for cl in new_clusters:
		_fitness_store[cl.id] = cl.fitness_score

	_prev_clusters = new_clusters.duplicate()
	return new_clusters


func _build_melody(positions: Array) -> Array:
	# Sort top→bottom, left→right
	var sorted: Array = positions.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y: return a.y < b.y
		return a.x < b.x
	)

	var notes: Array = []
	for pos in sorted:
		var v := pos as Vector2i
		var cell: CellState = grid.cells[v.y][v.x]
		for note in cell.genome:
			notes.append((note as DNANote).copy())
		if notes.size() >= 16:
			break   # Cap melody at 16 notes

	return notes


func _classify(positions: Array) -> String:
	var sz: int = positions.size()
	if sz == 0:
		return "empty"
	if sz == 1:
		return "still"
	if sz <= 4:
		return "stable"
	if sz <= 12:
		return "evolving"
	return "complex"


## Update stored fitness for a cluster (called by FitnessManager).
func update_fitness(cluster_id: int, delta: float) -> void:
	var current: float = _fitness_store.get(cluster_id, 50.0)
	_fitness_store[cluster_id] = clampf(current + delta, 0.0, 100.0)
	for cl in clusters:
		if cl.id == cluster_id:
			cl.fitness_score = _fitness_store[cluster_id]
			break
